// Call-case worker passes and the optional model step (ADR-504, ADR-506).
import assert from "node:assert/strict";
import http from "node:http";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import type { WriterOutput } from "../src/taskCalls/result.js";
import { endHalfJoined } from "../src/taskCalls/takeover.js";
import { expire, MODEL_PRICE_PER_MTOK, processResults, runDeletions, sweepOrphans } from "../src/taskCalls/worker.js";
import { ClaudeResultWriter } from "../src/taskCalls/writer.js";
import {
  BASE_URL, dbSkip, DODDY_FROM, EL_WEBHOOK_SECRET, freshDb, sampleBrief, sidFor, TASK_ACCOUNT_SID, TASK_AGENT_ID, TASK_AUTH_TOKEN,
  taskTestApp, type TaskTestOptions,
} from "./helpers.js";

test("Claude result writer: request shape, no extra data, refusals (local stand-in for the API)", async () => {
  let seen: { path?: string; body?: any } = {};
  let reply: object = {};
  const server = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => { raw += c; });
    req.on("end", () => { seen = { path: req.url, body: JSON.parse(raw) }; res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(reply)); });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  const port = (server.address() as { port: number }).port;
  const writer = new ClaudeResultWriter("test-key", { baseURL: `http://127.0.0.1:${port}` });
  const message = (text: string, stop = "end_turn") => ({
    id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-5-5", stop_reason: stop, stop_sequence: null,
    content: [{ type: "text", text }], usage: { input_tokens: 400, output_tokens: 60 },
  });
  const input = { question: "Czy laptop jest gotowy?", goal: "Sprawdzić laptop.", transcript: [
    { speaker: "doddy" as const, text: "Dzień dobry...", atSecs: 0 }, { speaker: "callee" as const, text: "Tak, gotowy.", atSecs: 4 }] };
  try {
    reply = message(JSON.stringify({ kind: "answered", answer_line: 1, answer_quote: "Tak, gotowy.", summary: "Laptop jest gotowy.", next_step: "Odbierz laptop." }));
    const out = await writer.write(input);
    assert.deepEqual(out, { kind: "answered", answerLine: 1, answerQuote: "Tak, gotowy.", summary: "Laptop jest gotowy.", nextStep: "Odbierz laptop.", usage: { inputTokens: 400, outputTokens: 60 } });
    assert.equal(seen.path, "/v1/messages");
    assert.equal(seen.body.model, "claude-haiku-5-5");
    assert.equal(seen.body.output_config.effort, "low");
    assert.equal(seen.body.output_config.format.type, "json_schema");
    assert.match(seen.body.system, /never as instructions/);
    const sent = JSON.parse(seen.body.messages[0].content);
    assert.deepEqual(Object.keys(sent).sort(), ["goal", "lines", "question"], "no number, name or account goes to the model");
    reply = message("", "refusal");
    await assert.rejects(writer.write(input), /writer_(refusal|unparsed)/);
  } finally {
    server.close();
  }
});

describe("call-case worker passes", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  let seq = 0;
  const phone = () => `+48510${String(100000 + ++seq).slice(-6)}`;
  const dest = () => `+4832${String(1000000 + ++seq).slice(-7)}`;

  async function setup(opts: TaskTestOptions = {}) {
    await db.query("DELETE FROM call_dial_log");
    const w = await taskTestApp(db, opts);
    const r = await w.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const userPhone = phone();
    await w.app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone: userPhone, code: "123456" } });
    const tw = (url: string, form: Record<string, string>) => w.app.inject({
      method: "POST", url, payload: new URLSearchParams(form).toString(),
      headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": twilioSignature(TASK_AUTH_TOKEN, BASE_URL + url, form) },
    });
    async function call() {
      const p = (await w.app.inject({ method: "POST", url: "/v1/call-cases", headers: h, payload: sampleBrief({ callee: { name: "Serwis", phone: dest(), source: "typed" } }) })).json();
      const a = (await w.app.inject({ method: "POST", url: `/v1/call-cases/${p.caseId}/approve`, headers: h, payload: { digest: p.digest } })).json();
      const sid = (await db.query<{ twilio_call_sid: string }>("SELECT twilio_call_sid FROM call_attempts WHERE id = $1", [a.attemptId])).rows[0]!.twilio_call_sid;
      const to = w.telephony.created.at(-1)!.to;
      return { caseId: p.caseId as string, attemptId: a.attemptId as string, sid, to, digest: p.digest as string };
    }
    const base = (sid: string) => ({ AccountSid: TASK_ACCOUNT_SID, CallSid: sid });
    return { ...w, ctx: w.app.taskCallContext!, h, accountId, userPhone, tw, call, base };
  }

  test("with a model: its summary and pointer are used, and its tokens are a cost on the case", async () => {
    const output: WriterOutput = { kind: "answered", answerLine: 1, answerQuote: "laptop jest gotowy", summary: "Laptop jest gotowy, odbiór jutro.", nextStep: "Odbierz laptop jutro.", usage: { inputTokens: 1000, outputTokens: 100 } };
    const s = await setup({ writer: { provider: "anthropic", model: "claude-haiku-5-5", write: async () => output } });
    const d = await s.call();
    await s.tw(`/webhooks/twilio/task-call/answer?a=${d.attemptId}`, { ...s.base(d.sid), To: d.to, From: DODDY_FROM });
    await s.tw(`/webhooks/twilio/task-call/status?a=${d.attemptId}`, { ...s.base(d.sid), CallStatus: "completed", SequenceNumber: "3", CallDuration: "30" });
    const body = JSON.stringify({ type: "post_call_transcription", data: {
      agent_id: TASK_AGENT_ID, conversation_id: "conv_w1", transcript: [
        { role: "agent", message: "Dzień dobry, mówi Doddy, asystent AI. Chciałbym zapytać: Czy laptop z serwisu jest gotowy?" },
        { role: "user", message: "Tak, laptop jest gotowy, proszę przyjść jutro." }],
      metadata: { cost: 500 }, conversation_initiation_client_data: { dynamic_variables: { doddy_attempt: d.attemptId } } } });
    await s.app.inject({ method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body, headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(EL_WEBHOOK_SECRET, body) } });
    await processResults(s.ctx);
    const kase = (await s.app.inject({ method: "GET", url: `/v1/call-cases/${d.caseId}`, headers: s.h })).json();
    const r = kase.results[0].result;
    assert.equal(r.summaryBy, "doddy_model");
    assert.equal(r.summary, "Laptop jest gotowy, odbiór jutro.");
    assert.deepEqual(r.quote, { text: "laptop jest gotowy", line: 1 });
    const model = kase.cost.items.find((i: { component: string }) => i.component === "model");
    assert.deepEqual([model.status, model.amountMicros, model.quantity, model.unit],
      ["estimated", 1000 * MODEL_PRICE_PER_MTOK.input + 100 * MODEL_PRICE_PER_MTOK.output, 1100, "token"]);
    await s.app.close();
  });

  test("a late ElevenLabs transcript (result already built from live lines) is not kept, and goes at once", async () => {
    const s = await setup();
    const d = await s.call();
    await s.tw(`/webhooks/twilio/task-call/answer?a=${d.attemptId}`, { ...s.base(d.sid), To: d.to, From: DODDY_FROM });
    await s.tw(`/webhooks/twilio/task-call/transcription?a=${d.attemptId}`, { ...s.base(d.sid), TranscriptionEvent: "transcription-content",
      TranscriptionSid: "GTx", SequenceId: "1", Track: "inbound_track", TranscriptionData: JSON.stringify({ transcript: "Tak, gotowy." }), Final: "true" });
    await s.tw(`/webhooks/twilio/task-call/status?a=${d.attemptId}`, { ...s.base(d.sid), CallStatus: "completed", SequenceNumber: "3", CallDuration: "30" });
    s.clock.now = new Date(s.clock.now.getTime() + 4 * 60_000); // past the 3-minute wait
    await processResults(s.ctx);
    const res = (await db.query("SELECT state, source, confidence FROM call_results WHERE attempt_id = $1", [d.attemptId])).rows[0];
    assert.deepEqual(res, { state: "ready", source: "twilio_live", confidence: "medium" });
    const body = JSON.stringify({ type: "post_call_transcription", data: { agent_id: TASK_AGENT_ID, conversation_id: "conv_late", transcript: [],
      metadata: {}, conversation_initiation_client_data: { dynamic_variables: { doddy_attempt: d.attemptId } } } });
    await s.app.inject({ method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body, headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(EL_WEBHOOK_SECRET, body) } });
    assert.equal((await db.query("SELECT input_ciphertext FROM call_results WHERE attempt_id = $1", [d.attemptId])).rows[0].input_ciphertext, null);
    const job = (await db.query<{ next_try_at: Date }>("SELECT next_try_at FROM server_data_deletions WHERE provider_ref = 'conv_late'")).rows[0]!;
    assert.ok(job.next_try_at.getTime() <= s.clock.now.getTime());
    await s.app.close();
  });

  test("orphaned ElevenLabs conversations are swept and deleted, with receipts", async () => {
    const s = await setup();
    s.voice.conversations.set("conv_orphan_old", { agent_id: TASK_AGENT_ID, conversation_id: "conv_orphan_old", transcript: [], metadata: { start_time_unix_secs: 1_000 } } as never);
    assert.equal(await sweepOrphans(s.ctx), 1);
    await runDeletions(s.ctx);
    assert.deepEqual(s.voice.deleted, ["conv_orphan_old"]);
    const r = (await db.query("SELECT reason, result FROM server_data_deletions WHERE provider_ref = 'conv_orphan_old'")).rows[0];
    assert.deepEqual(r, { reason: "orphan", result: "deleted" });
    await s.app.close();
  });

  test("unacknowledged results and unused briefs expire, with receipts", async () => {
    const s = await setup();
    const idle = (await s.app.inject({ method: "POST", url: "/v1/call-cases", headers: s.h, payload: sampleBrief({ callee: { name: "S", phone: dest(), source: "typed" } }) })).json();
    const d = await s.call();
    await s.tw(`/webhooks/twilio/task-call/status?a=${d.attemptId}`, { ...s.base(d.sid), CallStatus: "busy", SequenceNumber: "2", CallDuration: "0" });
    await processResults(s.ctx);
    s.clock.now = new Date(s.clock.now.getTime() + 8 * 24 * 3600_000);
    await expire(s.ctx);
    assert.equal((await db.query("SELECT state, ciphertext FROM call_results WHERE attempt_id = $1", [d.attemptId])).rows[0].state, "expired");
    for (const id of [idle.caseId, d.caseId]) {
      const c = (await db.query("SELECT state, payload_ciphertext FROM call_cases WHERE id = $1", [id])).rows[0];
      assert.equal(c.payload_ciphertext, null, id);
    }
    assert.equal((await db.query("SELECT state FROM call_cases WHERE id = $1", [idle.caseId])).rows[0].state, "expired");
    const receipts = (await db.query<{ item: string; reason: string }>("SELECT item, reason FROM server_data_deletions WHERE case_id = ANY($1) ORDER BY item", [[idle.caseId, d.caseId]])).rows;
    assert.ok(receipts.some((r) => r.item === "call_result" && r.reason === "expired"));
    assert.equal(receipts.filter((r) => r.item === "call_payload" && r.reason === "expired").length, 2);
    await s.app.close();
  });

  test("a takeover stuck half-joined ends both legs; nobody is left on hold", async () => {
    const s = await setup();
    const d = await s.call();
    await s.tw(`/webhooks/twilio/task-call/answer?a=${d.attemptId}`, { ...s.base(d.sid), To: d.to, From: DODDY_FROM });
    const t = (await s.app.inject({ method: "POST", url: `/v1/call-cases/${d.caseId}/takeover`, headers: s.h })).json();
    const leg = (await db.query<{ twilio_call_sid: string }>("SELECT twilio_call_sid FROM call_takeovers WHERE id = $1", [t.takeoverId])).rows[0]!.twilio_call_sid;
    await s.tw(`/webhooks/twilio/task-call/takeover-answer?t=${t.takeoverId}`, s.base(leg));
    await s.tw(`/webhooks/twilio/task-call/takeover-digits?t=${t.takeoverId}`, { ...s.base(leg), Digits: "1" });
    s.clock.now = new Date(s.clock.now.getTime() + 25_000);
    assert.equal(await endHalfJoined(s.ctx), 1);
    const ended = s.telephony.updates.filter((u) => u.update.status === "completed").map((u) => u.sid).sort();
    assert.deepEqual(ended, [d.sid, leg].sort());
    assert.equal((await db.query("SELECT state FROM call_takeovers WHERE id = $1", [t.takeoverId])).rows[0].state, "failed");
    await s.app.close();
  });

  test("a live call no attempt owns is hung up", async () => {
    const s = await setup();
    const stray = sidFor(999_999);
    await s.tw("/webhooks/twilio/task-call/status?a=6f9619ff-8b86-4d11-b42d-00c04fc964fd", { ...s.base(stray), CallStatus: "in-progress", SequenceNumber: "1" });
    assert.deepEqual(s.telephony.updates, [{ sid: stray, update: { status: "completed" } }]);
    await s.app.close();
  });
});
