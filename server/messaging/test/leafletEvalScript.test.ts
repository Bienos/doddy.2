// The leaflet review script (scripts/leaflet-eval.mjs): its options and caps, the cost estimate, the sheet and
// JSON writers, the folder and key rules, and one run of the whole thing against the fake web and the fake model
// of the other leaflet tests. No real network and no real model: nothing here reaches a shop or Anthropic.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, describe, test } from "node:test";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { PageOutput } from "../src/deals/vision.js";
import type { ModelReply } from "../src/deals/types.js";
import { BIEDRONKA_API, chainsWeb, fakePng, FakeModel, FakeWeb, read } from "./dealsFakes.js";

interface Money { minor: number; currency: "PLN" }
interface Product {
  name: string; size: string | null; price: Money; regularPrice: Money | null; lowest30d: Money | null; printedUnitPrice: string | null;
  conditions: string[]; validFrom: string | null; validTo: string | null; unitPrice: { minor: number; per: string } | null;
  check: boolean; doubts: string[]; matchedItems: string[]; conditionKinds?: string[];
}
interface Page { leaflet: number; number: number; url: string; imageUrl: string; status: string; reason?: string; products: Product[] }
interface Result {
  notice?: string; startedAt: string; chain: string; items: string[]; model: string; maxPages: number; status: string; reason?: string;
  leaflets: { title?: string; url: string; validFrom?: string; validTo?: string; strategy: string; pagesAvailable: number }[];
  pages: Page[];
  totals: {
    pagesPlanned: number; pagesSent: number; pagesRead: number; pagesNotRead: number; byStatus: Record<string, number>; products: number; flagged: number;
    inputTokens: number; outputTokens: number; estimatedCostUsd: number; worstCaseCostUsd?: number; elapsedMs: number;
  };
  pricing: { model: string; inputPerMillionUsd: number; outputPerMillionUsd: number; promptTokensUpTo: number; appliesToRunModel: boolean };
}
interface Options { chain: string; maxPages: number; items: string[]; out: string | undefined; dryRun: boolean; help: boolean }
interface Io {
  env?: Record<string, string | undefined>;
  stdout?: (s: string) => void;
  stderr?: (s: string) => void;
  tmp?: string;
  repoRoot?: string;
  modules?: unknown;
  fetcher?: unknown;
  model?: unknown;
  now?: () => Date;
  signal?: AbortSignal;
}
interface LeafletEvalScript {
  REPO_ROOT: string;
  NOTICE: string;
  PRICE: { model: string; inputPerMillionUsd: number; outputPerMillionUsd: number; promptTokensUpTo: number };
  WORST_CASE: { imageTokens: number; overheadTokens: number; maxOutputTokens: number };
  DEFAULT_MAX_PAGES: number;
  HARD_MAX_PAGES: number;
  parseArgs(argv: string[]): { ok: true; options: Options } | { ok: false; error: string };
  checkKey(env: Record<string, string | undefined>, dryRun: boolean): { ok: boolean; key?: string; error?: string };
  resolveOutDir(out: string | undefined, o?: { tmp?: string; repoRoot?: string; now?: Date }): { ok: boolean; dir?: string; error?: string };
  estimateCost(u: { inputTokens: number; outputTokens: number }): number;
  worstCaseCost(pages: number, limits?: { imageTokens: number; overheadTokens: number; maxOutputTokens: number }): number;
  formatUsd(n: number): string;
  renderMarkdown(r: Result): string;
  renderJson(r: Result): string;
  writeReport(dir: string, r: Result, o?: { repoRoot?: string }): { json: string; markdown: string };
  loadDealsModules(): Promise<unknown>;
  evaluate(options: object, deps: object): Promise<Result>;
  main(argv: string[], io?: Io): Promise<number>;
}
// The script is plain JavaScript next to src/, outside the TypeScript build. The tests run from dist/test, so the
// script is two levels up (the same way the fixtures are reached).
const script = (await import(new URL("../../scripts/leaflet-eval.mjs", import.meta.url).href)) as LeafletEvalScript;

const scratch = mkdtempSync(path.join(tmpdir(), "doddy-leaflet-eval-test-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
let counter = 0;
const fresh = (name = "d") => path.join(scratch, `${name}-${++counter}`);
const closeTo = (a: number, b: number) => assert.ok(Math.abs(a - b) < 1e-9, `${a} is not ${b}`);
const must = <T extends { ok: boolean }>(r: T): T => { assert.ok(r.ok, JSON.stringify(r)); return r; };

describe("options", () => {
  test("the defaults: Biedronka, 50 pages, masło / mleko / kawa, a real run", () => {
    const r = script.parseArgs([]);
    assert.ok(r.ok);
    assert.deepEqual(r.options, { chain: "biedronka", maxPages: 50, items: ["masło", "mleko", "kawa"], out: undefined, dryRun: false, help: false });
    assert.equal(script.DEFAULT_MAX_PAGES, 50);
    assert.equal(script.HARD_MAX_PAGES, 60);
  });

  test("every option, spelled with a space or with =; items trimmed, empties and repeats dropped", () => {
    const a = script.parseArgs(["--chain", "lidl", "--max-pages", "30", "--items", "masło, mleko ,, kawa,MLEKO", "--out", "/tmp/review", "--dry-run"]);
    assert.ok(a.ok);
    assert.deepEqual(a.options, { chain: "lidl", maxPages: 30, items: ["masło", "mleko", "kawa"], out: "/tmp/review", dryRun: true, help: false });
    const b = script.parseArgs(["--chain=dino", "--max-pages=1", "--items=pieluchy rozmiar 4", "--out=/tmp/x"]);
    assert.ok(b.ok);
    assert.deepEqual(b.options, { chain: "dino", maxPages: 1, items: ["pieluchy rozmiar 4"], out: "/tmp/x", dryRun: false, help: false });
    for (const chain of ["biedronka", "lidl", "dino", "rossmann"]) assert.ok(script.parseArgs(["--chain", chain]).ok, chain);
    const h = script.parseArgs(["-h"]);
    assert.ok(h.ok && h.options.help);
  });

  test("--max-pages: 1 to 60, a whole number; 60 is the hard cap and more is refused, not trimmed", () => {
    for (const n of ["1", "50", "60"]) assert.ok(script.parseArgs(["--max-pages", n]).ok, n);
    for (const n of ["61", "100", "1000", "0", "-1", "5.5", "abc", "", "1e2", "0050x"]) {
      const r = script.parseArgs(["--max-pages", n]);
      assert.ok(!r.ok, n);
      assert.match(r.error, /1 to 60/, n);
    }
  });

  test("the other refusals: chain, items, missing values, stray words; nothing typed is echoed back", () => {
    const refused = (argv: string[]) => { const r = script.parseArgs(argv); assert.ok(!r.ok, argv.join(" ")); return r.error; };
    assert.match(refused(["--chain", "kaufland"]), /one of: biedronka, lidl, dino, rossmann, zabka/);
    assert.match(refused(["--chain"]), /--chain needs a value/);
    assert.match(refused(["--items", "--dry-run"]), /--items needs a value/);
    assert.match(refused(["--items", ", ,"]), /1 to 12 items/);
    assert.match(refused(["--items", Array.from({ length: 13 }, (_, i) => `rzecz${i}`).join(",")]), /1 to 12 items/);
    assert.ok(script.parseArgs(["--items", Array.from({ length: 12 }, (_, i) => `rzecz${i}`).join(",")]).ok);
    assert.match(refused(["--items", "x".repeat(61)]), /at most 60 characters/);
    assert.match(refused(["--items", "masło\u0007"]), /control characters/);
    assert.match(refused(["--out", " "]), /--out needs a folder/);
    assert.match(refused(["--dry-run=yes"]), /takes no value/);
    assert.match(refused(["--frobnicate"]), /Unknown option --frobnicate/);
    // A key typed where it doesn't belong never comes back in the message.
    for (const argv of [["sk-ant-SECRET-1"], ["--api-key", "sk-ant-SECRET-2"], ["--api-key=sk-ant-SECRET-3"], ["--sk-ant-SECRET-4"], ["--chain=sk-ant-SECRET-5"]]) {
      assert.doesNotMatch(refused(argv), /SECRET/, argv.join(" "));
    }
  });
});

describe("the key", () => {
  test("a real run refuses to start without ANTHROPIC_API_KEY, with a plain message", () => {
    for (const env of [{}, { ANTHROPIC_API_KEY: "" }, { ANTHROPIC_API_KEY: "   " }]) {
      const r = script.checkKey(env, false);
      assert.equal(r.ok, false);
      assert.match(r.error!, /ANTHROPIC_API_KEY is not set/);
      assert.match(r.error!, /--dry-run/);
    }
    assert.deepEqual(script.checkKey({ ANTHROPIC_API_KEY: " sk-test " }, false), { ok: true, key: "sk-test" });
  });

  test("a dry run needs no key, and does not take one even when it is set", () => {
    assert.deepEqual(script.checkKey({}, true), { ok: true });
    assert.deepEqual(script.checkKey({ ANTHROPIC_API_KEY: "sk-test" }, true), { ok: true });
  });
});

describe("cost", () => {
  test("Haiku 5.5's published price: $0.10 per million input tokens, $0.50 per million output tokens", () => {
    assert.deepEqual(script.PRICE, { model: "claude-haiku-5-5", inputPerMillionUsd: 0.1, outputPerMillionUsd: 0.5, promptTokensUpTo: 100_000 });
    closeTo(script.estimateCost({ inputTokens: 1_000_000, outputTokens: 0 }), 0.1);
    closeTo(script.estimateCost({ inputTokens: 0, outputTokens: 1_000_000 }), 0.5);
    closeTo(script.estimateCost({ inputTokens: 300_000, outputTokens: 25_000 }), 0.0425);
    closeTo(script.estimateCost({ inputTokens: 0, outputTokens: 0 }), 0);
  });

  test("the worst case for n pages: the full image budget, the instructions' allowance and the full reply, on every page", () => {
    const { imageTokens, overheadTokens, maxOutputTokens } = script.WORST_CASE;
    assert.equal(maxOutputTokens, 8000, "the reader's own max_tokens");
    closeTo(script.worstCaseCost(1), ((imageTokens + overheadTokens) * 0.1 + maxOutputTokens * 0.5) / 1_000_000);
    closeTo(script.worstCaseCost(50), 50 * script.worstCaseCost(1));
    closeTo(script.worstCaseCost(50), 0.23392);
    closeTo(script.worstCaseCost(0), 0);
    closeTo(script.worstCaseCost(2, { imageTokens: 1000, overheadTokens: 0, maxOutputTokens: 1000 }), (2 * 1000 * 0.1 + 2 * 1000 * 0.5) / 1_000_000);
  });

  test("dollars are shown with four decimals when small", () => {
    assert.equal(script.formatUsd(0.0425), "$0.0425");
    assert.equal(script.formatUsd(0.23392), "$0.23");
    assert.equal(script.formatUsd(0), "$0.0000");
  });
});

describe("the folder", () => {
  const repo = fresh("repo");
  const outside = fresh("outside");
  mkdirSync(repo, { recursive: true });
  mkdirSync(outside, { recursive: true });

  test("the script's idea of the repository root is the real one (CLAUDE.md and the server beside it)", () => {
    assert.ok(existsSync(path.join(script.REPO_ROOT, "CLAUDE.md")));
    assert.ok(existsSync(path.join(script.REPO_ROOT, "server", "messaging", "scripts", "leaflet-eval.mjs")));
  });

  test("inside the repository is refused, whichever way it is spelled; outside is fine", () => {
    // Only resolveOutDir is asked here (it writes nothing), so this can't put a file in the real repository.
    for (const dir of [
      path.join(script.REPO_ROOT, "review"), script.REPO_ROOT, path.join(script.REPO_ROOT, "server", "messaging", "tmp", "deep", "er"),
      path.join(script.REPO_ROOT, "server", "..", "docs", "x"), path.relative(process.cwd(), path.join(script.REPO_ROOT, "x")),
    ]) {
      const r = script.resolveOutDir(dir);
      assert.equal(r.ok, false, dir);
      assert.match(r.error!, /inside the repository/);
    }
    const ok = script.resolveOutDir(path.join(tmpdir(), "somewhere-else"));
    assert.ok(ok.ok);
    assert.equal(ok.dir, path.join(tmpdir(), "somewhere-else"));
  });

  test("a symlink out of a folder that looks outside can't smuggle the files into the repository", () => {
    symlinkSync(repo, path.join(outside, "link"));
    assert.equal(script.resolveOutDir(path.join(outside, "link", "review"), { repoRoot: repo }).ok, false);
    assert.equal(script.resolveOutDir(path.join(outside, "review"), { repoRoot: repo }).ok, true);
    assert.equal(script.resolveOutDir(path.join(repo, "a", "b"), { repoRoot: repo }).ok, false);
    assert.equal(script.resolveOutDir(repo, { repoRoot: repo }).ok, false);
    assert.equal(script.resolveOutDir(`${repo}-sibling`, { repoRoot: repo }).ok, true, "a folder that only starts with the repo's name is not inside it");
  });

  test("without --out the default is a new folder under the system temp directory, never in the repo", () => {
    const r = must(script.resolveOutDir(undefined, { tmp: outside, repoRoot: repo, now: new Date("2026-10-24T10:00:00Z") }));
    assert.equal(r.dir, path.join(outside, "doddy-leaflet-eval-20261024T100000Z"));
    assert.equal(script.resolveOutDir(undefined, { tmp: path.join(repo, "tmp"), repoRoot: repo }).ok, false, "a temp directory inside the repo is refused too");
  });
});

// ---------- the sheet and the JSON ----------

const P1: Product = {
  name: "Masło Extra 82%", size: "200 g", price: { minor: 499, currency: "PLN" }, regularPrice: { minor: 649, currency: "PLN" }, lowest30d: null,
  printedUnitPrice: "24,95 zł/kg", conditions: ["z aplikacją Moja Biedronka", "max 4 szt."], validFrom: "22.10", validTo: "26.10",
  unitPrice: { minor: 2495, per: "kg" }, check: false, doubts: [], matchedItems: ["masło"],
};
const P2: Product = {
  name: "Mleko | UHT <b>3,2%</b>", size: "1 l", price: { minor: 329, currency: "PLN" }, regularPrice: null, lowest30d: null, printedUnitPrice: null,
  conditions: [], validFrom: null, validTo: null, unitPrice: { minor: 329, per: "l" }, check: true, doubts: ["low_confidence_read"], matchedItems: [],
};
const fakeResult = (): Result => ({
  startedAt: "2026-10-24T10:00:00.000Z", chain: "biedronka", items: ["masło", "mleko"], model: "claude-haiku-5-5", maxPages: 50, status: "read",
  leaflets: [{ title: "Codziennie niskie ceny P - oferta od 22.10", url: "https://www.biedronka.pl/pl/press,id,x,title,y", validFrom: "2026-10-22", strategy: "all", pagesAvailable: 85 }],
  pages: [
    { leaflet: 0, number: 1, url: "https://www.biedronka.pl/pl/press,id,x,title,y", imageUrl: "https://images.biedronka.cloud/a/1.png", status: "read", products: [P1, P2] },
    { leaflet: 0, number: 2, url: "https://www.biedronka.pl/pl/press,id,x,title,y", imageUrl: "https://images.biedronka.cloud/a/2.png", status: "read", products: [] },
    { leaflet: 0, number: 3, url: "https://www.biedronka.pl/pl/press,id,x,title,y", imageUrl: "https://images.biedronka.cloud/a/3.png", status: "blocked", reason: "http_403", products: [] },
  ],
  totals: {
    pagesPlanned: 3, pagesSent: 2, pagesRead: 2, pagesNotRead: 1, byStatus: { blocked: 1 }, products: 2, flagged: 1,
    inputTokens: 12_345, outputTokens: 678, estimatedCostUsd: script.estimateCost({ inputTokens: 12_345, outputTokens: 678 }), elapsedMs: 83_000,
  },
  pricing: { ...script.PRICE, appliesToRunModel: true },
});

describe("the review sheet and the JSON", () => {
  test("the Markdown starts with the notice: facts from a leaflet, for the owner's review only, delete afterwards, ADR-609", () => {
    const md = script.renderMarkdown(fakeResult());
    const first = md.split("\n")[0]!;
    assert.match(first, /^> \*\*Notice:\*\* This file holds facts read from a chain's leaflet/);
    assert.match(first, /quality review only/);
    assert.match(first, /Delete it afterwards/);
    assert.match(first, /keeps no leaflet data \(ADR-609\)/);
    assert.match(first, /no page images/);
  });

  test("the run's facts: leaflet, pages, tokens and the cost at Haiku 5.5's prices, time taken", () => {
    const md = script.renderMarkdown(fakeResult());
    assert.match(md, /^# Leaflet reading review: biedronka$/m);
    assert.match(md, /took 1 min 23 s/);
    assert.match(md, /Result: \*\*read\*\*\./);
    assert.match(md, /Items looked for: masło, mleko\./);
    assert.match(md, /Codziennie niskie ceny P - oferta od 22\.10, 2026-10-22 to \?, 85 pages/);
    assert.match(md, /Pages: 3 planned \(at most 50\), 2 read, 1 not read \(1 blocked\)\./);
    assert.match(md, /Products returned: 2, 1 of them with the `check` flag\./);
    assert.match(md, /Tokens used: 12,345 in, 678 out\. Estimated cost: \$0\.0016 at claude-haiku-5-5's published prices \(\$0\.10 \/ \$0\.50 per million tokens, prompts up to 100,000 tokens\)\./);
    const other = script.renderMarkdown({ ...fakeResult(), model: "claude-sonnet-5-5", pricing: { ...script.PRICE, appliesToRunModel: false } });
    assert.match(other, /the run used claude-sonnet-5-5, so treat this as a rough figure/);
  });

  test("per page: the addresses (never an image), a row per product with the code's unit price and check flag, blocked pages said so", () => {
    const md = script.renderMarkdown(fakeResult());
    assert.match(md, /^## Page 1$/m);
    assert.match(md, /Address: `https:\/\/www\.biedronka\.pl\/pl\/press,id,x,title,y`; page image address: `https:\/\/images\.biedronka\.cloud\/a\/1\.png`/);
    assert.ok(md.includes("| 1 | Masło Extra 82% | 200 g | 4,99 zł | 6,49 zł | - | 24,95 zł/kg | 24,95 zł/kg | z aplikacją Moja Biedronka; max 4 szt. | 22.10-26.10 | - | masło | [ ] |"));
    assert.ok(md.includes("| 2 | Mleko \\| UHT &lt;b&gt;3,2%&lt;/b&gt; | 1 l | 3,29 zł | - | - | - | 3,29 zł/l | - | - | CHECK (low_confidence_read) | none | [ ] |"),
      "a pipe or a tag in a name from a page can't break out of its cell");
    assert.match(md, /^## Page 2$/m);
    assert.match(md, /The reader returned no products for this page\./);
    assert.match(md, /^Not read: blocked \(http_403\)\.$/m);
    assert.equal((md.match(/Missed on this page: _{8}/g) ?? []).length, 2, "a line to write what the reader missed, on each page that was read");
  });

  test("a result without its own notice still starts with it; the JSON carries it first and the same facts", () => {
    const r = fakeResult();
    const json = script.renderJson(r);
    const parsed = JSON.parse(json) as Record<string, unknown> & Result;
    assert.equal(Object.keys(parsed)[0], "notice");
    assert.equal(parsed.notice, script.NOTICE);
    assert.deepEqual(parsed.pages, r.pages);
    assert.deepEqual(parsed.totals, r.totals);
    assert.ok(json.endsWith("}\n"));
    assert.match(script.renderMarkdown({ ...r, notice: undefined }), /^> \*\*Notice:\*\* This file holds facts read from a chain's leaflet/);
  });

  test("a blocked chain's sheet says blocked and why, with no pages", () => {
    const r: Result = { ...fakeResult(), status: "blocked", reason: "blocked:robots", leaflets: [], pages: [], totals: { ...fakeResult().totals, pagesPlanned: 0, pagesSent: 0, pagesRead: 0, pagesNotRead: 0, byStatus: {}, products: 0, flagged: 0, inputTokens: 0, outputTokens: 0, estimatedCostUsd: 0 } };
    const md = script.renderMarkdown(r);
    assert.match(md, /Result: \*\*blocked\*\* \(blocked:robots\)\./);
    assert.doesNotMatch(md, /^## Page/m);
  });

  test("writeReport: one .json and one .md in the folder, private, never over an existing file", () => {
    const dir = fresh("out");
    const files = script.writeReport(dir, fakeResult());
    assert.deepEqual(readdirSync(dir).sort(), ["leaflet-eval-biedronka-20261024T100000Z.json", "leaflet-eval-biedronka-20261024T100000Z.md"]);
    assert.equal(files.json, path.join(dir, "leaflet-eval-biedronka-20261024T100000Z.json"));
    assert.equal(files.markdown, path.join(dir, "leaflet-eval-biedronka-20261024T100000Z.md"));
    assert.equal(readFileSync(files.markdown, "utf8"), script.renderMarkdown(fakeResult()));
    assert.equal(readFileSync(files.json, "utf8"), script.renderJson(fakeResult()));
    assert.equal(statSync(files.json).mode & 0o777, 0o600);
    assert.equal(statSync(files.markdown).mode & 0o777, 0o600);
    assert.throws(() => script.writeReport(dir, fakeResult()), /EEXIST/);
  });

  test("writeReport refuses a folder inside the repository and creates nothing there", () => {
    const repo = fresh("repo");
    mkdirSync(repo);
    const inside = path.join(repo, "review");
    assert.throws(() => script.writeReport(inside, fakeResult(), { repoRoot: repo }), /inside the repository/);
    assert.equal(existsSync(inside), false);
  });
});

// ---------- the whole run, against the fake web and the fake model ----------

const NOW = new Date("2026-10-24T10:00:00.000Z");
const KEY = "sk-ant-test-SECRET-0123456789";
const IMAGE_HOST = "https://images.biedronka.cloud/";

/** A tripwire for what must not be touched: any use throws. */
const untouchable = new Proxy({}, { get() { throw new Error("this must not be used"); } });

function harness(web: FakeWeb = chainsWeb()) {
  const io = { out: "", err: "" };
  return {
    web, io,
    fetcher: new PoliteFetcher({ fetch: web.fetch }),
    sinks: { stdout: (s: string) => { io.out += s; }, stderr: (s: string) => { io.err += s; }, now: () => NOW },
  };
}
/** Everything asked of the image host, robots.txt included; and the page images alone. */
const imageHostRequests = (web: FakeWeb) => web.requests.filter((r) => r.url.startsWith(IMAGE_HOST)).map((r) => r.url);
const imageRequests = (web: FakeWeb) => imageHostRequests(web).filter((u) => !u.endsWith("/robots.txt"));
const filesIn = (dir: string) => (existsSync(dir) ? readdirSync(dir).sort() : []);
const jsonIn = (dir: string): Result => JSON.parse(readFileSync(path.join(dir, filesIn(dir).find((f) => f.endsWith(".json"))!), "utf8")) as Result;

describe("a run against the fakes", () => {
  test("a real run: pages in order up to --max-pages, each product with the code's unit price and flags, two files and nothing else", async () => {
    const modules = await script.loadDealsModules();
    const { web, io, fetcher, sinks } = harness();
    const model = new FakeModel()
      .page("biedronka:1", { products: [read({ name: "Masło Extra 82%", size: "200 g", price: "4,99", regularPrice: "6,49", unitPrice: "24,95 zł/kg",
        conditions: [{ kind: "app", quantity: null, text: null, price: null, percent: null }, { kind: "limit", quantity: 4, text: null, price: null, percent: null }], validFrom: "22.10", validTo: "26.10" })] })
      .page("biedronka:2", { products: [read({ name: "Masło Polskie 200 g", price: "5,99", unitPrice: "19,99 zł/kg" })] })
      .page("biedronka:3", "refuse")
      .page("biedronka:4", "throw")
      .page("biedronka:5", { products: [read({ name: "Mleko UHT 3,2% 1 l", price: "3,29", confidence: "low" }), read({ name: "Chleb żytni", price: "4,50" })] });
    const out = fresh("run");
    const code = await script.main(["--max-pages", "5", "--items", "masło,mleko", "--out", out], { ...sinks, env: { ANTHROPIC_API_KEY: KEY }, modules, fetcher, model });
    assert.equal(code, 0, io.err);

    // Never more than --max-pages, in leaflet order; the model was given the items and the chain.
    assert.deepEqual(model.reads.map((r) => r.marker).sort(), ["biedronka:1", "biedronka:2", "biedronka:3", "biedronka:4", "biedronka:5"]);
    assert.equal(imageRequests(web).length, 5);
    assert.deepEqual(model.reads[0]!.queries, ["masło", "mleko"]);
    assert.ok(model.reads.every((r) => r.chain === "biedronka"));

    // Two files, no image anywhere.
    const files = filesIn(out);
    assert.deepEqual(files, ["leaflet-eval-biedronka-20261024T100000Z.json", "leaflet-eval-biedronka-20261024T100000Z.md"]);
    for (const f of files) {
      const text = readFileSync(path.join(out, f), "latin1");
      assert.doesNotMatch(text, /DODDYTEST|PNG/, `${f} holds no page image`);
      assert.doesNotMatch(text, /SECRET|sk-ant/, `${f} holds no key`);
    }
    assert.doesNotMatch(io.out + io.err, /SECRET|sk-ant/, "the key is never printed");

    const r = jsonIn(out);
    assert.equal(r.status, "read");
    assert.deepEqual(r.pages.map((p) => [p.number, p.status]), [[1, "read"], [2, "read"], [3, "refused"], [4, "error"], [5, "read"]]);
    assert.equal(r.pages[3]!.reason, "Error");
    assert.ok(r.pages.every((p) => p.imageUrl.startsWith(IMAGE_HOST) && p.url.startsWith("https://www.biedronka.pl/")), "addresses only");
    assert.deepEqual(r.totals, {
      pagesPlanned: 5, pagesSent: 5, pagesRead: 3, pagesNotRead: 2, byStatus: { refused: 1, error: 1 }, products: 4, flagged: 2,
      inputTokens: 8000, outputTokens: 600, estimatedCostUsd: script.estimateCost({ inputTokens: 8000, outputTokens: 600 }), elapsedMs: 0,
    });

    const [butter] = r.pages[0]!.products;
    assert.deepEqual(butter, {
      name: "Masło Extra 82%", size: "200 g", price: { minor: 499, currency: "PLN" }, regularPrice: { minor: 649, currency: "PLN" }, lowest30d: null,
      printedUnitPrice: "24,95 zł/kg", conditions: ["z aplikacją Moja Biedronka", "max 4 szt."], validFrom: "22.10", validTo: "26.10",
      unitPrice: { minor: 2495, per: "kg" }, check: false, doubts: [], matchedItems: ["masło"], conditionKinds: ["app", "limit"],
    });
    const [wrongUnit] = r.pages[1]!.products;
    assert.deepEqual(wrongUnit!.unitPrice, { minor: 2995, per: "kg" }, "the unit price is the code's, not the printed 19,99");
    assert.equal(wrongUnit!.check, true);
    assert.deepEqual(wrongUnit!.doubts, ["unit_price_disagrees"]);
    const [milk, bread] = r.pages[4]!.products;
    assert.deepEqual(milk!.doubts, ["low_confidence_read"]);
    assert.deepEqual(milk!.matchedItems, ["mleko"]);
    assert.deepEqual(bread!.matchedItems, [], "the service would drop a product that matches no item");

    const md = readFileSync(path.join(out, "leaflet-eval-biedronka-20261024T100000Z.md"), "utf8");
    assert.match(md.split("\n")[0]!, /^> \*\*Notice:\*\* .*Delete it afterwards/);
    assert.match(md, /Not read: refused\./);
    assert.match(md, /Not read: error \(Error\)\./);
    assert.match(io.out, /Review sheet: .*\.md/);
    assert.match(io.out, /delete them afterwards/);
  });

  test("never more than the hard cap, even when asked for more through the function itself", async () => {
    const modules = await script.loadDealsModules();
    // A leaflet of 85 pages (the saved fixture is trimmed to a few).
    const web = chainsWeb();
    const pages = Array.from({ length: 85 }, (_, i) => ({ page: i, image: `${IMAGE_HOST}big/${i + 1}.png` }));
    web.on(BIEDRONKA_API, { headers: { "content-type": "application/json" }, body: JSON.stringify({ images_mobile: pages }) });
    for (const p of pages) web.on(p.image, { headers: { "content-type": "image/png" }, body: fakePng(1146, 1800, `big:${p.page + 1}`) });
    const { fetcher } = harness(web);
    const model = new FakeModel();
    const r = await script.evaluate({ chain: "biedronka", maxPages: 1000, items: ["masło"], model: "claude-haiku-5-5" }, { modules, fetcher, model, now: () => NOW });
    assert.equal(r.leaflets[0]!.pagesAvailable, 85, "the leaflet has more; only 60 were read");
    assert.equal(model.reads.length, 60);
    assert.equal(imageRequests(web).length, 60);
    assert.equal(r.totals.pagesPlanned, 60);
    assert.equal(r.maxPages, 60);
    assert.deepEqual(r.pages.map((p) => p.number), Array.from({ length: 60 }, (_, i) => i + 1), "the first 60, in order");
  });

  test("--dry-run: no key, no model, no image fetched, nothing written; the pages and the worst case are printed", async () => {
    const modules = await script.loadDealsModules();
    const { web, io, fetcher, sinks } = harness();
    const model = new FakeModel();
    const out = fresh("dry");
    const code = await script.main(["--dry-run", "--max-pages", "3", "--out", out], { ...sinks, env: {}, modules, fetcher, model });
    assert.equal(code, 0, io.err);
    assert.equal(model.reads.length, 0);
    assert.equal(imageRequests(web).length, 0, "no page image is downloaded");
    assert.equal(existsSync(out), false, "nothing is written");
    assert.match(io.out, /^Dry run: /);
    assert.match(io.out, /Would read 3 pages \(at most 3\), in leaflet order:/);
    for (const n of [1, 2, 3]) assert.match(io.out, new RegExp(`page +${n}  https://images\\.biedronka\\.cloud/`));
    assert.doesNotMatch(io.out, /page +4 /);
    assert.match(io.out, /Worst case: \$0\.0\d+ for these pages/);
    assert.match(io.out, /\$0\.10 \/ \$0\.50 per million tokens/);
    assert.match(io.out, /Items: masło, mleko, kawa/);
    // The same with a key in the environment: a dry run still doesn't use it.
    const again = harness();
    assert.equal(await script.main(["--dry-run"], { ...again.sinks, env: { ANTHROPIC_API_KEY: KEY }, modules, fetcher: again.fetcher, model }), 0);
    assert.equal(model.reads.length, 0);
    assert.doesNotMatch(again.io.out + again.io.err, /SECRET|sk-ant/);
  });

  test("a chain that blocks is reported as blocked, asked once, never worked around", async () => {
    const modules = await script.loadDealsModules();
    // The chain's own page says 403.
    const blockedPage = harness();
    blockedPage.web.on("https://www.biedronka.pl/pl/w-tym-tygodniu", { status: 403, body: "no" });
    const model = new FakeModel();
    const out = fresh("blocked");
    const code = await script.main(["--out", out], { ...blockedPage.sinks, env: { ANTHROPIC_API_KEY: KEY }, modules, fetcher: blockedPage.fetcher, model });
    assert.equal(code, 1);
    assert.equal(blockedPage.web.hits("https://www.biedronka.pl/pl/w-tym-tygodniu"), 1, "not retried");
    assert.equal(model.reads.length, 0);
    const r = jsonIn(out);
    assert.equal(r.status, "blocked");
    assert.match(r.reason!, /http_403/);
    assert.deepEqual(r.pages, []);
    assert.match(blockedPage.io.out, /biedronka: blocked/);

    // The page images answer 403: every page blocked, each asked once, the model never called.
    const blockedImages = harness();
    for (const url of [...blockedImages.web.routes.keys()]) if (url.startsWith(IMAGE_HOST)) blockedImages.web.on(url, { status: 403, body: "no" });
    const out2 = fresh("blocked-images");
    assert.equal(await script.main(["--max-pages", "4", "--out", out2], { ...blockedImages.sinks, env: { ANTHROPIC_API_KEY: KEY }, modules, fetcher: blockedImages.fetcher, model }), 1);
    assert.equal(imageRequests(blockedImages.web).length, 4);
    assert.equal(model.reads.length, 0);
    const r2 = jsonIn(out2);
    assert.equal(r2.status, "blocked");
    assert.deepEqual(r2.totals.byStatus, { blocked: 4 });

    // robots.txt disallows the image host: nothing is fetched from it but robots.txt itself.
    const disallowed = harness();
    disallowed.web.robots("https://images.biedronka.cloud", "User-agent: *\nDisallow: /\n");
    const out3 = fresh("robots");
    assert.equal(await script.main(["--max-pages", "4", "--out", out3], { ...disallowed.sinks, env: { ANTHROPIC_API_KEY: KEY }, modules, fetcher: disallowed.fetcher, model }), 1);
    assert.deepEqual(imageHostRequests(disallowed.web), [`${IMAGE_HOST}robots.txt`]);
    assert.equal(model.reads.length, 0);
    assert.deepEqual(jsonIn(out3).totals.byStatus, { disallowed: 4 });
  });

  test("when the API refuses the key the run stops, rather than fetching and failing 50 times", async () => {
    const modules = await script.loadDealsModules();
    const { web, io, fetcher, sinks } = harness();
    let calls = 0;
    class Refused extends FakeModel {
      override async readPage(): Promise<ModelReply<PageOutput>> { calls++; throw Object.assign(new Error(`invalid x-api-key ${KEY}`), { status: 401 }); }
    }
    const out = fresh("auth");
    const code = await script.main(["--max-pages", "40", "--out", out], { ...sinks, env: { ANTHROPIC_API_KEY: KEY }, modules, fetcher, model: new Refused() });
    assert.equal(code, 1);
    assert.ok(calls >= 1 && calls <= 4, `${calls} calls: at most one batch`);
    assert.ok(imageRequests(web).length <= 8);
    const r = jsonIn(out);
    assert.equal(r.status, "failed");
    assert.equal(r.reason, "the API refused the key; stopped");
    assert.ok(r.pages.some((p) => p.reason === "api_401"));
    assert.doesNotMatch(io.out + io.err + readFileSync(path.join(out, filesIn(out)[0]!), "utf8"), /SECRET|sk-ant|invalid x-api-key/, "nothing the API said is kept");
  });

  test("Rossmann publishes no page images: nothing for the reader to judge, said plainly", async () => {
    const modules = await script.loadDealsModules();
    const { io, fetcher, sinks } = harness();
    const model = new FakeModel();
    const out = fresh("rossmann");
    const code = await script.main(["--chain", "rossmann", "--items", "pieluchy rozmiar 4", "--out", out], { ...sinks, env: { ANTHROPIC_API_KEY: KEY }, modules, fetcher, model });
    assert.equal(code, 1);
    assert.equal(model.reads.length, 0);
    assert.equal(jsonIn(out).status, "no_pages");
    assert.match(io.out, /rossmann\.pl as a search term/);
  });
});

describe("what stops before anything is fetched or sent", () => {
  const stops = async (argv: string[], env: Record<string, string | undefined>, extra: Partial<Io> = {}) => {
    const io = { out: "", err: "" };
    const code = await script.main(argv, {
      env, modules: untouchable, fetcher: untouchable, model: untouchable, now: () => NOW,
      stdout: (s) => { io.out += s; }, stderr: (s) => { io.err += s; }, ...extra,
    });
    return { code, ...io };
  };

  test("no key, no --dry-run: exit 2 and the message; the web, the code and the model are never touched", async () => {
    const r = await stops([], {});
    assert.equal(r.code, 2);
    assert.match(r.err, /ANTHROPIC_API_KEY is not set/);
    assert.equal(r.out, "");
    assert.equal((await stops(["--chain", "lidl", "--max-pages", "5"], { ANTHROPIC_API_KEY: "" })).code, 2);
  });

  test("--out inside the repository: exit 2, even with a key and even for a dry run", async () => {
    // A stand-in repository in the temp area, so that a failure of this rule could never write into the real one.
    const repoRoot = fresh("repo");
    mkdirSync(repoRoot);
    const dir = path.join(repoRoot, "leaflet-review-never-made");
    for (const argv of [["--out", dir], ["--dry-run", "--out", dir]]) {
      const r = await stops(argv, { ANTHROPIC_API_KEY: KEY }, { repoRoot });
      assert.equal(r.code, 2);
      assert.match(r.err, /inside the repository/);
      assert.doesNotMatch(r.err, /SECRET|sk-ant/);
    }
    assert.equal(existsSync(dir), false);
  });

  test("bad options: exit 2 with the usage; --help: exit 0 with the usage; a bad model id is refused", async () => {
    for (const argv of [["--max-pages", "61"], ["--chain", "kaufland"], ["--bogus"], [KEY]]) {
      const r = await stops(argv, { ANTHROPIC_API_KEY: KEY });
      assert.equal(r.code, 2, argv.join(" "));
      assert.match(r.err, /Usage: node scripts\/leaflet-eval\.mjs/);
      assert.doesNotMatch(r.err, /SECRET|sk-ant/);
    }
    const help = await stops(["--help"], {});
    assert.equal(help.code, 0);
    assert.match(help.out, /--max-pages N .*hard cap/);
    assert.match(help.out, /never inside the repository/);
    const model = await stops([], { ANTHROPIC_API_KEY: KEY, DEALS_VISION_MODEL: "Not A Model!" });
    assert.equal(model.code, 2);
    assert.match(model.err, /DEALS_VISION_MODEL is not a model id/);
  });
});
