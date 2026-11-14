// What Doddy leaves at its providers, and when it goes: phone-agent conversations at ElevenLabs, task-call records at
// Twilio (on the task account), and the content-free dial log. Real Postgres; stand-ins for Twilio and ElevenLabs.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { after, before, describe, test } from "node:test";
import { queuePhoneAgentDeletions, sweepPhoneAgentOrphans } from "../src/calls.js";
import { DEFAULT_ASSISTANT_SETTINGS, loadConfig } from "../src/config.js";
import type { Db } from "../src/db.js";
import { runDueDeletions } from "../src/providerRecords.js";
import { TwilioRecordDeleter, twilioSignature } from "../src/providers/twilio.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { DIAL_LOG_KEEP_DAYS, pruneDialLog } from "../src/taskCalls/service.js";
import { runDeletions } from "../src/taskCalls/worker.js";
import {
  BASE_URL, dbSkip, DODDY_FROM, FakeDeleter, FakeVoice, freshDb, sampleBrief, sidFor, TASK_ACCOUNT_SID, TASK_AUTH_TOKEN, taskTestApp,
  testApp, twilioRequest,
} from "./helpers.js";

const PHONE_AGENT = "agent_phone_deletions";
const SECRET = "phone-deletions-webhook-secret-01";

test("Twilio records on the task account are deleted with that account's own credentials", async () => {
  const seen: { url: string; auth: string; method: string }[] = [];
  const real = globalThis.fetch;
  globalThis.fetch = (async (url: string | URL, init?: RequestInit) => {
    seen.push({ url: String(url), auth: String((init?.headers as Record<string, string>).authorization), method: init?.method ?? "GET" });
    return new Response(null, { status: 204 });
  }) as typeof fetch;
  const basic = (sid: string, token: string) => "Basic " + Buffer.from(`${sid}:${token}`).toString("base64");
  const ca = "CA" + "c".repeat(32);
  try {
    const { providersFrom } = await import("../src/providers/index.js");
    const main = {
      DATABASE_URL: "postgres://x/y", TWILIO_ACCOUNT_SID: "AC" + "1".repeat(32), TWILIO_AUTH_TOKEN: "main-token",
      TWILIO_MESSAGING_SERVICE_SID: "MG1", TWILIO_VERIFY_SERVICE_SID: "VA1",
    };
    // A subaccount for task calls: its records are deleted there, with its token.
    const sub = providersFrom(loadConfig({ ...main, TWILIO_TASK_ACCOUNT_SID: "AC" + "2".repeat(32), TWILIO_TASK_AUTH_TOKEN: "sub-token" }));
    assert.deepEqual(await sub.taskDeleter!.deleteRecord("call", ca), { kind: "deleted" });
    assert.deepEqual(seen.at(-1), {
      url: `https://api.twilio.com/2010-04-01/Accounts/${"AC" + "2".repeat(32)}/Calls/${ca}.json`,
      auth: basic("AC" + "2".repeat(32), "sub-token"), method: "DELETE",
    });
    // No subaccount: the task pair falls back to the main pair, as the task-call client does.
    const same = providersFrom(loadConfig(main));
    await same.taskDeleter!.deleteRecord("call", ca);
    assert.deepEqual(seen.at(-1), {
      url: `https://api.twilio.com/2010-04-01/Accounts/${"AC" + "1".repeat(32)}/Calls/${ca}.json`,
      auth: basic("AC" + "1".repeat(32), "main-token"), method: "DELETE",
    });
    // No Twilio at all: nothing to delete with.
    assert.equal(providersFrom(loadConfig({ DATABASE_URL: "postgres://x/y" })).taskDeleter, undefined);
    // Anything that isn't a call or message id never reaches Twilio.
    const before = seen.length;
    assert.deepEqual(await new TwilioRecordDeleter("AC" + "2".repeat(32), "t").deleteRecord("call", "../Messages/x"), { kind: "failed", code: "bad_sid" });
    assert.equal(seen.length, before);
  } finally {
    globalThis.fetch = real;
  }
});

describe("provider records against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  let n = 0;
  const phone = () => `+48510${String(200000 + ++n).slice(-6)}`;
  const dest = () => `+4832${String(2000000 + ++n).slice(-7)}`;

  async function account(app: Awaited<ReturnType<typeof testApp>>["app"], opts: { inbound?: boolean } = {}) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.9.0.${++n}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const number = phone();
    assert.equal((await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone: number, code: "123456" } })).statusCode, 200);
    if (opts.inbound) assert.equal((await app.inject({ method: "PUT", url: "/v1/calls/settings", headers: h, payload: { inboundEnabled: true } })).statusCode, 204);
    return { accountId, h, phone: number };
  }

  const postCall = (conversationId: string, callSid: string | null) => JSON.stringify({
    type: "post_call_transcription",
    data: {
      agent_id: PHONE_AGENT, conversation_id: conversationId,
      transcript: [{ role: "agent", message: "Cześć, tu Doddy." }, { role: "user", message: "Dzień dobry." }],
      metadata: { call_duration_secs: 12, phone_call: callSid ? { call_sid: callSid } : null },
    },
  });

  async function conversationOf(callSid: string): Promise<string | null> {
    for (let i = 0; i < 50; i++) {
      const v = (await db.query<{ conversation_id: string | null }>("SELECT conversation_id FROM calls WHERE call_sid = $1", [callSid])).rows[0]?.conversation_id;
      if (v) return v;
      await new Promise((r) => setTimeout(r, 20));
    }
    return null;
  }

  test("a phone-agent call without recaps keeps its conversation id, so deleting the account deletes the conversation", async () => {
    // Recaps can't be made here (no writer): the conversation id is stored all the same.
    const w = await testApp(db, { phoneRecaps: { phoneAgentId: PHONE_AGENT, webhookSecret: SECRET, settings: DEFAULT_ASSISTANT_SETTINGS } });
    const me = await account(w.app, { inbound: true });
    const callSid = "CA" + "d1".repeat(16);
    // An incoming call, recorded by the voice webhook without a conversation id.
    const voice = await w.app.inject(twilioRequest("/webhooks/twilio/voice", { CallSid: callSid, From: me.phone, To: "+48221234567" }));
    assert.equal(voice.statusCode, 200);
    assert.equal((await db.query("SELECT conversation_id FROM calls WHERE call_sid = $1", [callSid])).rows[0]?.conversation_id, null);

    const body = postCall("conv_phone_no_recap", callSid);
    const r = await w.app.inject({ method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body,
      headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(SECRET, body) } });
    assert.equal(r.statusCode, 200);
    assert.equal(await conversationOf(callSid), "conv_phone_no_recap");
    // A second delivery changes nothing; another call's payload never takes this row.
    const again = postCall("conv_other", callSid);
    await w.app.inject({ method: "POST", url: "/webhooks/elevenlabs/post-call", payload: again,
      headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(SECRET, again) } });
    await new Promise((r2) => setTimeout(r2, 100));
    assert.equal(await conversationOf(callSid), "conv_phone_no_recap");

    assert.equal((await w.app.inject({ method: "DELETE", url: "/v1/account", headers: me.h })).statusCode, 204);
    const { rows } = await db.query("SELECT reason, result FROM server_data_deletions WHERE provider_ref = 'conv_phone_no_recap'");
    assert.deepEqual(rows, [{ reason: "account_deleted", result: "pending" }]);
    await w.app.close();
  });

  test("without the encryption key the conversation id is still stored (no recap is ever made)", async () => {
    const w = await testApp(db, { cipher: undefined, phoneRecaps: { phoneAgentId: PHONE_AGENT, webhookSecret: SECRET, settings: DEFAULT_ASSISTANT_SETTINGS } });
    const me = await account(w.app);
    const callSid = "CA" + "d2".repeat(16);
    await db.query("INSERT INTO calls (id, account_id, direction, status, call_sid) VALUES ($1, $2, 'outbound', 'answered', $3)", [randomUUID(), me.accountId, callSid]);
    const body = postCall("conv_phone_no_key", callSid);
    const r = await w.app.inject({ method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body,
      headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(SECRET, body) } });
    assert.equal(r.statusCode, 200);
    assert.equal(await conversationOf(callSid), "conv_phone_no_key");
    assert.equal((await db.query("SELECT 1 FROM phone_recaps")).rowCount, 0);
    await w.app.close();
  });

  test("the orphan sweep covers the phone agent: conversations no call owns are deleted and read back gone", async () => {
    await db.query("DELETE FROM server_data_deletions");
    const w = await testApp(db);
    const me = await account(w.app);
    const now = new Date("2026-11-12T12:00:00Z");
    const ago = (hours: number) => Math.floor(now.getTime() / 1000) - hours * 3600;
    const voice = new FakeVoice();
    const conv = (id: string, startedHoursAgo: number, callSid?: string) => voice.conversations.set(id, {
      agent_id: PHONE_AGENT, conversation_id: id, transcript: [],
      metadata: { start_time_unix_secs: ago(startedHoursAgo), ...(callSid ? { phone_call: { call_sid: callSid } } : {}) },
    } as never);
    const sidOwned = "CA" + "e1".repeat(16);
    const sidByCall = "CA" + "e2".repeat(16);
    await db.query("INSERT INTO calls (id, account_id, direction, status, call_sid, conversation_id) VALUES ($1, $2, 'inbound', 'completed', $3, 'conv_owned')",
      [randomUUID(), me.accountId, sidOwned]);
    // The post-call webhook never came for this one: the sweep finds its call by the Twilio id and keeps it.
    await db.query("INSERT INTO calls (id, account_id, direction, status, call_sid) VALUES ($1, $2, 'inbound', 'completed', $3)",
      [randomUUID(), me.accountId, sidByCall]);
    conv("conv_owned", 72, sidOwned);
    conv("conv_by_call", 48, sidByCall);
    conv("conv_orphan", 48, "CA" + "e3".repeat(16)); // its account was deleted before the webhook came
    conv("conv_no_call", 30); // never a call through this server (a test from the dashboard)
    conv("conv_fresh", 1); // its webhook may still be on the way

    const ctx = { db, voice, now: () => now, log: () => {} };
    assert.equal(await sweepPhoneAgentOrphans(ctx, PHONE_AGENT), 2);
    assert.equal(await sweepPhoneAgentOrphans(ctx, PHONE_AGENT), 0, "queued once");
    assert.equal((await db.query("SELECT conversation_id FROM calls WHERE call_sid = $1", [sidByCall])).rows[0]?.conversation_id, "conv_by_call");

    assert.equal(await runDeletions(ctx), 2);
    assert.deepEqual(voice.deleted.sort(), ["conv_no_call", "conv_orphan"]);
    const { rows } = await db.query("SELECT provider_ref, reason, result FROM server_data_deletions WHERE reason = 'orphan' ORDER BY provider_ref");
    assert.deepEqual(rows, [
      { provider_ref: "conv_no_call", reason: "orphan", result: "deleted" },
      { provider_ref: "conv_orphan", reason: "orphan", result: "deleted" },
    ]);
    // The one found by its call is deleted with the account, like any other.
    assert.equal(await queuePhoneAgentDeletions(db, me.accountId, now), 2);
    await w.app.close();
  });

  test("task-call records at Twilio are queued once final, and deleted on the task account after their costs are read", async () => {
    await db.query("DELETE FROM call_dial_log; DELETE FROM provider_deletions");
    const w = await taskTestApp(db);
    const me = await account(w.app);
    const tw = (url: string, form: Record<string, string>) => w.app.inject({
      method: "POST", url, payload: new URLSearchParams(form).toString(),
      headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": twilioSignature(TASK_AUTH_TOKEN, BASE_URL + url, form) },
    });
    const base = (sid: string) => ({ AccountSid: TASK_ACCOUNT_SID, CallSid: sid });
    const p = (await w.app.inject({ method: "POST", url: "/v1/call-cases", headers: me.h, payload: sampleBrief({ callee: { name: "Serwis", phone: dest(), source: "typed" } }) })).json();
    const a = (await w.app.inject({ method: "POST", url: `/v1/call-cases/${p.caseId}/approve`, headers: me.h, payload: { digest: p.digest } })).json();
    const sid = (await db.query<{ twilio_call_sid: string }>("SELECT twilio_call_sid FROM call_attempts WHERE id = $1", [a.attemptId])).rows[0]!.twilio_call_sid;
    const to = w.telephony.created.at(-1)!.to;
    await tw(`/webhooks/twilio/task-call/answer?a=${a.attemptId}`, { ...base(sid), To: to, From: DODDY_FROM });
    const queued = async () => (await db.query<{ sid: string; account: string }>("SELECT sid, account FROM provider_deletions ORDER BY sid")).rows;
    assert.deepEqual(await queued(), [], "nothing while the call is live");

    // The takeover leg rings the user and isn't answered; the callee's call then ends.
    const start = await w.app.inject({ method: "POST", url: `/v1/call-cases/${p.caseId}/takeover`, headers: me.h });
    assert.equal(start.statusCode, 202, start.body);
    const { takeoverId } = start.json() as { takeoverId: string };
    const leg = (await db.query<{ twilio_call_sid: string }>("SELECT twilio_call_sid FROM call_takeovers WHERE id = $1", [takeoverId])).rows[0]!.twilio_call_sid;
    await tw(`/webhooks/twilio/task-call/takeover-status?t=${takeoverId}`, { ...base(leg), CallStatus: "ringing" });
    assert.deepEqual(await queued(), []);
    await tw(`/webhooks/twilio/task-call/takeover-status?t=${takeoverId}`, { ...base(leg), CallStatus: "no-answer" });
    await tw(`/webhooks/twilio/task-call/status?a=${a.attemptId}`, { ...base(sid), CallStatus: "completed", SequenceNumber: "9", CallDuration: "40" });
    // A final call on the task account that no attempt owns any more (its account was deleted mid-call) goes too.
    const stray = sidFor(0xfeed01);
    await tw(`/webhooks/twilio/task-call/status?a=${randomUUID()}`, { ...base(stray), CallStatus: "completed" });
    // Another account's signature-checked request for a call on some other account is not ours to delete.
    await tw(`/webhooks/twilio/task-call/status?a=${randomUUID()}`, { AccountSid: "AC" + "9".repeat(32), CallSid: sidFor(0xfeed02), CallStatus: "completed" });
    assert.deepEqual(await queued(), [leg, sid, stray].sort().map((s) => ({ sid: s, account: "task" })));

    // A forwarded call-back's child leg (on the main account, whose signature the voice webhooks check).
    const child = "CA" + "f1".repeat(16);
    const done = await w.app.inject(twilioRequest("/webhooks/twilio/callback-done", { CallSid: "CA" + "f2".repeat(16), DialCallSid: child, DialCallStatus: "completed" }));
    assert.equal(done.statusCode, 200);
    assert.equal((await db.query("SELECT account FROM provider_deletions WHERE sid = $1", [child])).rows[0]?.account, "main");

    const mainDeleter = new FakeDeleter();
    const taskDeleter = new FakeDeleter();
    // Without the task account's credentials its records wait; the main account's go.
    await runDueDeletions(db, { main: mainDeleter }, 0);
    assert.deepEqual(mainDeleter.deleted, [{ kind: "call", sid: child }]);
    // The call's and the leg's prices are still being read from Twilio: those records wait for them.
    await runDueDeletions(db, { main: mainDeleter, task: taskDeleter }, 0);
    assert.deepEqual(taskDeleter.deleted, [{ kind: "call", sid: stray }]);
    await db.query("UPDATE call_cost_items SET status = 'unknown', settled_at = now(), next_try_at = NULL WHERE status = 'pending'");
    await runDueDeletions(db, { main: mainDeleter, task: taskDeleter }, 0);
    assert.deepEqual(taskDeleter.deleted.map((d) => d.sid).sort(), [leg, sid, stray].sort());
    assert.equal(mainDeleter.deleted.length, 1, "the main account's credentials never touch a task record");
    assert.equal((await db.query("SELECT 1 FROM provider_deletions WHERE done_at IS NULL")).rowCount, 0);

    // Calls that ended before migration 032 are queued by it: its backfill, run on these finished ones.
    await db.query("DELETE FROM provider_deletions");
    const sql = readFileSync(new URL("../../migrations/032_task_call_records.sql", import.meta.url), "utf8");
    await db.query(sql.slice(sql.indexOf("INSERT INTO provider_deletions")));
    assert.deepEqual(await queued(), [leg, sid].sort().map((s) => ({ sid: s, account: "task" })));
    await w.app.close();
  });

  test("the dial log keeps only what the limits read", async () => {
    await db.query("DELETE FROM call_dial_log");
    const h = Buffer.alloc(32, 1);
    const now = new Date("2026-11-12T12:00:00Z");
    for (const hoursAgo of [1, 23, 47, 49, 24 * 10]) {
      await db.query("INSERT INTO call_dial_log (destination_hash, caller_phone_hash, dialed_at) VALUES ($1, $1, $2)", [h, new Date(now.getTime() - hoursAgo * 3600_000)]);
    }
    assert.equal(DIAL_LOG_KEEP_DAYS, 2);
    assert.equal(await pruneDialLog(db, now), 2);
    const left = (await db.query<{ dialed_at: Date }>("SELECT dialed_at FROM call_dial_log ORDER BY dialed_at DESC")).rows;
    assert.deepEqual(left.map((r) => (now.getTime() - r.dialed_at.getTime()) / 3600_000), [1, 23, 47]);
  });
});
