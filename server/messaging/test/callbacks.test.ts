// Call-backs (decision 2026-11-09-call-backs-and-contact-calls, limits in 2026-11-12-call-back-limits): someone Doddy
// called on a user's behalf who calls Doddy's number back is put through to that user, while the route is fresh, only
// one user has one, that user has calls on and the day's caps allow it; every other stranger still hears the fixed line.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { attestationAllowsForward, pruneCallbackRoutes, rememberCallbackRoute } from "../src/callbacks.js";
import type { Db } from "../src/db.js";
import { caseKeys, destinationHash } from "../src/taskCalls/payload.js";
import { dbSkip, DODDY_FROM, freshDb, sampleBrief, taskTestApp, testApp, testCipher, twilioRequest } from "./helpers.js";

const DAY = 24 * 60 * 60_000;
const NOT_PUT_THROUGH = /Nie mogę teraz połączyć tej rozmowy/;

test("Twilio's StirVerstat: only an A-level attestation, or none sent at all, lets a call-back through", () => {
  for (const ok of [undefined, "", "TN-Validation-Passed-A", "TN-Validation-Passed-A-Passthrough"]) {
    assert.equal(attestationAllowsForward(ok), true, String(ok));
  }
  for (const no of ["TN-Validation-Passed-B", "TN-Validation-Passed-C", "TN-Validation-Passed-A-Diverted", "TN-Validation-Failed-A",
    "TN-Validation-Failed", "No-TN-Validation", "tn-validation-passed-a", "something else"]) {
    assert.equal(attestationAllowsForward(no), false, no);
  }
});

describe("call-backs against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  let seq = 0;
  const nextPhone = () => `+48500${String(200000 + ++seq).slice(-6)}`;
  const nextDestination = () => `+4822${String(2000000 + ++seq).slice(-7)}`;
  const hashOf = (n: string) => destinationHash(caseKeys(testCipher), n);

  /** A user with a verified number; calls on unless `callsOn` is false. */
  async function user(app: FastifyInstance, callsOn = true, phone = nextPhone()) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const v = await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } });
    assert.equal(v.statusCode, 200, v.body);
    if (callsOn) await setCalls(app, h, true);
    return { accountId, h, phone };
  }
  const setCalls = async (app: FastifyInstance, h: object, on: boolean) => {
    const r = await app.inject({ method: "PUT", url: "/v1/calls/settings", headers: h as Record<string, string>, payload: { inboundEnabled: on } });
    assert.equal(r.statusCode, 204, r.body);
  };

  /** A call case to `destination`, approved and dialled. */
  async function dialFor(app: FastifyInstance, h: object, destination: string) {
    const created = await app.inject({
      method: "POST", url: "/v1/call-cases", headers: h as Record<string, string>,
      payload: sampleBrief({ callee: { name: "Michał", phone: destination, source: "contacts" } }) as never,
    });
    assert.equal(created.statusCode, 201, created.body);
    const preview = created.json() as { caseId: string; digest: string };
    const approved = await app.inject({
      method: "POST", url: `/v1/call-cases/${preview.caseId}/approve`, headers: h as Record<string, string>,
      payload: { digest: preview.digest },
    });
    assert.equal(approved.statusCode, 202, approved.body);
  }

  const callIn = (app: FastifyInstance, from: string, to = DODDY_FROM, extra: Record<string, string> = {}) =>
    app.inject(twilioRequest("/webhooks/twilio/voice", { From: from, To: to, CallSid: "CA" + "c".repeat(32), ...extra }));

  /** The app with the call-back limits a test sets, and a clock it moves. */
  async function limited(limits: Record<string, number>, start = "2026-11-12T10:00:00Z") {
    const clock = { now: new Date(start) };
    const t = await testApp(db, { limits: { accountsPerIpDay: 100_000, ...limits }, now: () => clock.now });
    return { ...t, clock };
  }

  test("someone Doddy called for a user is put through to that user, with Doddy's number as caller ID and a time limit", async () => {
    const { app } = await taskTestApp(db);
    const owner = await user(app);
    const michal = nextDestination();
    await dialFor(app, owner.h, michal);

    const r = await callIn(app, michal);
    assert.equal(r.statusCode, 200);
    assert.match(r.headers["content-type"] as string, /xml/);
    assert.match(r.body, /Tu Doddy, asystent AI\. Łączę z osobą, w której imieniu dzwonił Doddy\./);
    assert.match(r.body, new RegExp(`<Dial callerId="\\${DODDY_FROM}" timeout="25" timeLimit="900" record="do-not-record"`));
    assert.match(r.body, new RegExp(`<Number>\\${owner.phone}</Number>`));
    assert.doesNotMatch(r.body, /<Record[\s>/]/);
    // The caller's own number is never what they are put through to, and the user's number isn't spoken.
    assert.doesNotMatch(r.body, new RegExp(`<Say[^>]*>[^<]*${owner.phone.slice(1)}`));
  });

  test("the route keeps a keyed hash of the number, never the number", async () => {
    const { app } = await taskTestApp(db);
    const owner = await user(app);
    const destination = nextDestination();
    await dialFor(app, owner.h, destination);
    const { rows } = await db.query<{ destination_hash: Buffer; account_id: string }>(
      "SELECT destination_hash, account_id FROM callback_routes WHERE account_id = $1", [owner.accountId]);
    assert.equal(rows.length, 1);
    assert.deepEqual(rows[0]!.destination_hash, hashOf(destination));
    assert.equal(rows[0]!.destination_hash.includes(Buffer.from(destination.slice(1))), false);
  });

  test("a stranger Doddy never called still hears the fixed line", async () => {
    const { app } = await taskTestApp(db);
    const r = await callIn(app, nextDestination());
    assert.match(r.body, /Ten numer działa tylko dla właściciela/);
    assert.doesNotMatch(r.body, /<Dial/);
  });

  test("when two users have a fresh route to the same number, nobody is put through: the caller hears a short line", async () => {
    const { app, clock } = await taskTestApp(db);
    const first = await user(app);
    const second = await user(app);
    const shared = nextDestination();
    await dialFor(app, first.h, shared);
    clock.now = new Date(clock.now.getTime() + 60 * 60_000);
    await dialFor(app, second.h, shared);
    const { rows } = await db.query("SELECT account_id FROM callback_routes WHERE destination_hash = $1", [hashOf(shared)]);
    assert.equal(rows.length, 2, "one route per user: the second dial doesn't take the first one's");
    const r = await callIn(app, shared);
    assert.match(r.body, NOT_PUT_THROUGH);
    assert.match(r.body, /<Hangup\/>/);
    assert.doesNotMatch(r.body, /<Dial/);
    assert.doesNotMatch(r.body, new RegExp(`${first.phone.slice(1)}|${second.phone.slice(1)}`));
  });

  test("one user's route: a newer dial renews it, an older one never moves it back", async () => {
    const { app } = await testApp(db);
    const owner = await user(app);
    const destination = nextDestination();
    const hash = hashOf(destination);
    const at = async () => (await db.query<{ last_dialed_at: Date }>(
      "SELECT last_dialed_at FROM callback_routes WHERE destination_hash = $1 AND account_id = $2", [hash, owner.accountId])).rows[0]!.last_dialed_at;
    const first = Math.floor(Date.now() / 1000) * 1000 - 2 * 60 * 60_000;
    await rememberCallbackRoute(db, hash, owner.accountId, new Date(first));
    await rememberCallbackRoute(db, hash, owner.accountId, new Date(first - 60 * 60_000));
    assert.equal((await at()).getTime(), first, "an older dial leaves it");
    await rememberCallbackRoute(db, hash, owner.accountId, new Date(first + 60 * 60_000));
    assert.equal((await at()).getTime(), first + 60 * 60_000, "a newer dial renews it");
    const r = await callIn(app, destination, "+48221234567");
    assert.match(r.body, new RegExp(`<Number>\\${owner.phone}</Number>`));
  });

  test("a route lasts 7 days by default: an old one isn't used, doesn't make a number shared, and the tidy deletes it", async () => {
    const t = await limited({});
    const now = t.clock.now.getTime();
    const old = await user(t.app);
    const fresh = await user(t.app);
    const shared = nextDestination();
    const onlyOld = nextDestination();
    await rememberCallbackRoute(db, hashOf(shared), old.accountId, new Date(now - 8 * DAY));
    await rememberCallbackRoute(db, hashOf(shared), fresh.accountId, new Date(now - 6 * DAY));
    await rememberCallbackRoute(db, hashOf(onlyOld), old.accountId, new Date(now - 7 * DAY - 60_000));

    assert.match((await callIn(t.app, shared, "+48221234567")).body, new RegExp(`<Number>\\${fresh.phone}</Number>`));
    const stale = await callIn(t.app, onlyOld, "+48221234567");
    assert.match(stale.body, /Ten numer działa tylko dla właściciela/, "an expired route is no route");

    // A longer setting keeps the 8-day-old route alive, so the number is shared again and nobody is put through.
    const longer = await testApp(db, { limits: { accountsPerIpDay: 100_000, callbackRouteDays: 10 }, now: () => t.clock.now });
    assert.match((await callIn(longer.app, shared, "+48221234567")).body, NOT_PUT_THROUGH);

    const pruned = await pruneCallbackRoutes(db, 7, new Date(now));
    assert.ok(pruned >= 2, `pruned ${pruned}`);
    const { rows } = await db.query("SELECT account_id FROM callback_routes WHERE destination_hash = ANY($1)", [[hashOf(shared), hashOf(onlyOld)]]);
    assert.deepEqual(rows.map((r) => r.account_id), [fresh.accountId]);
  });

  test("a user whose calls are off is never put through; turning them on lets the next call-back through", async () => {
    const { app } = await taskTestApp(db);
    const owner = await user(app, false);
    const destination = nextDestination();
    await dialFor(app, owner.h, destination);
    const off = await callIn(app, destination);
    assert.match(off.body, NOT_PUT_THROUGH);
    assert.doesNotMatch(off.body, /<Dial/);
    await setCalls(app, owner.h, true);
    assert.match((await callIn(app, destination)).body, new RegExp(`<Number>\\${owner.phone}</Number>`));
  });

  test("call-backs on one route are capped per day; the next day they go through again", async () => {
    const t = await limited({ callbackForwardsPerRouteDay: 2 });
    const owner = await user(t.app);
    const destination = nextDestination();
    await rememberCallbackRoute(db, hashOf(destination), owner.accountId, t.clock.now);
    for (let i = 0; i < 2; i++) assert.match((await callIn(t.app, destination, "+48221234567")).body, /<Dial/, `call ${i + 1}`);
    const third = await callIn(t.app, destination, "+48221234567");
    assert.match(third.body, NOT_PUT_THROUGH);
    assert.doesNotMatch(third.body, /<Dial/);
    t.clock.now = new Date(t.clock.now.getTime() + DAY);
    assert.match((await callIn(t.app, destination, "+48221234567")).body, /<Dial/);
  });

  test("when Twilio sends StirVerstat, only an A-level attestation is put through", async () => {
    const t = await limited({ callbackForwardsPerRouteDay: 20 });
    const owner = await user(t.app);
    const destination = nextDestination();
    await rememberCallbackRoute(db, hashOf(destination), owner.accountId, t.clock.now);
    const verstat = async (v?: string) => (await callIn(t.app, destination, "+48221234567", v === undefined ? {} : { StirVerstat: v })).body;
    assert.match(await verstat(), /<Dial/, "not sent: Polish calls carry no SHAKEN/STIR");
    assert.match(await verstat("TN-Validation-Passed-A"), /<Dial/);
    for (const v of ["TN-Validation-Passed-B", "TN-Validation-Passed-C", "TN-Validation-Failed-A", "No-TN-Validation"]) {
      const body = await verstat(v);
      assert.match(body, NOT_PUT_THROUGH, v);
      assert.doesNotMatch(body, /<Dial/, v);
    }
  });

  test("call-backs count towards the server's daily cap of calls put through", async () => {
    const t = await limited({ inboundCallsPerServerDay: 1 }, "2026-12-01T10:00:00Z");
    const a = await user(t.app);
    const b = await user(t.app);
    const [toA, toB] = [nextDestination(), nextDestination()];
    await rememberCallbackRoute(db, hashOf(toA), a.accountId, t.clock.now);
    await rememberCallbackRoute(db, hashOf(toB), b.accountId, t.clock.now);
    assert.match((await callIn(t.app, toA, "+48221234567")).body, /<Dial/);
    const full = await callIn(t.app, toB, "+48221234567");
    assert.match(full.body, NOT_PUT_THROUGH);
    const { rows } = await db.query("SELECT forwards FROM callback_routes WHERE destination_hash = $1", [hashOf(toB)]);
    assert.deepEqual(rows, [{ forwards: 0 }], "the route's own count is not used up by a call the server refused");
  });

  test("a deleted account takes its routes with it", async () => {
    const { app } = await taskTestApp(db);
    const owner = await user(app);
    const destination = nextDestination();
    await dialFor(app, owner.h, destination);
    await db.query("DELETE FROM accounts WHERE id = $1", [owner.accountId]);
    const r = await callIn(app, destination);
    assert.match(r.body, /Ten numer działa tylko dla właściciela/);
  });

  test("call-backs work even while the phone agent isn't set up", async () => {
    const { app } = await testApp(db, { registrar: undefined });
    const owner = await user(app);
    const destination = nextDestination();
    await rememberCallbackRoute(db, hashOf(destination), owner.accountId, new Date());
    const forwarded = await callIn(app, destination, "+48221234567");
    assert.match(forwarded.body, new RegExp(`<Number>\\${owner.phone}</Number>`));
    const stranger = await callIn(app, nextDestination(), "+48221234567");
    assert.match(stranger.body, /nie są jeszcze włączone/);
  });

  test("after the dial: an unanswered call-back hears why; an answered one just ends", async () => {
    const { app } = await testApp(db);
    const missed = await app.inject(twilioRequest("/webhooks/twilio/callback-done", { DialCallStatus: "no-answer" }));
    assert.match(missed.body, /Nie udało się połączyć/);
    assert.match(missed.body, /<Hangup\/>/);
    const done = await app.inject(twilioRequest("/webhooks/twilio/callback-done", { DialCallStatus: "completed" }));
    assert.doesNotMatch(done.body, /<Say/);
    const forged = await app.inject({ ...twilioRequest("/webhooks/twilio/callback-done", { DialCallStatus: "no-answer" }), headers: {
      "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": "forged" } });
    assert.notEqual(forged.statusCode, 200);
  });
});
