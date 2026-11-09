// Call-backs (decision 2026-11-09-call-backs-and-contact-calls): someone Doddy called on a user's behalf who calls
// Doddy's number back is put through to that user; every other stranger still hears the fixed line.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { rememberCallbackRoute } from "../src/callbacks.js";
import type { Db } from "../src/db.js";
import { caseKeys, destinationHash } from "../src/taskCalls/payload.js";
import { dbSkip, DODDY_FROM, freshDb, sampleBrief, taskTestApp, testApp, testCipher, twilioRequest } from "./helpers.js";

describe("call-backs against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  let seq = 0;
  const nextPhone = () => `+48500${String(200000 + ++seq).slice(-6)}`;
  const nextDestination = () => `+4822${String(2000000 + ++seq).slice(-7)}`;

  async function user(app: FastifyInstance, phone = nextPhone()) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const v = await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } });
    assert.equal(v.statusCode, 200, v.body);
    return { accountId, h, phone };
  }

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

  const callIn = (app: FastifyInstance, from: string, to = DODDY_FROM) =>
    app.inject(twilioRequest("/webhooks/twilio/voice", { From: from, To: to, CallSid: "CA" + "c".repeat(32) }));

  test("someone Doddy called for a user is put through to that user, with Doddy's number as caller ID", async () => {
    const { app } = await taskTestApp(db);
    const owner = await user(app);
    const michal = nextDestination();
    await dialFor(app, owner.h, michal);

    const r = await callIn(app, michal);
    assert.equal(r.statusCode, 200);
    assert.match(r.headers["content-type"] as string, /xml/);
    assert.match(r.body, /Tu Doddy, asystent AI\. Łączę z osobą, w której imieniu dzwonił Doddy\./);
    assert.match(r.body, new RegExp(`<Dial callerId="\\${DODDY_FROM}" timeout="25" record="do-not-record"`));
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
    assert.deepEqual(rows[0]!.destination_hash, destinationHash(caseKeys(testCipher), destination));
    assert.equal(rows[0]!.destination_hash.includes(Buffer.from(destination.slice(1))), false);
  });

  test("a stranger Doddy never called still hears the fixed line", async () => {
    const { app } = await taskTestApp(db);
    const r = await callIn(app, nextDestination());
    assert.match(r.body, /Ten numer działa tylko dla właściciela/);
    assert.doesNotMatch(r.body, /<Dial/);
  });

  test("the newest dial wins when two users called the same number", async () => {
    const { app, clock } = await taskTestApp(db);
    const first = await user(app);
    const second = await user(app);
    const shared = nextDestination();
    await dialFor(app, first.h, shared);
    clock.now = new Date(clock.now.getTime() + 60 * 60_000);
    await dialFor(app, second.h, shared);
    const r = await callIn(app, shared);
    assert.match(r.body, new RegExp(`<Number>\\${second.phone}</Number>`));
  });

  test("an older dial never takes the route back from a newer one", async () => {
    const { app } = await testApp(db);
    const newer = await user(app);
    const older = await user(app);
    const destination = nextDestination();
    const hash = destinationHash(caseKeys(testCipher), destination);
    await rememberCallbackRoute(db, hash, newer.accountId, new Date("2026-11-09T12:00:00Z"));
    await rememberCallbackRoute(db, hash, older.accountId, new Date("2026-11-09T11:00:00Z"));
    const r = await callIn(app, destination, "+48221234567");
    assert.match(r.body, new RegExp(`<Number>\\${newer.phone}</Number>`));
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
    await rememberCallbackRoute(db, destinationHash(caseKeys(testCipher), destination), owner.accountId, new Date());
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
