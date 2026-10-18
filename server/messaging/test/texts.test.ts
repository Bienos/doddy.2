import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { textApprovalHash } from "../src/approval.js";
import { sha256 } from "../src/crypto.js";
import type { Db } from "../src/db.js";
import { dispatchDue, reconcileUnknownSms } from "../src/outbox.js";
import { APPROVED_TEXTS_PER_DAY } from "../src/routes/texts.js";
import { dbSkip, FakeSms, freshDb, testApp, testCipher, twilioRequest } from "./helpers.js";

// Texts the user approves on a card (ADR-490, unit U2): bound to the exact number and text.
describe("approved texts against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let sms: FakeSms;

  before(async () => {
    db = await freshDb();
    ({ app, sms } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  let accounts = 0;
  /** An account with a verified number and, unless told otherwise, consent to texts. */
  async function texter(phone: string, consent = true) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.1.0.${++accounts}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    assert.equal((await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } })).statusCode, 200);
    if (consent) {
      assert.equal((await app.inject({ method: "PUT", url: "/v1/phone/sms-consent", headers: h, payload: { consent: true, textVersion: "sms-v1" } })).statusCode, 204);
    }
    return { accountId, h };
  }
  const approve = (to: string, body: string) => textApprovalHash(to, body).toString("hex");
  const send = (h: object, body: string, approvalHash: string, idempotencyKey: string = randomUUID()) =>
    app.inject({ method: "POST", url: "/v1/texts", headers: h as Record<string, string>, payload: { body, approvalHash, idempotencyKey } });
  const row = async (id: string) => (await db.query(
    `SELECT state, approved_text, approval_hash, body_hash, body, body_ciphertext, error_code, provider_message_id,
            delivery_status, lookup, lookup_attempts FROM outbound_messages WHERE id = $1`, [id])).rows[0];

  test("a text goes out only with the hash of the verified number and the exact text", async () => {
    const off = await texter("+48500200001", false);
    assert.equal((await send(off.h, "Hi", approve("+48500200001", "Hi"))).json().error, "sms_not_enabled");

    const { accountId, h } = await texter("+48500200002");
    const body = "Call mum ";
    for (const wrong of [approve("+48500200999", body), approve("+48500200002", "Call mum")]) {
      const r = await send(h, body, wrong);
      assert.equal(r.statusCode, 409);
      assert.equal(r.json().error, "approval_mismatch");
    }
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [accountId])).rowCount, 0, "nothing queued");

    const ok = await send(h, body, approve("+48500200002", body));
    assert.equal(ok.statusCode, 202);
    const id = ok.json().messages[0].id as string;
    const queued = await row(id);
    assert.equal(queued.approved_text, true);
    assert.equal(queued.approval_hash.toString("hex"), approve("+48500200002", body));
    assert.ok(queued.body_hash.equals(sha256(body)));
    assert.equal(queued.body, null, "stored encrypted");
    assert.ok(queued.body_ciphertext);

    await dispatchDue(db, { sms, cipher: testCipher });
    assert.deepEqual(sms.sent.at(-1), { to: "+48500200002", body }, "exactly the approved text, not trimmed");
    const sent = await row(id);
    assert.deepEqual([sent.state, sent.approval_hash, sent.body_hash, sent.body_ciphertext], ["sent", null, null, null]);
  });

  test("the same tap again is the same text; a key can't be reused for another text", async () => {
    const { accountId, h } = await texter("+48500200003");
    const key = randomUUID();
    const first = await send(h, "Parcel code 4417", approve("+48500200003", "Parcel code 4417"), key);
    const again = await send(h, "Parcel code 4417", approve("+48500200003", "Parcel code 4417"), key);
    assert.equal(again.statusCode, 202);
    assert.equal(again.json().messages[0].id, first.json().messages[0].id);
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [accountId])).rowCount, 1);
    const other = await send(h, "Parcel code 9999", approve("+48500200003", "Parcel code 9999"), key);
    assert.equal(other.statusCode, 409);
    assert.equal(other.json().error, "idempotency_mismatch");
  });

  test("a number changed after the approval sends nothing", async () => {
    const { accountId, h } = await texter("+48500200004");
    const r = await send(h, "See you at 6", approve("+48500200004", "See you at 6"));
    await db.query("UPDATE phone_numbers SET e164 = '+48500200994' WHERE account_id = $1", [accountId]);
    await dispatchDue(db, { sms, cipher: testCipher });
    assert.deepEqual(sms.sent.filter((s) => s.body === "See you at 6"), [], "not sent to either number");
    const failed = await row(r.json().messages[0].id);
    assert.deepEqual([failed.state, failed.error_code, failed.approval_hash, failed.body_hash], ["failed", "approval_mismatch", null, null]);
  });

  test("an unknown outcome is never resent; Twilio's list settles it later", async () => {
    const { h } = await texter("+48500200005");
    const queue = async (body: string) => {
      const r = await send(h, body, approve("+48500200005", body));
      return r.json().messages[0].id as string;
    };
    const age = (id: string) => db.query("UPDATE outbound_messages SET updated_at = now() - interval '3 minutes' WHERE id = $1", [id]);

    // Found: Twilio did create it.
    const found = await queue("Dentist moved to 15:00");
    sms.next = [{ kind: "unknown", code: "twilio_500" }];
    await dispatchDue(db, { sms, cipher: testCipher });
    const sentCount = sms.sent.length;
    await dispatchDue(db, { sms, cipher: testCipher });
    assert.equal(sms.sent.length, sentCount, "never resent");
    const unknown = await row(found);
    assert.equal(unknown.state, "unknown");
    assert.ok(unknown.body_hash, "kept for the lookup");
    assert.equal(await reconcileUnknownSms(db, sms), 0, "too early to ask");
    await age(found);
    sms.recent = [
      { sid: "SMolder", body: "Dentist moved to 15:00", createdAt: new Date(Date.now() - 60 * 60_000), status: "delivered" },
      { sid: "SMother", body: "Something else", createdAt: new Date(), status: "sent" },
      { sid: "SMfound", body: "Dentist moved to 15:00", createdAt: new Date(), status: "delivered" },
    ];
    assert.equal(await reconcileUnknownSms(db, sms), 1);
    const settled = await row(found);
    assert.deepEqual(
      [settled.state, settled.provider_message_id, settled.delivery_status, settled.lookup, settled.approval_hash, settled.body_hash],
      ["sent", "SMfound", "delivered", "found", null, null], "an hour-old copy of the same text isn't this one");
    const status = (await app.inject({ method: "GET", url: `/v1/updates/${found}`, headers: h })).json();
    assert.deepEqual([status.state, status.deliveryStatus, status.lookup], ["sent", "delivered", "found"]);

    // Not found: it stays unknown and says Twilio has no record of it.
    const missing = await queue("Bring the umbrella");
    sms.next = [{ kind: "unknown", code: "twilio_network" }];
    await dispatchDue(db, { sms, cipher: testCipher });
    await age(missing);
    sms.recent = [];
    await reconcileUnknownSms(db, sms);
    const notFound = await row(missing);
    assert.deepEqual([notFound.state, notFound.lookup, notFound.body_hash], ["unknown", "not_found", null]);

    // Twilio can't be asked: three tries, then it says so.
    const unasked = await queue("Gate code 2580");
    sms.next = [{ kind: "unknown", code: "twilio_502" }];
    await dispatchDue(db, { sms, cipher: testCipher });
    sms.recent = undefined;
    for (let i = 0; i < 3; i++) {
      await age(unasked);
      await reconcileUnknownSms(db, sms);
    }
    const gaveUp = await row(unasked);
    assert.deepEqual([gaveUp.state, gaveUp.lookup, gaveUp.lookup_attempts, gaveUp.body_hash], ["unknown", "failed", 3, null]);
    sms.recent = [];
  });

  test("delivery receipts only move forward", async () => {
    const { h } = await texter("+48500200006");
    const r = await send(h, "On my way", approve("+48500200006", "On my way"));
    const id = r.json().messages[0].id as string;
    await dispatchDue(db, { sms, cipher: testCipher });
    const sid = (await row(id)).provider_message_id as string;
    const receipt = (status: string) => app.inject(twilioRequest("/webhooks/twilio/status", { MessageSid: sid, MessageStatus: status }));
    for (const [status, stored] of [["sent", "sent"], ["delivered", "delivered"], ["sent", "delivered"], ["queued", "delivered"], ["made_up", "delivered"]]) {
      assert.equal((await receipt(status!)).statusCode, 204);
      assert.equal((await row(id)).delivery_status, stored, status);
    }
  });

  test("cancelling a queued update erases its encrypted text", async () => {
    const { h } = await texter("+48500200007");
    const later = new Date(Date.now() + 3_600_000).toISOString();
    const r = await app.inject({ method: "POST", url: "/v1/updates", headers: h,
      payload: { text: "Later", channels: ["sms"], sendAt: later, idempotencyKey: randomUUID() } });
    const id = r.json().messages[0].id as string;
    assert.ok((await row(id)).body_ciphertext);
    assert.equal((await app.inject({ method: "DELETE", url: `/v1/updates/${id}`, headers: h })).statusCode, 204);
    const cancelled = await row(id);
    assert.deepEqual([cancelled.state, cancelled.body_ciphertext, cancelled.body_hash], ["cancelled", null, null]);
  });

  test(`daily limits: ${APPROVED_TEXTS_PER_DAY} per account, then 300 across the server`, async () => {
    const { h } = await texter("+48500200008");
    for (let i = 0; i < APPROVED_TEXTS_PER_DAY; i++) {
      assert.equal((await send(h, `Note ${i}`, approve("+48500200008", `Note ${i}`))).statusCode, 202, `text ${i}`);
    }
    const over = await send(h, "One more", approve("+48500200008", "One more"));
    assert.equal(over.statusCode, 429);
    assert.equal(over.json().error, "daily_limit");

    const other = await texter("+48500200009");
    await db.query(
      `INSERT INTO outbound_messages (id, account_id, channel, idempotency_key, send_at, state, approved_text)
       SELECT gen_random_uuid(), $1, 'sms', 'bulk' || g, now(), 'sent', true FROM generate_series(1, 300) g`, [other.accountId]);
    const third = await texter("+48500200010");
    const serverOver = await send(third.h, "Hello", approve("+48500200010", "Hello"));
    assert.equal(serverOver.statusCode, 429);
    assert.equal(serverOver.json().error, "server_daily_limit");
  });

  test("without SMS or the encryption key on the server, texts say not configured", async () => {
    // Without the key a text would be stored readable, and the card says it is kept encrypted.
    let n = 0;
    for (const missing of [{ sms: undefined }, { cipher: undefined }]) {
      const bare = await testApp(db, missing);
      const r = await bare.app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.1.9.${++n}` });
      const h = { authorization: `Bearer ${r.json().deviceToken}` };
      const res = await bare.app.inject({ method: "POST", url: "/v1/texts", headers: h, payload: { body: "x", approvalHash: "0".repeat(64), idempotencyKey: "k" } });
      assert.equal(res.statusCode, 503);
      assert.equal(res.json().error, "sms_not_configured");
      await bare.app.close();
    }
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE idempotency_key = 'k'")).rowCount, 0);
  });
});
