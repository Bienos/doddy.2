// Shopping errands end to end against real Postgres, through the HTTP API (docs/implementation/
// SHOPPING.md): the draft echoes kind and priorities with the fixture's digest, the worker hands the
// shopping runner the priorities, and the stored result carries the shopping block. The shopping
// runner here is the real one with a fake model, a fake offer source and a fake fetcher.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { after, before, beforeEach, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { DEFAULT_ERRAND_SETTINGS } from "../src/config.js";
import type { ErrandContext } from "../src/errands/context.js";
import type { ErrandResearcher, ErrandTask, ResearchControl, ResearchOutcome } from "../src/errands/researcher.js";
import { ErrandResultSchema } from "../src/errands/schema.js";
import { researchNext } from "../src/errands/worker.js";
import type { Db } from "../src/db.js";
import { RoutingErrandResearcher, ShoppingErrandResearcher, type ShoppingCardReply, type ShoppingMessage, type ShoppingModelApi } from "../src/shopping/runner.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const fx = JSON.parse(readFileSync(path.resolve(here, "../../../../schemas/fixtures/errand_create_shopping_v1.json"), "utf8"));

class ScriptedApi implements ShoppingModelApi {
  readonly model = "claude-sonnet-5-5";
  private step = 0;
  async research(): Promise<ShoppingMessage> {
    // The API reports each response's own server-tool use: two searches in the first, none after.
    if (this.step++ === 0) {
      const usage = { input_tokens: 2000, output_tokens: 300, server_tool_use: { web_search_requests: 2, web_fetch_requests: 1 } };
      return { content: [{ type: "tool_use", id: "t1", name: "find_offers", input: { query: "zmywarka do zabudowy 45 cm" } }], stop_reason: "tool_use", usage };
    }
    return { content: [{ type: "text", text: "o1 najcichsza." }], stop_reason: "end_turn", usage: { input_tokens: 2000, output_tokens: 300 } };
  }
  async card(): Promise<ShoppingCardReply> {
    return { kind: "ok", usage: { input_tokens: 500, output_tokens: 200 }, card: {
      picks: [{ role: "best", offerId: "o1", why: "Najcichsza z ofert do 2000 zł.", tradeoff: null }, { role: "cheapest", offerId: "o2", why: "Najtańsza.", tradeoff: "Głośniejsza." }],
      offerNotes: [{ offerId: "o1", notes: "42 dB" }], budget: { amount: 2000 }, recommendation: null,
      howChosen: ["Po Twojej kolejności."], watchOuts: [], unknowns: ["Czy cena się utrzyma."], rejected: [], next: [],
    } };
  }
}

const general: ErrandResearcher & { tasks: ErrandTask[] } = {
  provider: "anthropic", model: "claude-opus-5-5", tasks: [],
  async research(t: ErrandTask, _c: ResearchControl): Promise<ResearchOutcome> {
    this.tasks.push(t);
    return { kind: "failed", code: "refused", usage: { inputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0, outputTokens: 0 }, searches: 0, fetches: 0, model: "claude-opus-5-5" };
  },
};

describe("shopping errands against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM errands; DELETE FROM errand_deletions;"); });

  async function world() {
    const queries: string[] = [];
    const shopping = new ShoppingErrandResearcher(new ScriptedApi(), {
      offers: { name: "fake", async search(q) {
        queries.push(q);
        return { kind: "ok", offers: [
          { title: "Zmywarka 45 cm 42 dB", shop: "Media Expert", priceText: "1 899,00 zł", link: "https://www.mediaexpert.pl/p/45" },
          { title: "Zmywarka 45 cm 47 dB", shop: "RTV Euro AGD", priceText: "1 449,00 zł", link: "https://www.google.com/shopping/product/1" },
        ] };
      } },
      fetcher: { async fetchPage() { return { kind: "blocked", reason: "403" }; } },
    });
    const clock = { now: new Date(Date.now() - 3600_000) };
    const base = await testApp(db, {
      errands: { settings: { ...DEFAULT_ERRAND_SETTINGS, enabled: true }, researcher: new RoutingErrandResearcher(general, shopping), now: () => clock.now, cancelPollMs: 10 },
    });
    const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
    const { deviceToken } = r.json() as { deviceToken: string };
    const api = (method: "GET" | "POST", url: string, payload?: unknown) =>
      base.app.inject({ method, url, headers: { authorization: `Bearer ${deviceToken}` }, payload: payload as never });
    return { api, clock, queries, ctx: base.app.errandContext as ErrandContext };
  }

  test("draft → approve → shopping run → result with the shopping block; prices from the offers", async () => {
    const w = await world();
    const created = await w.api("POST", "/v1/errands", fx.request);
    assert.equal(created.statusCode, 201, created.body);
    const draft = created.json();
    assert.equal(draft.digest, fx.digest, "the same digest the app computes from the fixture");
    assert.equal(draft.kind, "shopping");
    assert.deepEqual(draft.priorities, ["Cisza", "Cena", "Gwarancja"]);
    assert.equal((await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: fx.researchDigestOfSameWords })).statusCode, 409,
      "the research digest of the same words does not approve a shopping errand");
    assert.equal((await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: draft.digest })).statusCode, 202);

    w.clock.now = new Date(w.clock.now.getTime() + 5000);
    assert.equal(await researchNext(w.ctx), draft.id);
    assert.deepEqual(w.queries, ["zmywarka do zabudowy 45 cm"]);
    const got = (await w.api("GET", `/v1/errands/${draft.id}`)).json();
    assert.equal(got.state, "done", JSON.stringify(got));
    assert.equal(got.kind, "shopping");
    assert.ok(ErrandResultSchema.safeParse(got.result).success);
    const s = got.result.shopping;
    assert.deepEqual(s.priorities, ["Cisza", "Cena", "Gwarancja"]);
    assert.deepEqual(s.picks.map((p: { role: string; offerId: string }) => [p.role, p.offerId]), [["best", "o1"], ["cheapest", "o2"]]);
    assert.deepEqual(s.offers.find((o: { id: string }) => o.id === "o1").price, { minor: 189900, currency: "PLN" });
    assert.equal(s.offers.find((o: { id: string }) => o.id === "o1").evidence, "listing");
    assert.equal(got.searches, 3, "two Anthropic searches and one offer search");
    const row = (await db.query("SELECT model FROM errands WHERE id = $1", [draft.id])).rows[0];
    assert.equal(row.model, "claude-sonnet-5-5", "the stored model is the one that ran");
    assert.equal(general.tasks.length, 0, "a shopping errand never goes to the research runner");
  });

  test("a research errand still goes to the research runner, with no kind in its task", async () => {
    const w = await world();
    const { kind: _k, priorities: _p, ...research } = fx.request;
    const draft = (await w.api("POST", "/v1/errands", research)).json();
    assert.equal(draft.digest, fx.researchDigestOfSameWords);
    assert.equal("kind" in draft, false);
    assert.equal((await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: draft.digest })).statusCode, 202);
    w.clock.now = new Date(w.clock.now.getTime() + 5000);
    await researchNext(w.ctx);
    assert.equal(general.tasks.length, 1);
    assert.equal("kind" in general.tasks[0]!, false);
  });
});
