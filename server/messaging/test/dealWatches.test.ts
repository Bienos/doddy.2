// Deal watches (owner, 13 Nov 2026: "daj znać, gdy masło będzie poniżej 5 zł"; decision
// docs/decisions/2026-11-13-leaflet-results-and-deal-watches.md): the item's words, an optional price and chains, checked
// in code against the leaflet catalog after its scans, at most once a day, with no page read. One push per new matching
// offer at most (one per watch per check), a kind only; quiet hours, a daily cap; deleted on request, when it ends and
// with the account. The catalog is an in-memory fake; the database is real (TEST_DATABASE_URL).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import { z } from "zod";
import { DEFAULT_DEAL_WATCH_SETTINGS, type DealWatchSettings } from "../src/config.js";
import type { CatalogStore, ChainSnapshot } from "../src/deals/catalog.js";
import {
  checkDealWatches, createBody, offerKey, pushText, tellDealWatches, tidyDealWatches, wordsAad, type DealWatchContext,
} from "../src/deals/dealWatches.js";
import { DEFAULT_DEALS_SETTINGS, type LeafletRead, type ReadChain } from "../src/deals/types.js";
import type { ReadProduct } from "../src/deals/vision.js";
import type { Db } from "../src/db.js";
import { dispatchDue, pushData } from "../src/outbox.js";
import { ENCRYPTED_COLUMNS } from "../src/reencrypt.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";
import { OfferSchema } from "./dealsFakes.js";

// ---------- the contract (schemas/fixtures/deal_watch_v1.json), strict ----------

const iso = z.string().datetime();
const catalogChain = z.enum(["biedronka", "lidl", "dino", "aldi", "zabka", "delikatesy", "leclerc", "komfort", "lewiatan", "natura", "action"]);
const WatchSchema = z.strictObject({
  id: z.uuid(), item: z.string().min(1).max(60), maxPriceMinor: z.number().int().positive().optional(), chains: z.array(catalogChain).min(1).optional(),
  language: z.enum(["pl", "en"]), createdAt: iso, endsAt: iso, lastCheckedAt: iso.optional(), found: z.number().int().min(0),
});
const ChainStateSchema = z.strictObject({ chain: catalogChain, readAt: iso, complete: z.boolean() });
const MatchOffer = OfferSchema.refine((o) => !o.check && o.match !== "similar", "only the item, only what the code stands behind");
const CreatedSchema = z.strictObject({ watch: WatchSchema, checkedAt: iso, offers: z.array(MatchOffer).max(20), chains: z.array(ChainStateSchema) });
const ListSchema = z.strictObject({ watches: z.array(WatchSchema).max(50) });
const OffersSchema = z.strictObject({ id: z.uuid(), checkedAt: iso, offers: z.array(MatchOffer).max(20), chains: z.array(ChainStateSchema) });
const fixture = JSON.parse(readFileSync(new URL("../../../../schemas/fixtures/deal_watch_v1.json", import.meta.url), "utf8")) as {
  request: unknown; created: unknown; list: unknown; offers: unknown; errors: Record<string, { status: number; body: unknown }>;
};

test("the deal-watch contract fixture passes the same strict schemas the routes are held to, and its request passes the route's", () => {
  assert.ok(CreatedSchema.safeParse(fixture.created).success, JSON.stringify(CreatedSchema.safeParse(fixture.created).error?.issues));
  assert.ok(ListSchema.safeParse(fixture.list).success);
  assert.ok(OffersSchema.safeParse(fixture.offers).success);
  assert.ok(createBody.safeParse(fixture.request).success);
  assert.deepEqual(Object.keys(fixture.errors).sort(), ["disabled", "invalid", "notFound", "serverFull", "tooMany"]);
});

const HOUR = 3_600_000;
// 10:00 in Warsaw: outside quiet hours (21:00–08:00).
const MORNING = new Date("2026-11-13T09:00:00.000Z");

type Row = [name: string, minor: number, opts?: { lowConfidence?: boolean }];

/** One chain's snapshot: one leaflet page whose reader read these products (test data, not real prices). */
function snapshot(chain: ReadChain, rows: Row[], scannedAt = MORNING): ChainSnapshot {
  const leaflet: LeafletRead = {
    leaflet: { title: "Gazetka", url: `https://${chain}.example/gazetka`, validFrom: "2026-11-10", validTo: "2026-11-30" },
    products: [], pages: [{ number: 1, imageUrl: `https://img.example/${chain}/1.png`, url: `https://${chain}.example/gazetka#1` }], strategy: "all",
  };
  const products: ReadProduct[] = rows.map(([name, minor, o]) => ({ name, price: { minor, currency: "PLN" }, conditions: [], lowConfidence: !!o?.lowConfidence }));
  return { chain, scannedAt: scannedAt.toISOString(), leaflets: [leaflet], reads: { "0:1": { products, promotions: [] } }, complete: true, reasons: [] };
}

class FakeCatalog implements CatalogStore {
  held = new Map<ReadChain, ChainSnapshot>();
  set(s: ChainSnapshot) { this.held.set(s.chain, s); return this; }
  async snapshots(chains: readonly ReadChain[]) { return new Map([...this.held].filter(([c]) => chains.includes(c))); }
}

describe("deal watches", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => {
    await db.query("DELETE FROM deal_watches");
    await db.query("DELETE FROM outbound_messages");
  });

  async function world(opts: { settings?: Partial<DealWatchSettings>; catalogOn?: boolean; wired?: boolean } = {}) {
    const clock = { now: MORNING };
    const catalog = new FakeCatalog()
      .set(snapshot("biedronka", [["Masło Extra 82% 200 g", 499], ["Margaryna Kasia 250 g", 399], ["Mleko UHT 3,2% 1 l", 329]]))
      .set(snapshot("lidl", [["Masło ekstra Pilos 200 g", 549]]));
    const logs: { msg: string; extra?: object }[] = [];
    const base = await testApp(db, {
      deals: { settings: { ...DEFAULT_DEALS_SETTINGS, catalog: { enabled: opts.catalogOn ?? true, everyHours: 6, maxPagesPerChain: 10 } }, catalog },
      ...(opts.wired === false ? {} : { dealWatches: { settings: { ...DEFAULT_DEAL_WATCH_SETTINGS, ...opts.settings }, now: () => clock.now } }),
      watchLog: (msg, extra) => logs.push({ msg, extra }),
    });
    const newAccount = async (withPush = true) => {
      const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
      const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
      const h = { authorization: `Bearer ${deviceToken}` };
      if (withPush) {
        const p = await base.app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h, payload: { token: "ab".repeat(32), environment: "production" } });
        assert.ok(p.statusCode < 300, p.body);
      }
      return { accountId, h };
    };
    const me = await newAccount();
    const api = (method: "GET" | "POST" | "DELETE", url: string, payload?: unknown, headers: object = me.h) =>
      base.app.inject({ method, url, headers: headers as Record<string, string>, payload: payload as never });
    const ctx = base.app.dealWatchContext as DealWatchContext;
    const watch = async (body: object, headers: object = me.h) => {
      const r = await api("POST", "/v1/deal-watches", body, headers);
      assert.equal(r.statusCode, 201, r.body);
      return r.json() as { watch: { id: string; item: string }; offers: { product: string; price: { minor: number }; match: string }[]; chains: unknown[] };
    };
    const pushes = async () => (await db.query<{ idempotency_key: string }>(
      "SELECT idempotency_key FROM outbound_messages WHERE idempotency_key LIKE 'deal-watch:%' ORDER BY created_at, idempotency_key")).rows.map((r) => r.idempotency_key);
    return { ...base, clock, catalog, logs, api, ctx, watch, pushes, me, newAccount, advance: (ms: number) => { clock.now = new Date(clock.now.getTime() + ms); } };
  }

  test("off unless switched on, with the key and the catalog: every route answers 503 and nothing is stored", async () => {
    for (const w of [await world({ wired: false }), await world({ catalogOn: false })]) {
      for (const [method, url] of [["POST", "/v1/deal-watches"], ["GET", "/v1/deal-watches"], ["GET", `/v1/deal-watches/${crypto.randomUUID()}/offers`],
        ["DELETE", `/v1/deal-watches/${crypto.randomUUID()}`]] as const) {
        const r = await w.api(method, url, method === "POST" ? { item: "masło", language: "pl" } : undefined);
        assert.equal(r.statusCode, 503, `${method} ${url}`);
        assert.deepEqual(r.json(), { error: "deal_watches_disabled" });
      }
    }
    const { rows } = await db.query("SELECT count(*)::int AS n FROM deal_watches");
    assert.equal(rows[0].n, 0);
  });

  test("strict bodies: unknown fields, an empty item, a chain the catalog doesn't read, a price of 0 are refused by field", async () => {
    const w = await world();
    const bad = async (body: object) => {
      const r = await w.api("POST", "/v1/deal-watches", body);
      assert.equal(r.statusCode, 400, JSON.stringify(body));
      return (r.json() as { fields: string[] }).fields;
    };
    assert.deepEqual(await bad({ item: "masło", language: "pl", note: "x" }), [""]);
    assert.deepEqual(await bad({ item: "  ", language: "pl" }), ["item"]);
    assert.deepEqual(await bad({ item: "masło", language: "pl", chains: ["rossmann"] }), ["chains.0"]);
    assert.deepEqual(await bad({ item: "masło", language: "pl", chains: ["lidl", "lidl"] }), ["chains"]);
    assert.deepEqual(await bad({ item: "masło", language: "pl", maxPriceMinor: 0 }), ["maxPriceMinor"]);
    assert.deepEqual(await bad({ item: "x".repeat(61), language: "pl" }), ["item"]);
    assert.equal((await w.api("POST", "/v1/deal-watches", { item: "masło", language: "pl" }, {})).statusCode, 401, "a device token is needed");
  });

  test("made: what matches now comes back at once (the item only, under the price), the words are stored encrypted, nothing else", async () => {
    const w = await world();
    const made = await w.watch({ item: "masło", maxPriceMinor: 500, language: "pl" });
    const parsed = CreatedSchema.safeParse(made);
    assert.ok(parsed.success, JSON.stringify(parsed.error?.issues));
    assert.deepEqual(made.offers.map((o) => [o.product, o.price.minor, o.match]), [["Masło Extra 82% 200 g", 499, "exact"]],
      "Lidl's 5,49 is over 5 zł; margarine is similar, never the item");
    assert.equal(made.watch.item, "masło");
    assert.equal(made.chains.length, 2);
    const { rows: [row] } = await db.query("SELECT * FROM deal_watches WHERE id = $1", [made.watch.id]);
    assert.deepEqual(Object.keys(row).sort(), ["account_id", "chains", "created_at", "ends_at", "id", "key_version", "language", "last_checked_at",
      "max_price_minor", "words_ciphertext"]);
    assert.equal(row.max_price_minor, 500);
    assert.equal(row.chains, null);
    assert.equal(Buffer.from(row.words_ciphertext).includes(Buffer.from("mas")), false, "the words are not in plain text");
    assert.equal(testCipher.decrypt(row.words_ciphertext, wordsAad(w.me.accountId, made.watch.id)), JSON.stringify({ item: "masło" }));
    assert.equal(row.ends_at.getTime() - row.created_at.getTime(), 60 * 24 * HOUR);
    // What matched at once is recorded as shown in the app, so it is never pushed later.
    const { rows: hits } = await db.query("SELECT told_by FROM deal_watch_hits WHERE watch_id = $1", [made.watch.id]);
    assert.deepEqual(hits, [{ told_by: "app" }]);
    assert.ok(ENCRYPTED_COLUMNS.some((c) => c.table === "deal_watches" && c.column === "words_ciphertext"), "a key rotation rewrites them");
    assert.equal(JSON.stringify(w.logs).includes("mas"), false, "logs carry ids and counts, never words");
  });

  test("list, offers and delete are the account's own; another account sees nothing and can't delete", async () => {
    const w = await world();
    const made = await w.watch({ item: "mleko", chains: ["biedronka"], language: "en" });
    const list = (await w.api("GET", "/v1/deal-watches")).json() as { watches: { id: string; item: string; chains?: string[]; found: number }[] };
    assert.ok(ListSchema.safeParse(list).success);
    assert.deepEqual(list.watches.map((x) => [x.id, x.item, x.chains, x.found]), [[made.watch.id, "mleko", ["biedronka"], 0]]);
    const offers = await w.api("GET", `/v1/deal-watches/${made.watch.id}/offers`);
    assert.equal(offers.statusCode, 200);
    assert.ok(OffersSchema.safeParse(offers.json()).success, offers.body);
    assert.deepEqual((offers.json() as { offers: { product: string }[] }).offers.map((o) => o.product), ["Mleko UHT 3,2% 1 l"]);
    const other = await w.newAccount();
    assert.deepEqual((await w.api("GET", "/v1/deal-watches", undefined, other.h)).json(), { watches: [] });
    assert.equal((await w.api("GET", `/v1/deal-watches/${made.watch.id}/offers`, undefined, other.h)).statusCode, 404);
    assert.equal((await w.api("DELETE", `/v1/deal-watches/${made.watch.id}`, undefined, other.h)).statusCode, 404);
    assert.equal((await w.api("DELETE", `/v1/deal-watches/${made.watch.id}`)).statusCode, 204);
    const { rows } = await db.query("SELECT (SELECT count(*)::int FROM deal_watches) AS w, (SELECT count(*)::int FROM deal_watch_hits) AS h");
    assert.deepEqual(rows[0], { w: 0, h: 0 }, "the watch and what it found are gone");
  });

  test("caps: watches per account, and for the server", async () => {
    const w = await world({ settings: { maxPerAccount: 2, maxPerServer: 3 } });
    await w.watch({ item: "masło", language: "pl" });
    await w.watch({ item: "mleko", language: "pl" });
    const third = await w.api("POST", "/v1/deal-watches", { item: "kawa", language: "pl" });
    assert.equal(third.statusCode, 409);
    assert.deepEqual(third.json(), { error: "too_many_watches" });
    const other = await w.newAccount();
    await w.watch({ item: "kawa", language: "pl" }, other.h);
    const full = await w.api("POST", "/v1/deal-watches", { item: "herbata", language: "pl" }, other.h);
    assert.deepEqual([full.statusCode, full.json()], [409, { error: "server_full" }]);
  });

  test("a new offer under the price after a scan: one push, a kind only; the same offer is never pushed twice", async () => {
    const w = await world();
    const made = await w.watch({ item: "masło", maxPriceMinor: 500, language: "pl" });
    w.advance(HOUR);
    w.catalog.set(snapshot("lidl", [["Masło ekstra Pilos 200 g", 479]], w.clock.now));
    const counts = await checkDealWatches(w.ctx, ["lidl"]);
    assert.deepEqual(counts, { checked: 1, new_offers: 1, told: 1 });
    const keys = await w.pushes();
    assert.equal(keys.length, 1);
    assert.match(keys[0]!, new RegExp(`^deal-watch:${made.watch.id}:[0-9a-f]{32}$`));
    assert.deepEqual(pushData(keys[0]), { kind: "deal-watch" });
    // The push says nothing of the item, the shop or the price. (Queued on the test's clock, an hour ahead of the database's.)
    await db.query("UPDATE outbound_messages SET send_at = now() - interval '1 minute' WHERE idempotency_key = $1", [keys[0]]);
    await dispatchDue(db, { push: w.push, sms: w.sms, cipher: testCipher });
    assert.deepEqual(w.push.sent.map((s) => [s.body, s.data]), [[pushText("pl"), { kind: "deal-watch" }]]);
    assert.doesNotMatch(pushText("pl") + pushText("en"), /mas|lidl|4,79|zł/i);

    // Checked at most once a day: a scan an hour later checks nothing.
    w.advance(HOUR);
    assert.deepEqual(await checkDealWatches(w.ctx, ["lidl"]), {});
    // A day later the same offer is still there: no second push.
    w.advance(24 * HOUR);
    assert.deepEqual(await checkDealWatches(w.ctx, ["lidl"]), { checked: 1 });
    assert.equal((await w.pushes()).length, 1);
    const list = (await w.api("GET", "/v1/deal-watches")).json() as { watches: { found: number; lastCheckedAt: string }[] };
    assert.equal(list.watches[0]!.found, 1);
    assert.equal(list.watches[0]!.lastCheckedAt, w.clock.now.toISOString());
  });

  test("only the item, only an offer the code stands behind, only under the price, only the watch's chains", async () => {
    const w = await world();
    await w.watch({ item: "masło", maxPriceMinor: 500, chains: ["biedronka"], language: "pl" });
    w.advance(25 * HOUR);
    w.catalog.set(snapshot("biedronka", [
      ["Masło Extra 82% 200 g", 499], ["Masło Polskie 200 g", 449, { lowConfidence: true }], ["Masło Łaciate 200 g", 599], ["Margaryna Rama 400 g", 299],
    ], w.clock.now));
    w.catalog.set(snapshot("lidl", [["Masło ekstra Pilos 200 g", 399]], w.clock.now));
    assert.deepEqual(await checkDealWatches(w.ctx, ["biedronka", "lidl"]), { checked: 1 });
    assert.deepEqual(await w.pushes(), []);
  });

  test("a brand watch: 'Pampers' finds Pampers, never Dada's nappies", async () => {
    const w = await world();
    w.catalog.set(snapshot("biedronka", [["Pieluchy Dada Extra Soft 4", 3999]]));
    const made = await w.watch({ item: "Pampers", language: "pl" });
    assert.deepEqual(made.offers, []);
    w.advance(25 * HOUR);
    w.catalog.set(snapshot("biedronka", [["Pieluchy Dada Extra Soft 4", 3999], ["Pampers Active Baby 4, 76 szt.", 6999]], w.clock.now));
    assert.deepEqual(await checkDealWatches(w.ctx, ["biedronka"]), { checked: 1, new_offers: 1, told: 1 });
  });

  test("several new offers at once: one push for the watch, the rest shown in the app", async () => {
    const w = await world();
    await w.watch({ item: "kawa", language: "pl" });
    w.advance(HOUR);
    w.catalog.set(snapshot("biedronka", [["Kawa mielona Jacobs 500 g", 2499], ["Lavazza Qualità Rossa 250 g", 1999]], w.clock.now));
    assert.deepEqual(await checkDealWatches(w.ctx, ["biedronka"]), { checked: 1, new_offers: 2, told: 1 });
    const { rows } = await db.query("SELECT told_by, count(*)::int AS n FROM deal_watch_hits GROUP BY told_by ORDER BY told_by");
    assert.deepEqual(rows, [{ told_by: "app", n: 1 }, { told_by: "push", n: 1 }]);
  });

  test("quiet hours hold the push until the morning; a push more than a day late is shown in the app only", async () => {
    const w = await world();
    await w.watch({ item: "masło", language: "pl" });
    w.clock.now = new Date("2026-11-13T21:30:00.000Z"); // 22:30 in Warsaw
    w.catalog.set(snapshot("lidl", [["Masło ekstra Pilos 200 g", 479]], w.clock.now));
    assert.deepEqual(await checkDealWatches(w.ctx, ["lidl"]), { checked: 1, new_offers: 1 });
    assert.deepEqual(await w.pushes(), []);
    w.clock.now = new Date("2026-11-14T07:15:00.000Z"); // 08:15
    assert.deepEqual(await tellDealWatches(w.ctx), { pushed: 1 });
    assert.equal((await w.pushes()).length, 1);

    const late = await world();
    await late.watch({ item: "mleko", language: "pl" });
    late.clock.now = new Date("2026-11-13T21:30:00.000Z");
    late.catalog.set(snapshot("lidl", [["Mleko 2% 1 l", 299]], late.clock.now));
    await checkDealWatches(late.ctx, ["lidl"]);
    late.clock.now = new Date("2026-11-15T09:00:00.000Z");
    assert.deepEqual(await tellDealWatches(late.ctx), { stale: 1 });
    assert.equal((await late.pushes()).length, 1, "only the first watch's push of the morning");
  });

  test("the account's daily cap and an account with no device: shown in the app only", async () => {
    const w = await world({ settings: { pushesPerDay: 1 } });
    await w.watch({ item: "masło", language: "pl" });
    await w.watch({ item: "mleko", language: "pl" });
    w.advance(HOUR);
    w.catalog.set(snapshot("lidl", [["Masło ekstra Pilos 200 g", 479], ["Mleko 2% 1 l", 299]], w.clock.now));
    const counts = await checkDealWatches(w.ctx, ["lidl"]);
    assert.equal(counts.told, 1);
    assert.equal((await w.pushes()).length, 1);
    const { rows } = await db.query("SELECT told_by FROM deal_watch_hits WHERE found_at > $1 ORDER BY told_by", [MORNING]);
    assert.deepEqual(rows.map((r) => r.told_by), ["app", "push"]);

    const quiet = await world();
    const noDevice = await quiet.newAccount(false);
    await quiet.watch({ item: "kawa", language: "pl" }, noDevice.h);
    quiet.advance(HOUR);
    quiet.catalog.set(snapshot("biedronka", [["Kawa mielona Jacobs 500 g", 2499]], quiet.clock.now));
    assert.deepEqual(await checkDealWatches(quiet.ctx, ["biedronka"]), { checked: 1, new_offers: 1 });
    assert.equal((await quiet.pushes()).length, 1, "no push for an account without a device");
    const { rows: told } = await db.query("SELECT told_by FROM deal_watch_hits h JOIN deal_watches w ON w.id = h.watch_id WHERE w.account_id = $1", [noDevice.accountId]);
    assert.deepEqual(told.map((r) => r.told_by), ["app"]);
  });

  test("an offer's key is a keyed hash of the watch and the offer, the same each time and different per watch", () => {
    const o = { chain: "lidl" as const, product: "Masło", price: { minor: 479, currency: "PLN" as const }, conditions: [], source: { url: "https://lidl.example/1" },
      readBy: "page_image" as const, check: false };
    assert.deepEqual(offerKey(testCipher, "a", o), offerKey(testCipher, "a", o));
    assert.notDeepEqual(offerKey(testCipher, "a", o), offerKey(testCipher, "b", o));
    assert.equal(offerKey(testCipher, "a", o).length, 16);
  });

  test("ended watches are deleted with what they found; deleting the account deletes its watches", async () => {
    const w = await world({ settings: { days: 1 } });
    await w.watch({ item: "masło", language: "pl" });
    w.advance(25 * HOUR);
    assert.deepEqual(await tidyDealWatches(w.ctx), { ended: 1 });
    await w.watch({ item: "mleko", language: "pl" });
    assert.equal((await w.api("DELETE", "/v1/account")).statusCode, 204);
    const { rows } = await db.query("SELECT (SELECT count(*)::int FROM deal_watches) AS w, (SELECT count(*)::int FROM deal_watch_hits) AS h");
    assert.deepEqual(rows[0], { w: 0, h: 0 });
  });
});
