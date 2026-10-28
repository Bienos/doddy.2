// POST /v1/deals/search against real Postgres, through the HTTP API, with a fake web and a fake model
// (SHOPPING.md §2, schemas/fixtures/deals_search_v1.json). Nothing here reaches the chains or Anthropic.
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { DEFAULT_DEALS_SETTINGS, type DealsSettings } from "../src/deals/types.js";
import { reserve } from "../src/deals/usage.js";
import { chainsWeb, contractFixture, FakeModel, read, ResponseSchema } from "./dealsFakes.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

describe("leaflet search route against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM deals_usage"); });

  async function world(opts: { settings?: Partial<DealsSettings>; off?: boolean } = {}) {
    const web = chainsWeb();
    const model = new FakeModel().page("biedronka:2", { products: [read({ name: "Masło Extra 82%", size: "200 g", price: "4,99" })] });
    // buildApp registers the route (app.ts); the test hands it the leaflet deps.
    const base = await testApp(db, {
      deals: opts.off ? undefined : {
        settings: { ...DEFAULT_DEALS_SETTINGS, ...opts.settings }, fetcher: new PoliteFetcher({ fetch: web.fetch }), model,
        now: () => new Date("2026-10-24T06:10:00Z"),
      },
    });
    const account = async () => {
      const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
      const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
      return { accountId, h: { authorization: `Bearer ${deviceToken}` } };
    };
    const ask = (h: Record<string, string>, payload: unknown) => base.app.inject({
      method: "POST", url: "/v1/deals/search", headers: { ...h, "content-type": "application/json" }, payload: JSON.stringify(payload),
    });
    return { ...base, web, model, account, ask };
  }
  const usageRow = async (accountId: string) =>
    (await db.query("SELECT requests, pages_read, input_tokens, output_tokens FROM deals_usage WHERE account_id = $1", [accountId])).rows
      .map((r) => [r.requests, r.pages_read, Number(r.input_tokens), Number(r.output_tokens)]);

  test("the contract's request gets the contract's response shape; only counts are stored", async () => {
    const w = await world();
    const a = await w.account();
    const res = await w.ask(a.h, contractFixture().request);
    assert.equal(res.statusCode, 200, res.body);
    const body = res.json();
    const parsed = ResponseSchema.safeParse(body);
    assert.ok(parsed.success, JSON.stringify(parsed.error?.issues));
    // Lidl: the fake serves one of its four current leaflets and this reader finds nothing on its pages, so
    // "nothing matched" can't be claimed: failed.
    assert.deepEqual(body.chains.map((c: { chain: string; status: string }) => [c.chain, c.status]), [
      ["biedronka", "checked"], ["lidl", "failed"], ["dino", "checked"], ["rossmann", "checked"], ["kaufland", "link_only"],
    ]);
    assert.deepEqual(body.items[0].offers.map((o: { chain: string; price: { minor: number } }) => [o.chain, o.price.minor]).slice(0, 1), [["dino", 449]]);
    const [requests, pages, input, output] = (await usageRow(a.accountId))[0] as number[];
    assert.equal(requests, 1);
    assert.equal(pages, w.model.reads.length);
    assert.equal(input, w.model.reads.length * 2000 + 300);
    assert.equal(output, w.model.reads.length * 150 + 20);
    const cols = (await db.query("SELECT column_name FROM information_schema.columns WHERE table_name = 'deals_usage' ORDER BY ordinal_position")).rows.map((r) => r.column_name);
    assert.deepEqual(cols, ["account_id", "day", "requests", "pages_read", "input_tokens", "output_tokens"], "no item, page or offer column");
  });

  test("401 without a device token; 503 deals_disabled when off; nothing fetched", async () => {
    const w = await world();
    assert.equal((await w.ask({}, contractFixture().request)).statusCode, 401);
    const off = await world({ settings: { enabled: false } });
    const a = await off.account();
    const res = await off.ask(a.h, contractFixture().request);
    assert.equal(res.statusCode, 503);
    assert.deepEqual(res.json(), contractFixture().errors.disabled!.body);
    const none = await world({ off: true });
    const b = await none.account();
    assert.equal((await none.ask(b.h, contractFixture().request)).statusCode, 503);
    assert.equal(off.web.requests.length + none.web.requests.length, 0);
  });

  test("400 invalid_request names the failing fields, never the values", async () => {
    const w = await world();
    const a = await w.account();
    const bad: [unknown, string[]][] = [
      [{ items: [], language: "pl" }, ["items"]],
      [{ items: Array.from({ length: 13 }, (_, i) => `x${i}`), language: "pl" }, ["items"]],
      [{ items: ["x".repeat(61)], language: "pl" }, ["items.0"]],
      [{ items: ["   "], language: "pl" }, ["items.0"]],
      [{ items: ["masło"], chains: ["spar"], language: "pl" }, ["chains.0"]],
      [{ items: ["masło"], chains: [], language: "pl" }, ["chains"]],
      [{ items: ["masło"], language: "pol" }, ["language"]],
      [{ items: ["masło"], language: "pl", extra: 1 }, [""]],
    ];
    for (const [payload, fields] of bad) {
      const res = await w.ask(a.h, payload);
      assert.equal(res.statusCode, 400, JSON.stringify(payload));
      assert.deepEqual(res.json(), { error: "invalid_request", fields }, JSON.stringify(payload));
    }
    assert.deepEqual(contractFixture().errors.invalid!.body, { error: "invalid_request", fields: ["items"] });
    assert.equal(w.web.requests.length, 0);
    assert.deepEqual(await usageRow(a.accountId), [], "an invalid request isn't counted");
  });

  test("items are trimmed; default chains are the six read chains; a link-only chain alone fetches nothing", async () => {
    const w = await world();
    const a = await w.account();
    const res = await w.ask(a.h, { items: ["  masło  "], language: "pl" });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().items[0].query, "masło");
    assert.deepEqual(res.json().chains.map((c: { chain: string }) => c.chain), ["biedronka", "lidl", "dino", "rossmann", "aldi", "zabka"]);
    const before = w.web.requests.length;
    const link = await w.ask(a.h, { items: ["masło"], chains: ["netto", "kaufland", "netto"], language: "pl" });
    assert.deepEqual(link.json().chains, [
      { chain: "netto", status: "link_only", leafletUrl: "https://netto.pl/gazetka-netto/" },
      { chain: "kaufland", status: "link_only", leafletUrl: "https://www.kaufland.pl/gazetka-promocyjna.html" },
    ]);
    assert.equal(w.web.requests.length, before);
  });

  test("the per-account cap: 429 daily_limit before anything is fetched", async () => {
    const w = await world({ settings: { dailyPerAccount: 2 } });
    const a = await w.account();
    const req = { items: ["masło"], chains: ["dino"], language: "pl" };
    assert.equal((await w.ask(a.h, req)).statusCode, 200);
    assert.equal((await w.ask(a.h, req)).statusCode, 200);
    const fetched = w.web.requests.length;
    const third = await w.ask(a.h, req);
    assert.equal(third.statusCode, 429);
    assert.deepEqual(third.json(), contractFixture().errors.dailyLimit!.body);
    assert.equal(w.web.requests.length, fetched);
    assert.equal((await usageRow(a.accountId))[0]![0], 2);
  });

  test("the server cap counts every account", async () => {
    const w = await world({ settings: { dailyPerServer: 1 } });
    const a = await w.account();
    const b = await w.account();
    const req = { items: ["masło"], chains: ["dino"], language: "pl" };
    assert.equal((await w.ask(a.h, req)).statusCode, 200);
    assert.equal((await w.ask(b.h, req)).statusCode, 429);
  });

  test("reservations are exact on both caps under concurrency", async () => {
    const w = await world();
    const a = await w.account();
    const mine = await Promise.all(Array.from({ length: 12 }, () => reserve(db, a.accountId, { perAccount: 3, perServer: 1000 })));
    assert.equal(mine.filter((r) => r === "ok").length, 3);
    assert.equal(mine.filter((r) => r === "account_cap").length, 9);
    await db.query("DELETE FROM deals_usage");
    const accounts = await Promise.all(Array.from({ length: 4 }, () => w.account()));
    const all = await Promise.all(accounts.flatMap((x) => Array.from({ length: 4 }, () => reserve(db, x.accountId, { perAccount: 10, perServer: 5 }))));
    assert.equal(all.filter((r) => r === "ok").length, 5);
    assert.equal(all.filter((r) => r === "server_cap").length, 11);
  });

  test("deleting the account deletes its counts", async () => {
    const w = await world();
    const a = await w.account();
    assert.equal((await w.ask(a.h, { items: ["masło"], chains: ["dino"], language: "pl" })).statusCode, 200);
    assert.equal((await usageRow(a.accountId)).length, 1);
    const del = await w.app.inject({ method: "DELETE", url: "/v1/account", headers: a.h });
    assert.ok(del.statusCode < 300, del.body);
    assert.equal((await usageRow(a.accountId)).length, 0);
  });
});
