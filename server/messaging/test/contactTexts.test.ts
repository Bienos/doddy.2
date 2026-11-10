import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { textApprovalHash } from "../src/approval.js";
import { CONTACT_TEXTS_PER_DAY } from "../src/contactTexts.js";
import type { Db } from "../src/db.js";
import { dispatchDue, reconcileUnknownSms } from "../src/outbox.js";
import { dbSkip, DODDY_NUMBER, FakeSms, freshDb, testApp, testCipher, twilioRequest } from "./helpers.js";

// Texts from Doddy's number to the user's contacts (decision 2026-11-09-texts-to-contacts): one tap per text, bound to
// the contact's number and the exact text, no signature, 50 a day per account, STOP honoured, off by default.
describe("texts to contacts against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let off: FastifyInstance;
  let sms: FakeSms;

  before(async () => {
    db = await freshDb();
    ({ app, sms } = await testApp(db, { contactTexts: true }));
    ({ app: off } = await testApp(db));
  });
  after(async () => {
    await app?.close();
    await off?.close();
    await db?.end();
  });

  let accounts = 0;
  /** An account; with `phone`, a verified number of its own (no consent to texts to itself needed). */
  async function user(phone?: string, on: FastifyInstance = app) {
    const r = await on.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.2.0.${++accounts}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    if (phone) {
      assert.equal((await on.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } })).statusCode, 200);
    }
    return { accountId, h };
  }
  const approve = (to: string, body: string) => textApprovalHash(to, body).toString("hex");
  const send = (h: object, to: string, body: string, approvalHash = approve(to, body), idempotencyKey: string = randomUUID(), on = app) =>
    on.inject({ method: "POST", url: "/v1/texts/contact", headers: h as Record<string, string>, payload: { to, body, approvalHash, idempotencyKey } });
  const row = async (id: string) => (await db.query(
    "SELECT state, to_e164, body, body_ciphertext, approval_hash, body_hash, error_code FROM outbound_messages WHERE id = $1", [id])).rows[0];
  /** Earlier tests leave texts queued; a test that drives the worker starts with none, so the fake's next outcome is its own. */
  const drain = () => db.query(
    `UPDATE outbound_messages SET state = 'cancelled', body = NULL, body_ciphertext = NULL, body_key_version = NULL,
       approval_hash = NULL, body_hash = NULL, to_e164 = NULL WHERE state = 'queued'`);
  const stop = (from: string, body = "STOP") =>
    app.inject(twilioRequest("/webhooks/twilio/sms", { From: from, Body: body, MessageSid: `SM${randomUUID().replace(/-/g, "")}` }));

  test("off by default: nothing is queued", async () => {
    const { h } = await user("+48500300001", off);
    const r = await send(h, "+48600300001", "Hej", undefined, undefined, off);
    assert.equal(r.statusCode, 503);
    assert.equal(r.json().error, "contact_texts_off");
  });

  test("the exact text goes to exactly the contact's number, with no signature", async () => {
    const { accountId, h } = await user("+48500300002");
    const body = "Spóźnię się 10 minut ";
    for (const wrong of [approve("+48600300999", body), approve("+48600300002", "Spóźnię się 10 minut")]) {
      const r = await send(h, "+48600300002", body, wrong);
      assert.equal(r.statusCode, 409);
      assert.equal(r.json().error, "approval_mismatch");
    }
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [accountId])).rowCount, 0, "nothing queued");

    const ok = await send(h, "+48600300002", body);
    assert.equal(ok.statusCode, 202);
    const id = ok.json().messages[0].id as string;
    const queued = await row(id);
    assert.equal(queued.to_e164, "+48600300002");
    assert.equal(queued.body, null, "stored encrypted");

    await dispatchDue(db, { sms, cipher: testCipher });
    assert.deepEqual(sms.sent.at(-1), { to: "+48600300002", body }, "the contact, exactly the approved text, nothing added");
    const sent = await row(id);
    assert.deepEqual([sent.state, sent.to_e164, sent.body_ciphertext, sent.approval_hash], ["sent", null, null, null],
      "the contact's number is erased with the text");
  });

  test("only an account with a verified number of its own, and never Doddy's number or another country", async () => {
    const none = await user();
    assert.equal((await send(none.h, "+48600300003", "Hej")).json().error, "phone_not_verified");
    const { h } = await user("+48500300004");
    assert.equal((await send(h, DODDY_NUMBER, "Hej")).json().error, "phone_not_allowed");
    assert.equal((await send(h, "+12025550123", "Hi")).json().error, "phone_not_allowed");
    const bad = await send(h, "600300005", "Hej");
    assert.equal(bad.statusCode, 400, "the app sends E.164; a number without its code is refused");
  });

  test("the same tap again is the same text; the key can't be reused for another number", async () => {
    const { accountId, h } = await user("+48500300006");
    const key = randomUUID();
    const first = await send(h, "+48600300006", "Kod 4417", undefined, key);
    const again = await send(h, "+48600300006", "Kod 4417", undefined, key);
    assert.equal(again.statusCode, 202);
    assert.equal(again.json().messages[0].id, first.json().messages[0].id);
    const other = await send(h, "+48600300007", "Kod 4417", undefined, key);
    assert.equal(other.json().error, "idempotency_mismatch");
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [accountId])).rowCount, 1);
  });

  test("fifty a day to contacts, counted apart from texts to the user's own number", async () => {
    const { accountId, h } = await user("+48500300008");
    for (let i = 0; i < CONTACT_TEXTS_PER_DAY; i++) {
      assert.equal((await send(h, "+48600300008", `Wiadomość ${i}`)).statusCode, 202, `text ${i + 1}`);
    }
    const over = await send(h, "+48600300008", "Jeszcze jedna");
    assert.equal(over.statusCode, 429);
    assert.equal(over.json().error, "daily_limit");
    const { rows: [counts] } = await db.query(
      "SELECT count(*)::int AS n FROM outbound_messages WHERE account_id = $1 AND to_e164 IS NOT NULL", [accountId]);
    assert.equal(counts.n, CONTACT_TEXTS_PER_DAY);
    const { rows: own } = await db.query(
      "SELECT n FROM daily_counters WHERE scope = 'sms_account' AND day = (now() AT TIME ZONE 'utc')::date AND key = encode(sha256($1::text::bytea), 'hex')",
      [accountId]);
    assert.equal(own.length, 0, "texts to contacts don't use up the user's texts to themselves");
  });

  test("a contact who answers STOP gets nothing more, queued texts are cancelled, START undoes it", async () => {
    const { h } = await user("+48500300009");
    const later = await send(h, "+48600300010", "Później");
    assert.equal((await stop("+48600300010")).statusCode, 200);
    const cancelled = await row(later.json().messages[0].id);
    assert.deepEqual([cancelled.state, cancelled.error_code, cancelled.to_e164, cancelled.body_ciphertext],
      ["cancelled", "contact_opted_out", null, null]);
    const refused = await send(h, "+48600300010", "Hej");
    assert.equal(refused.statusCode, 409);
    assert.equal(refused.json().error, "contact_opted_out");
    const { rows } = await db.query("SELECT number_hash FROM contact_text_opt_outs");
    assert.ok(rows.every((r: { number_hash: Buffer }) => !r.number_hash.toString("utf8").includes("600300010")), "only a hash is kept");

    await stop("+48600300010", "START");
    assert.equal((await send(h, "+48600300010", "Hej")).statusCode, 202);
  });

  test("Twilio saying the contact unsubscribed records the opt-out, not the user's own", async () => {
    const { accountId, h } = await user("+48500300011");
    await drain();
    await send(h, "+48600300011", "Hej");
    sms.next.push({ kind: "rejected", code: "21610", unsubscribed: true });
    await dispatchDue(db, { sms, cipher: testCipher });
    assert.equal((await send(h, "+48600300011", "Hej 2")).json().error, "contact_opted_out");
    const { rows: [me] } = await db.query("SELECT sms_opted_out_at FROM phone_numbers WHERE account_id = $1", [accountId]);
    assert.equal(me.sms_opted_out_at, null, "the user's own number is untouched");
  });

  test("an unknown outcome is looked up by the contact's number and never sent again", async () => {
    const { h } = await user("+48500300012");
    await drain();
    const r = await send(h, "+48600300012", "Hej, to ja");
    const id = r.json().messages[0].id as string;
    sms.next.push({ kind: "unknown", code: "timeout" });
    await dispatchDue(db, { sms, cipher: testCipher });
    assert.equal((await row(id)).to_e164, "+48600300012", "kept while the outcome is looked up");
    await db.query("UPDATE outbound_messages SET updated_at = now() - interval '10 minutes' WHERE id = $1", [id]);
    sms.recent = [{ sid: "SMfound1", body: "Hej, to ja", createdAt: new Date(), status: "delivered" }];
    sms.lookups = [];
    await reconcileUnknownSms(db, sms);
    assert.deepEqual(sms.lookups, ["+48600300012"]);
    const found = await row(id);
    assert.deepEqual([found.state, found.to_e164], ["sent", null]);
    const before = sms.sent.length;
    await dispatchDue(db, { sms, cipher: testCipher });
    assert.equal(sms.sent.length, before, "never resent");
  });

  test("the user's own STOP doesn't cancel their texts to contacts", async () => {
    const { h } = await user("+48500300013");
    const r = await send(h, "+48600300013", "Hej");
    await stop("+48500300013");
    assert.equal((await row(r.json().messages[0].id)).state, "queued");
  });
});
