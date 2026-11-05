// Price watches end to end against real Postgres, through the HTTP API and the worker's passes, with a fake shop in
// place of the real pages and a clock the test moves (docs/implementation/SHOPPING_WATCH.md). Nothing here reaches a
// shop, Apple or Anthropic; no model is involved in watches at all.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import { DEFAULT_WATCH_SETTINGS, type WatchSettings } from "../src/config.js";
import type { Db } from "../src/db.js";
import { bodyAad, dispatchDue } from "../src/outbox.js";
import type { FetchOutcome } from "../src/shopping/pagecheck.js";
import { watchContext, type WatchContext } from "../src/watches/context.js";
import { approveWatch, createWatch } from "../src/watches/service.js";
import { BATCH, claimDue, CLAIM_MINUTES, newWatchLoopState, runWatchPasses } from "../src/watches/worker.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";
import {
  blocked, disallowed, failedRead, FakeShop, FX_URL, gate, noPricePage, pdfPage, productPage, watchFixture as fx,
} from "./watchesFakes.js";

const HOUR = 3_600_000;
const SIX = 6 * HOUR;
const DAY = 86_400_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const WORDS = ["Zmywarka", "Media Expert", "mediaexpert", "przyklad-45", "https://"];
type PageSetting = Parameters<FakeShop["set"]>[1];

describe("price watches against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  // The worker claims due watches of any account and the dispatcher sends any due message: each test starts with none.
  beforeEach(async () => { await db.query("DELETE FROM price_watches; DELETE FROM outbound_messages;"); });

  interface WorldOptions {
    settings?: Partial<WatchSettings>;
    /** Which wiring the app gets (default "on"). */
    wiring?: "on" | "none" | "disabled" | "no_fetcher" | "no_cipher";
    jitterMs?: number;
  }

  async function world(opts: WorldOptions = {}) {
    // Four days in the past, so pushes queued while the test steps through days are due for the dispatcher (DB clock).
    const clock = { now: new Date(Math.floor(Date.now() / 1000) * 1000 - 4 * DAY) };
    const shop = new FakeShop(() => clock.now.getTime());
    const sleeps: number[] = [];
    const logs: { msg: string; extra?: object }[] = [];
    const wiring = opts.wiring ?? "on";
    const watches = wiring === "none" ? undefined : {
      settings: { ...DEFAULT_WATCH_SETTINGS, ...opts.settings, ...(wiring === "disabled" ? { enabled: false } : {}) },
      fetcher: wiring === "no_fetcher" ? undefined : shop,
      now: () => clock.now,
      sleep: async (ms: number) => { sleeps.push(ms); clock.now = new Date(clock.now.getTime() + ms); },
      jitterMs: () => opts.jitterMs ?? 0,
    };
    const base = await testApp(db, {
      ...(wiring === "no_cipher" ? { cipher: undefined } : {}),
      ...(watches ? { watches } : {}),
      watchLog: (msg, extra) => logs.push({ msg, extra }),
    });
    const newAccount = async () => {
      const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
      const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
      return { accountId, h: { authorization: `Bearer ${deviceToken}` } };
    };
    const me = await newAccount();
    const api = (method: "GET" | "POST" | "DELETE" | "PUT", url: string, payload?: unknown, headers: object = me.h) =>
      base.app.inject({ method, url, headers: headers as Record<string, string>, payload: payload as never });
    const ctx = base.app.watchContext as WatchContext;
    const tickOn = (state = newWatchLoopState()) => runWatchPasses(ctx, state);
    const state = newWatchLoopState();
    const w = {
      ...base, shop, clock, sleeps, logs, api, ctx, state, accountId: me.accountId, h: me.h, newAccount,
      tick: () => runWatchPasses(ctx, state),
      tickOn,
      advance: (ms: number) => { clock.now = new Date(clock.now.getTime() + ms); },
    };
    return w;
  }
  type World = Awaited<ReturnType<typeof world>>;

  /** Makes a draft: the shop shows `page` at the request's address (default: above the number). */
  async function draft(w: World, over: object = {}, page?: PageSetting) {
    const req = { ...fx.request, ...over };
    if (page) w.shop.set(req.url, page);
    else if (!w.shop.has(req.url)) w.shop.set(req.url, productPage(1899));
    const r = await w.api("POST", "/v1/watches", req);
    assert.equal(r.statusCode, 201, r.body);
    return r.json() as { id: string; digest: string; expiresAt: string; currentMinor: number };
  }
  /** A draft, approved with its own digest. */
  async function watchIt(w: World, over: object = {}, page?: PageSetting) {
    const d = await draft(w, over, page);
    const a = await w.api("POST", `/v1/watches/${d.id}/approve`, { digest: d.digest });
    assert.equal(a.statusCode, 202, a.body);
    return { ...d, endsAt: (a.json() as { endsAt: string }).endsAt, createdAt: w.clock.now.toISOString() };
  }
  const row = async (id: string) => (await db.query("SELECT * FROM price_watches WHERE id = $1", [id])).rows[0];
  const count = async (accountId?: string) =>
    (await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM price_watches ${accountId ? "WHERE account_id = $1" : ""}`, accountId ? [accountId] : [])).rows[0]!.n;
  const pushToken = (w: World, h: object = w.h) => w.api("PUT", "/v1/device/push-token", { token: "ab".repeat(32), environment: "sandbox" }, h);
  /** What was queued for the account, decrypted: the push words. */
  async function queued(accountId: string): Promise<string[]> {
    const { rows } = await db.query<{ id: string; channel: string; body_ciphertext: Buffer }>(
      "SELECT id, channel, body_ciphertext FROM outbound_messages WHERE account_id = $1 ORDER BY send_at, id", [accountId]);
    return rows.map((r) => {
      assert.equal(r.channel, "push");
      return testCipher.decrypt(r.body_ciphertext, bodyAad(accountId, r.id));
    });
  }
  const iso = (ms: number) => new Date(ms).toISOString();

  // ---------- create ----------

  test("create reads the page once and answers the contract's preview; the stored row holds nothing readable", async () => {
    const w = await world();
    w.shop.set(FX_URL, productPage(1899));
    const r = await w.api("POST", "/v1/watches", fx.request);
    assert.equal(r.statusCode, 201, r.body);
    const p = r.json();
    assert.deepEqual(Object.keys(p), Object.keys(fx.preview), "the contract's fields, in the contract's order");
    assert.match(p.id, UUID);
    assert.equal(p.digest, fx.digest, "the same request has the fixture's digest");
    assert.deepEqual({ ...p, id: "", checkedAt: "", expiresAt: "" }, { ...fx.preview, id: "", checkedAt: "", expiresAt: "" });
    assert.equal(p.currentMinor, 189900);
    assert.equal(p.checkedAt, w.clock.now.toISOString());
    assert.equal(new Date(p.expiresAt).getTime() - w.clock.now.getTime(), 10 * 60_000);
    assert.equal(w.shop.count(), 1, "the page was read exactly once");

    const raw = await row(p.id);
    assert.equal(raw.state, "draft");
    assert.equal(raw.account_id, w.accountId);
    assert.equal(raw.payload_digest.toString("hex"), fx.digest);
    assert.equal(raw.threshold_minor, "180000");
    assert.equal(raw.currency, "PLN");
    assert.equal(raw.checks_done, 0);
    assert.equal(raw.approved_at, null);
    for (const [col, v] of Object.entries(raw)) {
      const bytes = Buffer.isBuffer(v) ? v : Buffer.from(JSON.stringify(v) ?? "", "utf8");
      for (const word of WORDS) assert.equal(bytes.includes(Buffer.from(word, "utf8")), false, `column ${col} holds "${word}"`);
    }
    // Encrypted for this account and this row only.
    const blob = JSON.parse(testCipher.decrypt(raw.content_ciphertext, `${w.accountId}:watch:${p.id}`));
    assert.deepEqual(blob, { language: "pl", shop: fx.request.shop, title: fx.request.title, url: FX_URL });
    assert.throws(() => testCipher.decrypt(raw.content_ciphertext, `${w.accountId}:watch:${randomUUID()}`), "another row");
    assert.throws(() => testCipher.decrypt(raw.content_ciphertext, `${randomUUID()}:watch:${p.id}`), "another account");

    // A draft reads as a draft with its window, and is left out of the list.
    const got = (await w.api("GET", `/v1/watches/${p.id}`)).json();
    assert.deepEqual(got, {
      id: p.id, state: "draft", title: fx.request.title, shop: fx.request.shop, url: FX_URL, thresholdMinor: 180000, currency: "PLN",
      language: "pl", createdAt: w.clock.now.toISOString(), expiresAt: p.expiresAt, checksDone: 0,
    });
    assert.deepEqual((await w.api("GET", "/v1/watches")).json(), { watches: [] });
    await w.app.close();
  });

  test("create stores the words exactly as sent, and a price one grosz above the number is a draft", async () => {
    const w = await world();
    const over = { title: "  Zmywarka  45 cm  ", shop: "Media  Expert ", thresholdMinor: 180000 };
    const d = await draft(w, over, productPage("1800.01"));
    assert.equal(d.currentMinor, 180001);
    const got = (await w.api("GET", `/v1/watches/${d.id}`)).json();
    assert.equal(got.title, over.title);
    assert.equal(got.shop, over.shop);
    await w.app.close();
  });

  test("create: every refusal in the contract, and nothing is stored for any of them", async () => {
    const w = await world();
    const create = (over: object = {}) => w.api("POST", "/v1/watches", { ...fx.request, ...over });
    const refused = async (page: PageSetting, status: number, body: object, over: object = {}) => {
      w.shop.set(FX_URL, page);
      const r = await create(over);
      assert.equal(r.statusCode, status, r.body);
      assert.deepEqual(r.json(), body);
    };
    await refused(blocked, 422, { error: "price_not_readable", reason: "blocked" });
    await refused(disallowed, 422, { error: "price_not_readable", reason: "not_allowed" });
    await refused(failedRead, 422, { error: "price_not_readable", reason: "failed" });
    await refused(noPricePage, 422, { error: "price_not_readable", reason: "no_price" });
    await refused(pdfPage, 422, { error: "price_not_readable", reason: "no_price" });
    await refused(() => { throw new Error("boom"); }, 422, { error: "price_not_readable", reason: "failed" });
    await refused(productPage(15, { currency: "EUR" }), 422, { error: "currency_mismatch" });
    await refused(productPage(1500), 422, { error: "already_below", currentMinor: 150000 });
    await refused(productPage(1800), 422, { error: "already_below", currentMinor: 180000 }); // at the number
    await refused(productPage(1800), 422, { error: "currency_mismatch" }, { currency: "EUR" }); // a price in another currency can't be compared
    // An address that isn't https is a bad request, never read.
    const before = w.shop.count();
    for (const [over, field] of [
      [{ url: "http://shop.example/p" }, "url"], [{ title: " " }, "title"], [{ shop: "" }, "shop"], [{ thresholdMinor: 0 }, "thresholdMinor"],
      [{ thresholdMinor: 1.5 }, "thresholdMinor"], [{ currency: "pln" }, "currency"], [{ language: "PL" }, "language"],
    ] as Array<[object, string]>) {
      const r = await create(over);
      assert.equal(r.statusCode, 400, JSON.stringify(over));
      assert.deepEqual(r.json(), { error: "invalid_request", fields: [field] });
    }
    assert.equal((await create({ extra: 1 })).statusCode, 400);
    assert.equal((await w.api("POST", "/v1/watches", { ...fx.request, digest: "x" })).statusCode, 400);
    assert.equal((await w.api("POST", "/v1/watches")).statusCode, 400, "no body");
    assert.equal(w.shop.count(), before, "an invalid request reads no page");
    assert.equal((await w.api("POST", "/v1/watches", fx.request, {})).statusCode, 401, "a device token is required");
    assert.equal((await w.api("GET", "/v1/watches", undefined, {})).statusCode, 401);
    assert.equal(await count(), 0);
    await w.app.close();
  });

  test("create and approve are limited to 30 an hour per device (429)", async () => {
    const w = await world();
    for (let i = 0; i < 30; i++) assert.equal((await w.api("POST", "/v1/watches", {})).statusCode, 400);
    const r = await w.api("POST", "/v1/watches", {});
    assert.equal(r.statusCode, 429);
    assert.deepEqual(r.json(), { error: "rate_limited" });
    const other = await w.newAccount();
    assert.equal((await w.api("POST", "/v1/watches", {}, other.h)).statusCode, 400, "another device has its own count");
    const missing = "0b9e8d7c-6a5f-4e3d-8c2b-1a0f9e8d7c6b";
    for (let i = 0; i < 30; i++) assert.equal((await w.api("POST", `/v1/watches/${missing}/approve`, { digest: "a".repeat(64) })).statusCode, 404);
    assert.equal((await w.api("POST", `/v1/watches/${missing}/approve`, { digest: "a".repeat(64) })).statusCode, 429);
    await w.app.close();
  });

  test("switched off or not set up: every route answers 503 watches_disabled and nothing is stored or read", async () => {
    for (const wiring of ["none", "disabled", "no_fetcher", "no_cipher"] as const) {
      const w = await world({ wiring });
      const id = "0b9e8d7c-6a5f-4e3d-8c2b-1a0f9e8d7c6b";
      const calls: Array<[Parameters<World["api"]>[0], string, unknown]> = [
        ["POST", "/v1/watches", fx.request], ["POST", `/v1/watches/${id}/approve`, { digest: "a".repeat(64) }], ["GET", "/v1/watches", undefined],
        ["GET", `/v1/watches/${id}`, undefined], ["POST", `/v1/watches/${id}/stop`, undefined], ["DELETE", `/v1/watches/${id}`, undefined],
      ];
      for (const [method, url, payload] of calls) {
        const r = await w.api(method, url, payload);
        assert.equal(r.statusCode, 503, `${wiring} ${method} ${url}`);
        assert.deepEqual(r.json(), { error: "watches_disabled" });
      }
      assert.equal(w.shop.count(), 0, wiring);
      assert.equal(await count(), 0, wiring);
      await w.app.close();
    }
  });

  // ---------- approve ----------

  test("approve: only a draft, only with its own digest, only within 10 minutes, only once", async () => {
    const w = await world();
    const d = await draft(w);
    const approve = (id: string, digest: string, h: object = w.h) => w.api("POST", `/v1/watches/${id}/approve`, { digest }, h);

    const wrong = await approve(d.id, "0".repeat(64));
    assert.equal(wrong.statusCode, 409);
    assert.deepEqual(wrong.json(), { error: "digest_mismatch" });
    assert.equal((await row(d.id)).state, "draft", "a wrong digest changes nothing");
    assert.equal((await w.api("POST", `/v1/watches/${d.id}/approve`, { digest: "xyz" })).statusCode, 400);
    assert.equal((await w.api("POST", `/v1/watches/${d.id}/approve`, { digest: d.digest, extra: 1 })).statusCode, 400);
    assert.equal((await w.api("POST", `/v1/watches/${d.id}/approve`, {})).statusCode, 400);
    assert.equal((await w.api("POST", "/v1/watches/not-a-uuid/approve", { digest: d.digest })).statusCode, 400);

    const stranger = await w.newAccount();
    assert.equal((await approve(d.id, d.digest, stranger.h)).statusCode, 404, "someone else's draft doesn't exist");
    assert.equal((await approve("0b9e8d7c-6a5f-4e3d-8c2b-1a0f9e8d7c6b", d.digest)).statusCode, 404);
    assert.equal((await row(d.id)).state, "draft");

    const approvedAt = w.clock.now;
    const ok = await approve(d.id, d.digest);
    assert.equal(ok.statusCode, 202, ok.body);
    assert.deepEqual(ok.json(), { id: d.id, state: "active", endsAt: iso(approvedAt.getTime() + 30 * DAY) });
    const r = await row(d.id);
    assert.equal(r.state, "active");
    assert.equal(r.approved_at.getTime(), approvedAt.getTime());
    assert.equal(r.ends_at.getTime() - r.approved_at.getTime(), 30 * DAY);
    assert.equal(r.next_check_at.getTime(), approvedAt.getTime() + SIX, "nothing is checked at approval; the first check is one interval later");
    assert.equal(w.shop.count(), 1, "approval reads no page");

    const again = await approve(d.id, d.digest);
    assert.equal(again.statusCode, 409);
    assert.deepEqual(again.json(), { error: "not_approvable", state: "active" });

    // The ten minutes: the last moment inside works, the moment of expiry does not.
    const late = await draft(w, { url: "https://www.euro.com.pl/p/1" });
    const edge = await draft(w, { url: "https://www.euro.com.pl/p/2" });
    w.advance(10 * 60_000 - 1);
    assert.equal((await approve(edge.id, edge.digest)).statusCode, 202);
    w.advance(1);
    const expired = await approve(late.id, late.digest);
    assert.equal(expired.statusCode, 409);
    assert.deepEqual(expired.json(), { error: "not_approvable", state: "expired" });
    assert.equal((await row(late.id)).state, "draft");
    await w.app.close();
  });

  test("approve: at most 5 active watches per account, even when approved at the same moment", async () => {
    const w = await world();
    const drafts: Array<Awaited<ReturnType<typeof draft>>> = [];
    for (let i = 0; i < 7; i++) drafts.push(await draft(w, { url: `https://www.euro.com.pl/p/${i}` }));
    const results = await Promise.all(drafts.map((d) => w.api("POST", `/v1/watches/${d.id}/approve`, { digest: d.digest })));
    const codes = results.map((r) => r.statusCode).sort();
    assert.deepEqual(codes, [202, 202, 202, 202, 202, 409, 409]);
    for (const r of results.filter((x) => x.statusCode === 409)) assert.deepEqual(r.json(), { error: "too_many_open_watches" });
    assert.equal((await db.query("SELECT count(*)::int AS n FROM price_watches WHERE state = 'active'")).rows[0].n, 5);

    // A place frees up when one stops; another account has its own five.
    const pairs = results.map((r, i) => ({ r, d: drafts[i]! }));
    const taken = pairs.filter((p) => p.r.statusCode === 202).map((p) => p.d);
    const refused = pairs.filter((p) => p.r.statusCode === 409).map((p) => p.d);
    assert.equal((await w.api("POST", `/v1/watches/${taken[0]!.id}/stop`)).statusCode, 204);
    assert.equal((await w.api("POST", `/v1/watches/${refused[0]!.id}/approve`, { digest: refused[0]!.digest })).statusCode, 202);
    assert.equal((await w.api("POST", `/v1/watches/${refused[1]!.id}/approve`, { digest: refused[1]!.digest })).statusCode, 409);
    const other = await world();
    for (let i = 0; i < 5; i++) await watchIt(other, { url: `https://www.euro.com.pl/q/${i}` });
    assert.equal(await count(other.accountId), 5);
    await w.app.close();
    await other.app.close();
  });

  test("approve honours WATCHES_MAX_OPEN, and the first check is one WATCHES_CHECK_HOURS (and the shift) later", async () => {
    const w = await world({ settings: { maxOpen: 1, checkHours: 1 }, jitterMs: 90_000 });
    const a = await watchIt(w, { url: "https://www.euro.com.pl/p/a" });
    const d = await draft(w, { url: "https://www.euro.com.pl/p/b" });
    const second = await w.api("POST", `/v1/watches/${d.id}/approve`, { digest: d.digest });
    assert.equal(second.statusCode, 409);
    assert.deepEqual(second.json(), { error: "too_many_open_watches" });
    assert.equal((await row(a.id)).next_check_at.getTime(), w.clock.now.getTime() + HOUR + 90_000);
    await w.app.close();
  });

  test("nothing is read before the approval, and a draft nobody approves is deleted after 10 minutes", async () => {
    const w = await world();
    const d = await draft(w);
    assert.equal(w.shop.count(), 1);
    w.advance(SIX);
    assert.deepEqual(await w.tick(), { drafts: 1 }, "no check, only the draft's removal");
    assert.equal(w.shop.count(), 1, "the draft was never checked");
    assert.equal(await row(d.id), undefined);
    const kept = await draft(w, { url: "https://www.euro.com.pl/p/9" });
    w.advance(10 * 60_000 - 1);
    assert.deepEqual(await w.tick(), {}, "still inside its ten minutes");
    assert.ok(await row(kept.id));
    w.advance(1);
    assert.deepEqual(await w.tick(), { drafts: 1 });
    await w.app.close();
  });

  // ---------- the checks ----------

  test("a check at or below the number triggers once: the summary, and exactly one push with no product words", async () => {
    const w = await world();
    assert.equal((await pushToken(w)).statusCode, 204);
    const a = await watchIt(w);
    w.shop.set(FX_URL, productPage(1799));
    w.advance(SIX);
    const counts = await w.tick();
    assert.deepEqual(counts, { claimed: 1, triggered: 1 });
    const checkedAt = w.clock.now.toISOString();
    const s = (await w.api("GET", `/v1/watches/${a.id}`)).json();
    assert.deepEqual(s, {
      id: a.id, state: "triggered", title: fx.request.title, shop: fx.request.shop, url: FX_URL, thresholdMinor: 180000, currency: "PLN", language: "pl",
      createdAt: a.createdAt, endsAt: a.endsAt, lastCheckedAt: checkedAt, lastPriceMinor: 179900, checksDone: 1, triggeredAt: checkedAt, triggeredPriceMinor: 179900,
    });
    assert.deepEqual(Object.keys(s).sort(), Object.keys(fx.summaries.triggered!).sort(), "the contract's fields for a triggered watch");

    const words = await queued(w.accountId);
    assert.deepEqual(words, ["Cena, której pilnujesz, spadła."]);
    for (const word of [...WORDS, "Zmywarka", "1799", "1 799", "zł", "PLN"]) assert.equal(words[0]!.includes(word), false, word);

    // Later ticks do nothing: not checked again, not announced again.
    for (let i = 0; i < 4; i++) { w.advance(SIX); assert.deepEqual(await w.tick(), {}); }
    assert.equal(w.shop.count(), 2, "one read at creation, one check");
    assert.equal((await queued(w.accountId)).length, 1);
    assert.equal((await row(a.id)).checks_done, 1);

    // The dispatcher delivers it as it is.
    await dispatchDue(db, { push: w.push, cipher: testCipher });
    assert.deepEqual(w.push.sent.map((p) => p.body), ["Cena, której pilnujesz, spadła."]);
    await w.app.close();
  });

  test("an English watch is announced in English; without a push device the watch is still triggered", async () => {
    const w = await world();
    await pushToken(w);
    const en = await watchIt(w, { language: "en" });
    w.shop.set(FX_URL, productPage(1000));
    w.advance(SIX);
    assert.equal((await w.tick()).triggered, 1);
    assert.deepEqual(await queued(w.accountId), ["A price you're watching dropped."]);
    assert.equal((await w.api("GET", `/v1/watches/${en.id}`)).json().language, "en");

    const quiet = await world();
    const q = await watchIt(quiet);
    quiet.shop.set(FX_URL, productPage(1000));
    quiet.advance(SIX);
    assert.equal((await quiet.tick()).triggered, 1);
    assert.equal((await quiet.api("GET", `/v1/watches/${q.id}`)).json().state, "triggered", "the app shows it when opened");
    assert.deepEqual(await queued(quiet.accountId), []);
    await w.app.close();
    await quiet.app.close();
  });

  test("the price exactly at the number triggers", async () => {
    const w = await world();
    const a = await watchIt(w);
    w.shop.set(FX_URL, productPage(1800));
    w.advance(SIX);
    assert.equal((await w.tick()).triggered, 1);
    const r = await row(a.id);
    assert.equal(r.state, "triggered");
    assert.equal(r.triggered_price_minor, "180000");
    await w.app.close();
  });

  test("no trigger for out of stock, another currency, an unreadable page, or a price above the number", async () => {
    const w = await world({ settings: { maxOpen: 20 } });
    await pushToken(w);
    const scenarios: Array<{ name: string; page: FetchOutcome; failures: number; last: string | null }> = [
      { name: "out of stock below the number", page: productPage(1500, { availability: "OutOfStock" }), failures: 0, last: null },
      { name: "sold out above the number", page: productPage(2500, { availability: "SoldOut" }), failures: 0, last: null },
      { name: "another currency, a tiny number", page: productPage(15, { currency: "EUR" }), failures: 0, last: null },
      { name: "blocked", page: blocked, failures: 1, last: null },
      { name: "not allowed by robots.txt", page: disallowed, failures: 1, last: null },
      { name: "a failed read", page: failedRead, failures: 1, last: null },
      { name: "no structured price (the prose says Cena 1 zł!)", page: noPricePage, failures: 1, last: null },
      { name: "not a page", page: pdfPage, failures: 1, last: null },
      { name: "above the number", page: productPage(1850), failures: 0, last: "185000" },
    ];
    const made = [];
    for (const [i, s] of scenarios.entries()) made.push({ ...s, ...(await watchIt(w, { url: `https://s${i}.example.com/p` })), url: `https://s${i}.example.com/p` });
    for (const m of made) w.shop.set(m.url, m.page);
    w.advance(SIX);
    const counts = await w.tick();
    assert.deepEqual(counts, { claimed: 9, checked: 9 });
    for (const m of made) {
      const r = await row(m.id);
      assert.equal(r.state, "active", m.name);
      assert.equal(r.checks_done, 1, m.name);
      assert.equal(r.consecutive_failures, m.failures, m.name);
      assert.equal(r.last_price_minor, m.last, m.name);
      assert.equal(r.triggered_at, null, m.name);
      assert.equal(r.next_check_at.getTime(), w.clock.now.getTime() + SIX, m.name);
      const s = (await w.api("GET", `/v1/watches/${m.id}`)).json();
      assert.equal("lastPriceMinor" in s, m.last !== null, `${m.name}: a price appears only after a confirmed read`);
      assert.equal(s.lastCheckedAt, w.clock.now.toISOString(), m.name);
    }
    assert.deepEqual(await queued(w.accountId), [], "nothing was announced");
    await w.app.close();
  });

  test("8 failed checks in a row end the watch as failed, with one push that claims nothing about the price", async () => {
    const w = await world();
    await pushToken(w);
    const a = await watchIt(w);
    w.shop.set(FX_URL, blocked);
    for (let i = 1; i <= 7; i++) {
      w.advance(SIX);
      assert.deepEqual(await w.tick(), { claimed: 1, checked: 1 }, `check ${i}`);
    }
    let r = await row(a.id);
    assert.equal(r.state, "active");
    assert.equal(r.consecutive_failures, 7);
    assert.deepEqual(await queued(w.accountId), []);
    w.advance(SIX);
    assert.deepEqual(await w.tick(), { claimed: 1, failed: 1 });
    r = await row(a.id);
    assert.equal(r.state, "failed");
    assert.equal(r.failure, "unreadable");
    assert.equal(r.checks_done, 8);
    assert.equal(r.next_check_at, null);
    assert.equal(r.finished_at.getTime(), w.clock.now.getTime());
    const s = (await w.api("GET", `/v1/watches/${a.id}`)).json();
    assert.deepEqual(s, {
      id: a.id, state: "failed", title: fx.request.title, shop: fx.request.shop, url: FX_URL, thresholdMinor: 180000, currency: "PLN", language: "pl",
      createdAt: a.createdAt, endsAt: a.endsAt, lastCheckedAt: w.clock.now.toISOString(), checksDone: 8, failure: "unreadable",
    });
    assert.deepEqual(Object.keys(s).sort(), Object.keys(fx.summaries.failed!).sort());
    const words = await queued(w.accountId);
    assert.deepEqual(words, ["Nie mogę już odczytać ceny, której pilnujesz."]);
    for (const word of [...WORDS, "spadła", "Zmywarka"]) assert.equal(words[0]!.includes(word), false, word);
    for (let i = 0; i < 3; i++) { w.advance(SIX); assert.deepEqual(await w.tick(), {}); }
    assert.equal((await queued(w.accountId)).length, 1);
    assert.equal(w.shop.count(), 9, "creation plus eight checks, then no more");
    await w.app.close();
  });

  test("a readable check in between resets the run of failures", async () => {
    const w = await world();
    const a = await watchIt(w);
    const step = async (page: FetchOutcome, n: number) => {
      w.shop.set(FX_URL, page);
      for (let i = 0; i < n; i++) { w.advance(SIX); await w.tick(); }
    };
    await step(failedRead, 7);
    assert.equal((await row(a.id)).consecutive_failures, 7);
    await step(productPage(1850), 1);
    assert.equal((await row(a.id)).consecutive_failures, 0);
    await step(failedRead, 7);
    const r = await row(a.id);
    assert.equal(r.state, "active");
    assert.equal(r.checks_done, 15);
    assert.equal(r.consecutive_failures, 7);
    assert.equal(r.last_price_minor, "185000", "the failures never overwrote the last confirmed price");
    await w.app.close();
  });

  test("30 days of checks, 120 of them: the last check comes first, then the watch expires; a drop at the last check still triggers", async () => {
    const w = await world();
    await pushToken(w);
    const quiet = await watchIt(w, { url: "https://www.mediaexpert.pl/p/quiet" });
    const late = await watchIt(w, { url: "https://www.euro.com.pl/p/late" });
    const quietUrl = "https://www.mediaexpert.pl/p/quiet";
    const lateUrl = "https://www.euro.com.pl/p/late";
    for (let k = 1; k <= 120; k++) {
      const { rows } = await db.query<{ m: Date }>("SELECT min(next_check_at) AS m FROM price_watches WHERE state = 'active'");
      w.clock.now = rows[0]!.m;
      if (k === 120) w.shop.set(lateUrl, productPage(1799));
      const counts = await w.tick();
      if (k < 120) assert.deepEqual(counts, { claimed: 2, checked: 2 }, `check ${k}`);
    }
    const q = await row(quiet.id);
    const l = await row(late.id);
    assert.equal(q.state, "expired");
    assert.equal(q.checks_done, 120, "four a day for thirty days");
    assert.equal(q.finished_at.getTime(), q.ends_at.getTime());
    assert.equal(q.last_price_minor, "189900");
    assert.equal(q.next_check_at, null);
    assert.equal(l.state, "triggered", "the final check ran before the watch expired");
    assert.equal(l.triggered_at.getTime(), l.ends_at.getTime());
    assert.equal(l.checks_done, 120);
    assert.equal(w.shop.count(quietUrl), 121);
    assert.deepEqual(await queued(w.accountId), ["Cena, której pilnujesz, spadła."], "expiry sends nothing; the drop sends one push");
    const s = (await w.api("GET", `/v1/watches/${quiet.id}`)).json();
    assert.equal(s.state, "expired");
    assert.equal(s.checksDone, 120);
    await w.app.close();
  });

  test("a worker that was down past the end still makes one check, then expires the watch", async () => {
    const w = await world();
    const a = await watchIt(w);
    const b = await watchIt(w, { url: "https://www.euro.com.pl/p/b" });
    w.shop.set(FX_URL, productPage(1799));
    w.advance(31 * DAY);
    assert.deepEqual(await w.tick(), { claimed: 2, triggered: 1, expired: 1 }, "checked first: a drop wins over expiry");
    assert.equal((await row(a.id)).state, "triggered");
    assert.equal((await row(b.id)).state, "expired");
    assert.equal((await row(b.id)).checks_done, 1, "one check, not thirty days of them");
    await w.app.close();
  });

  test("a due time is never checked twice: two ticks racing, and a tick right after", async () => {
    const w = await world({ settings: { maxOpen: 20 } });
    const ids = [];
    for (let i = 0; i < 6; i++) ids.push((await watchIt(w, { url: `https://h${i}.example.com/p` })).id);
    w.advance(SIX);
    const before = w.shop.count();
    // Two workers (two loop states, as two processes would have) race for the same due watches.
    const [a, b] = await Promise.all([w.tickOn(), w.tickOn()]);
    assert.equal((a.claimed ?? 0) + (b.claimed ?? 0), 6, "every watch was claimed by exactly one worker");
    assert.equal(w.shop.count() - before, 6, "and read exactly once");
    for (const id of ids) assert.equal((await row(id)).checks_done, 1);
    assert.deepEqual(await w.tick(), {}, "nothing is due until the next interval");
    assert.equal(w.shop.count() - before, 6);
    w.advance(SIX);
    assert.equal((await w.tick()).claimed, 6);
    for (const id of ids) assert.equal((await row(id)).checks_done, 2);
    await w.app.close();
  });

  test("while one worker is reading a watch's page, another worker's tick leaves that watch alone", async () => {
    const w = await world();
    const a = await watchIt(w);
    const reading = gate<void>();
    const answer = gate<FetchOutcome>();
    // Only the first request waits: if a second one is ever made, the test fails instead of hanging.
    let requests = 0;
    w.shop.set(FX_URL, async () => {
      if (requests++ > 0) return productPage(1899);
      reading.open();
      return answer.promise;
    });
    w.advance(SIX);
    const first = w.tickOn();
    await reading.promise;
    const calls = w.shop.count();
    assert.deepEqual(await w.tickOn(), {}, "the second worker finds nothing due");
    assert.equal(w.shop.count(), calls, "and reads nothing");
    answer.open(productPage(1899));
    assert.deepEqual(await first, { claimed: 1, checked: 1 });
    assert.equal((await row(a.id)).checks_done, 1);
    await w.app.close();
  });

  test("a claim that was never recorded (the worker died) is picked up again when its claim ends, not before", async () => {
    const w = await world();
    const a = await watchIt(w);
    w.advance(SIX);
    const claimed = await claimDue(w.ctx);
    assert.equal(claimed.length, 1, "the dead worker held it");
    const calls = w.shop.count();
    assert.deepEqual(await w.tick(), {}, "held: not due for anyone else");
    w.advance((CLAIM_MINUTES - 1) * 60_000);
    assert.deepEqual(await w.tick(), {});
    assert.equal(w.shop.count(), calls);
    w.advance(2 * 60_000);
    assert.deepEqual(await w.tick(), { claimed: 1, checked: 1 }, "the claim lapsed: the next tick checks it");
    assert.equal(w.shop.count(), calls + 1);
    assert.equal((await row(a.id)).checks_done, 1, "and it counts once");
    await w.app.close();
  });

  test("a stop that comes while a page is being read wins: the late result is dropped", async () => {
    const w = await world();
    await pushToken(w);
    const a = await watchIt(w);
    const reading = gate<void>();
    const answer = gate<FetchOutcome>();
    w.shop.set(FX_URL, async () => { reading.open(); return answer.promise; });
    w.advance(SIX);
    const ticking = w.tick();
    await reading.promise;
    assert.equal((await w.api("POST", `/v1/watches/${a.id}/stop`)).statusCode, 204);
    answer.open(productPage(1799)); // a drop, arriving too late
    assert.deepEqual(await ticking, { claimed: 1, superseded: 1 });
    const r = await row(a.id);
    assert.equal(r.state, "stopped");
    assert.equal(r.checks_done, 0);
    assert.equal(r.triggered_at, null);
    assert.deepEqual(await queued(w.accountId), [], "no push for a watch the user stopped");
    await w.app.close();
  });

  test("a delete that comes while a page is being read wins: no row, no push", async () => {
    const w = await world();
    await pushToken(w);
    const a = await watchIt(w);
    const reading = gate<void>();
    const answer = gate<FetchOutcome>();
    w.shop.set(FX_URL, async () => { reading.open(); return answer.promise; });
    w.advance(SIX);
    const ticking = w.tick();
    await reading.promise;
    assert.equal((await w.api("DELETE", `/v1/watches/${a.id}`)).statusCode, 204);
    answer.open(productPage(1799));
    assert.deepEqual(await ticking, { claimed: 1, superseded: 1 });
    assert.equal(await row(a.id), undefined);
    assert.deepEqual(await queued(w.accountId), []);
    await w.app.close();
  });

  test("shutdown while a page is being read gives the watch back: it isn't recorded and isn't a failure", async () => {
    const w = await world();
    const a = await watchIt(w);
    const due = (await row(a.id)).next_check_at as Date;
    const reading = gate<void>();
    const answer = gate<FetchOutcome>();
    w.shop.set(FX_URL, async () => { reading.open(); return answer.promise; });
    w.advance(SIX);
    const state = newWatchLoopState();
    const ticking = w.tickOn(state);
    await reading.promise;
    state.shutdown.abort();
    answer.open(blocked);
    assert.deepEqual(await ticking, { claimed: 1, released: 1 });
    const r = await row(a.id);
    assert.equal(r.checks_done, 0);
    assert.equal(r.consecutive_failures, 0);
    assert.equal(r.next_check_at.getTime(), due.getTime(), "due again as before");
    w.shop.set(FX_URL, productPage(1899));
    assert.deepEqual(await w.tick(), { claimed: 1, checked: 1 }, "the next process checks it");
    await w.app.close();
  });

  test("one watch at a time, two seconds apart per host, ten per tick", async () => {
    const w = await world({ settings: { maxOpen: 20 } });
    const urls = [
      "https://www.mediaexpert.pl/p/1", "https://www.mediaexpert.pl/p/2", "https://www.mediaexpert.pl/p/3", "https://www.euro.com.pl/p/1",
    ];
    for (const url of urls) await watchIt(w, { url });
    w.advance(SIX);
    const before = w.shop.calls.length;
    assert.deepEqual(await w.tick(), { claimed: 4, checked: 4 });
    const calls = w.shop.calls.slice(before);
    const onMedia = calls.filter((c) => c.url.includes("mediaexpert"));
    assert.equal(onMedia.length, 3);
    for (let i = 1; i < onMedia.length; i++) assert.ok(onMedia[i]!.at - onMedia[i - 1]!.at >= 2000, "two seconds between requests to one host");
    assert.deepEqual(w.sleeps, [2000, 2000], "the other host never waited");

    // Twelve due at once: ten in the first tick, the rest in the next.
    const many = await world({ settings: { maxOpen: 20 } });
    for (let i = 0; i < 12; i++) await watchIt(many, { url: `https://m${i}.example.com/p` });
    many.advance(SIX);
    assert.equal(BATCH, 10);
    assert.deepEqual(await many.tick(), { claimed: 10, checked: 10 });
    assert.deepEqual(await many.tick(), { claimed: 2, checked: 2 });
    assert.deepEqual(await many.tick(), {});
    await w.app.close();
    await many.app.close();
  });

  test("with watches switched off the worker checks nothing, but still tidies", async () => {
    const w = await world();
    const a = await watchIt(w);
    const stopped = await watchIt(w, { url: "https://www.euro.com.pl/p/s" });
    await w.api("POST", `/v1/watches/${stopped.id}/stop`);
    const off = watchContext(db, { settings: { ...DEFAULT_WATCH_SETTINGS, enabled: false }, fetcher: w.shop, now: () => w.clock.now }, testCipher, undefined, () => {});
    assert.equal(off!.enabled, false);
    const calls = w.shop.count();
    w.advance(SIX);
    assert.deepEqual(await runWatchPasses(off!, newWatchLoopState()), {});
    w.advance(31 * DAY);
    assert.deepEqual(await runWatchPasses(off!, newWatchLoopState()), { swept: 1 }, "the finished watch is still deleted on time");
    assert.equal(w.shop.count(), calls, "nothing was read");
    assert.equal((await row(a.id)).checks_done, 0);
    await w.app.close();
  });

  // ---------- stop, delete, list ----------

  test("stop: only an active watch; it is never checked again", async () => {
    const w = await world();
    const a = await watchIt(w);
    const d = await draft(w, { url: "https://www.euro.com.pl/p/d" });
    const stranger = await w.newAccount();
    assert.equal((await w.api("POST", `/v1/watches/${a.id}/stop`, undefined, stranger.h)).statusCode, 404);
    assert.equal((await w.api("POST", "/v1/watches/0b9e8d7c-6a5f-4e3d-8c2b-1a0f9e8d7c6b/stop")).statusCode, 404);
    assert.equal((await w.api("POST", `/v1/watches/${a.id}/stop`, { reason: "x" })).statusCode, 400, "the body is empty");
    assert.equal((await w.api("POST", `/v1/watches/${d.id}/stop`)).statusCode, 409);
    assert.deepEqual((await w.api("POST", `/v1/watches/${d.id}/stop`)).json(), { error: "not_stoppable", state: "draft" });
    assert.equal((await row(a.id)).state, "active");

    assert.equal((await w.api("POST", `/v1/watches/${a.id}/stop`)).statusCode, 204);
    const r = await row(a.id);
    assert.equal(r.state, "stopped");
    assert.equal(r.next_check_at, null);
    assert.equal(r.finished_at.getTime(), w.clock.now.getTime());
    const again = await w.api("POST", `/v1/watches/${a.id}/stop`);
    assert.equal(again.statusCode, 409);
    assert.deepEqual(again.json(), { error: "not_stoppable", state: "stopped" });
    const calls = w.shop.count();
    w.advance(SIX);
    assert.deepEqual(await w.tick(), { drafts: 1 }, "only the stale draft was tidied; the stopped watch has no work");
    assert.equal(w.shop.count(), calls);
    assert.equal((await w.api("GET", `/v1/watches/${a.id}`)).json().state, "stopped");

    // A triggered watch can't be stopped either: it already ended.
    const t = await watchIt(w, { url: "https://www.euro.com.pl/p/t" });
    w.shop.set("https://www.euro.com.pl/p/t", productPage(1000));
    w.advance(SIX);
    await w.tick();
    assert.deepEqual((await w.api("POST", `/v1/watches/${t.id}/stop`)).json(), { error: "not_stoppable", state: "triggered" });
    await w.app.close();
  });

  test("delete: in any state the row, content and all, is gone when it answers; only your own", async () => {
    const w = await world();
    const stranger = await w.newAccount();
    const active = await watchIt(w, { url: "https://www.euro.com.pl/p/2" });
    const hit = await watchIt(w, { url: "https://www.euro.com.pl/p/3" });
    w.shop.set("https://www.euro.com.pl/p/3", productPage(1000));
    w.advance(SIX);
    await w.tick();
    assert.equal((await row(hit.id)).state, "triggered");
    const failed = await watchIt(w, { url: "https://www.euro.com.pl/p/4" });
    w.shop.set("https://www.euro.com.pl/p/4", blocked);
    for (let i = 0; i < 8; i++) { w.advance(SIX); await w.tick(); }
    assert.equal((await row(failed.id)).state, "failed");
    const stopped = await watchIt(w, { url: "https://www.euro.com.pl/p/5" });
    await w.api("POST", `/v1/watches/${stopped.id}/stop`);
    const draftOne = await draft(w, { url: "https://www.euro.com.pl/p/1" });

    assert.equal((await w.api("DELETE", `/v1/watches/${active.id}`, undefined, stranger.h)).statusCode, 404);
    assert.ok(await row(active.id), "someone else's delete changed nothing");
    for (const id of [draftOne.id, active.id, hit.id, failed.id, stopped.id]) {
      const r = await w.api("DELETE", `/v1/watches/${id}`);
      assert.equal(r.statusCode, 204, id);
      assert.equal(await row(id), undefined, "gone, content and all");
      assert.equal((await w.api("GET", `/v1/watches/${id}`)).statusCode, 404);
      assert.deepEqual((await w.api("DELETE", `/v1/watches/${id}`)).json(), { error: "not_found" });
    }
    assert.equal(await count(w.accountId), 0);
    assert.equal((await w.api("DELETE", "/v1/watches/not-a-uuid")).statusCode, 400);
    await w.app.close();
  });

  test("list: newest first, drafts left out, at most 50; get: your own only; the shapes are the contract's", async () => {
    const w = await world({ settings: { maxOpen: 100 } });
    const stranger = await w.newAccount();
    const ids: string[] = [];
    for (let i = 0; i < 52; i++) {
      w.advance(1000);
      const url = `https://www.euro.com.pl/p/${i}`;
      w.shop.set(url, productPage(1899));
      const c = await createWatch(w.ctx, w.accountId, { ...fx.request, url });
      assert.ok("draft" in c);
      const a = await approveWatch(w.ctx, w.accountId, c.draft.id, c.draft.digest);
      assert.ok("approved" in a);
      ids.push(c.draft.id);
    }
    await draft(w, { url: "https://www.euro.com.pl/p/draft" });
    const list = (await w.api("GET", "/v1/watches")).json().watches as Array<{ id: string; state: string }>;
    assert.equal(list.length, 50);
    assert.deepEqual(list.map((x) => x.id), ids.slice(-50).reverse(), "newest first");
    assert.ok(list.every((x) => x.state === "active"));
    assert.deepEqual(Object.keys(list[0]!).sort(), Object.keys(fx.summaries.active!).sort() .filter((k) => k !== "lastCheckedAt" && k !== "lastPriceMinor"),
      "an active watch that hasn't been checked has no last check or price (never null)");
    assert.deepEqual((await w.api("GET", "/v1/watches", undefined, stranger.h)).json(), { watches: [] });
    assert.equal((await w.api("GET", `/v1/watches/${ids[0]}`, undefined, stranger.h)).statusCode, 404);
    assert.equal((await w.api("GET", `/v1/watches/${ids[0]}`)).statusCode, 200);

    // After a check the active summary has exactly the contract's fields.
    const w2 = await world();
    const a2 = await watchIt(w2);
    w2.advance(SIX);
    await w2.tick();
    const s = (await w2.api("GET", `/v1/watches/${a2.id}`)).json();
    assert.deepEqual(Object.keys(s).sort(), Object.keys(fx.summaries.active!).sort());
    assert.equal(s.state, "active");
    assert.equal(s.checksDone, 1);
    await w.app.close();
    await w2.app.close();
  });

  test("a row whose content can't be opened is left out of the list, and a check of it counts as a failed read", async () => {
    const w = await world();
    const a = await watchIt(w);
    await db.query("UPDATE price_watches SET threshold_minor = 999 WHERE id = $1", [a.id]); // no longer what the user approved
    assert.deepEqual((await w.api("GET", "/v1/watches")).json(), { watches: [] });
    assert.equal((await w.api("GET", `/v1/watches/${a.id}`)).statusCode, 404);
    const calls = w.shop.count();
    w.advance(SIX);
    assert.deepEqual(await w.tick(), { claimed: 1, checked: 1 });
    assert.equal(w.shop.count(), calls, "a row that isn't what was approved is never read");
    const r = await row(a.id);
    assert.equal(r.consecutive_failures, 1);
    assert.equal(r.last_price_minor, null);
    assert.equal((await w.api("DELETE", `/v1/watches/${a.id}`)).statusCode, 204, "but it can still be deleted");
    await w.app.close();
  });

  // ---------- tidying ----------

  test("a finished watch is deleted 30 days after it ended (any end), not a moment before", async () => {
    const w = await world();
    await pushToken(w);
    const stopped = await watchIt(w, { url: "https://www.euro.com.pl/p/s" });
    await w.api("POST", `/v1/watches/${stopped.id}/stop`);
    const hit = await watchIt(w, { url: "https://www.euro.com.pl/p/h" });
    w.shop.set("https://www.euro.com.pl/p/h", productPage(1000));
    const bad = await watchIt(w, { url: "https://www.euro.com.pl/p/b" });
    w.shop.set("https://www.euro.com.pl/p/b", blocked);
    for (let i = 0; i < 8; i++) { w.advance(SIX); await w.tick(); }
    const quiet = await watchIt(w, { url: "https://www.euro.com.pl/p/q" });
    const ended = {
      stopped: (await row(stopped.id)).finished_at.getTime(),
      hit: (await row(hit.id)).finished_at.getTime(),
      bad: (await row(bad.id)).finished_at.getTime(),
    };
    assert.deepEqual((await db.query("SELECT state FROM price_watches ORDER BY state")).rows.map((r) => r.state), ["active", "failed", "stopped", "triggered"]);

    // Just before the 30 days of the earliest end: everything is still there.
    w.clock.now = new Date(Math.min(...Object.values(ended)) + 30 * DAY - 1);
    assert.deepEqual(await w.tick(), { claimed: 1, checked: 1 }, "only the active watch had work (its check is due)");
    assert.equal(await count(), 4);
    // At 30 days after the stop: that one goes; the others, finished later, stay until their own day.
    w.clock.now = new Date(ended.stopped + 30 * DAY);
    assert.equal((await w.tick()).swept, 1);
    assert.equal(await row(stopped.id), undefined);
    w.clock.now = new Date(ended.hit + 30 * DAY);
    assert.equal((await w.tick()).swept, 1, "a drop is kept 30 days too");
    assert.equal(await row(hit.id), undefined);
    assert.ok(await row(bad.id));
    assert.equal((await row(quiet.id)).state, "active", "a watch that hasn't ended is never swept");
    // The failed watch goes on its own day; the quiet one reaches its 30 days at that moment: it expires, it isn't swept the same day.
    w.clock.now = new Date(ended.bad + 30 * DAY);
    const last = await w.tick();
    assert.equal(last.swept, 1);
    assert.equal(last.expired, 1);
    assert.equal(await row(bad.id), undefined);
    assert.equal((await row(quiet.id)).state, "expired");
    assert.equal(await count(), 1);
    await w.app.close();
  });

  test("deleting the account removes its watches, drafts and finished ones alike", async () => {
    const w = await world();
    const other = await world();
    await watchIt(w, { url: "https://www.euro.com.pl/p/1" });
    await draft(w, { url: "https://www.euro.com.pl/p/2" });
    const stopped = await watchIt(w, { url: "https://www.euro.com.pl/p/3" });
    await w.api("POST", `/v1/watches/${stopped.id}/stop`);
    const keep = await watchIt(other);
    assert.equal(await count(w.accountId), 3);
    assert.equal((await w.api("DELETE", "/v1/account")).statusCode, 204);
    assert.equal(await count(w.accountId), 0);
    assert.ok(await row(keep.id), "another account's watch is untouched");
    await w.app.close();
    await other.app.close();
  });

  // ---------- privacy ----------

  test("logs carry ids, outcomes and counts, never words or addresses", async () => {
    const w = await world();
    await pushToken(w);
    const a = await watchIt(w);
    await watchIt(w, { url: "https://www.euro.com.pl/p/b" }, productPage(1899));
    w.shop.set(FX_URL, productPage(1799));
    w.shop.set("https://www.euro.com.pl/p/b", () => { throw new Error("boom https://www.euro.com.pl/p/b Zmywarka"); });
    w.advance(SIX);
    await w.tick();
    // Refusals and every other path that logs.
    w.shop.set("https://www.euro.com.pl/p/c", blocked);
    await w.api("POST", "/v1/watches", { ...fx.request, url: "https://www.euro.com.pl/p/c" });
    await w.api("POST", "/v1/watches", { ...fx.request, url: "http://x.example/p" });
    await w.api("POST", `/v1/watches/${a.id}/stop`);
    await w.api("DELETE", `/v1/watches/${a.id}`);
    await db.query("UPDATE price_watches SET threshold_minor = 5"); // content that no longer opens
    w.advance(SIX);
    await w.tick();
    const text = JSON.stringify(w.logs);
    assert.ok(w.logs.length >= 6, "the test must see real log lines");
    assert.ok(text.includes(a.id), "ids are logged");
    for (const word of [...WORDS, "Zmywarka", "euro.com.pl", "shop", "Expert", "boom", "42 dB", "1799", "179900", "189900", "1899"]) {
      assert.equal(text.includes(word), false, `a log line holds "${word}"`);
    }
    assert.ok(w.logs.some((l) => l.msg === "watch checked"));
    await w.app.close();
  });

  test("the table refuses states the code must never write", async () => {
    const w = await world();
    const a = await watchIt(w);
    const d = await draft(w, { url: "https://www.euro.com.pl/p/d" });
    const refuse = async (sql: string, id = a.id) => assert.rejects(db.query(sql, [id]), /violates check constraint/, sql);
    // triggered without a confirmed read at or below the number
    await refuse("UPDATE price_watches SET state = 'triggered', next_check_at = NULL, finished_at = now() WHERE id = $1");
    await refuse(`UPDATE price_watches SET state = 'triggered', next_check_at = NULL, finished_at = now(), triggered_at = now(),
      triggered_price_minor = 999999, last_price_minor = 999999, checks_done = 1, last_checked_at = now() WHERE id = $1`); // above the number
    await refuse(`UPDATE price_watches SET state = 'triggered', next_check_at = NULL, finished_at = now(), triggered_at = now(),
      triggered_price_minor = 100, checks_done = 1, last_checked_at = now() WHERE id = $1`); // no matching last price
    // failed without 8 failures in a row, or with a code on a watch that didn't fail
    await refuse("UPDATE price_watches SET state = 'failed', failure = 'unreadable', next_check_at = NULL, finished_at = now() WHERE id = $1");
    await refuse("UPDATE price_watches SET failure = 'unreadable' WHERE id = $1");
    await refuse("UPDATE price_watches SET failure = 'blocked', state = 'failed', next_check_at = NULL, finished_at = now(), consecutive_failures = 8, checks_done = 8, last_checked_at = now() WHERE id = $1");
    await refuse("UPDATE price_watches SET consecutive_failures = 8, checks_done = 8, last_checked_at = now() WHERE id = $1"); // 8 failures but still active
    await refuse("UPDATE price_watches SET consecutive_failures = 9, checks_done = 9, last_checked_at = now() WHERE id = $1");
    // counters that don't add up
    await refuse("UPDATE price_watches SET checks_done = 3 WHERE id = $1"); // checks without a last check time
    await refuse("UPDATE price_watches SET last_price_minor = 5 WHERE id = $1"); // a price without a check
    await refuse("UPDATE price_watches SET consecutive_failures = 2 WHERE id = $1"); // more failures than checks
    // the active/ended bookkeeping
    await refuse("UPDATE price_watches SET next_check_at = NULL WHERE id = $1"); // active without a due time
    await refuse("UPDATE price_watches SET state = 'stopped' WHERE id = $1"); // ended without a time, still due
    await refuse("UPDATE price_watches SET ends_at = ends_at + interval '1 hour' WHERE id = $1"); // not 30 days
    await refuse("UPDATE price_watches SET state = 'draft' WHERE id = $1"); // a draft with an approval
    await refuse("UPDATE price_watches SET state = 'paused' WHERE id = $1");
    // a draft is unchecked, unapproved and short-lived
    await refuse("UPDATE price_watches SET checks_done = 1, last_checked_at = now() WHERE id = $1", d.id);
    await refuse("UPDATE price_watches SET state = 'active', approved_at = now() WHERE id = $1", d.id); // active without due time and end
    await refuse("UPDATE price_watches SET expires_at = created_at + interval '11 minutes' WHERE id = $1", d.id);
    // the user's number and the words
    await refuse("UPDATE price_watches SET threshold_minor = 0 WHERE id = $1");
    await refuse("UPDATE price_watches SET threshold_minor = 1000000001 WHERE id = $1");
    await refuse("UPDATE price_watches SET currency = 'pln' WHERE id = $1");
    await refuse("UPDATE price_watches SET language = 'pol' WHERE id = $1");
    await refuse("UPDATE price_watches SET payload_digest = '\\x00' WHERE id = $1");
    await refuse("UPDATE price_watches SET content_key_version = 0 WHERE id = $1");
    await assert.rejects(db.query("UPDATE price_watches SET content_ciphertext = NULL WHERE id = $1", [a.id]), /not-null constraint/, "no row without its content");
    await assert.rejects(db.query("UPDATE price_watches SET account_id = gen_random_uuid() WHERE id = $1", [a.id]), /foreign key/);
    await w.app.close();
  });
});
