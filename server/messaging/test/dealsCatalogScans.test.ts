// Every leaflet page, eventually (13 Nov 2026; decision docs/decisions/2026-11-13-leaflet-results-and-deal-watches.md).
// The live scans of 12 and 13 Nov: Lidl 160 of 290 pages a scan (about 700,000 input tokens), E.Leclerc cut at 120 of its
// pages every time, the same Biedronka pages failing as `image_failed` (a cold image comes as a 6 MB PNG, over the 3 MB
// cap; one opening-hours page is a 26 MB PNG its host won't convert). A scan now reads the pages never tried first and
// those of running leaflets first, stays inside a daily token budget, asks for an image again after a moment and then in
// a smaller rendition, and records which pages are missing and why. Fake adapters, web and reader; the database half
// runs with TEST_DATABASE_URL.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import {
  CATALOG_CHAINS, catalogPageKey, DbCatalogStore, fetchPageImage, IMAGE_RETRY_WAIT_MS, materialFromSnapshot, missingSummary, readingOrder,
  runCatalogPass, scanChain, type CatalogPageRead, type MissingWhy, type PageReadStore, type StoredPageRead, type TokenBudget,
} from "../src/deals/catalog.js";
import { leclercLeaflets, LECLERC_CATALOG_MAX_PAGES, LECLERC_MAX_PAGES, type ListedLeaflet } from "../src/deals/chains/leclerc.js";
import { parseFlyer } from "../src/deals/chains/lidl.js";
import type { FetchResult, PageFetcher } from "../src/deals/fetcher.js";
import type { ChainAdapter, ChainContext, ChainRead, DealsModelApi, LeafletRead, ModelReply, PageImage, ReadChain } from "../src/deals/types.js";
import type { PageOutput } from "../src/deals/vision.js";
import type { Db } from "../src/db.js";
import { fakePng, FakeModel, markerOf, read } from "./dealsFakes.js";
import { dbSkip, freshDb } from "./helpers.js";

const NOW = new Date("2026-11-13T06:00:00.000Z");
const TODAY = "2026-11-13";

function leaflet(chain: string, pages: number, dates: { validFrom?: string; validTo?: string } = { validFrom: "2026-11-10", validTo: "2026-11-16" },
  url = `https://${chain}.example/gazetka`): LeafletRead {
  return {
    leaflet: { title: "Gazetka", url, ...dates },
    products: [],
    pages: Array.from({ length: pages }, (_, i) => ({ number: i + 1, imageUrl: `https://img.example/${chain}/${i + 1}.png`, url: `${url}#${i + 1}` })),
    strategy: "all",
  };
}

class FakeAdapter implements ChainAdapter {
  readonly hosts = ["img.example"];
  calls: ChainContext[] = [];
  constructor(readonly chain: ReadChain, public answer: ChainRead) {}
  async read(ctx: ChainContext): Promise<ChainRead> { this.calls.push(ctx); return this.answer; }
}

/** Page images by address; `answers` overrides one address with a list of answers, one per request. */
class ImageWeb implements PageFetcher {
  readonly fetched: string[] = [];
  readonly answers = new Map<string, FetchResult[]>();
  async fetchPage(url: string): Promise<FetchResult> {
    this.fetched.push(url);
    const queued = this.answers.get(url);
    if (queued?.length) return queued.length > 1 ? queued.shift()! : queued[0]!;
    const m = /\/([a-z]+)\/(\d+)(-small)?\.png$/.exec(url);
    if (!m) return { kind: "failed", reason: "not_found" };
    return { kind: "ok", status: 200, contentType: "image/png", body: fakePng(1200, 1700, `${m[1]}:${m[2]}${m[3] ?? ""}`), finalUrl: url };
  }
}

const TOO_LARGE: FetchResult = { kind: "failed", reason: "too_large" };

class CatalogModel extends FakeModel {
  readonly catalogReads: string[] = [];
  async readCatalogPage(req: { image: PageImage; chain: ReadChain }, signal: AbortSignal): Promise<ModelReply<PageOutput>> {
    this.catalogReads.push(markerOf(req.image.data));
    const r = await this.readPage({ image: req.image, chain: req.chain, queries: [] }, signal);
    this.reads.pop();
    return r;
  }
}
/** The fake reader spends 2,000 input and 150 output tokens a page. */
const PAGE_COST = 2150;

class MemoryPageReads implements PageReadStore {
  readonly rows = new Map<string, StoredPageRead>();
  async get(chain: ReadChain, keys: readonly string[]) {
    const out = new Map<string, StoredPageRead>();
    for (const k of keys) { const r = this.rows.get(`${chain}|${k}`); if (r) out.set(k, r); }
    return out;
  }
  async putOk(chain: ReadChain, key: string, r: CatalogPageRead) {
    const { readAt: _at, ...kept } = r;
    this.rows.set(`${chain}|${key}`, { kind: "ok", read: kept, readAt: NOW.toISOString() });
  }
  async putFailed(chain: ReadChain, key: string, failure?: MissingWhy) {
    const held = this.rows.get(`${chain}|${key}`);
    if (held?.kind === "ok") return;
    this.rows.set(`${chain}|${key}`, { kind: "failed", attempts: (held?.attempts ?? 0) + 1, ...(failure ? { failure } : {}) });
  }
}

const sleeps: number[] = [];
const deps = (over: Partial<Parameters<typeof scanChain>[2]> = {}) => ({
  fetcher: new ImageWeb(), model: new CatalogModel() as DealsModelApi | undefined, pageReads: new MemoryPageReads(), today: TODAY, now: () => NOW,
  maxPages: 100, concurrency: 1, signal: new AbortController().signal, log: () => {},
  sleep: async (ms: number) => { sleeps.push(ms); }, ...over,
});

const budget = (chainLeft: number, allLeft = 1e9): TokenBudget & { spent: number[] } => {
  const spent: number[] = [];
  return { chainLeft, allLeft, spent, spend: async (n) => { spent.push(n); } };
};

describe("which pages a scan reads first", () => {
  test("never tried before tried once; running leaflets before those that start later; then leaflet and page order", () => {
    const leaflets = [leaflet("lidl", 2, { validFrom: "2026-11-17", validTo: "2026-11-23" }), leaflet("lidl", 2)];
    const job = (li: number, n: number, tried = false) => ({ li, page: leaflets[li]!.pages[n - 1]!, tried });
    const order = readingOrder([job(0, 1), job(0, 2), job(1, 2, true), job(1, 1)], leaflets, TODAY);
    assert.deepEqual(order.map((j) => [j.li, j.page.number, j.tried]), [[1, 1, false], [0, 1, false], [0, 2, false], [1, 2, true]]);
  });

  test("the cap takes the pages never tried: a page that failed once waits behind them, and the rest are recorded as not read yet", async () => {
    const d = deps({ maxPages: 2 });
    const l = leaflet("biedronka", 3);
    await d.pageReads.putFailed("biedronka", catalogPageKey(l, l.pages[0]!.imageUrl), "read_failed");
    const r = await scanChain("biedronka", new FakeAdapter("biedronka", { kind: "ok", leaflets: [l] }), d);
    assert.ok(r.kind === "ok");
    assert.deepEqual((d.model as CatalogModel).catalogReads, ["biedronka:2", "biedronka:3"]);
    assert.deepEqual(r.snapshot.missing, [{ leaflet: 0, page: 1, why: "not_read_yet" }]);
    assert.equal(r.snapshot.complete, false);
    assert.equal(missingSummary(r.snapshot.missing), "not_read_yet:1");
  });

  test("a scan asks the adapter for every leaflet and page (forCatalog), not one search's share", async () => {
    const adapter = new FakeAdapter("lidl", { kind: "ok", leaflets: [leaflet("lidl", 1)] });
    await scanChain("lidl", adapter, deps());
    assert.equal(adapter.calls[0]!.forCatalog, true);
    // E.Leclerc: a search still takes 120 pages; the catalog takes them all (up to 600).
    const listed: ListedLeaflet[] = Array.from({ length: 9 }, (_, i) => ({
      id: String(i), validFrom: "2026-11-10", validTo: "2026-11-20", alcohol: false,
      images: Array.from({ length: 25 }, (_, p) => `https://leclerc.pl/wp-content/uploads/${i}-${p}.jpg`),
    }));
    const pages = (max: number) => leclercLeaflets(listed, TODAY, max).leaflets.reduce((n, l) => n + l.pages.length, 0);
    assert.equal(pages(LECLERC_MAX_PAGES), 120);
    assert.equal(pages(LECLERC_CATALOG_MAX_PAGES), 225);
    assert.equal(leclercLeaflets(listed, TODAY, LECLERC_CATALOG_MAX_PAGES).dropped, 0);
  });
});

describe("the daily token budget", () => {
  test("a scan stops before a page that would pass what is left; the rest wait, and every page's cost is booked", async () => {
    const tokens = budget(3 * PAGE_COST);
    const d = deps({ tokens });
    const r = await scanChain("biedronka", new FakeAdapter("biedronka", { kind: "ok", leaflets: [leaflet("biedronka", 5)] }), d);
    assert.ok(r.kind === "ok");
    // The first page is reckoned at 6,000 tokens, then at what pages really cost here (2,150).
    assert.equal(r.stats.pagesRead, 3);
    assert.equal(r.stats.pagesOverBudget, 2);
    assert.deepEqual(tokens.spent, [PAGE_COST, PAGE_COST, PAGE_COST]);
    assert.ok(r.snapshot.reasons.includes("token_budget"));
    assert.deepEqual(r.snapshot.missing?.map((m) => [m.page, m.why]), [[4, "not_read_yet"], [5, "not_read_yet"]]);
  });

  test("the budget for all chains binds too; nothing left reads nothing, and the chain's own data is still kept", async () => {
    const none = await scanChain("biedronka", new FakeAdapter("biedronka", { kind: "ok", leaflets: [leaflet("biedronka", 2)] }),
      deps({ tokens: budget(1e9, 0) }));
    assert.ok(none.kind === "ok");
    assert.equal(none.stats.pagesRead, 0);
    assert.equal(none.stats.pagesOverBudget, 2);
    const data: LeafletRead = { ...leaflet("aldi", 1), strategy: "none", products: [
      { name: "Masło ekstra 200 g", price: { minor: 549, currency: "PLN" }, conditions: [], url: "https://aldi.example/p/1" }] };
    const aldi = await scanChain("aldi", new FakeAdapter("aldi", { kind: "ok", leaflets: [data] }), deps({ tokens: budget(0, 0) }));
    assert.ok(aldi.kind === "ok");
    assert.equal(aldi.snapshot.complete, true, "a data-only chain needs no tokens");
  });

  test("a page already read is never read again for the same leaflet version, budget or not", async () => {
    const d = deps();
    const adapter = new FakeAdapter("zabka", { kind: "ok", leaflets: [leaflet("zabka", 3)] });
    await scanChain("zabka", adapter, d);
    const tokens = budget(1e9);
    const again = await scanChain("zabka", adapter, { ...d, tokens });
    assert.ok(again.kind === "ok");
    assert.equal(again.stats.pagesKnown, 3);
    assert.deepEqual(tokens.spent, []);
    assert.equal((d.model as CatalogModel).catalogReads.length, 3);
  });
});

describe("page images that come too large", () => {
  test("asked for once more a moment later: a cold image host sends the full PNG first and the WebP next", async () => {
    sleeps.length = 0;
    const web = new ImageWeb();
    const url = "https://img.example/biedronka/2.png";
    web.answers.set(url, [TOO_LARGE, { kind: "ok", status: 200, contentType: "image/webp", body: fakePng(1146, 1800, "biedronka:2"), finalUrl: url }]);
    const d = deps({ fetcher: web });
    const r = await scanChain("biedronka", new FakeAdapter("biedronka", { kind: "ok", leaflets: [leaflet("biedronka", 3)] }), d);
    assert.ok(r.kind === "ok");
    assert.equal(r.snapshot.complete, true);
    assert.deepEqual(sleeps, [IMAGE_RETRY_WAIT_MS]);
    assert.equal(web.fetched.filter((u) => u === url).length, 2);
  });

  test("still too large: the chain's smaller rendition, when it publishes one", async () => {
    const web = new ImageWeb();
    web.answers.set("https://img.example/lidl/1.png", [TOO_LARGE]);
    const l = leaflet("lidl", 1);
    l.pages[0]!.smallerImageUrl = "https://img.example/lidl/1-small.png";
    const d = deps({ fetcher: web });
    const r = await scanChain("lidl", new FakeAdapter("lidl", { kind: "ok", leaflets: [l] }), d);
    assert.ok(r.kind === "ok");
    assert.deepEqual((d.model as CatalogModel).catalogReads, ["lidl:1-small"]);
    assert.equal(r.snapshot.complete, true);
    // Lidl publishes both: `zoom` (2400 px) is read, `image` (1200 px) is the smaller rendition.
    const flyer = parseFlyer({ success: true, flyer: { name: "Gazetka", offerStartDate: "2026-11-13", offerEndDate: "2026-11-16", pages: [
      { number: 1, zoom: "https://imgproxy.leaflets.schwarz/z/1.jpg", image: "https://imgproxy.leaflets.schwarz/i/1.jpg" },
      { number: 2, image: "https://imgproxy.leaflets.schwarz/i/2.jpg" },
    ] } }, "gazetka", TODAY);
    assert.ok(typeof flyer === "object");
    assert.deepEqual(flyer.pages.map((p) => [p.imageUrl, p.smallerImageUrl]), [
      ["https://imgproxy.leaflets.schwarz/z/1.jpg", "https://imgproxy.leaflets.schwarz/i/1.jpg"],
      ["https://imgproxy.leaflets.schwarz/i/2.jpg", undefined],
    ]);
  });

  test("too large with no smaller rendition (Biedronka's 26 MB opening-hours page): recorded as missing, tried twice, then left", async () => {
    const web = new ImageWeb();
    web.answers.set("https://img.example/biedronka/3.png", [TOO_LARGE]);
    const d = deps({ fetcher: web });
    const adapter = new FakeAdapter("biedronka", { kind: "ok", leaflets: [leaflet("biedronka", 3)] });
    const first = await scanChain("biedronka", adapter, d);
    assert.ok(first.kind === "ok");
    assert.deepEqual(first.snapshot.missing, [{ leaflet: 0, page: 3, why: "image_too_large" }]);
    assert.deepEqual(first.snapshot.pages, { read: 2, of: 3 });
    assert.ok(first.snapshot.reasons.includes("image_too_large"));
    const second = await scanChain("biedronka", adapter, d);
    assert.ok(second.kind === "ok");
    assert.deepEqual(second.snapshot.missing, [{ leaflet: 0, page: 3, why: "image_too_large", gaveUp: true }]);
    const third = await scanChain("biedronka", adapter, d);
    assert.ok(third.kind === "ok");
    assert.deepEqual(third.snapshot.missing, [{ leaflet: 0, page: 3, why: "image_too_large", gaveUp: true }]);
    assert.equal(web.fetched.filter((u) => u.endsWith("/3.png")).length, 4, "two scans, two requests each; the third asks nothing");
    assert.equal(missingSummary(third.snapshot.missing), "image_too_large_gave_up:1");
  });

  test("an image host that refuses AI input is recorded as refused, never as a reader's failure", async () => {
    const web = new ImageWeb();
    web.answers.set("https://img.example/natura/1.png", [{ kind: "disallowed", reason: "content_signal" }]);
    const out = await fetchPageImage(web, leaflet("natura", 1).pages[0]!, new AbortController().signal, async () => {});
    assert.deepEqual(out, { fail: "image_refused", reason: "image_disallowed" });
  });
});

describe("when a snapshot's offers were read", () => {
  test("each page keeps its own read time across scans; the material says it comes from the catalog", async () => {
    const d = deps();
    const r = await scanChain("dino", new FakeAdapter("dino", { kind: "ok", leaflets: [leaflet("dino", 2)] }), d);
    assert.ok(r.kind === "ok");
    const snap = { ...r.snapshot, reads: { ...r.snapshot.reads, "0:2": { ...r.snapshot.reads["0:2"]!, readAt: "2026-11-12T21:35:00.000Z" } } };
    const m = materialFromSnapshot(snap, TODAY, NOW);
    assert.ok(typeof m === "object");
    assert.equal(m.fromCatalog, true);
    assert.equal(m.readAt, NOW.toISOString());
    assert.equal(m.pageReadAt?.get("0:2"), "2026-11-12T21:35:00.000Z");
  });
});

describe("scans in the database", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  test("the day's spend is booked per chain; the next pass the same day reads only what the budget leaves; afterScans gets the chains", async () => {
    const model = new CatalogModel().page("biedronka:1", { products: [read({ name: "Masło Extra 82%", size: "200 g", price: "4,99" })] });
    const adapters = Object.fromEntries(CATALOG_CHAINS.map((c) => [c, new FakeAdapter(c, c === "biedronka"
      ? { kind: "ok", leaflets: [leaflet("biedronka", 4)] } : { kind: "no_leaflet" })])) as unknown as Record<ReadChain, ChainAdapter>;
    const logs: { msg: string; extra?: object }[] = [];
    const after: ReadChain[][] = [];
    let clock = NOW;
    const ctx = {
      db, adapters, fetcher: new ImageWeb(), model, everyHours: 6, maxPagesPerChain: 50, dailyTokensPerChain: 6000, dailyTokens: 1e9,
      now: () => clock, today: () => TODAY, log: (msg: string, extra?: object) => logs.push({ msg, extra }),
      afterScans: async (chains: ReadChain[]) => { after.push(chains); return { checked: 1 }; },
    };
    const first = await runCatalogPass(ctx);
    assert.equal(first.watch_checked, 1);
    assert.equal(after[0]!.length, CATALOG_CHAINS.length, "every chain scanned, the no-leaflet ones included");
    // 6,000 is reckoned for the first page; the others wait for it and are reckoned at its real 2,150: two pages fit
    // 6,000, a third would pass it (four pages are read at once, so this also checks that waiting pages aren't lost).
    assert.equal(model.catalogReads.length, 2);
    const { rows } = await db.query("SELECT chain, day::text AS day, tokens::int AS tokens FROM leaflet_catalog_tokens");
    assert.deepEqual(rows, [{ chain: "biedronka", day: TODAY, tokens: 2 * PAGE_COST }]);
    const scanned = logs.find((l) => l.msg === "leaflet catalog scanned" && (l.extra as { chain: string }).chain === "biedronka")!.extra as Record<string, unknown>;
    assert.equal(scanned.pagesOverBudget, 2);
    assert.equal(scanned.missing, "not_read_yet:2");
    assert.equal(scanned.tokensLeftChain, 6000 - 2 * PAGE_COST);
    assert.equal(JSON.stringify(logs).includes("Masło"), false, "codes and counts only");

    // Six hours later, the same day: the chain's budget is spent, so nothing more is read.
    clock = new Date(NOW.getTime() + 6 * 3600_000 + 1000);
    await runCatalogPass(ctx);
    assert.equal(model.catalogReads.length, 2);
    // The next day the rest is read.
    const nextDay = { ...ctx, today: () => "2026-11-14", now: () => new Date(NOW.getTime() + 24 * 3600_000) };
    await runCatalogPass(nextDay);
    assert.equal(model.catalogReads.length, 4);
    const held = await new DbCatalogStore(db).snapshots(["biedronka"]);
    assert.equal(held.get("biedronka")!.complete, true);
    assert.equal(held.get("biedronka")!.missing, undefined);
    const reads = held.get("biedronka")!.reads;
    assert.equal(Object.values(reads).filter((r) => r.readAt === NOW.toISOString()).length, 2, "the pages read the day before keep their time");
    assert.equal(Object.values(reads).filter((r) => r.readAt === nextDay.now().toISOString()).length, 2);
  });
});
