// Call cases end to end against real Postgres, with fake Twilio and ElevenLabs (ADR-500..507).
// The "impossible by construction" list in docs/decisions/calls.md maps to these tests.
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { twilioSignature } from "../src/providers/twilio.js";
import type { TaskCallContext } from "../src/taskCalls/context.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { AGENT_VARIABLE_NAMES } from "../src/taskCalls/payload.js";
import { dialAttempt } from "../src/taskCalls/service.js";
import { processResults, runDeletions, runTaskCallPasses, settleCosts } from "../src/taskCalls/worker.js";
import {
  BASE_URL, dbSkip, DODDY_FROM, EL_WEBHOOK_SECRET, freshDb, sampleBrief, TASK_ACCOUNT_SID, TASK_AGENT_ID, TASK_AUTH_TOKEN, taskTestApp,
  testApp, VALID_PESEL, type FakeTelephony, type FakeVoice, type TaskTestOptions,
} from "./helpers.js";

type Form = Record<string, string>;

describe("call cases against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM call_dial_log"); });

  let phoneSeq = 0;
  const nextPhone = () => `+48500${String(100000 + ++phoneSeq).slice(-6)}`;
  let destSeq = 0;
  const nextDestination = () => `+4822${String(1000000 + ++destSeq).slice(-7)}`;

  interface World {
    app: FastifyInstance; telephony: FakeTelephony; voice: FakeVoice; clock: { now: Date }; ctx: TaskCallContext;
    settings: TaskTestOptions["settings"] & object; logs: { msg: string; extra?: object }[];
  }

  async function world(opts: TaskTestOptions = {}): Promise<World> {
    const w = await taskTestApp(db, opts);
    return { ...w, ctx: w.app.taskCallContext!, settings: w.settings };
  }

  async function user(w: World, phone = nextPhone()) {
    const r = await w.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const v = await w.app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } });
    assert.equal(v.statusCode, 200);
    return { accountId, h, phone };
  }

  const api = (w: World, method: "GET" | "POST" | "PUT" | "DELETE", url: string, h: object, payload?: unknown) =>
    w.app.inject({ method, url, headers: h as Record<string, string>, payload: payload as never });

  function twilio(w: World, url: string, form: Form, token = TASK_AUTH_TOKEN) {
    return w.app.inject({
      method: "POST", url, payload: new URLSearchParams(form).toString(),
      headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": twilioSignature(token, BASE_URL + url, form) },
    });
  }

  async function createCase(w: World, h: object, over: Parameters<typeof sampleBrief>[0] = {}) {
    const r = await api(w, "POST", "/v1/call-cases", h, sampleBrief({ callee: { name: "Serwis Laptop", phone: nextDestination(), source: "contacts" }, ...over }));
    return r;
  }

  /** Brief → approval → dial. */
  async function dialled(w: World, h: object, over: Parameters<typeof sampleBrief>[0] = {}) {
    const created = await createCase(w, h, over);
    assert.equal(created.statusCode, 201, created.body);
    const preview = created.json();
    const approved = await api(w, "POST", `/v1/call-cases/${preview.caseId}/approve`, h, { digest: preview.digest });
    assert.equal(approved.statusCode, 202, approved.body);
    const { attemptId } = approved.json() as { attemptId: string };
    const params = w.telephony.created.at(-1)!;
    const { rows } = await db.query<{ twilio_call_sid: string }>("SELECT twilio_call_sid FROM call_attempts WHERE id = $1", [attemptId]);
    return { caseId: preview.caseId as string, attemptId, sid: rows[0]!.twilio_call_sid, preview, to: params.to };
  }

  const callForm = (sid: string, extra: Form = {}): Form => ({ AccountSid: TASK_ACCOUNT_SID, CallSid: sid, ...extra });

  async function answer(w: World, d: { attemptId: string; sid: string; to: string }, extra: Form = {}) {
    return twilio(w, `/webhooks/twilio/task-call/answer?a=${d.attemptId}`, callForm(d.sid, { To: d.to, From: DODDY_FROM, CallStatus: "in-progress", ...extra }));
  }

  let lineSeq = 0;
  async function say(w: World, d: { attemptId: string; sid: string }, track: "inbound_track" | "outbound_track", text: string) {
    return twilio(w, `/webhooks/twilio/task-call/transcription?a=${d.attemptId}`, callForm(d.sid, {
      TranscriptionEvent: "transcription-content", TranscriptionSid: "GT1", SequenceId: String(++lineSeq), Track: track,
      TranscriptionData: JSON.stringify({ transcript: text, confidence: 0.9 }), Final: "true",
    }));
  }

  const status = (w: World, d: { attemptId: string; sid: string }, callStatus: string, seq: number, duration = "42") =>
    twilio(w, `/webhooks/twilio/task-call/status?a=${d.attemptId}`, callForm(d.sid, { CallStatus: callStatus, SequenceNumber: String(seq), CallDuration: duration }));

  function postCall(w: World, data: object, secret = EL_WEBHOOK_SECRET) {
    const body = JSON.stringify({ type: "post_call_transcription", event_timestamp: 1, data });
    return w.app.inject({
      method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body,
      headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(secret, body) },
    });
  }

  const conversation = (attemptId: string, id: string, turns: [string, string][], cost = 1200) => ({
    agent_id: TASK_AGENT_ID, conversation_id: id, status: "done",
    transcript: turns.map(([role, message], i) => ({ role, message, time_in_call_secs: i * 5 })),
    metadata: { call_duration_secs: 40, cost, termination_reason: "end_call tool was called", start_time_unix_secs: 1_700_000_000 },
    conversation_initiation_client_data: { dynamic_variables: { doddy_attempt: attemptId } },
  });

  // ---------------------------------------------------------------------------------------------

  test("without configuration the API says so and fakes nothing", async () => {
    const { app } = await testApp(db);
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const h = { authorization: `Bearer ${(r.json() as { deviceToken: string }).deviceToken}` };
    assert.equal((await app.inject({ method: "POST", url: "/v1/call-cases", headers: h, payload: sampleBrief() })).statusCode, 503);
    assert.equal((await app.inject({ method: "GET", url: "/v1/call-cases/availability", headers: h })).json().configured, false);
    await app.close();
  });

  test("a brief becomes a preview built from the payload; refused briefs never get one", async () => {
    const w = await world();
    const u = await user(w);
    const ok = await createCase(w, u.h);
    assert.equal(ok.statusCode, 201);
    const p = ok.json();
    assert.match(p.openingLine, /^Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny\. Chciałbym zapytać: Czy laptop z serwisu jest gotowy\?$/);
    assert.equal(p.recordsAudio, false);
    assert.equal(p.notice, "off");
    assert.equal(p.maxDurationSecs, 240);
    assert.match(p.digest, /^[0-9a-f]{64}$/);
    assert.equal(p.callee.source, "contacts");

    const refused = async (over: Parameters<typeof sampleBrief>[0]) => (await api(w, "POST", "/v1/call-cases", u.h, sampleBrief(over))).json();
    for (const phone of ["112", "+48 997", "999", "700 123 456", "801 123 456", "+44 20 7946 0000", "118 913"]) {
      assert.equal((await refused({ callee: { name: "X", phone, source: "typed" } })).error, "destination_refused", phone);
    }
    assert.equal((await refused({ callee: { name: "X", phone: u.phone, source: "typed" } })).reason, "own_number");
    assert.equal((await refused({ callee: { name: "X", phone: DODDY_FROM, source: "typed" } })).reason, "doddy_number");
    assert.equal((await refused({ goal: `PESEL ${VALID_PESEL}` })).reason, "pesel_not_ticked");
    assert.equal((await refused({ question: "Proszę zarezerwować stolik na 19" })).reason, "question_commits");
    const strict = await api(w, "POST", "/v1/call-cases", u.h, { ...sampleBrief(), dialTo: "+48600100200" });
    assert.equal(strict.statusCode, 400);

    const stranger = await w.app.inject({ method: "POST", url: "/v1/accounts" });
    const sh = { authorization: `Bearer ${(stranger.json() as { deviceToken: string }).deviceToken}` };
    assert.equal((await createCase(w, sh)).json().error, "no_verified_phone");
    assert.equal(w.telephony.created.length, 0);
    await w.app.close();
  });

  test("no call without approving the exact stored payload; bodies can't smuggle anything", async () => {
    const w = await world();
    const u = await user(w);
    const p = (await createCase(w, u.h)).json();
    const wrong = "0".repeat(64);
    assert.equal((await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: wrong })).json().error, "digest_mismatch");
    assert.equal((await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest, to: "+48600100200" })).statusCode, 400);
    assert.equal((await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest, maxDurationSecs: 300 })).statusCode, 400);
    assert.equal(w.telephony.created.length, 0);

    // Another account can't approve it, even with the right digest.
    const other = await user(w);
    assert.equal((await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, other.h, { digest: p.digest })).statusCode, 404);

    const ok = await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest });
    assert.equal(ok.statusCode, 202);
    const attemptId = ok.json().attemptId as string;
    assert.equal(w.telephony.created.length, 1);
    const c = w.telephony.created[0]!;
    assert.deepEqual({ to: c.to, from: c.from, timeLimitSecs: c.timeLimitSecs, timeoutSecs: c.timeoutSecs },
      { to: p.callee.phone.replace(/\s/g, "").replace(/^/, "+48"), from: DODDY_FROM, timeLimitSecs: 260, timeoutSecs: 25 });
    for (const url of [c.url, c.fallbackUrl, c.statusCallback]) assert.ok(url.startsWith(BASE_URL) && url.endsWith(`?a=${attemptId}`), url);

    // The database itself refuses an attempt bound to any digest but its case's own.
    const unapproved = (await createCase(w, u.h)).json();
    await assert.rejects(db.query(
      `INSERT INTO call_attempts (id, case_id, account_id, attempt_no, approved_digest, dial_not_before, dial_deadline, state, time_limit_secs)
       VALUES (gen_random_uuid(), $1, $2, 1, $3, now(), now() + interval '5 minutes', 'scheduled', 260)`,
      [unapproved.caseId, u.accountId, Buffer.from(p.digest, "hex")]), /foreign key/);
    // ...and a dial outside its window.
    await assert.rejects(db.query("UPDATE call_attempts SET dial_started_at = dial_deadline + interval '1 second' WHERE id = $1", [attemptId]), /check constraint/);
    await w.app.close();
  });

  test("parallel approvals and parallel dials place exactly one call", async () => {
    const w = await world();
    const u = await user(w);
    const p = (await createCase(w, u.h)).json();
    const results = await Promise.all(Array.from({ length: 5 }, () => api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest })));
    assert.deepEqual(results.map((r) => r.statusCode).sort(), [202, 409, 409, 409, 409]);
    assert.equal(w.telephony.created.length, 1);

    const q = (await createCase(w, (await user(w)).h)).json();
    // Schedule without dialling, then race two dials of the same attempt.
    const attemptId = "6f9619ff-8b86-4d11-b42d-00c04fc964ff";
    await db.query(
      `INSERT INTO call_attempts (id, case_id, account_id, attempt_no, approved_digest, dial_not_before, dial_deadline, state, time_limit_secs, created_at, updated_at)
       SELECT $1, id, account_id, 1, payload_digest, $2, $3, 'scheduled', 260, $2, $2 FROM call_cases WHERE id = $4`,
      [attemptId, w.clock.now, new Date(w.clock.now.getTime() + 300_000), q.caseId]);
    await db.query("UPDATE call_cases SET state = 'active' WHERE id = $1", [q.caseId]);
    const raced = await Promise.all([dialAttempt(w.ctx, attemptId), dialAttempt(w.ctx, attemptId)]);
    assert.deepEqual(raced.map((r) => r.kind).sort(), ["dialing", "not_scheduled"]);
    assert.equal(w.telephony.created.length, 2);
    await w.app.close();
  });

  test("an unknown Twilio outcome is never redialled", async () => {
    const w = await world();
    const u = await user(w);
    w.telephony.nextCreate.push({ kind: "unknown", code: "twilio_network" });
    const p = (await createCase(w, u.h)).json();
    const r = await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest });
    assert.equal(r.json().state, "unknown");
    for (let i = 0; i < 3; i++) await runTaskCallPasses(w.ctx, { lastSweep: Date.now() });
    assert.equal(w.telephony.created.length, 1);
    // A second approval is refused while the first may still be ringing.
    assert.equal((await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest })).json().error, "attempt_open");
    await w.app.close();
  });

  test("the answer webhook registers exactly the approved variables, once", async () => {
    const w = await world();
    const u = await user(w);
    const d = await dialled(w, u.h, { facts: [{ kind: "pesel", text: VALID_PESEL }] });
    assert.equal((await twilio(w, `/webhooks/twilio/task-call/answer?a=${d.attemptId}`, callForm(d.sid, { To: d.to, From: DODDY_FROM }), "wrong-token")).statusCode, 403);
    // A forged number (signed, but not this call's) gets the apology and no voice.
    const forged = await answer(w, { ...d, to: "+48221111111" });
    assert.match(forged.body, /Przepraszamy, mamy problem techniczny/);
    assert.equal(w.voice.registered.length, 0);

    // The forged request claimed the answer; a new attempt shows the real path.
    const d2 = await dialled(w, (await user(w)).h, { facts: [{ kind: "pesel", text: VALID_PESEL }] });
    const ok = await answer(w, d2);
    assert.match(ok.body, /<Start><Transcription name="doddy-live"/);
    assert.match(ok.body, /<Stream url="wss:\/\/api.elevenlabs.io\//);
    assert.equal(w.voice.registered.length, 1);
    const reg = w.voice.registered[0]!;
    assert.deepEqual(Object.keys(reg.variables).sort(), [...AGENT_VARIABLE_NAMES, "doddy_attempt"].sort());
    assert.equal(reg.variables.doddy_attempt, d2.attemptId);
    assert.equal(reg.variables.doddy_facts, `- PESEL: ${VALID_PESEL}`);
    assert.equal(reg.to, d2.to);
    assert.equal(reg.from, DODDY_FROM);
    // Replayed: no second conversation.
    const replay = await answer(w, d2);
    assert.match(replay.body, /problem techniczny/);
    assert.equal(w.voice.registered.length, 1);
    await w.app.close();
  });

  test("full call: live lines, answer card quoting the reply, costs, ack with receipts, ElevenLabs deletion", async () => {
    const w = await world();
    const u = await user(w);
    const d = await dialled(w, u.h);
    await status(w, d, "ringing", 1);
    await answer(w, d);
    await say(w, d, "outbound_track", "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny.");
    await say(w, d, "inbound_track", "Tak, laptop jest gotowy, można odebrać jutro od dziesiątej.");
    const live = (await api(w, "GET", `/v1/call-cases/${d.caseId}/live`, u.h)).json();
    assert.equal(live.attempt.phase, "talking");
    assert.deepEqual(live.lines.map((l: { speaker: string }) => l.speaker), ["doddy", "callee"]);
    const more = (await api(w, "GET", `/v1/call-cases/${d.caseId}/live?after=${encodeURIComponent(live.cursor)}`, u.h)).json();
    assert.equal(more.lines.length, 0);

    await status(w, d, "completed", 3, "41");
    const reply = "Tak, laptop jest gotowy, można odebrać jutro od dziesiątej.";
    w.voice.conversations.set("conv_1", conversation(d.attemptId, "conv_1", [
      ["agent", "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: Czy laptop z serwisu jest gotowy?"],
      ["user", reply], ["agent", "Dziękuję bardzo, do widzenia."]]) as never);
    assert.equal((await postCall(w, w.voice.conversations.get("conv_1")!)).statusCode, 200);
    assert.equal(await processResults(w.ctx), 1);

    const kase = (await api(w, "GET", `/v1/call-cases/${d.caseId}`, u.h)).json();
    const res = kase.results[0];
    assert.equal(res.outcome, "answered");
    assert.equal(res.result.quote.text, reply);
    assert.equal(res.result.confidence, "high");
    assert.equal(res.result.source, "elevenlabs");
    // Live lines are gone once the card is built.
    assert.equal((await db.query("SELECT 1 FROM call_live_lines WHERE attempt_id = $1", [d.attemptId])).rowCount, 0);
    // Voice cost from the webhook: 1200 credits × 0.0001 USD.
    const voiceCost = kase.cost.items.find((i: { component: string }) => i.component === "elevenlabs_voice");
    assert.deepEqual([voiceCost.status, voiceCost.amountMicros, voiceCost.unit], ["estimated", 120000, "credit"]);
    w.telephony.records.set(d.sid, { status: "completed", durationSecs: 41, price: "-0.02700", priceUnit: "usd" });
    w.clock.now = new Date(w.clock.now.getTime() + 5 * 60_000);
    await settleCosts(w.ctx);
    const after = (await api(w, "GET", `/v1/call-cases/${d.caseId}`, u.h)).json();
    const call = after.cost.items.find((i: { component: string }) => i.component === "twilio_call");
    assert.deepEqual([call.status, call.amountMicros, call.currency], ["reported", 27000, "USD"]);
    assert.equal(after.cost.complete, true);
    assert.equal(after.cost.approximate, true);

    // ElevenLabs copy deleted after processing, confirmed by a read.
    await runDeletions(w.ctx);
    assert.deepEqual(w.voice.deleted, ["conv_1"]);
    // The app saves the result, then acknowledges it: the server deletes its copies.
    assert.equal((await api(w, "POST", `/v1/call-cases/${d.caseId}/ack`, u.h, { attemptId: d.attemptId, resultDigest: "f".repeat(64) })).statusCode, 409);
    const ack = await api(w, "POST", `/v1/call-cases/${d.caseId}/ack`, u.h, { attemptId: d.attemptId, resultDigest: res.resultDigest });
    assert.equal(ack.statusCode, 200);
    const receipts = ack.json().deletions as { item: string; location: string; result: string; reason: string }[];
    const has = (item: string, location: string, result: string) => receipts.some((r) => r.item === item && r.location === location && r.result === result);
    assert.ok(has("call_input", "doddy_server", "deleted"));
    assert.ok(has("live_lines", "doddy_server", "deleted"));
    assert.ok(has("call_result", "doddy_server", "deleted"));
    assert.ok(has("call_payload", "doddy_server", "deleted"));
    assert.ok(has("elevenlabs_conversation", "elevenlabs", "deleted"));
    const { rows } = await db.query("SELECT payload_ciphertext, state FROM call_cases WHERE id = $1", [d.caseId]);
    assert.equal(rows[0].payload_ciphertext, null);
    assert.equal(rows[0].state, "finished");
    assert.equal((await db.query("SELECT ciphertext FROM call_results WHERE attempt_id = $1", [d.attemptId])).rows[0].ciphertext, null);
    // Idempotent.
    assert.equal((await api(w, "POST", `/v1/call-cases/${d.caseId}/ack`, u.h, { attemptId: d.attemptId, resultDigest: res.resultDigest })).statusCode, 200);

    // Nothing in the logs is content: no number, name, question or answer.
    const text = JSON.stringify(w.logs);
    for (const secret of [d.to, u.phone, "Anny", "Serwis", "laptop", reply, "12345"]) assert.equal(text.includes(secret), false, secret);
    await w.app.close();
  });

  test("calling hours and limits are checked at dial time", async () => {
    const late = await world({ start: "2026-10-19T17:56:00Z" }); // 19:56 Warsaw: a 4-minute call wouldn't fit
    const u = await user(late);
    const p = (await createCase(late, u.h)).json();
    assert.equal(p.callableNow, false);
    assert.equal((await api(late, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest })).json().error, "outside_hours");
    assert.equal(late.telephony.created.length, 0);
    await late.app.close();

    const w = await world({ settings: { limits: { userPerHour: 1 } as never } });
    const v = await user(w);
    await dialled(w, v.h);
    const second = (await createCase(w, v.h)).json();
    const r = await api(w, "POST", `/v1/call-cases/${second.caseId}/approve`, v.h, { digest: second.digest });
    assert.deepEqual([r.json().error, r.json().gate], ["gate_refused", "limit_user_hour"]);
    await w.app.close();

    // One call at a time per account.
    const y = await world();
    const z = await user(y);
    await dialled(y, z.h);
    const other = (await createCase(y, z.h)).json();
    const busy = await api(y, "POST", `/v1/call-cases/${other.caseId}/approve`, z.h, { digest: other.digest });
    assert.deepEqual([busy.json().error, busy.json().gate], ["gate_refused", "one_live_call"]);
    assert.equal(y.telephony.created.length, 1);
    await y.app.close();

    // Same destination from two users within 15 minutes: the second is refused.
    const x = await world();
    const a = await user(x);
    const b = await user(x);
    const dest = nextDestination();
    await dialled(x, a.h, { callee: { name: "Serwis", phone: dest, source: "typed" } });
    const q = (await createCase(x, b.h, { callee: { name: "Serwis", phone: dest, source: "typed" } })).json();
    const refused = await api(x, "POST", `/v1/call-cases/${q.caseId}/approve`, b.h, { digest: q.digest });
    assert.equal(refused.statusCode, 409);
    assert.deepEqual([refused.json().error, refused.json().gate], ["gate_refused", "limit_destination_gap"]);
    assert.equal(x.telephony.created.length, 1);
    await x.app.close();
  });

  test("the kill switch stops new calls, answers with the apology, and ends calls in progress", async () => {
    const w = await world();
    const u = await user(w);
    const live = await dialled(w, u.h);
    await answer(w, live);
    const pending = (await createCase(w, (await user(w)).h)).json();
    w.settings.killSwitch = true;
    assert.equal((await createCase(w, u.h)).statusCode, 503);
    assert.equal((await api(w, "POST", `/v1/call-cases/${pending.caseId}/approve`, u.h, { digest: pending.digest })).statusCode, 503);
    await runTaskCallPasses(w.ctx, { lastSweep: Date.now() });
    const end = w.telephony.updates.find((x) => x.sid === live.sid);
    assert.ok(end?.update.twiml?.includes("Przepraszam, muszę już kończyć"));
    const { rows } = await db.query("SELECT end_reason FROM call_attempts WHERE id = $1", [live.attemptId]);
    assert.equal(rows[0].end_reason, "kill_switch");
    await w.app.close();
  });

  test("a live agent that drifted from its spec blocks dialling and answering", async () => {
    const w = await world();
    const u = await user(w);
    (w.voice.agent as any).conversation_config.agent.prompt.tool_ids = ["tool_pay_anything"];
    await w.ctx.drift.refresh();
    const p = (await createCase(w, u.h)).json();
    const r = await api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, u.h, { digest: p.digest });
    assert.deepEqual([r.json().error, r.json().gate], ["gate_refused", "agent_drift"]);
    assert.equal(w.telephony.created.length, 0);
    await w.app.close();
  });

  test("at the approved maximum Doddy says goodbye; Zakończ ends it at once", async () => {
    const w = await world();
    const u = await user(w);
    const d = await dialled(w, u.h, { maxDurationSecs: 120 });
    await answer(w, d);
    w.clock.now = new Date(w.clock.now.getTime() + 121_000);
    await runTaskCallPasses(w.ctx, { lastSweep: Date.now() });
    assert.ok(w.telephony.updates.some((x) => x.sid === d.sid && x.update.twiml?.includes("muszę już kończyć")));
    assert.equal((await db.query("SELECT end_reason FROM call_attempts WHERE id = $1", [d.attemptId])).rows[0].end_reason, "time_limit");
    await w.app.close();
  });

  test("Zakończ while ringing cancels; another account can't end it", async () => {
    const w = await world();
    const u = await user(w);
    const d = await dialled(w, u.h);
    const other = await user(w);
    assert.equal((await api(w, "POST", `/v1/call-cases/${d.caseId}/end`, other.h)).statusCode, 404);
    const r = await api(w, "POST", `/v1/call-cases/${d.caseId}/end`, u.h);
    assert.equal(r.statusCode, 202);
    assert.deepEqual(w.telephony.updates.at(-1), { sid: d.sid, update: { status: "canceled" } });
    await w.app.close();
  });

  test("Przejmij rings only the verified phone, joins only after 1, and stops listening", async () => {
    const w = await world();
    const u = await user(w);
    const d = await dialled(w, u.h);
    await answer(w, d);
    const start = await api(w, "POST", `/v1/call-cases/${d.caseId}/takeover`, u.h);
    assert.equal(start.statusCode, 202);
    const leg = w.telephony.created.at(-1)!;
    assert.equal(leg.to, u.phone);
    assert.equal(leg.from, DODDY_FROM);
    const { takeoverId } = start.json() as { takeoverId: string };
    // A second tap returns the same takeover.
    assert.equal((await api(w, "POST", `/v1/call-cases/${d.caseId}/takeover`, u.h)).json().takeoverId, takeoverId);
    const legSid = (await db.query<{ twilio_call_sid: string }>("SELECT twilio_call_sid FROM call_takeovers WHERE id = $1", [takeoverId])).rows[0]!.twilio_call_sid;

    const prompt = await twilio(w, `/webhooks/twilio/task-call/takeover-answer?t=${takeoverId}`, callForm(legSid));
    assert.match(prompt.body, /Doddy jest na linii: Serwis Laptop\. Naciśnij 1, aby przejąć rozmowę\./);
    const declined = await twilio(w, `/webhooks/twilio/task-call/takeover-digits?t=${takeoverId}`, callForm(legSid, { Digits: "2" }));
    assert.match(declined.body, /Doddy rozmawia dalej/);
    assert.equal(w.telephony.updates.some((x) => x.sid === d.sid), false);

    const again = (await api(w, "POST", `/v1/call-cases/${d.caseId}/takeover`, u.h)).json() as { takeoverId: string };
    const sid2 = (await db.query<{ twilio_call_sid: string }>("SELECT twilio_call_sid FROM call_takeovers WHERE id = $1", [again.takeoverId])).rows[0]!.twilio_call_sid;
    await twilio(w, `/webhooks/twilio/task-call/takeover-answer?t=${again.takeoverId}`, callForm(sid2));
    const join = await twilio(w, `/webhooks/twilio/task-call/takeover-digits?t=${again.takeoverId}`, callForm(sid2, { Digits: "1" }));
    assert.match(join.body, /<Dial><Conference/);
    const redirect = w.telephony.updates.find((x) => x.sid === d.sid)!;
    assert.match(redirect.update.twiml!, /<Stop><Transcription name="doddy-live"\/><\/Stop><Say[^>]*>Chwileczkę, przekazuję rozmowę do Anny\.<\/Say><Dial><Conference/);
    // Nothing the user says is kept.
    await say(w, d, "inbound_track", "To jest już rozmowa z Anną.");
    assert.equal((await db.query("SELECT 1 FROM call_live_lines WHERE attempt_id = $1", [d.attemptId])).rowCount, 0);
    // Both in: the time limit becomes the user's.
    for (const sid of [d.sid, sid2]) {
      await twilio(w, `/webhooks/twilio/task-call/conference?t=${again.takeoverId}`, callForm(sid, { StatusCallbackEvent: "participant-join" }));
    }
    assert.ok(w.telephony.updates.some((x) => x.sid === d.sid && x.update.timeLimitSecs === 1860));
    // The kill switch ends AI calls only, not one the user has joined.
    w.settings.killSwitch = true;
    const before = w.telephony.updates.length;
    await runTaskCallPasses(w.ctx, { lastSweep: Date.now() });
    assert.equal(w.telephony.updates.filter((x, i) => i >= before && x.sid === d.sid).length, 0);
    await w.app.close();
  });

  test("no answer: honest card, nothing charged for voice, retry at a set time is a new approval", async () => {
    const w = await world();
    const u = await user(w);
    const d = await dialled(w, u.h);
    await status(w, d, "ringing", 1);
    await status(w, d, "no-answer", 2, "0");
    await processResults(w.ctx);
    const kase = (await api(w, "GET", `/v1/call-cases/${d.caseId}`, u.h)).json();
    assert.equal(kase.results[0].outcome, "no_answer");
    assert.equal(kase.results[0].result.nextStep.kind, "retry");
    const zero = kase.cost.items.filter((i: { status: string }) => i.status === "zero").map((i: { component: string }) => i.component).sort();
    assert.deepEqual(zero, ["elevenlabs_voice", "twilio_transcription"]);

    // Retry in two hours (13:00 Warsaw).
    const at = new Date(w.clock.now.getTime() + 2 * 3600_000).toISOString();
    const retry = await api(w, "POST", `/v1/call-cases/${d.caseId}/approve`, u.h, { digest: d.preview.digest, at });
    assert.deepEqual([retry.statusCode, retry.json().state], [202, "scheduled"]);
    assert.equal(w.telephony.created.length, 1);
    w.clock.now = new Date(Date.parse(at) + 30_000);
    await runTaskCallPasses(w.ctx, { lastSweep: Date.now() });
    assert.equal(w.telephony.created.length, 2);
    // A retry nobody dialled within its window expires; it is never dialled late.
    const r2 = (await db.query<{ twilio_call_sid: string; id: string }>(
      "SELECT twilio_call_sid, id FROM call_attempts WHERE case_id = $1 AND attempt_no = 2", [d.caseId])).rows[0]!;
    await answer(w, { attemptId: r2.id, sid: r2.twilio_call_sid, to: d.to });
    await status(w, { attemptId: r2.id, sid: r2.twilio_call_sid }, "completed", 5);
    assert.equal((await api(w, "POST", `/v1/call-cases/${d.caseId}/approve`, u.h, { digest: d.preview.digest })).json().error, "already_answered");
    await w.app.close();
  });

  test("every dialled attempt has its costs; a part nobody reports becomes unknown, never zero", async () => {
    const w = await world({ settings: { prices: { elevenLabsUsdPerCredit: undefined, transcriptionUsdPerMin: undefined } } });
    const u = await user(w);
    const d = await dialled(w, u.h);
    await answer(w, d);
    await status(w, d, "completed", 4, "60");
    const { rows } = await db.query<{ component: string; status: string }>("SELECT component, status FROM call_cost_items WHERE attempt_id = $1 ORDER BY component", [d.attemptId]);
    assert.deepEqual(rows.map((r) => r.component), ["elevenlabs_voice", "twilio_call", "twilio_transcription"]);
    w.clock.now = new Date(w.clock.now.getTime() + 25 * 3600_000);
    for (let i = 0; i < 3; i++) await settleCosts(w.ctx);
    const settled = await db.query<{ component: string; status: string; amount_micros: string | null }>(
      "SELECT component, status, amount_micros FROM call_cost_items WHERE attempt_id = $1 ORDER BY component", [d.attemptId]);
    for (const r of settled.rows) {
      assert.equal(r.status, "unknown", r.component);
      assert.equal(r.amount_micros, null, r.component);
    }
    const all = await db.query(
      `SELECT a.id FROM call_attempts a WHERE a.dial_started_at IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM call_cost_items i WHERE i.attempt_id = a.id AND i.component = 'twilio_call')`);
    assert.equal(all.rowCount, 0, "a dialled attempt without a cost");
    await w.app.close();
  });

  test("post-call webhook: bad signatures refused, other agents ignored, unknown conversations deleted", async () => {
    const w = await world();
    const body = conversation("6f9619ff-8b86-4d11-b42d-00c04fc964fe", "conv_orphan", [["user", "x"]]);
    assert.equal((await postCall(w, body, "wrong-secret-0123456789")).statusCode, 401);
    assert.equal((await postCall(w, { ...body, agent_id: "agent_memory_s2", conversation_id: "conv_s2" })).statusCode, 200);
    assert.equal((await db.query("SELECT 1 FROM server_data_deletions WHERE provider_ref = 'conv_s2'")).rowCount, 0);
    assert.equal((await postCall(w, body)).statusCode, 200);
    const job = await db.query<{ reason: string; result: string }>("SELECT reason, result FROM server_data_deletions WHERE provider_ref = 'conv_orphan'");
    assert.deepEqual(job.rows[0], { reason: "orphan", result: "pending" });
    await w.app.close();
  });

  test("deleting the account mid-call ends the call and keeps the ElevenLabs deletion", async () => {
    const w = await world();
    const u = await user(w);
    const d = await dialled(w, u.h);
    await answer(w, d);
    await db.query("UPDATE call_attempts SET el_conversation_id = 'conv_del' WHERE id = $1", [d.attemptId]);
    assert.equal((await api(w, "DELETE", "/v1/account", u.h)).statusCode, 204);
    assert.ok(w.telephony.updates.some((x) => x.sid === d.sid));
    const job = await db.query<{ account_id: string | null; result: string }>("SELECT account_id, result FROM server_data_deletions WHERE provider_ref = 'conv_del'");
    assert.deepEqual(job.rows[0], { account_id: null, result: "pending" });
    assert.equal((await db.query("SELECT 1 FROM call_cases WHERE account_id = $1", [u.accountId])).rowCount, 0);
    await w.app.close();
  });
});
