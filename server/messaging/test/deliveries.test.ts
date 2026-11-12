import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { deliveryApprovalHash } from "../src/approval.js";
import type { Db } from "../src/db.js";
import { DEFAULT_DELIVERY_LIMITS, pruneDeliveries, type DeliveryDeps, type DeliveryLimits } from "../src/delivery/deliveries.js";
import {
  UberDirectClient, uberAddressJson, type CreateRequest, type DeliveryProvider, type Quote, type QuoteRequest, type UberDelivery,
  type UberOutcome,
} from "../src/delivery/uberDirect.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

// Deliveries through Uber Direct (decision 2026-11-12-uber-direct-deliveries): the Uber client against a
// fake network, and the routes against real Postgres with a scripted stand-in for Uber.

const ADDRESS = { street: "Lipowy Dwór 41c", city: "Iława", postcode: "14-200", country: "PL" };

// ---------------------------------------------------------------------------------------------------------
// The Uber client

type Reply = { status: number; body?: unknown } | Error;

function fakeFetch(replies: Reply[]) {
  const calls: { url: string; init: RequestInit }[] = [];
  const impl = (async (url: string | URL, init: RequestInit = {}) => {
    calls.push({ url: String(url), init });
    const next = replies.shift();
    if (!next) throw new Error("no more replies");
    if (next instanceof Error) throw next;
    return new Response(next.body === undefined ? "" : JSON.stringify(next.body), { status: next.status });
  }) as typeof fetch;
  return { impl, calls };
}

const TOKEN = { status: 200, body: { access_token: "tok-1", expires_in: 2592000 } };
const client = (replies: Reply[], mode: "test" | "live" = "test") => {
  const f = fakeFetch(replies);
  return { c: new UberDirectClient({ clientId: "client-id", clientSecret: "client-secret", customerId: "cus_12345678", mode },
    f.impl, () => 1_000_000), calls: f.calls };
};
const createReq: CreateRequest = {
  quoteId: "dqt_1", pickupName: "Pat", pickupAddress: ADDRESS, pickupPhone: "+48500100200",
  dropoffName: "Ola", dropoffAddress: { ...ADDRESS, street: "Długa 5", apartment: "m. 3", city: "Warszawa", postcode: "00-001" },
  dropoffPhone: "+48600700800", dropoffNotes: "Ring twice", items: [{ name: "keys", quantity: 1, size: "small" }],
  doddyId: "11111111-1111-4111-8111-111111111111",
};

test("Uber client: signs in once with client credentials and the deliveries scope, then reuses the token", async () => {
  const quote = { status: 200, body: { id: "dqt_1", fee: 1999, currency: "pln", expires: "2026-11-12T10:15:00Z", dropoff_eta: "2026-11-12T11:00:00Z" } };
  const { c, calls } = client([TOKEN, quote, quote]);
  const q = await c.quote({ pickupAddress: ADDRESS, pickupPhone: "+48500100200", dropoffAddress: ADDRESS, dropoffPhone: "+48600700800" });
  await c.quote({ pickupAddress: ADDRESS, pickupPhone: "+48500100200", dropoffAddress: ADDRESS, dropoffPhone: "+48600700800" });
  assert.equal(calls.length, 3, "one sign-in for two quotes");
  assert.equal(calls[0]!.url, "https://auth.uber.com/oauth/v2/token");
  const form = new URLSearchParams(String(calls[0]!.init.body));
  assert.equal(form.get("grant_type"), "client_credentials");
  assert.equal(form.get("scope"), "eats.deliveries");
  assert.equal(calls[1]!.url, "https://api.uber.com/v1/customers/cus_12345678/delivery_quotes");
  assert.equal((calls[1]!.init.headers as Record<string, string>).authorization, "Bearer tok-1");
  assert.deepEqual(q, { kind: "ok", value: {
    quoteId: "dqt_1", fee: 1999, currency: "PLN", expiresAt: new Date("2026-11-12T10:15:00Z"), dropoffEta: new Date("2026-11-12T11:00:00Z"),
  } });
});

test("Uber client: the address is Uber's structured JSON, with the flat number as a second street line", () => {
  assert.deepEqual(JSON.parse(uberAddressJson(createReq.dropoffAddress)),
    { street_address: ["Długa 5", "m. 3"], city: "Warszawa", state: "", zip_code: "00-001", country: "PL" });
});

test("Uber client: a create carries Doddy's id as idempotency key and external id, and asks for the robot courier in test mode only", async () => {
  const created = { status: 200, body: { id: "del_1", status: "pending", tracking_url: "https://track.example/1", fee: 1999, currency: "pln", live_mode: false, external_id: createReq.doddyId } };
  for (const mode of ["test", "live"] as const) {
    const { c, calls } = client([TOKEN, created], mode);
    const r = await c.create(createReq);
    assert.equal(r.kind, "ok");
    const body = JSON.parse(String(calls[1]!.init.body)) as Record<string, unknown>;
    assert.equal(body.idempotency_key, createReq.doddyId);
    assert.equal(body.external_id, createReq.doddyId);
    assert.equal(body.quote_id, "dqt_1");
    assert.equal(body.dropoff_notes, "Ring twice");
    assert.deepEqual(body.manifest_items, [{ name: "keys", quantity: 1, size: "small" }]);
    assert.equal("test_specifications" in body, mode === "test", mode);
  }
});

test("Uber client: an answer that may have booked is unknown and never sent twice; a refusal before booking is not", async () => {
  const cases: [Reply, string][] = [
    [{ status: 500, body: { code: "internal" } }, "unknown"],
    [{ status: 502 }, "unknown"],
    [{ status: 504 }, "unknown"],
    [Object.assign(new Error("timed out"), { name: "TimeoutError" }), "unknown"],
    [new Error("socket hang up"), "unknown"],
    [{ status: 200, body: { nothing: true } }, "unknown"],
    [{ status: 429 }, "transient"],
    [{ status: 503 }, "transient"],
    [{ status: 400, body: { code: "address_undeliverable", message: "secret detail" } }, "rejected"],
    [{ status: 422, body: { message: "no code" } }, "rejected"],
  ];
  for (const [reply, kind] of cases) {
    const { c, calls } = client([TOKEN, reply]);
    const r = await c.create(createReq);
    assert.equal(r.kind, kind, JSON.stringify(reply instanceof Error ? reply.message : reply));
    assert.equal(calls.length, 2, "sent once");
    if (r.kind === "rejected") assert.match(r.code, /^(address_undeliverable|http_422)$/);
  }
});

test("Uber client: a 401 renews the token and sends once more; Uber never accepted the first", async () => {
  const created = { status: 200, body: { id: "del_1", status: "pending", external_id: createReq.doddyId } };
  const { c, calls } = client([TOKEN, { status: 401 }, { status: 200, body: { access_token: "tok-2", expires_in: 3600 } }, created]);
  assert.equal((await c.create(createReq)).kind, "ok");
  assert.equal(calls.length, 4);
  assert.equal((calls[3]!.init.headers as Record<string, string>).authorization, "Bearer tok-2");
});

test("Uber client: no token means nothing was sent", async () => {
  const { c, calls } = client([{ status: 400, body: { error: "invalid_client" } }]);
  assert.deepEqual(await c.create(createReq), { kind: "transient", code: "auth_unavailable" });
  assert.equal(calls.length, 1);
});

test("Uber client: an unclear quote is only 'couldn't get a price'", async () => {
  const { c } = client([TOKEN, { status: 502 }]);
  assert.equal((await c.quote({ pickupAddress: ADDRESS, pickupPhone: "+48500100200", dropoffAddress: ADDRESS, dropoffPhone: "+48600700800" })).kind, "transient");
});

test("Uber client: finds a delivery by Doddy's id among the latest ones", async () => {
  const list = { status: 200, body: { data: [{ id: "del_0", status: "delivered", external_id: "other" }, { id: "del_1", status: "pickup", external_id: createReq.doddyId }] } };
  const { c, calls } = client([TOKEN, list, list]);
  const found = await c.findByExternalId(createReq.doddyId);
  assert.equal(found.kind === "ok" && found.value?.id, "del_1");
  assert.match(calls[1]!.url, /\/deliveries\?limit=50$/);
  assert.deepEqual(await c.findByExternalId("missing"), { kind: "ok", value: null });
});

test("delivery approval hash: length-prefixed fields, as the shared vectors (computed independently here)", () => {
  const card = { pickup: "Pat, Lipowy Dwór 41c, 14-200 Iława, PL", dropoff: "Ola, Długa 5 m. 3, 00-001 Warszawa, PL",
    dropoffPhone: "+48600700800", items: "1× keys (small)", note: "" };
  const fields = ["doddy-approval-1", "delivery", createReq.doddyId, "1999", "PLN", card.pickup, card.dropoff, card.dropoffPhone, card.items, card.note];
  const h = createHash("sha256");
  for (const f of fields) { h.update(`${Buffer.byteLength(f, "utf8")}:`); h.update(f, "utf8"); }
  assert.equal(deliveryApprovalHash(createReq.doddyId, 1999, "PLN", card).toString("hex"), h.digest("hex"));
});

// ---------------------------------------------------------------------------------------------------------
// The routes, against real Postgres

/** Uber, scripted: each call takes the next answer queued for it, or a sensible default. */
class FakeUber implements DeliveryProvider {
  quotes: QuoteRequest[] = [];
  creates: CreateRequest[] = [];
  cancels: string[] = [];
  gets: string[] = [];
  finds: string[] = [];
  next: {
    quote: UberOutcome<Quote>[]; create: UberOutcome<UberDelivery>[]; get: UberOutcome<UberDelivery>[];
    cancel: UberOutcome<UberDelivery>[]; find: UberOutcome<UberDelivery | null>[];
  } = { quote: [], create: [], get: [], cancel: [], find: [] };
  fee = 1999;

  delivery(over: Partial<UberDelivery> = {}): UberDelivery {
    return { id: "del_1", status: "pending", trackingUrl: "https://track.example/1", fee: this.fee, currency: "PLN", liveMode: false, externalId: null, ...over };
  }
  async quote(req: QuoteRequest): Promise<UberOutcome<Quote>> {
    this.quotes.push(req);
    return this.next.quote.shift() ?? { kind: "ok", value: {
      quoteId: `dqt_${this.quotes.length}`, fee: this.fee, currency: "PLN", expiresAt: new Date(Date.now() + 15 * 60_000), dropoffEta: null,
    } };
  }
  async create(req: CreateRequest): Promise<UberOutcome<UberDelivery>> {
    this.creates.push(req);
    return this.next.create.shift() ?? { kind: "ok", value: this.delivery({ externalId: req.doddyId }) };
  }
  async get(id: string): Promise<UberOutcome<UberDelivery>> {
    this.gets.push(id);
    return this.next.get.shift() ?? { kind: "ok", value: this.delivery({ id }) };
  }
  async cancel(id: string): Promise<UberOutcome<UberDelivery>> {
    this.cancels.push(id);
    return this.next.cancel.shift() ?? { kind: "ok", value: this.delivery({ id, status: "canceled" }) };
  }
  async findByExternalId(doddyId: string): Promise<UberOutcome<UberDelivery | null>> {
    this.finds.push(doddyId);
    return this.next.find.shift() ?? { kind: "ok", value: null };
  }
}

describe("deliveries against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let off: FastifyInstance;
  let uber: FakeUber;
  const limits: DeliveryLimits = { ...DEFAULT_DELIVERY_LIMITS, perServerDaily: 1000 };

  before(async () => {
    db = await freshDb();
    uber = new FakeUber();
    const deliveries: DeliveryDeps = { provider: uber, mode: "test", limits };
    ({ app } = await testApp(db, { deliveries }));
    ({ app: off } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await off?.close();
    await db?.end();
  });
  beforeEach(() => {
    uber.quotes = []; uber.creates = []; uber.cancels = []; uber.gets = []; uber.finds = [];
    uber.next = { quote: [], create: [], get: [], cancel: [], find: [] };
    uber.fee = 1999;
    limits.maxFee = DEFAULT_DELIVERY_LIMITS.maxFee;
    limits.perAccountDaily = DEFAULT_DELIVERY_LIMITS.perAccountDaily;
  });

  let accounts = 0;
  let phones = 0;
  /** An account with a verified Polish number (or none). */
  async function owner(opts: { verified?: boolean } = {}) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.9.0.${++accounts}` });
    const { deviceToken } = r.json() as { deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const phone = `+4850${String(1_000_000 + ++phones).padStart(7, "0")}`;
    if (opts.verified !== false) {
      assert.equal((await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } })).statusCode, 200);
    }
    return { h, phone };
  }

  const order = (over: object = {}) => ({
    pickup: { name: "Pat", address: ADDRESS },
    dropoff: { name: "Ola", phone: "+48600700800", address: { street: "Długa 5", apartment: "m. 3", city: "Warszawa", postcode: "00-001", country: "PL" } },
    items: [{ name: "keys", quantity: 1, size: "small" }],
    note: "Ring twice",
    ...over,
  });

  interface Quoted { id: string; fee: number; currency: string; card: { pickup: string; dropoff: string; dropoffPhone: string; items: string; note: string } }
  const tapOf = (q: Quoted) => deliveryApprovalHash(q.id, q.fee, q.currency, q.card).toString("hex");
  async function quote(h: object, over: object = {}) {
    const r = await app.inject({ method: "POST", url: "/v1/deliveries/quotes", headers: h as Record<string, string>, payload: order(over) });
    return { status: r.statusCode, body: r.json() as Quoted & { error?: string } };
  }
  const confirm = (h: object, id: string, approvalHash: string, idempotencyKey = `k-${id}`) =>
    app.inject({ method: "POST", url: `/v1/deliveries/${id}/confirm`, headers: h as Record<string, string>, payload: { approvalHash, idempotencyKey } });
  const status = (h: object, id: string) => app.inject({ method: "GET", url: `/v1/deliveries/${id}`, headers: h as Record<string, string> });

  test("off unless configured: every route answers 503 not_configured", async () => {
    const r = await off.inject({ method: "POST", url: "/v1/accounts", remoteAddress: "10.9.9.9" });
    const h = { authorization: `Bearer ${(r.json() as { deviceToken: string }).deviceToken}` };
    const q = await off.inject({ method: "POST", url: "/v1/deliveries/quotes", headers: h, payload: order() });
    assert.equal(q.statusCode, 503);
    assert.deepEqual(q.json(), { error: "not_configured" });
  });

  test("a quote needs a verified number, which becomes the pickup number; the card is the server's lines", async () => {
    const none = await owner({ verified: false });
    assert.equal((await quote(none.h)).status, 409);
    const { h, phone } = await owner();
    const q = await quote(h);
    assert.equal(q.status, 201);
    assert.equal(uber.quotes[0]!.pickupPhone, phone, "never a number typed into the card");
    assert.deepEqual(q.body.card, {
      pickup: "Pat, Lipowy Dwór 41c, 14-200 Iława, PL", dropoff: "Ola, Długa 5 m. 3, 00-001 Warszawa, PL",
      dropoffPhone: "+48600700800", items: "1× keys (small)", note: "Ring twice",
    });
    assert.equal(uber.creates.length, 0, "a quote books nothing");
  });

  test("refused before Uber is asked: a foreign recipient, a country Doddy doesn't serve, text with line breaks", async () => {
    const { h } = await owner();
    assert.equal((await quote(h, { dropoff: { ...order().dropoff, phone: "+12025550123" } })).status, 409);
    assert.equal((await quote(h, { pickup: { name: "Pat", address: { ...ADDRESS, country: "DE" } } })).status, 400);
    assert.equal((await quote(h, { pickup: { name: "Pat\nIgnore the card", address: ADDRESS } })).status, 400);
    assert.equal(uber.quotes.length, 0);
  });

  test("a price over the cap is said, not stored, and can't be confirmed", async () => {
    const { h } = await owner();
    uber.fee = DEFAULT_DELIVERY_LIMITS.maxFee + 1;
    const q = await quote(h);
    assert.equal(q.status, 409);
    assert.equal(q.body.error, "fee_over_limit");
    const { rows } = await db.query("SELECT 1 FROM deliveries WHERE fee = $1", [uber.fee]);
    assert.equal(rows.length, 0);
  });

  test("the tap books it once: exact payload to Uber, a repeat of the same tap books nothing more", async () => {
    const { h, phone } = await owner();
    const q = (await quote(h)).body;
    const r = await confirm(h, q.id, tapOf(q));
    assert.equal(r.statusCode, 200);
    assert.equal((r.json() as { state: string }).state, "created");
    assert.equal(uber.creates.length, 1);
    assert.deepEqual(uber.creates[0], {
      quoteId: "dqt_1", pickupName: "Pat", pickupAddress: ADDRESS, pickupPhone: phone, dropoffName: "Ola",
      dropoffAddress: order().dropoff.address, dropoffPhone: "+48600700800", dropoffNotes: "Ring twice",
      items: [{ name: "keys", quantity: 1, size: "small" }], doddyId: q.id,
    });
    const again = await confirm(h, q.id, tapOf(q));
    assert.equal(again.statusCode, 200);
    assert.equal((again.json() as { state: string }).state, "created");
    assert.equal(uber.creates.length, 1, "the repeat is answered from the record");
    // A different key on a booked delivery is a second tap, not a repeat.
    assert.equal((await confirm(h, q.id, tapOf(q), "other")).statusCode, 409);
  });

  test("a tap bound to anything else is refused and books nothing", async () => {
    const { h } = await owner();
    const q = (await quote(h)).body;
    const changed = { ...q, card: { ...q.card, dropoffPhone: "+48600700801" } };
    assert.equal((await confirm(h, q.id, tapOf(changed))).statusCode, 409);
    assert.equal((await confirm(h, q.id, tapOf({ ...q, fee: q.fee - 1 }))).statusCode, 409);
    assert.equal(uber.creates.length, 0);
    // Another account can't see or confirm it.
    const other = await owner();
    assert.equal((await confirm(other.h, q.id, tapOf(q))).statusCode, 404);
    assert.equal((await status(other.h, q.id)).statusCode, 404);
  });

  test("a lapsed quote can't be confirmed, and its details are erased", async () => {
    const { h } = await owner();
    uber.next.quote.push({ kind: "ok", value: { quoteId: "dqt_old", fee: 1999, currency: "PLN", expiresAt: new Date(Date.now() + 10_000), dropoffEta: null } });
    const q = (await quote(h)).body;
    const r = await confirm(h, q.id, tapOf(q));
    assert.equal(r.statusCode, 409);
    assert.equal((r.json() as { error: string }).error, "quote_expired");
    const { rows: [row] } = await db.query<{ state: string; payload_ciphertext: Buffer | null }>(
      "SELECT state, payload_ciphertext FROM deliveries WHERE id = $1", [q.id]);
    assert.equal(row!.state, "expired");
    assert.equal(row!.payload_ciphertext, null);
    assert.equal(uber.creates.length, 0);
  });

  test("two a day per account: the third tap is refused before Uber", async () => {
    const { h } = await owner();
    for (let i = 0; i < DEFAULT_DELIVERY_LIMITS.perAccountDaily; i++) {
      const q = (await quote(h)).body;
      assert.equal((await confirm(h, q.id, tapOf(q))).statusCode, 200);
    }
    const q = (await quote(h)).body;
    const r = await confirm(h, q.id, tapOf(q));
    assert.equal(r.statusCode, 429);
    assert.equal((r.json() as { error: string }).error, "daily_limit");
    assert.equal(uber.creates.length, DEFAULT_DELIVERY_LIMITS.perAccountDaily);
  });

  test("an unclear answer is unknown, never re-sent, and settled by Doddy's id at Uber", async () => {
    const { h } = await owner();
    const q = (await quote(h)).body;
    uber.next.create.push({ kind: "unknown", code: "timeout" });
    const r = await confirm(h, q.id, tapOf(q));
    assert.equal((r.json() as { state: string }).state, "unknown");
    // The same tap again: the record answers, Uber is not asked to create again.
    assert.equal((await confirm(h, q.id, tapOf(q))).statusCode, 200);
    assert.equal(uber.creates.length, 1);
    // Not found yet: still unknown, not "failed" and not "created".
    assert.equal((await status(h, q.id)).json().state, "unknown");
    uber.next.find.push({ kind: "ok", value: uber.delivery({ id: "del_9", status: "pickup", externalId: q.id }) });
    const settled = (await status(h, q.id)).json() as { state: string; uberStatus: string };
    assert.deepEqual([settled.state, settled.uberStatus], ["created", "pickup"]);
    assert.deepEqual(uber.finds, [q.id, q.id]);
    assert.equal(uber.creates.length, 1);
  });

  test("a refusal is failed with its code, and the details are erased", async () => {
    const { h } = await owner();
    const q = (await quote(h)).body;
    uber.next.create.push({ kind: "rejected", code: "address_undeliverable" });
    const r = (await confirm(h, q.id, tapOf(q))).json() as { state: string; errorCode: string; card: unknown };
    assert.deepEqual([r.state, r.errorCode, r.card], ["failed", "address_undeliverable", null]);
  });

  test("delivered: status comes from Uber and the details are erased", async () => {
    const { h } = await owner();
    const q = (await quote(h)).body;
    await confirm(h, q.id, tapOf(q));
    uber.next.get.push({ kind: "ok", value: uber.delivery({ status: "delivered" }) });
    const r = (await status(h, q.id)).json() as { state: string; card: unknown; trackingUrl: string };
    assert.deepEqual([r.state, r.card, r.trackingUrl], ["delivered", null, "https://track.example/1"]);
    assert.deepEqual(uber.gets, ["del_1"]);
  });

  test("test mode: a delivery Uber marks live is cancelled at once and recorded as failed", async () => {
    const { h } = await owner();
    const q = (await quote(h)).body;
    uber.next.create.push({ kind: "ok", value: uber.delivery({ liveMode: true }) });
    const r = (await confirm(h, q.id, tapOf(q))).json() as { state: string; errorCode: string };
    assert.deepEqual([r.state, r.errorCode], ["failed", "live_delivery_in_test_mode"]);
    assert.deepEqual(uber.cancels, ["del_1"]);
  });

  test("cancel: only what Uber confirms; a refusal leaves the delivery as it is", async () => {
    const { h } = await owner();
    const q = (await quote(h)).body;
    await confirm(h, q.id, tapOf(q));
    uber.next.cancel.push({ kind: "rejected", code: "courier_picked_up" });
    const refused = await app.inject({ method: "POST", url: `/v1/deliveries/${q.id}/cancel`, headers: h, payload: { confirm: true } });
    assert.equal(refused.statusCode, 409);
    assert.equal((await status(h, q.id)).json().state, "created");
    const ok = await app.inject({ method: "POST", url: `/v1/deliveries/${q.id}/cancel`, headers: h, payload: { confirm: true } });
    assert.equal((ok.json() as { state: string }).state, "cancelled");
  });

  test("the list shows the latest, and the prune expires lapsed quotes and erases their details", async () => {
    const { h } = await owner();
    const q = (await quote(h)).body;
    const list = (await app.inject({ method: "GET", url: "/v1/deliveries", headers: h })).json() as { deliveries: { id: string }[] };
    assert.equal(list.deliveries[0]!.id, q.id);
    await db.query("UPDATE deliveries SET quote_expires_at = now() - interval '11 minutes' WHERE id = $1", [q.id]);
    assert.ok(await pruneDeliveries(db) >= 1);
    const { rows: [row] } = await db.query<{ state: string; payload_ciphertext: Buffer | null }>(
      "SELECT state, payload_ciphertext FROM deliveries WHERE id = $1", [q.id]);
    assert.deepEqual([row!.state, row!.payload_ciphertext], ["expired", null]);
  });
});
