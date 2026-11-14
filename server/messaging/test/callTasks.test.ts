// Call tasks (decision docs/decisions/2026-11-09-restaurant-calls-one-tap.md): up to three places, one
// tap, called in turn until one says yes; the result by push and, if chosen, by text to the person's own number.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { bodyAad } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import type { CallResult, WriterInput, WriterOutput } from "../src/taskCalls/result.js";
import { answerOf, MAX_PLACES } from "../src/taskCalls/tasks.js";
import { processResults, runTaskCallPasses } from "../src/taskCalls/worker.js";
import {
  BASE_URL, dbSkip, DODDY_FROM, EL_WEBHOOK_SECRET, freshDb, TASK_ACCOUNT_SID, TASK_AGENT_ID, TASK_AUTH_TOKEN, taskTestApp, testCipher,
  type TaskTestOptions,
} from "./helpers.js";

/** A stand-in for the result step: "tak" in the callee's last line is yes, "nie" is no, anything else unclear. */
const writer = {
  provider: "anthropic" as const,
  model: "claude-haiku-5-5",
  write: async (input: WriterInput): Promise<WriterOutput> => {
    const lines = input.transcript.map((l, i) => ({ ...l, i })).filter((l) => l.speaker === "callee");
    const last = lines.at(-1)!;
    const said = last.text.toLowerCase();
    const answer = said.startsWith("tak") ? "yes" : said.startsWith("nie") ? "no" : "unclear";
    return { kind: "answered", answerLine: last.i, answerQuote: last.text, summary: last.text, nextStep: "Zadzwoń, by potwierdzić.", answer };
  },
};

const result = (over: Partial<CallResult>): CallResult => ({
  format: 1, outcome: "answered", source: "elevenlabs", confidence: "high", confidenceReasons: [], summary: "", summaryBy: "rules",
  quote: { text: "Tak, mamy stolik.", line: 1 }, transcript: [], nextStep: { kind: "none", text: "" }, warnings: [], callbackPromised: false,
  takenOverAtSecs: null, durationSecs: 30, ...over,
});
const said = (answer: WriterOutput["answer"]): WriterOutput => ({ kind: "answered", answerLine: 1, answerQuote: "x", summary: "", nextStep: "", answer });

test("what a place's call means for the task: a yes needs the model's yes and a quote; anything less is unclear", () => {
  assert.equal(answerOf(result({}), said("yes")), "yes");
  assert.equal(answerOf(result({ quote: null }), said("yes")), "unclear", "no quote cut from the transcript");
  assert.equal(answerOf(result({ confidence: "low" }), said("yes")), "unclear");
  assert.equal(answerOf(result({ warnings: [{ kind: "possible_commitment", line: 2 }] }), said("yes")), "unclear");
  assert.equal(answerOf(result({}), undefined), "unclear", "no model step: Doddy doesn't guess");
  assert.equal(answerOf(result({}), said("unclear")), "unclear");
  assert.equal(answerOf(result({ quote: null }), said("no")), "no");
  for (const outcome of ["no_answer", "busy", "voicemail", "ivr", "wrong_number", "failed"] as const) {
    assert.equal(answerOf(result({ outcome, quote: null }), undefined), "none", outcome);
  }
  assert.equal(answerOf(result({ outcome: "taken_over" }), said("yes")), "stop", "the person took the call over");
  for (const outcome of ["not_placed", "voice_unavailable", "unknown"] as const) {
    assert.equal(answerOf(result({ outcome, quote: null }), undefined), "stop", `${outcome}: never "nobody said yes" when nobody was asked`);
  }
  assert.equal(MAX_PLACES, 3);
});

describe("call tasks", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  let seq = 0;
  const phone = () => `+48510${String(200000 + ++seq).slice(-6)}`;
  const dest = () => `+4832${String(2000000 + ++seq).slice(-7)}`;

  async function setup(opts: TaskTestOptions & { smsConsent?: boolean } = {}) {
    await db.query("DELETE FROM call_dial_log");
    const w = await taskTestApp(db, { writer, ...opts });
    const r = await w.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    await w.app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone: phone(), code: "123456" } });
    if (opts.smsConsent !== false) {
      const consent = await w.app.inject({ method: "PUT", url: "/v1/phone/sms-consent", headers: h, payload: { consent: true, textVersion: "sms-v1" } });
      assert.equal(consent.statusCode, 204, consent.body);
    }
    const api = (method: "GET" | "POST" | "PUT", url: string, payload?: object) => w.app.inject({ method, url, headers: h, ...(payload ? { payload } : {}) });
    const token = await api("PUT", "/v1/device/push-token", { token: (++seq).toString(16).padStart(64, "a"), environment: "sandbox" });
    assert.ok(token.statusCode < 300, token.body);
    const tw = (url: string, form: Record<string, string>) => w.app.inject({
      method: "POST", url, payload: new URLSearchParams(form).toString(),
      headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": twilioSignature(TASK_AUTH_TOKEN, BASE_URL + url, form) },
    });
    const ctx = w.app.taskCallContext!;
    return { ...w, ctx, h, accountId, api, tw };
  }
  type S = Awaited<ReturnType<typeof setup>>;

  const task = (places: { name: string; phone: string }[], over: object = {}) => ({
    kind: "ask",
    places: places.map((p) => ({ ...p, source: "places", sourceLabel: "Wyszukiwanie miejsc Doddy" })),
    principal: { name: "Patryk", genitive: "Patryka" },
    goal: "Znaleźć stolik na randkę dziś wieczorem.",
    question: "Czy mają Państwo wolny stolik dla dwóch osób dziś o 19:00",
    textResult: true,
    ...over,
  });

  /** The open attempt of a task's place, with what Twilio was asked to dial. */
  async function current(s: S, caseId: string) {
    const { rows } = await db.query<{ id: string; twilio_call_sid: string | null; state: string }>(
      "SELECT id, twilio_call_sid, state FROM call_attempts WHERE case_id = $1 ORDER BY attempt_no DESC LIMIT 1", [caseId]);
    return rows[0];
  }

  /** The place answers, says `line`, the call ends, and the result step runs. */
  async function answers(s: S, caseId: string, line: string, conv: string) {
    const a = (await current(s, caseId))!;
    const sid = a.twilio_call_sid!;
    const to = s.telephony.created.at(-1)!.to;
    const base = { AccountSid: TASK_ACCOUNT_SID, CallSid: sid };
    await s.tw(`/webhooks/twilio/task-call/answer?a=${a.id}`, { ...base, To: to, From: DODDY_FROM });
    await s.tw(`/webhooks/twilio/task-call/status?a=${a.id}`, { ...base, CallStatus: "completed", SequenceNumber: "3", CallDuration: "30" });
    const body = JSON.stringify({ type: "post_call_transcription", data: {
      agent_id: TASK_AGENT_ID, conversation_id: conv, transcript: [
        { role: "agent", message: "Dzień dobry, mówi Doddy, asystent AI. Chciałbym zapytać: Czy mają Państwo wolny stolik dla dwóch osób dziś o 19:00?" },
        { role: "user", message: line }],
      metadata: { cost: 300 }, conversation_initiation_client_data: { dynamic_variables: { doddy_attempt: a.id } } } });
    const r = await s.app.inject({ method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body,
      headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(EL_WEBHOOK_SECRET, body) } });
    assert.ok(r.statusCode < 300, r.body);
    await processResults(s.ctx);
  }

  async function noAnswer(s: S, caseId: string) {
    const a = (await current(s, caseId))!;
    await s.tw(`/webhooks/twilio/task-call/status?a=${a.id}`, { AccountSid: TASK_ACCOUNT_SID, CallSid: a.twilio_call_sid!, CallStatus: "no-answer", SequenceNumber: "2", CallDuration: "0" });
    await processResults(s.ctx);
  }

  async function texts(s: S, taskId: string) {
    const { rows } = await db.query<{ id: string; body_ciphertext: Buffer }>(
      "SELECT id, body_ciphertext FROM outbound_messages WHERE account_id = $1 AND channel = 'sms' AND idempotency_key = $2", [s.accountId, `call-task:${taskId}`]);
    return rows.map((r) => testCipher.decrypt(r.body_ciphertext, bodyAad(s.accountId, r.id)));
  }
  async function pushes(s: S) {
    const { rows } = await db.query<{ n: number }>(
      "SELECT count(*)::int AS n FROM outbound_messages WHERE account_id = $1 AND channel = 'push' AND idempotency_key LIKE 'call-result:%'", [s.accountId]);
    return rows[0]!.n;
  }
  const dialledTo = (s: S) => s.telephony.created.map((c) => c.to);

  test("one tap: the first place says no, the second says yes, the third is never called; one push and one text", async () => {
    const s = await setup();
    const places = [{ name: "Trattoria Uno", phone: dest() }, { name: "Osteria Due", phone: dest() }, { name: "Pizzeria Tre", phone: dest() }];
    const created = await s.api("POST", "/v1/call-tasks", task(places));
    assert.equal(created.statusCode, 201, created.body);
    const p = created.json();
    assert.equal(p.places.length, 3);
    assert.deepEqual(p.places.map((x: { callee: { name: string; source: string } }) => [x.callee.name, x.callee.source]),
      places.map((x) => [x.name, "places"]), "the card names each place and where its number came from");
    assert.equal(p.textResult, true);
    assert.deepEqual(dialledTo(s), [], "nothing is dialled before the tap");

    // A place can't be approved on its own: only the task's one tap calls it, in its turn.
    const alone = await s.api("POST", `/v1/call-cases/${p.places[1].caseId}/approve`, { digest: p.places[1].digest });
    assert.equal(alone.statusCode, 409);
    assert.equal(alone.json().error, "part_of_task");
    // The tap must carry the task's digest, not a place's.
    assert.equal((await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.places[0].digest })).json().error, "digest_mismatch");

    const tap = await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    assert.equal(tap.statusCode, 202, tap.body);
    assert.equal(dialledTo(s).length, 1);
    assert.equal((await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest })).json().error, "not_approvable", "one tap, once");

    await answers(s, p.places[0].caseId, "Nie, niestety wszystko zajęte.", "conv_t1");
    let t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.equal(t.state, "active");
    assert.equal(t.places[0].answer, "no");
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() }); // the worker dials the next place
    assert.equal(dialledTo(s).length, 2);

    await answers(s, p.places[1].caseId, "Tak, mamy wolny stolik o 19.", "conv_t2");
    t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome, t.outcomePosition], ["finished", "yes", 2]);
    assert.equal(t.places[2].state, "cancelled", "the third place's brief is deleted, never called");
    assert.equal(t.places[2].preview, null);
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() });
    assert.equal(dialledTo(s).length, 2, "nobody else is called");

    const sent = await texts(s, p.taskId);
    assert.equal(sent.length, 1);
    assert.equal(sent[0], "Doddy: Osteria Due odpowiada: „Tak, mamy wolny stolik o 19.”. Szczegóły w aplikacji Doddy.");
    assert.equal(await pushes(s), 1, "one push for the whole task, never one per place");
    await s.app.close();
  });

  test("the result text quotes the place's words without links, addresses or long numbers", async () => {
    const s = await setup();
    const p = (await s.api("POST", "/v1/call-tasks", task([{ name: "Osteria Due", phone: dest() }]))).json();
    await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    await answers(s, p.places[0].caseId,
      "Tak, o 19 jest stolik, proszę potwierdzić na https://osteria-due.example/rez?id=7 albo www.osteria.pl, mail rezerwacje@osteria.pl, tel. 600 123 456, kod 4821937.",
      "conv_t_links");
    const [sent] = await texts(s, p.taskId);
    assert.equal(sent,
      "Doddy: Osteria Due odpowiada: „Tak, o 19 jest stolik, proszę potwierdzić na … albo …, mail …, tel. …, kod ….”. Szczegóły w aplikacji Doddy.");
    await s.app.close();
  });

  test("a place that doesn't pick up is skipped; when nobody says yes the text says so", async () => {
    const s = await setup();
    const places = [{ name: "Uno", phone: dest() }, { name: "Due", phone: dest() }];
    const p = (await s.api("POST", "/v1/call-tasks", task(places))).json();
    await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    await noAnswer(s, p.places[0].caseId);
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() });
    assert.equal(dialledTo(s).length, 2);
    await answers(s, p.places[1].caseId, "Nie mamy dziś miejsc.", "conv_t3");
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.outcome, t.places[0].answer, t.places[1].answer], ["none", "none", "no"]);
    assert.deepEqual(await texts(s, p.taskId), ["Doddy: żadne z 2 miejsc nie potwierdziło. Szczegóły w aplikacji Doddy."]);
    assert.equal(await pushes(s), 1);
    await s.app.close();
  });

  test("an answer that isn't a clear yes or no stops the task for the person to read; nothing more is dialled", async () => {
    const s = await setup();
    const p = (await s.api("POST", "/v1/call-tasks", task([{ name: "Uno", phone: dest() }, { name: "Due", phone: dest() }]))).json();
    await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    await answers(s, p.places[0].caseId, "Może o 20, proszę zadzwonić później.", "conv_t4");
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() });
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome, t.outcomePosition], ["finished", "unclear", 1]);
    assert.equal(dialledTo(s).length, 1);
    assert.deepEqual(await texts(s, p.taskId), ["Doddy: rozmowa z Uno się odbyła, ale odpowiedź nie jest jasna. Sprawdź ją w aplikacji Doddy."]);
    await s.app.close();
  });

  test("no text unless the card said so, and never without the person's consent to texts", async () => {
    for (const [over, consent] of [[{ textResult: false }, true], [{}, false]] as const) {
      const s = await setup({ smsConsent: consent });
      const p = (await s.api("POST", "/v1/call-tasks", task([{ name: "Uno", phone: dest() }], over))).json();
      await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
      await answers(s, p.places[0].caseId, "Tak, zapraszamy.", `conv_t5_${consent}`);
      assert.equal((await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json().outcome, "yes");
      assert.deepEqual(await texts(s, p.taskId), []);
      await s.app.close();
    }
  });

  test("the text choice is part of what the tap approves", async () => {
    const s = await setup();
    const places = [{ name: "Uno", phone: dest() }];
    const a = (await s.api("POST", "/v1/call-tasks", task(places, { textResult: true }))).json();
    const b = (await s.api("POST", "/v1/call-tasks", task(places, { textResult: false }))).json();
    assert.notEqual(a.digest, b.digest);
    assert.equal((await s.api("POST", `/v1/call-tasks/${b.taskId}/approve`, { digest: a.digest })).json().error, "digest_mismatch");
    await s.app.close();
  });

  test("refusals: the same number twice, more than three places, a number Doddy may not call, an unknown field", async () => {
    const s = await setup();
    const n = dest();
    assert.equal((await s.api("POST", "/v1/call-tasks", task([{ name: "A", phone: n }, { name: "B", phone: n }]))).json().error, "duplicate_place");
    const four = Array.from({ length: MAX_PLACES + 1 }, (_, i) => ({ name: `P${i}`, phone: dest() }));
    assert.equal((await s.api("POST", "/v1/call-tasks", task(four))).statusCode, 400);
    const premium = await s.api("POST", "/v1/call-tasks", task([{ name: "A", phone: dest() }, { name: "B", phone: "+48 700 123 456" }]));
    assert.deepEqual([premium.statusCode, premium.json().error], [400, "destination_refused"]);
    assert.equal((await s.api("POST", "/v1/call-tasks", task([{ name: "A", phone: dest() }], { book: true }))).statusCode, 400);
    const { rows } = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM call_tasks WHERE account_id = $1", [s.accountId]);
    assert.equal(rows[0]!.n, 0, "a refused task stores nothing");
    await s.app.close();
  });

  test("cancelling stops the task: the place on the line finishes, nobody else is called, no text", async () => {
    const s = await setup();
    const p = (await s.api("POST", "/v1/call-tasks", task([{ name: "Uno", phone: dest() }, { name: "Due", phone: dest() }]))).json();
    await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    assert.equal((await s.api("POST", `/v1/call-tasks/${p.taskId}/cancel`)).statusCode, 204);
    await answers(s, p.places[0].caseId, "Nie, brak miejsc.", "conv_t6");
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() });
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.equal(t.state, "cancelled");
    assert.equal(dialledTo(s).length, 1);
    assert.equal(t.places[1].preview, null, "the waiting place's brief is deleted");
    assert.deepEqual(await texts(s, p.taskId), []);
    assert.equal(await pushes(s), 0, "a cancelled task sends nothing");
    await s.app.close();
  });

  test("a call Doddy couldn't place stops the task: nobody else is called, and the text never says nobody said yes", async () => {
    const s = await setup();
    const p = (await s.api("POST", "/v1/call-tasks", task([{ name: "Uno", phone: dest() }, { name: "Due", phone: dest() }]))).json();
    s.voice.agent = { agent_id: "changed" }; // the live agent no longer matches its spec: every dial is refused
    await s.ctx.drift.refresh();
    const tap = await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    assert.equal(tap.json().error, "gate_refused", tap.body);
    s.clock.now = new Date(s.clock.now.getTime() + 4 * 60_000);
    await processResults(s.ctx);
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() });
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome], ["finished", "stopped"]);
    assert.deepEqual(dialledTo(s), []);
    assert.deepEqual(await texts(s, p.taskId), ["Doddy: zatrzymałem dzwonienie przed końcem listy. Szczegóły w aplikacji Doddy."]);
    await s.app.close();
  });

  test("an unapproved task lapses after 30 minutes; one started late in the evening stops at the end of calling hours", async () => {
    const s = await setup();
    const p = (await s.api("POST", "/v1/call-tasks", task([{ name: "Uno", phone: dest() }]))).json();
    s.clock.now = new Date(s.clock.now.getTime() + 31 * 60_000);
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() });
    assert.equal((await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json().state, "expired");
    assert.equal((await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest })).json().error, "not_approvable");
    await s.app.close();

    // 22:52 in Warsaw: the first call fits, the next one wouldn't end before 23:00.
    const late = await setup({ start: "2026-10-19T20:52:00Z" });
    const q = (await late.api("POST", "/v1/call-tasks", task([{ name: "Uno", phone: dest() }, { name: "Due", phone: dest() }], { maxDurationSecs: 60 }))).json();
    assert.equal((await late.api("POST", `/v1/call-tasks/${q.taskId}/approve`, { digest: q.digest })).statusCode, 202);
    late.clock.now = new Date(late.clock.now.getTime() + 8 * 60_000); // 23:00: a 60-second call with ringing no longer fits
    await noAnswer(late, q.places[0].caseId);
    const t = (await late.api("GET", `/v1/call-tasks/${q.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome], ["finished", "stopped"]);
    assert.equal(dialledTo(late).length, 1);
    assert.deepEqual(await texts(late, q.taskId), ["Doddy: zatrzymałem dzwonienie przed końcem listy. Szczegóły w aplikacji Doddy."]);
    await late.app.close();
  });
});
