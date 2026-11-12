// Booking calls (decision docs/decisions/2026-11-12-book-agent.md): a separate agent that may accept
// exactly the booking on the approved card, by saying one server-built sentence.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { bodyAad } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { checkAgentSafety } from "../src/taskCalls/agentSafety.js";
import { TASK_BOOK_AGENT_SPEC } from "../src/taskCalls/agentSpec.js";
import { bookingConfirmLine, bookingDateAllowed, bookingLines, bookingQuestion, type Booking } from "../src/taskCalls/booking.js";
import { briefSchema, checkBriefContent } from "../src/taskCalls/brief.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { buildCallResult, type CallResult, type ResultFacts, type WriterInput, type WriterOutput } from "../src/taskCalls/result.js";
import { answerOf } from "../src/taskCalls/tasks.js";
import { processResults } from "../src/taskCalls/worker.js";
import {
  BASE_URL, BOOK_PROMPT, compliantAgent, dbSkip, DODDY_FROM, EL_WEBHOOK_SECRET, freshDb, TASK_ACCOUNT_SID, TASK_AGENT_ID, TASK_AUTH_TOKEN,
  TASK_BOOK_AGENT_ID, taskTestApp, testCipher, type TaskTestOptions,
} from "./helpers.js";

const table: Booking = { name: "Anna Kowalska", date: "2026-11-13", time: "19:00", partySize: 2 };
const haircut: Booking = { name: "Jan Nowak", date: "2026-11-17", time: "10:30", service: "strzyżenie męskie" };

// ---------- the sentences, built in code ----------

test("the booking's question, confirmation and lines are built in code, in Polish", () => {
  assert.equal(bookingQuestion(table), "Czy mogą Państwo zarezerwować stolik dla 2 osób w piątek 13 listopada o 19:00 na nazwisko Anna Kowalska?");
  assert.equal(bookingConfirmLine(table), "Dobrze, proszę o rezerwację: stolik dla 2 osób, piątek 13 listopada, 19:00, na nazwisko Anna Kowalska.");
  assert.equal(bookingQuestion(haircut), "Czy mogą Państwo zarezerwować strzyżenie męskie we wtorek 17 listopada o 10:30 na nazwisko Jan Nowak?");
  assert.equal(bookingQuestion({ ...table, partySize: 1, service: "kolacja degustacyjna" }),
    "Czy mogą Państwo zarezerwować kolacja degustacyjna dla 1 osoby w piątek 13 listopada o 19:00 na nazwisko Anna Kowalska?");
  assert.equal(bookingLines(haircut), "- Co: strzyżenie męskie\n- Kiedy: wtorek 17 listopada 2026, 10:30\n- Na nazwisko: Jan Nowak");
  assert.match(bookingQuestion({ ...table, date: "2026-11-18" }), / w środę 18 listopada /);
});

test("a booking is today or later and at most 60 days ahead, in Warsaw time", () => {
  const now = new Date("2026-11-12T23:30:00Z"); // already 13 Nov in Warsaw
  assert.equal(bookingDateAllowed({ ...table, date: "2026-11-12" }, now), false);
  assert.equal(bookingDateAllowed({ ...table, date: "2026-11-13" }, now), true);
  assert.equal(bookingDateAllowed({ ...table, date: "2027-01-12" }, now), true);
  assert.equal(bookingDateAllowed({ ...table, date: "2027-01-13" }, now), false);
});

const brief = (over: object) => ({
  callee: { name: "Trattoria Demo", phone: "+48322000001", source: "places" },
  principal: { name: "Anna", genitive: "Anny" },
  goal: "Zarezerwować stolik na kolację.",
  facts: [],
  ...over,
});

test("the brief: a booking needs its details; its question is never written by anyone but the server", () => {
  const ok = briefSchema.safeParse(brief({ kind: "book", booking: table }));
  assert.ok(ok.success);
  assert.equal(ok.data.question, bookingQuestion(table));
  assert.equal(checkBriefContent(ok.data), undefined, "a booking question asks to book by design");
  const fields = (b: object) => { const r = briefSchema.safeParse(b); return r.success ? [] : r.error.issues.map((i) => i.path.join(".")); };
  assert.deepEqual(fields(brief({ kind: "book" })), ["booking"]);
  assert.deepEqual(fields(brief({ kind: "book", booking: table, question: "Czy mogę zapłacić kartą?" })), ["question"]);
  assert.deepEqual(fields(brief({ kind: "ask", question: "Czy mają stolik?", booking: table })), ["booking"]);
  assert.deepEqual(fields(brief({ kind: "book", booking: { ...table, partySize: undefined } })), ["booking.service"]);
  assert.deepEqual(fields(brief({ kind: "book", booking: { ...table, date: "2026-02-30" } })), ["booking.date"]);
  assert.deepEqual(fields(brief({ kind: "book", booking: { ...table, time: "25:00" } })), ["booking.time"]);
  assert.deepEqual(fields(brief({ kind: "book", booking: { ...table, deposit: true } })), ["booking"]);
  // An ask call still may not commit; the old shape without `kind` is still an ask.
  const ask = briefSchema.parse(brief({ question: "Chciałbym zarezerwować stolik" }));
  assert.equal(ask.kind, "ask");
  assert.equal(checkBriefContent(ask)?.reason, "question_commits");
  assert.deepEqual(fields(brief({ kind: "book", booking: { ...table, name: "Anna {{doddy_facts}}" } })), ["booking.name"], "no template braces in a name");
});

// ---------- the result ----------

const facts = (lines: [string, string][], over: Partial<ResultFacts> = {}): ResultFacts => ({
  endReason: "completed", answered: true, voiceConnected: true, takenOverAtSecs: null, durationSecs: 40,
  question: bookingQuestion(table), callbackLine: "Sprawdzę to u Anny i oddzwonię.",
  allowedTexts: [`Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: ${bookingQuestion(table)}`, bookingQuestion(table), bookingConfirmLine(table)],
  transcript: lines.map(([speaker, text]) => ({ speaker: speaker as "doddy" | "callee", text, atSecs: null })),
  source: "elevenlabs", voicemailToolUsed: false, bookingConfirmLine: bookingConfirmLine(table), ...over,
});
const opening = `Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: ${bookingQuestion(table)}`;

test("the confirmation sentence is the one commitment allowed; any other still warns", () => {
  const ok = buildCallResult(facts([["doddy", opening], ["callee", "Tak, mamy wolne o 19."],
    ["doddy", `${bookingConfirmLine(table).toUpperCase()} Dziękuję.`], ["callee", "Zapisane, do zobaczenia."]]));
  assert.equal(ok.bookingConfirmed, true);
  assert.deepEqual(ok.warnings, []);
  const other = buildCallResult(facts([["doddy", opening], ["callee", "Mamy o 20."], ["doddy", "Zgadzam się, biorę 20:00."]]));
  assert.equal(other.bookingConfirmed, false);
  assert.deepEqual(other.warnings.map((w) => w.kind), ["possible_commitment"]);
  const both = buildCallResult(facts([["doddy", opening], ["callee", "Tak."], ["doddy", `${bookingConfirmLine(table)} Zapłacę zaliczkę.`]]));
  assert.equal(both.bookingConfirmed, true);
  assert.deepEqual(both.warnings.map((w) => w.kind), ["possible_commitment"], "the sentence doesn't cover what follows it");
  const ask = buildCallResult(facts([["doddy", opening], ["callee", "Tak."]], { bookingConfirmLine: undefined }));
  assert.equal("bookingConfirmed" in ask, false, "an ask call's result has no booking field");
});

const result = (over: Partial<CallResult>): CallResult => ({
  format: 1, outcome: "answered", source: "elevenlabs", confidence: "high", confidenceReasons: [], summary: "", summaryBy: "rules",
  quote: { text: "Tak, zapisuję.", line: 1 }, transcript: [], nextStep: { kind: "none", text: "" }, warnings: [], callbackPromised: false,
  takenOverAtSecs: null, durationSecs: 30, ...over,
});
const said = (answer: WriterOutput["answer"]): WriterOutput => ({ kind: "answered", answerLine: 1, answerQuote: "x", summary: "", nextStep: "", answer });

test("a booking counts as made only with Doddy's confirmation sentence, the model's yes and a quote", () => {
  assert.equal(answerOf(result({ bookingConfirmed: true }), said("yes"), "book"), "yes");
  assert.equal(answerOf(result({ bookingConfirmed: false }), said("yes"), "book"), "unclear", "they said yes but Doddy never accepted");
  assert.equal(answerOf(result({}), said("yes"), "book"), "unclear");
  assert.equal(answerOf(result({ bookingConfirmed: true }), said("no"), "book"), "unclear", "Doddy accepted; the person must read it, never the next place");
  assert.equal(answerOf(result({ bookingConfirmed: true }), said("unclear"), "book"), "unclear");
  assert.equal(answerOf(result({ bookingConfirmed: false }), said("no"), "book"), "no");
  assert.equal(answerOf(result({ bookingConfirmed: true, warnings: [{ kind: "possible_commitment", line: 3 }] }), said("yes"), "book"), "unclear");
  assert.equal(answerOf(result({}), said("yes")), "yes", "ask calls unchanged");
});

test("the booking agent's own prompt is checked; the ask agent's prompt on it is drift", () => {
  assert.deepEqual(checkAgentSafety(compliantAgent(BOOK_PROMPT, TASK_BOOK_AGENT_ID), TASK_BOOK_AGENT_SPEC), []);
  assert.deepEqual(checkAgentSafety(compliantAgent(), TASK_BOOK_AGENT_SPEC), ["prompt_changed"]);
  assert.deepEqual(checkAgentSafety(compliantAgent(BOOK_PROMPT)), ["prompt_changed"], "and the reverse");
});

// ---------- end to end, with fake providers ----------

/** Stand-in result step: "tak" in the callee's last line is yes. Records what it was given. */
const seen: WriterInput[] = [];
const writer = {
  provider: "anthropic" as const,
  model: "claude-haiku-5-5",
  write: async (input: WriterInput): Promise<WriterOutput> => {
    seen.push(input);
    const lines = input.transcript.map((l, i) => ({ ...l, i })).filter((l) => l.speaker === "callee");
    const last = lines.at(-1)!;
    const answer = last.text.toLowerCase().startsWith("tak") ? "yes" : last.text.toLowerCase().startsWith("nie") ? "no" : "unclear";
    return { kind: "answered", answerLine: last.i, answerQuote: last.text, summary: last.text, nextStep: "", answer };
  },
};

describe("booking calls", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  let seq = 0;
  const phone = () => `+48510${String(300000 + ++seq).slice(-6)}`;
  const dest = () => `+4832${String(3000000 + ++seq).slice(-7)}`;

  async function setup(opts: TaskTestOptions = {}) {
    await db.query("DELETE FROM call_dial_log");
    // Thursday 12 Nov 2026, 11:00 in Warsaw.
    const w = await taskTestApp(db, { writer, start: "2026-11-12T10:00:00Z", ...opts });
    const r = await w.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    await w.app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone: phone(), code: "123456" } });
    await w.app.inject({ method: "PUT", url: "/v1/phone/sms-consent", headers: h, payload: { consent: true, textVersion: "sms-v1" } });
    const api = (method: "GET" | "POST", url: string, payload?: object) => w.app.inject({ method, url, headers: h, ...(payload ? { payload } : {}) });
    const tw = (url: string, form: Record<string, string>) => w.app.inject({
      method: "POST", url, payload: new URLSearchParams(form).toString(),
      headers: { "content-type": "application/x-www-form-urlencoded", "x-twilio-signature": twilioSignature(TASK_AUTH_TOKEN, BASE_URL + url, form) },
    });
    return { ...w, ctx: w.app.taskCallContext!, accountId, api, tw };
  }
  type S = Awaited<ReturnType<typeof setup>>;

  const bookTask = (places: { name: string; phone: string }[], booking: Booking = table) => ({
    kind: "book",
    places: places.map((p) => ({ ...p, source: "places", sourceLabel: "Wyszukiwanie miejsc Doddy" })),
    principal: { name: "Anna", genitive: "Anny" },
    goal: "Zarezerwować stolik na kolację.",
    booking,
    textResult: true,
  });

  async function placeCall(s: S, caseId: string, agentId: string, lines: [string, string][], conv: string) {
    const { rows } = await db.query<{ id: string; twilio_call_sid: string }>(
      "SELECT id, twilio_call_sid FROM call_attempts WHERE case_id = $1 ORDER BY attempt_no DESC LIMIT 1", [caseId]);
    const a = rows[0]!;
    const base = { AccountSid: TASK_ACCOUNT_SID, CallSid: a.twilio_call_sid };
    await s.tw(`/webhooks/twilio/task-call/answer?a=${a.id}`, { ...base, To: s.telephony.created.at(-1)!.to, From: DODDY_FROM });
    await s.tw(`/webhooks/twilio/task-call/status?a=${a.id}`, { ...base, CallStatus: "completed", SequenceNumber: "3", CallDuration: "40" });
    const body = JSON.stringify({ type: "post_call_transcription", data: {
      agent_id: agentId, conversation_id: conv,
      transcript: lines.map(([role, message]) => ({ role: role === "doddy" ? "agent" : "user", message })),
      metadata: { cost: 300 }, conversation_initiation_client_data: { dynamic_variables: { doddy_attempt: a.id } } } });
    const r = await s.app.inject({ method: "POST", url: "/webhooks/elevenlabs/post-call", payload: body,
      headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(EL_WEBHOOK_SECRET, body) } });
    assert.ok(r.statusCode < 300, r.body);
    await processResults(s.ctx);
  }

  async function texts(s: S, taskId: string) {
    const { rows } = await db.query<{ id: string; body_ciphertext: Buffer }>(
      "SELECT id, body_ciphertext FROM outbound_messages WHERE account_id = $1 AND channel = 'sms' AND idempotency_key = $2", [s.accountId, `call-task:${taskId}`]);
    return rows.map((r) => testCipher.decrypt(r.body_ciphertext, bodyAad(s.accountId, r.id)));
  }

  test("without the booking agent set up, a booking is refused and nothing is stored", async () => {
    const s = await setup();
    const r = await s.api("POST", "/v1/call-tasks", bookTask([{ name: "Trattoria Demo", phone: dest() }]));
    assert.equal(r.statusCode, 503, r.body);
    assert.equal(r.json().error, "booking_not_configured");
    assert.equal((await s.api("GET", "/v1/call-cases/availability")).json().booking, false);
    const { rows } = await db.query("SELECT 1 FROM call_tasks WHERE account_id = $1", [s.accountId]);
    assert.equal(rows.length, 0);
    await s.app.close();
  });

  test("one tap books: the booking agent talks, Doddy says the approved sentence, the text says it's booked", async () => {
    seen.length = 0;
    const s = await setup({ bookAgentPrompt: BOOK_PROMPT });
    assert.equal((await s.api("GET", "/v1/call-cases/availability")).json().booking, true);
    const places = [{ name: "Trattoria Uno", phone: dest() }, { name: "Osteria Due", phone: dest() }];
    const created = await s.api("POST", "/v1/call-tasks", bookTask(places));
    assert.equal(created.statusCode, 201, created.body);
    const p = created.json();
    assert.equal(p.kind, "book");
    const card = p.places[0];
    assert.deepEqual(card.booking, table, "the card shows exactly what may be booked");
    assert.equal(card.question, bookingQuestion(table));
    assert.equal(card.confirmLine, bookingConfirmLine(table));
    assert.match(card.forbidden[0], /^Rezerwuje tylko dokładnie to: stolik dla 2 osób, piątek 13 listopada, 19:00, na nazwisko Anna Kowalska\./);
    assert.ok(card.forbidden.some((f: string) => /zaliczki/.test(f)));

    const tap = await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    assert.equal(tap.statusCode, 202, tap.body);

    // The first place: they can only do 20:00. Doddy doesn't accept; the next place is called.
    await placeCall(s, card.caseId, TASK_BOOK_AGENT_ID,
      [["doddy", card.openingLine], ["callee", "Nie, o 19 nie mamy, może 20?"], ["doddy", "Sprawdzę to u Anny i oddzwonię."]], "conv_b1");
    const registered = s.voice.registered.at(-1)!;
    assert.equal(registered.agentId, TASK_BOOK_AGENT_ID, "a booking is talked by the booking agent, never the ask agent");
    assert.equal(registered.variables.doddy_booking_confirm_line, bookingConfirmLine(table));
    assert.equal(registered.variables.doddy_booking, bookingLines(table));
    let t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.equal(t.places[0].answer, "no");
    const { runTaskCallPasses } = await import("../src/taskCalls/worker.js");
    await runTaskCallPasses(s.ctx, { lastSweep: Date.now() });

    await placeCall(s, p.places[1].caseId, TASK_BOOK_AGENT_ID,
      [["doddy", p.places[1].openingLine], ["callee", "Tak, mamy wolne o 19."], ["doddy", bookingConfirmLine(table)], ["callee", "Tak, zapisane na Annę Kowalską."]], "conv_b2");
    t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome, t.outcomePosition], ["finished", "yes", 2]);
    assert.deepEqual(await texts(s, p.taskId), ["Doddy: Osteria Due potwierdza rezerwację: „Tak, zapisane na Annę Kowalską.”. Szczegóły w aplikacji Doddy."]);
    assert.equal(seen.at(-1)!.booking, bookingLines(table), "the result step is told exactly what was to be booked");
    await s.app.close();
  });

  test("a yes Doddy never accepted is not a booking: the task stops for the person to read", async () => {
    const s = await setup({ bookAgentPrompt: BOOK_PROMPT });
    const p = (await s.api("POST", "/v1/call-tasks", bookTask([{ name: "Barber Demo", phone: dest() }, { name: "Barber Dwa", phone: dest() }], haircut))).json();
    await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    await placeCall(s, p.places[0].caseId, TASK_BOOK_AGENT_ID,
      [["doddy", p.places[0].openingLine], ["callee", "Tak, może być."]], "conv_b3");
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome], ["finished", "unclear"]);
    assert.equal(s.telephony.created.length, 1, "the second barber is never called");
    assert.match((await texts(s, p.taskId))[0]!, /nie wiem na pewno, czy rezerwacja jest przyjęta/);
    await s.app.close();
  });

  test("the booking agent drifting stops bookings, not questions; a past day is refused", async () => {
    const s = await setup({ bookAgentPrompt: BOOK_PROMPT });
    s.voice.agentsById.set(TASK_BOOK_AGENT_ID, compliantAgent("changed in the dashboard", TASK_BOOK_AGENT_ID));
    await s.ctx.driftFor("book").refresh();
    assert.equal((await s.api("GET", "/v1/call-cases/availability")).json().booking, false);
    assert.equal((await s.api("GET", "/v1/call-cases/availability")).json().available, true, "ask calls still work");
    const p = (await s.api("POST", "/v1/call-tasks", bookTask([{ name: "Trattoria Demo", phone: dest() }]))).json();
    const tap = await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    assert.equal(tap.statusCode, 409, tap.body);
    assert.deepEqual([tap.json().error, tap.json().gate], ["gate_refused", "agent_drift"]);
    assert.equal(s.telephony.created.length, 0);

    const past = await s.api("POST", "/v1/call-tasks", bookTask([{ name: "Trattoria Demo", phone: dest() }], { ...table, date: "2026-11-11" }));
    assert.equal(past.statusCode, 400);
    assert.deepEqual([past.json().field, past.json().reason], ["places.0.booking.date", "booking_date"]);
    // The ask agent's id never accepts a booking's post-call webhook as its own, and the reverse: matched by attempt only.
    assert.notEqual(TASK_AGENT_ID, TASK_BOOK_AGENT_ID);
    await s.app.close();
  });
});
