import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { DEFAULT_SMS_SETTINGS } from "../src/config.js";
import type { Db } from "../src/db.js";
import { TextCipher } from "../src/crypto.js";
import { DailyTextLimit, dispatchDue, enqueue, MAX_ATTEMPTS } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { BASE_URL, dbSkip, FakeOutbound, FakePush, FakeSms, freshDb, testApp, testCipher, TWILIO_TOKEN } from "./helpers.js";

const APNS_TOKEN = "ab".repeat(32);
const PHONE = "+48500100200";

describe("server against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let push: FakePush;
  let sms: FakeSms;
  let outbound: FakeOutbound;

  before(async () => {
    db = await freshDb();
    ({ app, push, sms, outbound } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  // Each test account comes from its own address, so the per-IP signup limit (10/hour) is
  // exercised by its own test below rather than by how many tests this suite has.
  let accounts = 0;
  async function newAccount() {
    accounts++;
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.77.${accounts >> 8}.${accounts & 255}` });
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
    const edited = await call("POST", "/v1/updates", a.headers, { ...update, text: "Your dentist is at 16:00" });
    assert.equal(edited.statusCode, 409, "same key with different text is refused, not silently ignored");
    assert.equal(edited.json().error, "idempotency_mismatch");

    const id = (first.json() as { messages: { id: string }[] }).messages[0]!.id;
    const { rows: queued } = await db.query("SELECT body, body_ciphertext FROM outbound_messages WHERE id = $1", [id]);
    assert.equal(queued[0].body, null, "queued text is encrypted at rest");
    assert.ok(!queued[0].body_ciphertext.toString("utf8").includes("dentist"));

    push.sent = [];
    await dispatchDue(db, { push, sms, cipher: testCipher });
    assert.equal(push.sent.length, 1);
    assert.equal(push.sent[0]!.body, "Your dentist is at 15:00");

    const status = await call("GET", `/v1/updates/${id}`, a.headers);
    assert.equal(status.json().state, "sent");
    const { rows } = await db.query("SELECT body, body_ciphertext FROM outbound_messages WHERE id = $1", [id]);
    assert.equal(rows[0].body, null);
    assert.equal(rows[0].body_ciphertext, null, "text erased once sent");

    const other = await newAccount();
    assert.equal((await call("GET", `/v1/updates/${id}`, other.headers)).statusCode, 404, "no cross-account reads");
  });

  test("push: a token Apple reports as gone is switched off", async () => {
    const a = await newAccount();
    await call("PUT", "/v1/device/push-token", a.headers, { token: "cd".repeat(32), environment: "production" });
    await call("POST", "/v1/updates", a.headers, { text: "hi", channels: ["push"], idempotencyKey: "gone" });
    push.next = [{ kind: "rejected", code: "apns_Unregistered", deviceGone: true }];
    await dispatchDue(db, { push, sms, cipher: testCipher });
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
    await dispatchDue(db, { push, sms, cipher: testCipher });
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
    await dispatchDue(db, { push, sms, cipher: testCipher });
    const tid = (t.json() as { messages: { id: string }[] }).messages[0]!.id;
    const { rows: tr } = await db.query("SELECT state, attempts, send_at > now() AS later FROM outbound_messages WHERE id = $1", [tid]);
    assert.deepEqual(tr[0], { state: "queued", attempts: 1, later: true });

    // Unknown outcome (timeout) → 'unknown', never resent.
    push.next = [{ kind: "unknown", code: "apns_timeout" }];
    const u = await call("POST", "/v1/updates", a.headers, { text: "u", channels: ["push"], idempotencyKey: "u" });
    await dispatchDue(db, { push, sms, cipher: testCipher });
    const uid = (u.json() as { messages: { id: string }[] }).messages[0]!.id;
    push.sent = [];
    await dispatchDue(db, { push, sms, cipher: testCipher });
    assert.equal((await call("GET", `/v1/updates/${uid}`, a.headers)).json().state, "unknown");
    assert.ok(!push.sent.some((s) => s.body === "u"));

    // A worker that died mid-send leaves 'sending'; it is reaped to 'unknown'.
    const s = await call("POST", "/v1/updates", a.headers, { text: "s", channels: ["push"], idempotencyKey: "s" });
    const sid = (s.json() as { messages: { id: string }[] }).messages[0]!.id;
    await db.query("UPDATE outbound_messages SET state = 'sending', updated_at = now() - interval '10 minutes' WHERE id = $1", [sid]);
    await dispatchDue(db, { push, sms, cipher: testCipher });
    assert.equal((await call("GET", `/v1/updates/${sid}`, a.headers)).json().state, "unknown");
  });

  test("a claimed message reaped by another worker before its turn is not sent", async () => {
    const a = await newAccount();
    await call("PUT", "/v1/device/push-token", a.headers, { token: "cd".repeat(32), environment: "sandbox" });
    const q = async (text: string) => (await call("POST", "/v1/updates", a.headers, { text, channels: ["push"], idempotencyKey: text })).json().messages[0].id;
    const first = await q("reap-1");
    const second = await q("reap-2");
    await db.query("UPDATE outbound_messages SET send_at = now() - interval '1 hour' WHERE id = $1", [first]);
    const sent: string[] = [];
    const slow = new FakePush();
    slow.send = async (_t, alert, id) => {
      sent.push(alert.body);
      // While this send is in flight, another worker's reaper marks the next one unknown.
      await db.query("UPDATE outbound_messages SET state = 'unknown', error_code = 'worker_interrupted', body = NULL, body_ciphertext = NULL, body_key_version = NULL WHERE id = $1", [second]);
      return { kind: "accepted", providerId: id };
    };
    await dispatchDue(db, { push: slow, cipher: testCipher });
    assert.ok(sent.includes("reap-1"));
    assert.ok(!sent.includes("reap-2"), "an unknown message is never sent afterwards");
  });

  test("a message the server can't decrypt fails without being sent", async () => {
    const a = await newAccount();
    await call("PUT", "/v1/device/push-token", a.headers, { token: "fa".repeat(32), environment: "sandbox" });
    const id = (await call("POST", "/v1/updates", a.headers, { text: "secret", channels: ["push"], idempotencyKey: "nokey" })).json().messages[0].id;
    await db.query("UPDATE outbound_messages SET send_at = now() - interval '2 hours' WHERE id = $1", [id]);
    const p = new FakePush();
    await dispatchDue(db, { push: p, cipher: new TextCipher(Buffer.alloc(32, 9)) });
    assert.ok(!p.sent.some((s) => s.target.deviceToken === "fa".repeat(32)));
    const { rows } = await db.query("SELECT state, error_code FROM outbound_messages WHERE id = $1", [id]);
    assert.deepEqual(rows[0], { state: "failed", error_code: "body_unreadable" });
  });

  test("transient refusals stop after MAX_ATTEMPTS and end as failed", async () => {
    const a = await newAccount();
    await call("PUT", "/v1/device/push-token", a.headers, { token: "ab12".repeat(16), environment: "sandbox" });
    const id = (await call("POST", "/v1/updates", a.headers, { text: "retry", channels: ["push"], idempotencyKey: "retry" })).json().messages[0].id;
    await db.query("UPDATE outbound_messages SET attempts = $2 - 1, send_at = now() - interval '3 hours' WHERE id = $1", [id, MAX_ATTEMPTS]);
    const p = new FakePush();
    p.next = [{ kind: "transient", code: "apns_503" }];
    await dispatchDue(db, { push: p, cipher: testCipher });
    const { rows } = await db.query("SELECT state, attempts, error_code FROM outbound_messages WHERE id = $1", [id]);
    assert.deepEqual(rows[0], { state: "failed", attempts: MAX_ATTEMPTS, error_code: "apns_503" });
  });

  test("a number proven by another account takes its queued texts with it", async () => {
    const old = await newAccount();
    const phone = "+48500100999";
    await call("POST", "/v1/phone/verification/check", old.headers, { phone, code: "123456" });
    await call("PUT", "/v1/phone/sms-consent", old.headers, { consent: true, textVersion: "sms-v1" });
    const q = await call("POST", "/v1/updates", old.headers, { text: "for old owner", channels: ["sms"], idempotencyKey: "moved",
      sendAt: new Date(Date.now() + 3_600_000).toISOString() });
    assert.equal(q.statusCode, 202);
    const fresh = await newAccount();
    assert.equal((await call("POST", "/v1/phone/verification/check", fresh.headers, { phone, code: "123456" })).statusCode, 200);
    const { rows } = await db.query("SELECT state, error_code FROM outbound_messages WHERE id = $1", [q.json().messages[0].id]);
    assert.deepEqual(rows[0], { state: "cancelled", error_code: "sms_not_enabled" });
    assert.equal((await call("GET", "/v1/phone", fresh.headers)).json().smsEnabled, false, "new owner starts without consent");
  });

  test("Twilio status callback records delivery", async () => {
    const a = await newAccount();
    await call("POST", "/v1/phone/verification/check", a.headers, { phone: "+48500999888", code: "123456" });
    await call("PUT", "/v1/phone/sms-consent", a.headers, { consent: true, textVersion: "sms-v1" });
    sms.next = [{ kind: "accepted", providerId: "SMdelivered1" }];
    const r = await call("POST", "/v1/updates", a.headers, { text: "x", channels: ["sms"], idempotencyKey: "d" });
    await dispatchDue(db, { push, sms, cipher: testCipher });
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

  test("verify codes go only to numbers in the allowed countries", async () => {
    const own = await testApp(db);
    try {
      const acc = (await own.app.inject({ method: "POST", url: "/v1/accounts" })).json() as { deviceToken: string };
      const start = (phone: string) => own.app.inject({
        method: "POST", url: "/v1/phone/verification", headers: { authorization: `Bearer ${acc.deviceToken}` }, payload: { phone },
      });
      for (const phone of ["+12025550123", "+79161234567", "+2348012345678", "+8801712345678"]) {
        const r = await start(phone);
        assert.equal(r.statusCode, 400, phone);
        assert.deepEqual(r.json(), { error: "phone_country_not_supported" });
      }
      assert.deepEqual(own.verifier.started, [], "Verify is never asked");
      assert.equal((await start("+48500999002")).statusCode, 202);
      assert.deepEqual(own.verifier.started, ["+48500999002"]);
    } finally {
      await own.app.close();
    }
  });

  test("a number verified outside the allowed countries is never texted or called", async () => {
    const a = await newAccount();
    const phone = "+12025550123";
    // As if verified before the list applied: the check takes any number Verify approved.
    assert.equal((await call("POST", "/v1/phone/verification/check", a.headers, { phone, code: "123456" })).statusCode, 200);
    assert.equal((await call("PUT", "/v1/phone/sms-consent", a.headers, { consent: true, textVersion: "sms-v1" })).statusCode, 204);
    const r = await call("POST", "/v1/updates", a.headers, { text: "Hello", channels: ["sms"], idempotencyKey: "country-1" });
    assert.equal(r.statusCode, 202);
    const id = (r.json() as { messages: { id: string }[] }).messages[0]!.id;
    await dispatchDue(db, { push, sms, cipher: testCipher });
    assert.equal(sms.sent.filter((s) => s.to === phone).length, 0, "never handed to Twilio");
    const m = (await call("GET", `/v1/updates/${id}`, a.headers)).json();
    assert.equal(m.state, "failed", "definitely not sent, not unknown");
    assert.equal(m.errorCode, "sms_country_not_supported");

    assert.equal((await call("PUT", "/v1/calls/settings", a.headers, { outboundConsent: true, outboundConsentTextVersion: "calls-v1" })).statusCode, 204);
    const placed = outbound.calls.length;
    const c = await call("POST", "/v1/calls/outbound", a.headers);
    assert.equal(c.statusCode, 409);
    assert.equal(c.json().error, "phone_country_not_supported");
    assert.equal(outbound.calls.length, placed, "never dialled");
    assert.equal((await db.query("SELECT 1 FROM calls WHERE account_id = $1", [a.accountId])).rowCount, 0);
  });

  test("texts: 20 a day per account; the 21st is refused, nothing of it is queued or sent; another account still texts", async () => {
    const texting = async (phone: string) => {
      const acc = await newAccount();
      assert.equal((await call("POST", "/v1/phone/verification/check", acc.headers, { phone, code: "123456" })).statusCode, 200);
      assert.equal((await call("PUT", "/v1/phone/sms-consent", acc.headers, { consent: true, textVersion: "sms-v1" })).statusCode, 204);
      return acc;
    };
    const phone = "+48500100301";
    const a = await texting(phone);
    await call("PUT", "/v1/device/push-token", a.headers, { token: "a1".repeat(32), environment: "sandbox" });
    const update = (k: string, channels = ["sms"]) => call("POST", "/v1/updates", a.headers, { text: `cap ${k}`, channels, idempotencyKey: k });
    for (let i = 1; i <= 20; i++) assert.equal((await update(`cap-${i}`)).statusCode, 202, `text ${i}`);
    const over = await update("cap-21");
    assert.equal(over.statusCode, 429);
    assert.deepEqual(over.json(), { error: "daily_text_limit" });
    assert.equal((await update("cap-22", ["push", "sms"])).statusCode, 429, "refused as a whole: the push isn't queued either");
    assert.equal((await update("cap-1")).statusCode, 202, "a retry of a text already queued is not counted again");
    const { rows } = await db.query<{ k: string }>("SELECT idempotency_key AS k FROM outbound_messages WHERE account_id = $1", [a.accountId]);
    assert.equal(rows.length, 20);
    assert.ok(!rows.some((r) => r.k === "cap-21" || r.k === "cap-22"));

    // Its own provider ids: they are unique across the database.
    const texts = new FakeSms();
    const send = texts.send.bind(texts);
    texts.send = async (to, body) => {
      const o = await send(to, body);
      return o.kind === "accepted" ? { ...o, providerId: `SMcap${texts.sent.length}` } : o;
    };
    while ((await dispatchDue(db, { push, sms: texts, cipher: testCipher })).processed) { /* until nothing is due */ }
    assert.equal(texts.sent.filter((s) => s.to === phone).length, 20);

    const b = await texting("+48500100302");
    assert.equal((await call("POST", "/v1/updates", b.headers, { text: "hi", channels: ["sms"], idempotencyKey: "b1" })).statusCode, 202);
  });

  test("texts: the server-wide cap counts every account (deleted ones too), and the next UTC day starts again", async () => {
    const [a, b, c] = [await newAccount(), await newAccount(), await newAccount()];
    const caps = { ...DEFAULT_SMS_SETTINGS, dailyPerAccount: 2, dailyPerServer: 3 };
    // Days no other test texts on, so the server-wide count is only these.
    const day1 = new Date("2031-03-01T23:59:00Z");
    const day2 = new Date("2031-03-02T00:01:00Z");
    const text = (accountId: string, key: string, now: Date) => enqueue(db, accountId, ["sms"], "x", now, key, { smsSettings: caps, now });
    const refused = (cap: string) => (err: unknown) => err instanceof DailyTextLimit && err.cap === cap;
    await text(a.accountId, "d1-a1", day1);
    await text(a.accountId, "d1-a2", day1);
    await assert.rejects(text(a.accountId, "d1-a3", day1), refused("account"));
    await text(b.accountId, "d1-b1", day1);
    await assert.rejects(text(b.accountId, "d1-b2", day1), refused("server"));
    assert.equal((await call("DELETE", "/v1/account", a.headers)).statusCode, 204);
    await assert.rejects(text(c.accountId, "d1-c1", day1), refused("server"));

    await text(b.accountId, "d2-b1", day2);
    await text(c.accountId, "d2-c1", day2);
    const { rows } = await db.query<{ k: string }>(
      "SELECT idempotency_key AS k FROM outbound_messages WHERE account_id = ANY($1) ORDER BY 1", [[b.accountId, c.accountId]]);
    assert.deepEqual(rows.map((r) => r.k), ["d1-b1", "d2-b1", "d2-c1"]);
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
