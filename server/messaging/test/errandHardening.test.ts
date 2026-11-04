// Errands, hardened (security review 4 Nov 2026): the research budget of one errand (ADR-702) in the research loop,
// in the request the SDK sends and in the shopping runner, and the refusal of links in the text of a create request
// (ADR-703). The model API is a fake or a local stand-in, never the real one.
import assert from "node:assert/strict";
import http from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, describe, test } from "node:test";
import { DEFAULT_ERRAND_SETTINGS } from "../src/config.js";
import type { Db } from "../src/db.js";
import { DEFAULT_RESEARCH_BUDGET, type BudgetLeft, type ResearchBudget } from "../src/errands/budget.js";
import {
  AnthropicErrandApi, runResearch, type CardReply, type ErrandModelApi, type ErrandResearcher, type ResearchControl, type ResearchMessage, type ResearchTurn,
} from "../src/errands/researcher.js";
import { createBody } from "../src/errands/schema.js";
import {
  AnthropicShoppingApi, runShopping, webToolsFor, type ShoppingCardReply, type ShoppingMessage, type ShoppingModelApi, type ShoppingTurn,
} from "../src/shopping/runner.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

const task = { id: "00000000-0000-4000-8000-000000000002", words: "sprawdź loty do Rzymu", brief: "Loty do Rzymu.", language: "pl" };
const control = (over: Partial<ResearchControl> = {}): ResearchControl & { logs: { msg: string; extra?: object }[] } => {
  const logs: { msg: string; extra?: object }[] = [];
  return { deadline: new Date(Date.now() + 60_000), isCancelled: async () => false, cancelPollMs: 5, log: (m, e) => logs.push({ msg: m, extra: e }), logs, ...over };
};
const note = (text = "Notatki z wyszukiwania.") => ({ type: "text", text });
const used = (search: number, fetch = 0) => [
  ...Array.from({ length: search }, (_, i) => ({ type: "server_tool_use", id: `s${i}-${Math.random()}`, name: "web_search", input: {} })),
  ...Array.from({ length: fetch }, (_, i) => ({ type: "server_tool_use", id: `f${i}-${Math.random()}`, name: "web_fetch", input: {} })),
];
const message = (stop: string, content: { type: string; [k: string]: unknown }[], output = 200): ResearchMessage =>
  ({ content, stop_reason: stop, usage: { input_tokens: 1000, output_tokens: output } });
const cardOk = (): CardReply => ({
  kind: "ok", usage: { input_tokens: 10, output_tokens: 5 },
  card: { answer: "Gotowe.", sections: [], recommendation: null, budget: null, next: [], sources: [] },
});

/** A fake model API that answers each research request from `step(n)` and records what room it was handed. */
class BudgetApi implements ErrandModelApi {
  readonly model = "claude-opus-5-5";
  lefts: (BudgetLeft | undefined)[] = [];
  constructor(private readonly step: (n: number) => ResearchMessage) {}
  async research(_m: ResearchTurn[], _s: AbortSignal, left?: BudgetLeft) {
    this.lefts.push(left);
    return this.step(this.lefts.length);
  }
  async card() { return cardOk(); }
}

const budget = (over: Partial<ResearchBudget> = {}): ResearchBudget => ({ maxSearches: 0, maxFetches: 0, maxRequests: 0, maxOutputTokens: 0, ...over });

describe("research loop: the budget of one errand (ADR-702)", () => {
  test("each request is handed what is left; a used-up count ends the research and the card is made from the notes so far", async () => {
    const api = new BudgetApi((n) => message("pause_turn", [...used(2), note(`Runda ${n}.`)]));
    const c = control();
    const out = await runResearch(api, task, c, budget({ maxSearches: 3 }));
    assert.equal(out.kind, "done", JSON.stringify(out));
    assert.deepEqual(api.lefts, [{ searches: 3 }, { searches: 1 }], "the second request may do one more look-up, the third never starts");
    const line = c.logs.find((l) => l.msg === "errand research budget reached; using its notes");
    assert.deepEqual(line?.extra, { errandId: task.id, limit: "searches", requests: 2 });
    assert.equal(out.searches, 4);
  });

  test("fetches are counted the same way", async () => {
    const api = new BudgetApi(() => message("pause_turn", [...used(0, 3), note()]));
    const c = control();
    await runResearch(api, task, c, budget({ maxFetches: 5 }));
    assert.deepEqual(api.lefts, [{ fetches: 5 }, { fetches: 2 }]);
    assert.equal(c.logs.find((l) => l.msg.includes("budget reached"))?.extra && (c.logs.find((l) => l.msg.includes("budget reached"))!.extra as { limit: string }).limit, "fetches");
  });

  test("requests are capped, so a model that keeps pausing is not resumed for ever", async () => {
    const api = new BudgetApi(() => message("pause_turn", [note()]));
    const out = await runResearch(api, task, control(), budget({ maxRequests: 4 }));
    assert.equal(out.kind, "done");
    assert.equal(api.lefts.length, 4);
  });

  test("the default budget is finite: a model that never ends its turn stops after 30 requests, with the notes it wrote", async () => {
    const api = new BudgetApi(() => message("pause_turn", [note()]));
    const out = await runResearch(api, task, control());
    assert.equal(out.kind, "done");
    assert.equal(api.lefts.length, DEFAULT_RESEARCH_BUDGET.maxRequests);
    assert.equal(api.lefts[0]?.searches, 40, "and each request is told it has 40 searches and 40 fetches");
    assert.equal(api.lefts[0]?.fetches, 40);
  });

  test("output tokens are counted over the whole errand and lower each request's max", async () => {
    const api = new BudgetApi(() => message("pause_turn", [note()], 9_000));
    const c = control();
    await runResearch(api, task, c, budget({ maxOutputTokens: 20_000 }));
    assert.deepEqual(api.lefts, [{ outputTokens: 20_000 }, { outputTokens: 11_000 }, { outputTokens: 2_000 }]);
    assert.equal((c.logs.find((l) => l.msg.includes("budget reached"))?.extra as { limit: string }).limit, "output_tokens");
  });

  test("0 is no limit, and only 0: nothing is capped and the request is told so", async () => {
    const api = new BudgetApi((n) => (n < 40 ? message("pause_turn", [...used(3, 3), note()], 5_000) : message("end_turn", [note("Koniec.")])));
    const out = await runResearch(api, task, control(), budget());
    assert.equal(out.kind, "done");
    assert.equal(api.lefts.length, 40);
    assert.ok(api.lefts.every((l) => l && Object.keys(l).length === 0), "no field: no max_uses and the usual max_tokens");
    assert.equal(out.kind === "done" && out.searches, 117);
  });

  test("a budget used up before any note was written fails as unreadable, like a run that left no notes", async () => {
    const api = new BudgetApi(() => message("pause_turn", [...used(1)]));
    const out = await runResearch(api, task, control(), budget({ maxRequests: 1 }));
    assert.equal(out.kind === "failed" && out.code, "unreadable_result");
  });

  test("the logs carry ids and counts, never words", async () => {
    const c = control();
    await runResearch(new BudgetApi(() => message("pause_turn", [note()])), task, c, budget({ maxRequests: 2 }));
    assert.equal(JSON.stringify(c.logs).includes("Rzymu"), false);
  });
});

/** What the real SDK sends, read at a local stand-in that refuses every request. */
async function sentBodies(run: (baseURL: string) => Promise<unknown>) {
  const seen: Array<Record<string, unknown> & { tools?: Array<Record<string, unknown>>; max_tokens?: number }> = [];
  const server = http.createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => chunks.push(c));
    req.on("end", () => {
      seen.push(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      res.writeHead(400, { "content-type": "application/json" });
      res.end(JSON.stringify({ type: "error", error: { type: "invalid_request_error", message: "stopped by the test" } }));
    });
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${(server.address() as AddressInfo).port}`).catch(() => {});
  } finally {
    server.close();
  }
  return seen;
}
const tools = (b: { tools?: Array<Record<string, unknown>> }) => b.tools!.filter((t) => typeof t.type === "string" && /^web_/.test(t.type as string));
const maxUses = (b: { tools?: Array<Record<string, unknown>> }) => tools(b).map((t) => [t.name, t.max_uses]);
const turn: ResearchTurn[] = [{ role: "user", content: "x" }];

describe("the request to Anthropic carries the budget (ADR-702)", () => {
  test("errand research: max_uses on both tools and max_tokens from the budget; what is left lowers them", async () => {
    const own = budget({ maxSearches: 7, maxFetches: 5, maxOutputTokens: 50_000 });
    const [first] = await sentBodies((baseURL) => new AnthropicErrandApi("test-key", { baseURL, budget: own }).research(turn, new AbortController().signal));
    assert.deepEqual(maxUses(first!), [["web_search", 7], ["web_fetch", 5]]);
    assert.equal(first!.max_tokens, 50_000);
    const [resumed] = await sentBodies((baseURL) => new AnthropicErrandApi("test-key", { baseURL, budget: own })
      .research(turn, new AbortController().signal, { searches: 2, fetches: 1, outputTokens: 20_000 }));
    assert.deepEqual(maxUses(resumed!), [["web_search", 2], ["web_fetch", 1]]);
    assert.equal(resumed!.max_tokens, 20_000);
  });

  test("with no budget given the defaults apply (40 and 40), and 0 on purpose leaves max_uses out", async () => {
    const [byDefault] = await sentBodies((baseURL) => new AnthropicErrandApi("test-key", { baseURL }).research(turn, new AbortController().signal));
    assert.deepEqual(maxUses(byDefault!), [["web_search", 40], ["web_fetch", 40]]);
    assert.equal(byDefault!.max_tokens, 64_000);
    const [unlimited] = await sentBodies((baseURL) => new AnthropicErrandApi("test-key", { baseURL, budget: budget() }).research(turn, new AbortController().signal));
    assert.deepEqual(maxUses(unlimited!), [["web_search", undefined], ["web_fetch", undefined]]);
    assert.equal(unlimited!.max_tokens, 64_000);
    assert.equal(tools(unlimited!).every((t) => !("max_uses" in t)), true);
  });

  test("shopping research: the web tools carry max_uses too, whichever model, and max_tokens stays within its 32000", async () => {
    for (const model of ["claude-haiku-5-5", "claude-sonnet-5-5"]) {
      const [r] = await sentBodies((baseURL) => new AnthropicShoppingApi("test-key", { baseURL, model, budget: budget({ maxSearches: 6, maxFetches: 4, maxOutputTokens: 100_000 }) })
        .research([{ role: "user", content: "x" }], new AbortController().signal));
      assert.deepEqual(maxUses(r!), [["web_search", 6], ["web_fetch", 4]], model);
      assert.equal(r!.max_tokens, 32_000, model);
      const custom = r!.tools!.filter((t) => !/^web_/.test(String(t.type ?? "")));
      assert.deepEqual(custom.map((t) => t.name), ["find_offers", "check_offer_page"]);
      assert.equal(custom.every((t) => !("max_uses" in t)), true, "the code's own tools have their own limits");
    }
    const [lowered] = await sentBodies((baseURL) => new AnthropicShoppingApi("test-key", { baseURL, budget: budget({ maxOutputTokens: 100_000 }) })
      .research([{ role: "user", content: "x" }], new AbortController().signal, { searches: 3, outputTokens: 12_000 }));
    assert.equal(lowered!.max_tokens, 12_000);
    assert.deepEqual(webToolsFor("claude-haiku-5-5", { searches: 3, fetches: 2 }).map((t) => [t.name, (t as { max_uses?: number }).max_uses]), [["web_search", 3], ["web_fetch", 2]]);
  });
});

describe("the shopping runner counts the budget over the whole errand (ADR-702)", () => {
  class ShopApi implements ShoppingModelApi {
    readonly model = "claude-haiku-5-5";
    lefts: (BudgetLeft | undefined)[] = [];
    async research(_m: ShoppingTurn[], _s: AbortSignal, left?: BudgetLeft): Promise<ShoppingMessage> {
      this.lefts.push(left);
      return { content: [...used(2), note("Szukam.")], stop_reason: "pause_turn", usage: { input_tokens: 100, output_tokens: 50 } };
    }
    async card(): Promise<ShoppingCardReply> { return { kind: "unparsed" }; }
  }
  const offers = { name: "none", search: async () => ({ kind: "not_set_up" as const, reason: "no key" }) };
  const fetcher = { fetch: async () => ({ kind: "failed" as const, reason: "no" }) } as never;

  test("a model that keeps pausing is stopped by the budget, and told what is left each time", async () => {
    const api = new ShopApi();
    const c = control();
    const out = await runShopping(api, { offers, fetcher, budget: budget({ maxSearches: 5 }) }, { ...task, kind: "shopping", priorities: ["cicha"] }, c);
    assert.deepEqual(api.lefts, [{ searches: 5 }, { searches: 3 }, { searches: 1 }]);
    assert.equal(out.kind, "done", "no confirmed price: the person is told so, as before");
    assert.deepEqual(c.logs.find((l) => l.msg === "shopping research budget reached; using its notes")?.extra,
      { errandId: task.id, limit: "searches", requests: 3 });
  });

  test("the default budget stops it at 30 requests", async () => {
    const api = new ShopApi();
    await runShopping(api, { offers, fetcher, budget: budget({ maxRequests: 30 }) }, { ...task, kind: "shopping", priorities: [] }, control());
    assert.equal(api.lefts.length, 30);
    const byDefault = new ShopApi();
    await runShopping(byDefault, { offers, fetcher }, { ...task, kind: "shopping", priorities: [] }, control());
    assert.ok(byDefault.lefts.length <= 30 && byDefault.lefts.length >= 1, "a shopping errand without a configured budget is not uncapped either");
  });
});

describe("a create request with a link in its text is refused (ADR-703)", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  const researcher: ErrandResearcher = { provider: "anthropic", model: "claude-opus-5-5", research: async () => { throw new Error("not run here"); } };
  const good = { words: "sprawdź loty i hotele do Rzymu do 2000 zł", brief: "Loty z Warszawy i hotele w Rzymie.", title: "Rzym", language: "pl" };

  async function world() {
    const { app } = await testApp(db, { errands: { settings: DEFAULT_ERRAND_SETTINGS, researcher } });
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const { deviceToken } = r.json() as { deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const create = (payload: object) => app.inject({ method: "POST", url: "/v1/errands", headers: h, payload: payload as never });
    return { app, create };
  }

  test("words, brief and title: 400 invalid_request that names the field and never the text; nothing is stored", async () => {
    const evil = [
      "zajrzyj na https://evil.example/collect?d=SECRET", "HTTP://EVIL.EXAMPLE/x", "www.evil.example", "evil.example/collect",
      "evil。example/collect", "https%3A%2F%2Fevil.example%2Fx", "evil.example%2Fcollect", "[tu](https://evil.example/x)", "10.0.0.1/admin",
      "javascript:alert(1)", "data:text/html;base64,AAAA",
    ];
    const before = (await db.query("SELECT 1 FROM errands")).rowCount;
    for (const field of ["words", "brief", "title"] as const) {
      const w = await world(); // a create is limited to 30 an hour per token: one account per field
      try {
        for (const text of evil) {
          const r = await w.create({ ...good, [field]: field === "title" ? text.slice(0, 80) : text });
          assert.equal(r.statusCode, 400, `${field}: ${text}`);
          assert.deepEqual(r.json(), { error: "invalid_request", fields: [field] });
          assert.ok(!r.body.includes("evil") && !r.body.includes("SECRET") && !r.body.includes("javascript"), "the text is not echoed");
        }
      } finally {
        await w.app.close();
      }
    }
    assert.equal((await db.query("SELECT 1 FROM errands")).rowCount, before, "no draft was made");
  });

  test("a shopping errand's priorities are checked too, and all offending fields are named", async () => {
    const w = await world();
    try {
      const shopping = { ...good, kind: "shopping", priorities: ["cicha", "https://evil.example/x", "energooszczędna"] };
      const r = await w.create(shopping);
      assert.equal(r.statusCode, 400);
      assert.deepEqual(r.json(), { error: "invalid_request", fields: ["priorities.1"] });
      const many = await w.create({ ...shopping, words: "www.evil.example", priorities: ["a", "b.example/c"] });
      assert.deepEqual(many.json(), { error: "invalid_request", fields: ["words", "priorities.1"] });
      assert.equal((await w.create({ ...shopping, priorities: ["cicha", "tania", "allegro.pl"] })).statusCode, 201);
    } finally {
      await w.app.close();
    }
  });

  test("a shop's bare domain name is fine, and so is everyday text", async () => {
    const w = await world();
    try {
      for (const words of ["porównaj ceny na allegro.pl i ceneo.pl", "Data: 12 listopada, godz. 12:30/13:00, cena 12.50 zł/szt", "sprawdź allegro.pl"]) {
        const r = await w.create({ ...good, words });
        assert.equal(r.statusCode, 201, `${words}: ${r.body}`);
        assert.equal((r.json() as { words: string }).words, words, "the words come back exactly as given");
      }
    } finally {
      await w.app.close();
    }
  });

  test("a request that was already stored with a link can still be read: only new requests are checked", () => {
    // decryptContent and the worker read stored content with createBody, which is unchanged (existing rows keep working).
    assert.ok(createBody.safeParse({ ...good, words: "https://old.example/x" }).success);
  });
});
