import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { dispatchDue } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { BASE_URL, dbSkip, FakePush, FakeSms, freshDb, testApp, TWILIO_TOKEN } from "./helpers.js";

const APNS_TOKEN = "ab".repeat(32);
const PHONE = "+48500100200";

describe("server against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let push: FakePush;
  let sms: FakeSms;

  before(async () => {
    db = await freshDb();
    ({ app, push, sms } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  async function newAccount() {
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    assert.equal(r.statusCode, 201);
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    return { accountId, headers: { authorization: `Bearer ${deviceToken}` } };
  }
  const call = (method: "GET" | "POST" | "PUT" | "DELETE", url: string, headers: object, payload?: object) =>
    app.inject({ method, url, headers: headers as Record<string, string>, payload });

  function twilioPost(url: string, form: Record<string, string>, signature = twilioSignature(TWILIO_TOKEN, BASE_URL + url, form)) {
    return app.inject({
      method: "POST", url, payload: new URLSearchParams(form).toString(),
      headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": signature },
    });
  }

  test("auth: missing or wrong token is 401; token is stored only as a hash", async () => {
    const a = await newAccount();
    assert.equal((await call("GET", "/v1/phone", {})).statusCode, 401);
    assert.equal((await call("GET", "/v1/phone", { authorization: "Bearer " + "x".repeat(43) })).statusCode, 401);
    assert.equal((await call("GET", "/v1/phone", a.headers)).statusCode, 200);
    const { rows } = await db.query("SELECT token_hash FROM devices WHERE account_id = $1", [a.accountId]);
    assert.equal((rows[0].token_hash as Buffer).length, 32);
  });

  test("push: refused until a device token exists, then sent once and text erased", async () => {
    const a = await newAccount();
    const update = { text: "Your dentist is at 15:00", channels: ["push"], idempotencyKey: "k1" };
    assert.equal((await call("POST", "/v1/updates", a.headers, update)).statusCode, 409);

    assert.equal((await call("PUT", "/v1/device/push-token", a.headers, { token: APNS_TOKEN, environment: "sandbox" })).statusCode, 204);
    const first = await call("POST", "/v1/updates", a.headers, update);
    assert.equal(first.statusCode, 202);
    const again = await call("POST", "/v1/updates", a.headers, update);
    assert.deepEqual(again.json(), first.json(), "same idempotency key returns the same message");

    push.sent = [];
    await dispatchDue(db, { push, sms });
    assert.equal(push.sent.length, 1);
    assert.equal(push.sent[0]!.body, "Your dentist is at 15:00");

    const id = (first.json() as { messages: { id: string }[] }).messages[0]!.id;
    const status = await call("GET", `/v1/updates/${id}`, a.headers);
    assert.equal(status.json().state, "sent");
    const { rows } = await db.query("SELECT body FROM outbound_messages WHERE id = $1", [id]);
    assert.equal(rows[0].body, null);

    const other = await newAccount();
    assert.equal((await call("GET", `/v1/updates/${id}`, other.headers)).statusCode, 404, "no cross-account reads");
  });

  test("push: a token Apple reports as gone is switched off", async () => {
    const a = await newAccount();
    await call("PUT", "/v1/device/push-token", a.headers, { token: "cd".repeat(32), environment: "production" });
    await call("POST", "/v1/updates", a.headers, { text: "hi", channels: ["push"], idempotencyKey: "gone" });
    push.next = [{ kind: "rejected", code: "apns_Unregistered", deviceGone: true }];
    await dispatchDue(db, { push, sms });
    const r = await call("POST", "/v1/updates", a.headers, { text: "hi again", channels: ["push"], idempotencyKey: "gone2" });
    assert.equal(r.statusCode, 409);
  });

  test("sms: needs verified number + consent; STOP blocks and cancels; START re-opens", async () => {
    const a = await newAccount();
    const update = (k: string) => ({ text: "Morning! 3 things today.", channels: ["sms"], idempotencyKey: k });
    assert.equal((await call("POST", "/v1/updates", a.headers, update("s0"))).statusCode, 409);

    assert.equal((await call("POST", "/v1/phone/verification", a.headers, { phone: PHONE })).statusCode, 202);
    assert.equal((await call("POST", "/v1/phone/verification/check", a.headers, { phone: PHONE, code: "111111" })).json().error, "wrong_code");
    assert.equal((await call("POST", "/v1/phone/verification/check", a.headers, { phone: PHONE, code: "000000" })).json().error, "code_expired");
    assert.equal((await call("POST", "/v1/phone/verification/check", a.headers, { phone: PHONE, code: "123456" })).statusCode, 200);

    assert.equal((await call("POST", "/v1/updates", a.headers, update("s1"))).statusCode, 409, "verified but no consent yet");
    assert.equal((await call("PUT", "/v1/phone/sms-consent", a.headers, { consent: true })).statusCode, 400, "consent needs the wording version");
    assert.equal((await call("PUT", "/v1/phone/sms-consent", a.headers, { consent: true, textVersion: "sms-v1" })).statusCode, 204);

    assert.equal((await call("POST", "/v1/updates", a.headers, update("s2"))).statusCode, 202);
    sms.sent = [];
    await dispatchDue(db, { push, sms });
    assert.deepEqual(sms.sent, [{ to: PHONE, body: "Morning! 3 things today." }]);

    // A queued text, then the user replies STOP before it goes out.
    const queued = await call("POST", "/v1/updates", a.headers, { ...update("s3"), sendAt: new Date(Date.now() + 3_600_000).toISOString() });
    assert.equal((await twilioPost("/webhooks/twilio/sms", { From: PHONE, Body: "STOP" }, "forged")).statusCode, 403);
    assert.equal((await twilioPost("/webhooks/twilio/sms", { From: PHONE, Body: "STOP" })).statusCode, 200);
    const qid = (queued.json() as { messages: { id: string }[] }).messages[0]!.id;
    assert.equal((await call("GET", `/v1/updates/${qid}`, a.headers)).json().state, "cancelled");
    assert.equal((await call("GET", "/v1/phone", a.headers)).json().optedOut, true);
    assert.equal((await call("POST", "/v1/updates", a.headers, update("s4"))).statusCode, 409);

    await twilioPost("/webhooks/twilio/sms", { From: PHONE, Body: "start" });
    assert.equal((await call("POST", "/v1/updates", a.headers, update("s5"))).statusCode, 202);
  });

  test("delivery receipts update the message; failures are not retried blindly", async () => {
    const a = await newAccount();
    await call("PUT", "/v1/device/push-token", a.headers, { token: "ef".repeat(32), environment: "sandbox" });

    // Transient refusal → back in the queue with a later send time.
    push.next = [{ kind: "transient", code: "apns_503" }];
    const t = await call("POST", "/v1/updates", a.headers, { text: "t", channels: ["push"], idempotencyKey: "t" });
    await dispatchDue(db, { push, sms });
    const tid = (t.json() as { messages: { id: string }[] }).messages[0]!.id;
    const { rows: tr } = await db.query("SELECT state, attempts, send_at > now() AS later FROM outbound_messages WHERE id = $1", [tid]);
    assert.deepEqual(tr[0], { state: "queued", attempts: 1, later: true });

    // Unknown outcome (timeout) → 'unknown', never resent.
    push.next = [{ kind: "unknown", code: "apns_timeout" }];
    const u = await call("POST", "/v1/updates", a.headers, { text: "u", channels: ["push"], idempotencyKey: "u" });
    await dispatchDue(db, { push, sms });
    const uid = (u.json() as { messages: { id: string }[] }).messages[0]!.id;
    push.sent = [];
    await dispatchDue(db, { push, sms });
    assert.equal((await call("GET", `/v1/updates/${uid}`, a.headers)).json().state, "unknown");
    assert.ok(!push.sent.some((s) => s.body === "u"));

    // A worker that died mid-send leaves 'sending'; it is reaped to 'unknown'.
    const s = await call("POST", "/v1/updates", a.headers, { text: "s", channels: ["push"], idempotencyKey: "s" });
    const sid = (s.json() as { messages: { id: string }[] }).messages[0]!.id;
    await db.query("UPDATE outbound_messages SET state = 'sending', updated_at = now() - interval '10 minutes' WHERE id = $1", [sid]);
    await dispatchDue(db, { push, sms });
    assert.equal((await call("GET", `/v1/updates/${sid}`, a.headers)).json().state, "unknown");
  });

  test("Twilio status callback records delivery", async () => {
    const a = await newAccount();
    await call("POST", "/v1/phone/verification/check", a.headers, { phone: "+48500999888", code: "123456" });
    await call("PUT", "/v1/phone/sms-consent", a.headers, { consent: true, textVersion: "sms-v1" });
    sms.next = [{ kind: "accepted", providerId: "SMdelivered1" }];
    const r = await call("POST", "/v1/updates", a.headers, { text: "x", channels: ["sms"], idempotencyKey: "d" });
    await dispatchDue(db, { push, sms });
    assert.equal((await twilioPost("/webhooks/twilio/status", { MessageSid: "SMdelivered1", MessageStatus: "delivered" })).statusCode, 204);
    const id = (r.json() as { messages: { id: string }[] }).messages[0]!.id;
    assert.equal((await call("GET", `/v1/updates/${id}`, a.headers)).json().deliveryStatus, "delivered");
  });

  test("deleting the account erases all of its rows", async () => {
    const a = await newAccount();
    await call("PUT", "/v1/device/push-token", a.headers, { token: "aa".repeat(32), environment: "sandbox" });
    await call("POST", "/v1/phone/verification/check", a.headers, { phone: "+48500777666", code: "123456" });
    await call("POST", "/v1/updates", a.headers, { text: "x", channels: ["push"], idempotencyKey: "z" });
    assert.equal((await call("DELETE", "/v1/account", a.headers)).statusCode, 204);
    for (const table of ["devices", "phone_numbers", "outbound_messages"]) {
      const { rowCount } = await db.query(`SELECT 1 FROM ${table} WHERE account_id = $1`, [a.accountId]);
      assert.equal(rowCount, 0, table);
    }
    assert.equal((await call("GET", "/v1/phone", a.headers)).statusCode, 401);
  });

  test("rate limits can't be dodged with a made-up Authorization or X-Forwarded-For header", async () => {
    // Its own app, so its limiter starts empty. Behind one proxy hop the client IP is the
    // right-most X-Forwarded-For entry, which here is the test client's own address.
    const own = await testApp(db, { trustProxyHops: 1 });
    try {
      const statuses: number[] = [];
      for (let i = 0; i < 12; i++) {
        const r = await own.app.inject({
          method: "POST", url: "/v1/accounts",
          headers: { authorization: `Bearer made-up-${i}`, "x-forwarded-for": `203.0.113.${i}, 198.51.100.7` },
        });
        statuses.push(r.statusCode);
      }
      assert.deepEqual(statuses.slice(0, 10), Array(10).fill(201));
      assert.deepEqual(statuses.slice(10), [429, 429]);
    } finally {
      await own.app.close();
    }
  });

  test("verify codes are capped per destination number, whichever account asks", async () => {
    const own = await testApp(db);
    try {
      const target = "+48500999001";
      const statuses: number[] = [];
      for (let i = 0; i < 4; i++) {
        const acc = (await own.app.inject({ method: "POST", url: "/v1/accounts" })).json() as { deviceToken: string };
        const r = await own.app.inject({
          method: "POST", url: "/v1/phone/verification",
          headers: { authorization: `Bearer ${acc.deviceToken}` }, payload: { phone: target },
        });
        statuses.push(r.statusCode);
      }
      assert.deepEqual(statuses, [202, 202, 202, 429]);
      assert.equal(own.verifier.started.filter((p: string) => p === target).length, 3);
      const { rows } = await db.query("SELECT 1 FROM phone_verification_starts WHERE phone_hash::text LIKE '%48500999001%'");
      assert.equal(rows.length, 0, "only a hash of the number is stored");
    } finally {
      await own.app.close();
    }
  });

  test("features without provider credentials answer 503, not a fake success", async () => {
    const bare = await testApp(db, { push: undefined, sms: undefined, verifier: undefined });
    const r = await bare.app.inject({ method: "POST", url: "/v1/accounts" });
    const h = { authorization: `Bearer ${r.json().deviceToken}` };
    assert.equal((await bare.app.inject({ method: "POST", url: "/v1/phone/verification", headers: h, payload: { phone: PHONE } })).statusCode, 503);
    assert.equal((await bare.app.inject({ method: "POST", url: "/v1/updates", headers: h, payload: { text: "x", channels: ["sms"], idempotencyKey: "n" } })).statusCode, 503);
    await bare.app.close();
  });
});
