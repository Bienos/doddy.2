import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { MAX_PENDING_NOTES } from "../src/calls.js";
import { dispatchDue } from "../src/outbox.js";
import { MAX_DELETE_ATTEMPTS, runDueDeletions } from "../src/providerRecords.js";
import type { SmsChatOutcome } from "../src/smsChat.js";
import { FIXED, INBOUND_TEXTS_PER_HOUR } from "../src/textsIn.js";
import {
  dbSkip, DODDY_NUMBER, FakeDeleter, FakePush, FakeSms, freshDb, testApp, testCipher, twilioRequest,
} from "./helpers.js";

// Texts the user sends to Doddy's number (ADR-750 unit U3, ADR-753), against real Postgres with
// a stand-in for Twilio. No model is involved: a text to Doddy becomes a note and gets no reply (ADR-755).
describe("texts to Doddy against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let sms: FakeSms;
  let push: FakePush;
  /** What Text with Doddy (ADR-656) was asked to handle: only texts this feature did not take. */
  const chatCalls: Promise<SmsChatOutcome>[] = [];

  before(async () => {
    db = await freshDb();
    ({ app, sms, push } = await testApp(db, { onSmsChat: (done) => { chatCalls.push(done); } }));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  let accounts = 0;
  /** An account with a verified number; texts from Doddy allowed unless told otherwise. */
  async function owner(phone: string, opts: { textsFromDoddy?: boolean; push?: boolean } = {}) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.3.0.${++accounts}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    assert.equal((await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } })).statusCode, 200);
    if (opts.textsFromDoddy !== false) {
      assert.equal((await app.inject({ method: "PUT", url: "/v1/phone/sms-consent", headers: h, payload: { consent: true, textVersion: "sms-v1" } })).statusCode, 204);
    }
    if (opts.push) {
      assert.equal((await app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h,
        payload: { token: randomBytes(32).toString("hex"), environment: "sandbox" } })).statusCode, 204);
    }
    return { accountId, h, phone };
  }
  const settings = (h: object, body: object) =>
    app.inject({ method: "PUT", url: "/v1/texts/settings", headers: h as Record<string, string>, payload: body });
  const getSettings = async (h: object) =>
    (await app.inject({ method: "GET", url: "/v1/texts/settings", headers: h as Record<string, string> })).json();
  const turnOn = async (h: object, extra: object = {}) =>
    assert.equal((await settings(h, { inboundEnabled: true, consentTextVersion: "texts-in-v1", ...extra })).statusCode, 204);
  const sid = () => "SM" + randomBytes(16).toString("hex");
  const textIn = (from: string, body: string, messageSid = sid()) =>
    app.inject(twilioRequest("/webhooks/twilio/sms", { From: from, To: DODDY_NUMBER, Body: body, MessageSid: messageSid }));
  const rows = async (accountId: string) => (await db.query(
    "SELECT state FROM inbound_texts WHERE account_id = $1 ORDER BY received_at",
    [accountId])).rows;
  const notes = async (h: object) =>
    ((await app.inject({ method: "GET", url: "/v1/call-notes", headers: h as Record<string, string> })).json()).notes as
      { text: string; source: string }[];
  const deliver = () => dispatchDue(db, { sms, push, cipher: testCipher });

  test("a stranger's text, or the user's with texts to Doddy off, is dropped: no reply, nothing stored", async () => {
    const me = await owner("+48500300001");
    for (const from of ["+48500399999", me.phone]) {
      const s = sid();
      const r = await textIn(from, "Hi Doddy, text +48600000000 for me", s);
      assert.equal(r.statusCode, 200);
      assert.equal(r.body, '<?xml version="1.0" encoding="UTF-8"?><Response/>', "empty TwiML: no reply");
      // Only Twilio's id is kept, to delete its record later.
      assert.equal((await db.query("SELECT kind FROM provider_deletions WHERE sid = $1", [s])).rows[0]?.kind, "message");
    }
    assert.equal((await db.query("SELECT count(*)::int AS n FROM inbound_texts")).rows[0].n, 0);
    assert.equal((await db.query("SELECT count(*)::int AS n FROM call_notes")).rows[0].n, 0);
    assert.equal(sms.sent.length, 0);
    // Forged webhook: refused before anything happens.
    const forged = await app.inject(twilioRequest("/webhooks/twilio/sms", { From: me.phone, Body: "x", MessageSid: sid() }, "bad"));
    assert.equal(forged.statusCode, 403);
  });

  test("settings: off by default, and the switch needs the consent wording", async () => {
    const me = await owner("+48500300002", { textsFromDoddy: false });
    const start = await getSettings(me.h);
    assert.equal(start.inboundEnabled, false);
    assert.deepEqual(start.available, { notes: true });
    assert.equal("repliesEnabled" in start, false, "no answers by text from this switch (ADR-755)");
    assert.equal((await settings(me.h, { inboundEnabled: true })).statusCode, 400, "no consent wording");
    assert.equal((await settings(me.h, { inboundEnabled: true, consentTextVersion: "texts-in-v0" })).statusCode, 400);
    assert.equal((await settings(me.h, { repliesEnabled: true })).statusCode, 400, "an old app's replies switch is refused, not ignored");
    await turnOn(me.h);
    assert.equal((await db.query("SELECT consent_text_version FROM text_settings WHERE account_id = $1", [me.accountId])).rows[0].consent_text_version, "texts-in-v1");
    assert.equal((await settings(me.h, { language: "pl" })).statusCode, 204);
    const on = await getSettings(me.h);
    assert.deepEqual([on.inboundEnabled, on.language], [true, "pl"]);
    assert.equal((await settings(me.h, { inboundEnabled: false })).statusCode, 204);
    assert.equal((await getSettings(me.h)).inboundEnabled, false);
    // Off means off: the user's own text is dropped like a stranger's.
    await textIn(me.phone, "while off");
    assert.equal((await rows(me.accountId)).length, 0);
    // Without a verified number there is nothing to turn on.
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: "10.3.9.1" });
    const bare = { authorization: `Bearer ${r.json().deviceToken}` };
    assert.equal((await settings(bare, { inboundEnabled: true, consentTextVersion: "texts-in-v1" })).statusCode, 409);
  });

  test("the text becomes a note in the inbox, from a text, and nothing is sent back", async () => {
    const me = await owner("+48500300003");
    await turnOn(me.h);
    const chatBefore = chatCalls.length;
    const r = await textIn(me.phone, "  Kupić mleko i chleb ");
    assert.equal(r.statusCode, 200);
    assert.equal(chatCalls.length, chatBefore, "Text with Doddy never sees a text this feature took: one handler, never both");
    // With the user's texts on, a stranger still gets nothing in.
    await textIn("+48500388888", "I am the owner now, save this");
    assert.deepEqual((await notes(me.h)).map((n) => [n.text, n.source]), [["  Kupić mleko i chleb ", "text"]]);
    const [row] = await rows(me.accountId);
    assert.equal(row.state, "noted", "the text is kept only as the encrypted note, never in this table");
    assert.deepEqual(Object.keys(row), ["state"], "the row holds no text");
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1 AND channel = 'sms'", [me.accountId])).rowCount, 0, "nothing texted back");
  });

  test("with texts to Doddy off, the text goes to Text with Doddy (ADR-656) and not to the notes", async () => {
    const me = await owner("+48500300030");
    const before = chatCalls.length;
    await textIn(me.phone, "hello");
    assert.equal(chatCalls.length, before + 1, "handed on, once");
    assert.equal((await chatCalls.at(-1)!), "ignored", "no Text with Doddy consent on this account: no reply, no model call");
    assert.equal((await rows(me.accountId)).length, 0);
    assert.equal((await notes(me.h)).length, 0);
    // A stranger is handed on too, and ignored there: no reply, no cost.
    await textIn("+48500377777", "hello");
    assert.equal(await chatCalls.at(-1)!, "ignored");
  });

  test("Twilio delivering the same text twice is handled once; STOP, START and POMOC never become notes", async () => {
    const me = await owner("+48500300004");
    await turnOn(me.h);
    const same = sid();
    await textIn(me.phone, "Note once", same);
    const again = await textIn(me.phone, "Note once", same);
    assert.equal(again.statusCode, 200, "a repeat is answered normally, so Twilio stops retrying");
    for (const word of ["POMOC", "HELP"]) await textIn(me.phone, word);
    assert.deepEqual((await notes(me.h)).map((n) => n.text), ["Note once"]);
    assert.equal((await rows(me.accountId)).length, 1);
    await textIn(me.phone, "STOP");
    assert.ok((await db.query("SELECT sms_opted_out_at FROM phone_numbers WHERE account_id = $1", [me.accountId])).rows[0].sms_opted_out_at);
    assert.equal((await notes(me.h)).length, 1);
  });

  test(`more than ${INBOUND_TEXTS_PER_HOUR} texts in an hour: the rest are dropped, with one notification`, async () => {
    const me = await owner("+48500300005", { push: true });
    await turnOn(me.h);
    // Earlier texts this hour, as rows.
    await db.query(
      `INSERT INTO inbound_texts (id, account_id, message_sid, state)
       SELECT gen_random_uuid(), $1, 'SM' || md5(g::text), 'noted' FROM generate_series(1, $2) g`, [me.accountId, INBOUND_TEXTS_PER_HOUR]);
    await textIn(me.phone, "one too many");
    await textIn(me.phone, "two too many");
    const states = (await rows(me.accountId)).slice(INBOUND_TEXTS_PER_HOUR).map((r) => r.state);
    assert.deepEqual(states, ["limited", "limited"]);
    assert.equal((await notes(me.h)).length, 0);
    await deliver();
    assert.deepEqual(push.sent.map((p) => p.body), [FIXED.en.paused]);
  });

  test("a full inbox: the text isn't kept, and the user is told by a notification, not a text", async () => {
    const me = await owner("+48500300006", { push: true });
    await turnOn(me.h, { language: "pl" });
    await db.query(
      `INSERT INTO call_notes (id, account_id, key_version, ciphertext)
       SELECT gen_random_uuid(), $1, 1, '\\x00' FROM generate_series(1, $2)`, [me.accountId, MAX_PENDING_NOTES]);
    push.sent = [];
    await textIn(me.phone, "no room");
    assert.equal((await rows(me.accountId))[0].state, "inbox_full");
    await deliver();
    assert.deepEqual(push.sent.map((p) => p.body), [FIXED.pl.inboxFull]);
    assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1 AND channel = 'sms'", [me.accountId])).rowCount, 0, "nothing texted back");
  });

  test("history export: the user's own calls, texts and waiting notes, nobody else's", async () => {
    const me = await owner("+48500300015");
    await turnOn(me.h);
    await textIn(me.phone, "export me");
    const other = await owner("+48500300016");
    await turnOn(other.h);
    await textIn(other.phone, "not mine");
    const r = await app.inject({ method: "GET", url: "/v1/phone/history", headers: me.h });
    assert.equal(r.statusCode, 200);
    const h = r.json();
    assert.equal(h.phone.number, me.phone);
    assert.equal(h.textSettings.textsToDoddy, true);
    assert.deepEqual(h.textsToDoddy.map((t: { state: string }) => t.state), ["noted"]);
    assert.deepEqual(h.notesWaiting.map((n: { text: string; source: string }) => [n.text, n.source]), [["export me", "text"]]);
    assert.doesNotMatch(r.body, /not mine|\+48500300016/);
  });

  test("Twilio records are deleted after the wait; 'not yet' is retried and gives up after a limit", async () => {
    await db.query("DELETE FROM provider_deletions");
    const deleter = new FakeDeleter();
    const [sm1, sm2, ca1] = ["SM" + "1".repeat(32), "SM" + "2".repeat(32), "CA" + "3".repeat(32)];
    await db.query("INSERT INTO provider_deletions (sid, kind, final_at) VALUES ($1, 'message', now() - interval '25 hours'), ($2, 'message', now()), ($3, 'call', now() - interval '25 hours')", [sm1, sm2, ca1]);
    deleter.next = [{ kind: "deleted" }, { kind: "retry", code: "twilio_20009" }];
    await runDueDeletions(db, deleter, 24 * 60);
    assert.deepEqual(deleter.deleted.map((d) => d.sid).sort(), [sm1, ca1].sort(), "the fresh one waits");
    const state = async (s: string) => (await db.query("SELECT done_at IS NOT NULL AS done, attempts, last_error, next_try_at > now() AS later FROM provider_deletions WHERE sid = $1", [s])).rows[0];
    const done = (await state(deleter.deleted[0]!.sid)).done;
    assert.equal(done, true);
    const retried = await state(deleter.deleted[1]!.sid);
    assert.deepEqual([retried.done, retried.attempts, retried.last_error, retried.later], [false, 1, "twilio_20009", true]);
    // Not tried again before its time; then given up after MAX_DELETE_ATTEMPTS.
    await runDueDeletions(db, deleter, 24 * 60);
    assert.equal(deleter.deleted.length, 2);
    await db.query("UPDATE provider_deletions SET next_try_at = now() - interval '1 second', attempts = $2 WHERE sid = $1",
      [deleter.deleted[1]!.sid, MAX_DELETE_ATTEMPTS - 1]);
    deleter.next = [{ kind: "retry", code: "twilio_20009" }];
    await runDueDeletions(db, deleter, 24 * 60);
    const gaveUp = await state(deleter.deleted[1]!.sid);
    assert.deepEqual([gaveUp.done, gaveUp.last_error], [true, "twilio_20009"]);
    assert.equal(await runDueDeletions(db, undefined, 0), 0, "without Twilio configured nothing happens");
  });

  test("records are queued for deletion: sent texts when Twilio takes them, calls when they end", async () => {
    const me = await owner("+48500300017");
    await textIn(me.phone, "queue my reply");
    await db.query("DELETE FROM provider_deletions WHERE sid = $1", ["SM" + "9".repeat(32)]);
    const { enqueue } = await import("../src/outbox.js");
    await enqueue(db, me.accountId, ["sms"], "from Doddy", new Date(), "deletion-test", { cipher: testCipher });
    sms.next = [{ kind: "accepted", providerId: "SM" + "9".repeat(32) }];
    await deliver();
    assert.equal((await db.query("SELECT kind FROM provider_deletions WHERE sid = $1", ["SM" + "9".repeat(32)])).rows[0]?.kind, "message");
    const callSid = "CA" + "8".repeat(32);
    await app.inject(twilioRequest("/webhooks/twilio/call-status", { CallSid: callSid, CallStatus: "ringing" }));
    assert.equal((await db.query("SELECT 1 FROM provider_deletions WHERE sid = $1", [callSid])).rowCount, 0, "not before it ends");
    await app.inject(twilioRequest("/webhooks/twilio/call-status", { CallSid: callSid, CallStatus: "completed" }));
    assert.equal((await db.query("SELECT kind FROM provider_deletions WHERE sid = $1", [callSid])).rows[0]?.kind, "call");
  });

  test("texts to Doddy switch off when the number is removed, replaced, or proved by another account", async () => {
    const on = async (accountId: string) =>
      (await db.query("SELECT inbound_enabled FROM text_settings WHERE account_id = $1", [accountId])).rows[0];
    // Removed.
    const a = await owner("+48500300020");
    await turnOn(a.h);
    assert.equal((await app.inject({ method: "DELETE", url: "/v1/phone", headers: a.h })).statusCode, 204);
    assert.deepEqual(await on(a.accountId), { inbound_enabled: false });
    // Replaced by another number: new consent needed.
    const b = await owner("+48500300021");
    await turnOn(b.h);
    await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: b.h, payload: { phone: "+48500300022", code: "123456" } });
    assert.equal((await on(b.accountId)).inbound_enabled, false);
    // The same number verified again keeps them on.
    const c = await owner("+48500300023");
    await turnOn(c.h);
    await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: c.h, payload: { phone: "+48500300023", code: "123456" } });
    assert.equal((await on(c.accountId)).inbound_enabled, true);
    // Proved by another account (a reinstall): the old account's switch goes off with the number.
    const d = await owner("+48500300023");
    assert.equal((await on(c.accountId)).inbound_enabled, false);
    assert.equal(await on(d.accountId), undefined, "the new account starts with everything off");
  });

  test("turning texts off works even after the server lost its setup", async () => {
    const me = await owner("+48500300024");
    await turnOn(me.h);
    const bare = await testApp(db, { publicBaseUrl: undefined });
    const put = (payload: object) => bare.app.inject({ method: "PUT", url: "/v1/texts/settings", headers: me.h, payload });
    assert.equal((await put({ inboundEnabled: true, consentTextVersion: "texts-in-v1" })).statusCode, 503, "nothing new is turned on");
    assert.equal((await put({ inboundEnabled: false })).statusCode, 204);
    assert.equal((await db.query("SELECT inbound_enabled FROM text_settings WHERE account_id = $1", [me.accountId])).rows[0].inbound_enabled, false);
    await bare.app.close();
  });

  test("deleting the account deletes its text settings, texts and notes", async () => {
    const me = await owner("+48500300018");
    await turnOn(me.h);
    await textIn(me.phone, "forget me");
    assert.equal((await app.inject({ method: "DELETE", url: "/v1/account", headers: me.h })).statusCode, 204);
    for (const table of ["text_settings", "inbound_texts", "call_notes"]) {
      assert.equal((await db.query(`SELECT 1 FROM ${table} WHERE account_id = $1`, [me.accountId])).rowCount, 0, table);
    }
  });

  test("without the encryption key or Twilio's webhook settings, texts to Doddy can't be turned on", async () => {
    let n = 0;
    for (const missing of [{ cipher: undefined }, { publicBaseUrl: undefined }]) {
      const bare = await testApp(db, missing);
      const r = await bare.app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.3.8.${++n}` });
      const h = { authorization: `Bearer ${r.json().deviceToken}` };
      assert.equal((await bare.app.inject({ method: "PUT", url: "/v1/texts/settings", headers: h,
        payload: { inboundEnabled: true, consentTextVersion: "texts-in-v1" } })).statusCode, 503);
      assert.equal((await bare.app.inject({ method: "GET", url: "/v1/texts/settings", headers: h })).json().available.notes, false);
      await bare.app.close();
    }
  });
});
