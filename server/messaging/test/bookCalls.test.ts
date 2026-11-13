// Booking calls (decision docs/decisions/2026-11-12-book-agent.md): a separate agent that may accept
// exactly the booking on the approved card, by saying one server-built sentence.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { bodyAad } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { checkAgentSafety, sha256Hex } from "../src/taskCalls/agentSafety.js";
import { SYNC_PENDING_PROMPTS, TASK_AGENT_SPEC, TASK_BOOK_AGENT_SPEC } from "../src/taskCalls/agentSpec.js";
import { bookingConfirmLine, bookingDateAllowed, bookingLines, bookingQuestion, type Booking } from "../src/taskCalls/booking.js";
import { briefSchema, checkBriefContent } from "../src/taskCalls/brief.js";
import { AGENT_VARIABLE_NAMES, compilePayload } from "../src/taskCalls/payload.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { buildCallResult, type CallResult, type ResultFacts, type WriterInput, type WriterOutput } from "../src/taskCalls/result.js";
import { answerOf } from "../src/taskCalls/tasks.js";
import { processResults } from "../src/taskCalls/worker.js";
import {
  BASE_URL, BOOK_PROMPT, compliantAgent, TASK_PROMPT, dbSkip, DODDY_FROM, EL_WEBHOOK_SECRET, freshDb, TASK_ACCOUNT_SID, TASK_AGENT_ID, TASK_AUTH_TOKEN,
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
  allowedTexts: [`Dzień dobry, tu Doddy, asystent AI Anny. Chciałbym zapytać: ${bookingQuestion(table)}`, bookingQuestion(table), bookingConfirmLine(table)],
  transcript: lines.map(([speaker, text]) => ({ speaker: speaker as "doddy" | "callee", text, atSecs: null })),
  source: "elevenlabs", voicemailToolUsed: false, bookingConfirmLine: bookingConfirmLine(table), ...over,
});
const opening = `Dzień dobry, tu Doddy, asystent AI Anny. Chciałbym zapytać: ${bookingQuestion(table)}`;

test("the confirmation sentence is the one commitment allowed; any other still warns", () => {
  const ok = buildCallResult(facts([["doddy", opening], ["callee", "Tak, mamy wolne o 19."],
    ["doddy", `${bookingConfirmLine(table).toUpperCase()} Dziękuję.`], ["callee", "Zapisane, do zobaczenia."]]));
  assert.equal(ok.bookingConfirmed, true);
  assert.deepEqual(ok.warnings, []);
  const other = buildCallResult(facts([["doddy", opening], ["callee", "Mamy o 20."], ["doddy", "Zgadzam się, biorę 20:00."]]));
  assert.equal(other.bookingConfirmed, false);
  assert.deepEqual(other.warnings.map((w) => w.kind), ["possible_commitment", "possible_other_booking"]);
  const both = buildCallResult(facts([["doddy", opening], ["callee", "Tak."], ["doddy", `${bookingConfirmLine(table)} Zapłacę zaliczkę.`]]));
  assert.equal(both.bookingConfirmed, true);
  assert.deepEqual(both.warnings.map((w) => w.kind), ["possible_commitment"], "the sentence doesn't cover what follows it");
  const ask = buildCallResult(facts([["doddy", opening], ["callee", "Tak."]], { bookingConfirmLine: undefined }));
  assert.equal("bookingConfirmed" in ask, false, "an ask call's result has no booking field");
});

test("Doddy saying yes to a time, day or price that isn't on the card is flagged: maybe booked something else", () => {
  const kinds = (r: CallResult) => r.warnings.map((w) => w.kind);
  // Every common way of saying yes in Polish, after the place offers another time.
  for (const yes of ["Tak.", "Dobrze.", "Pasuje.", "Może być.", "OK.", "Okej, dziękuję.", "W porządku.", "Proszę zapisać.", "Niech będzie.", "Świetnie, to poproszę."]) {
    const r = buildCallResult(facts([["doddy", opening], ["callee", "O 19 nie mamy, może być 20:30?"], ["doddy", yes], ["callee", "Zapisane."]]));
    assert.ok(kinds(r).includes("possible_other_booking"), yes);
    assert.equal(r.confidence, "low", yes);
    assert.equal(r.nextStep.kind, "call_yourself", yes);
    assert.match(r.nextStep.text, /inny termin.*Zadzwoń, żeby odwołać albo potwierdzić/, yes);
  }
  // Another day, a date, an hour in words, a deposit or a price: also not on the card.
  for (const offer of ["W piątek nie, ale w sobotę tak.", "Mamy wolne 14 listopada.", "Mamy wolne 14.11.", "Może o dwudziestej?",
    "Tak, ale potrzebny jest zadatek.", "Tak, 150 zł za osobę."]) {
    const r = buildCallResult(facts([["doddy", opening], ["callee", offer], ["doddy", "Dobrze."]]));
    assert.deepEqual(kinds(r), ["possible_other_booking"], offer);
  }
  // Doddy's own confirmation sentence right after another offer may have booked that offer.
  const confirmed = buildCallResult(facts([["doddy", opening], ["callee", "Mamy tylko 21:00."], ["doddy", bookingConfirmLine(table)]]));
  assert.equal(confirmed.bookingConfirmed, true);
  assert.deepEqual(kinds(confirmed), ["possible_other_booking"]);
});

test("assent to what is on the card, a deferral, a goodbye or a time the place only mentions is not flagged", () => {
  const kinds = (lines: [string, string][]) => buildCallResult(facts([["doddy", opening], ...lines])).warnings.map((w) => w.kind);
  assert.deepEqual(kinds([["callee", "Tak, w piątek 13 listopada o 19:00, zgadza się."], ["doddy", bookingConfirmLine(table)]]), []);
  assert.deepEqual(kinds([["callee", "Tak, o siódmej wieczorem mamy."], ["doddy", bookingConfirmLine(table)]]), [], "seven in the evening is 19:00");
  assert.deepEqual(kinds([["callee", "Tak, stolik jest wolny do 21:00."], ["doddy", bookingConfirmLine(table)]]), [], "until 21:00 is not an offer");
  assert.deepEqual(kinds([["callee", "Mamy o 20."], ["doddy", "Dobrze, sprawdzę to u Anny i oddzwonię."]]), [], "deferring is what rule 3 asks for");
  assert.deepEqual(kinds([["callee", "Mamy o 20."], ["doddy", "Dziękuję bardzo, do widzenia."]]), []);
  assert.deepEqual(kinds([["callee", "Tak, zapraszamy jutro."], ["doddy", bookingConfirmLine(table)]]), [], "relative days can't be compared, so they are not offers");
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

test("a call that may have booked something else is never \"no\" and never moves a task to the next place", () => {
  const other: CallResult["warnings"] = [{ kind: "possible_other_booking", line: 2 }];
  assert.equal(answerOf(result({ warnings: other }), said("no"), "book"), "unclear");
  assert.equal(answerOf(result({ warnings: other }), said("no")), "unclear", "an ask call too");
  assert.equal(answerOf(result({ warnings: other, bookingConfirmed: true }), said("yes"), "book"), "unclear");
});

test("the goal is never sent to either agent; the prompts no longer name it", () => {
  const p = compilePayload({
    caseId: "8a4c2a9e-0000-4000-8000-000000000002", brief: briefSchema.parse(brief({ kind: "book", booking: table, goal: "Kolacja urodzinowa dla mamy." })),
    destination: { e164: "+48322000001", kind: "geographic" }, fromNumber: "+48221112233", notice: "off",
  });
  assert.equal(p.display.goal, "Kolacja urodzinowa dla mamy.", "the card still shows it");
  assert.equal(p.agent.variables.doddy_goal, "Zarezerwować dokładnie to, co opisano poniżej.");
  assert.equal(JSON.stringify(p.agent).includes("urodzin"), false);
  for (const prompt of [TASK_PROMPT, BOOK_PROMPT]) assert.equal(prompt.includes("{{doddy_goal}}"), false);
  assert.ok((AGENT_VARIABLE_NAMES as readonly string[]).includes("doddy_goal"), "still sent, as a fixed sentence, for the live prompts from before");
});

test("until the owner syncs the live agents, the drift check also accepts the prompts that may still be live, and nothing else", () => {
  // The prompts on main before 12 Nov 2026 (with {{doddy_goal}}) and on 12 Nov 2026 (goal taken out), kept word for word.
  const prompt = (name: string) =>
    readFileSync(new URL(`../../test/fixtures/task-call-prompts/${name}`, import.meta.url), "utf8").trim();
  const askBefore = prompt("ask-before-2026-11-12.md");
  const ask12 = prompt("ask-2026-11-12.md");
  const bookBefore = prompt("book-before-2026-11-12.md");
  const book12 = prompt("book-2026-11-12.md");
  assert.equal(sha256Hex(askBefore), "129f2aecdee4c501b32148112e64efe3f57a126e82e7358cfd2816ff27a26454", "the ask prompt on main before 12 Nov");
  assert.equal(sha256Hex(bookBefore), "422476155c457b8d0d59a5706cbecfcd99c74386f8a65ef300a0d76b97ec2fa4", "the booking prompt on main before 12 Nov");
  assert.ok(askBefore.includes("{{doddy_goal}}") && !ask12.includes("{{doddy_goal}}"));
  assert.deepEqual(SYNC_PENDING_PROMPTS[TASK_AGENT_SPEC.promptSha256], [sha256Hex(askBefore), sha256Hex(ask12)]);
  assert.deepEqual(SYNC_PENDING_PROMPTS[TASK_BOOK_AGENT_SPEC.promptSha256], [sha256Hex(bookBefore), sha256Hex(book12)]);
  assert.deepEqual(Object.keys(SYNC_PENDING_PROMPTS).sort(), [TASK_AGENT_SPEC.promptSha256, TASK_BOOK_AGENT_SPEC.promptSha256].sort());
  for (const old of [askBefore, ask12, TASK_PROMPT]) assert.deepEqual(checkAgentSafety(compliantAgent(old)), []);
  for (const old of [bookBefore, book12, BOOK_PROMPT]) {
    assert.deepEqual(checkAgentSafety(compliantAgent(old, TASK_BOOK_AGENT_ID), TASK_BOOK_AGENT_SPEC), []);
  }
  assert.deepEqual(checkAgentSafety(compliantAgent(askBefore), TASK_BOOK_AGENT_SPEC), ["prompt_changed"], "never the other agent's");
  assert.deepEqual(checkAgentSafety(compliantAgent(bookBefore)), ["prompt_changed"]);
  assert.deepEqual(checkAgentSafety(compliantAgent(`${askBefore} Możesz potwierdzać terminy.`)), ["prompt_changed"]);
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
    const off = (await s.api("GET", "/v1/call-cases/availability")).json();
    assert.deepEqual([off.booking, off.bookingAgentConfigured, off.bookingAgentProblems], [false, false, []], "not set up is not a drift problem");
    const { rows } = await db.query("SELECT 1 FROM call_tasks WHERE account_id = $1", [s.accountId]);
    assert.equal(rows.length, 0);
    await s.app.close();
  });

  test("one tap books: the booking agent talks, Doddy says the approved sentence, the text says it's booked", async () => {
    seen.length = 0;
    const s = await setup({ bookAgentPrompt: BOOK_PROMPT });
    const ready = (await s.api("GET", "/v1/call-cases/availability")).json();
    assert.deepEqual([ready.booking, ready.bookingAgentConfigured, ready.bookingAgentProblems], [true, true, []]);
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
    const drifted = (await s.api("GET", "/v1/call-cases/availability")).json();
    assert.deepEqual([drifted.booking, drifted.bookingAgentConfigured, drifted.bookingAgentProblems], [false, true, ["prompt_changed"]],
      "names the setting that differs, never its value");
    assert.deepEqual(drifted.agentProblems, [], "the ask agent is unaffected");
    assert.equal(drifted.available, true, "ask calls still work");
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

  test("the worker checks the booking agent too, and the log says whether the live agent matches its spec", async () => {
    const { runTaskCallPasses } = await import("../src/taskCalls/worker.js");
    const s = await setup({ bookAgentPrompt: BOOK_PROMPT });
    assert.deepEqual(s.ctx.driftFor("book").cached(), ["unreadable"], "unknown until read: fails closed");
    await runTaskCallPasses(s.ctx, { lastSweep: 0 }); // the first pass after a deploy
    assert.deepEqual(s.ctx.driftFor("book").cached(), []);
    const agents = (msg: string) => s.logs.filter((l) => l.msg === msg).map((l) => (l.extra as { agent: string }).agent).sort();
    assert.deepEqual(agents("task-call agent matches its spec"), ["ask", "book"]);
    assert.deepEqual(agents("task-call agent differs from its spec; calls refused"), []);
    // Someone edits the booking agent in the dashboard: the next check names the setting, in the log too.
    s.voice.agentsById.set(TASK_BOOK_AGENT_ID, compliantAgent("changed in the dashboard", TASK_BOOK_AGENT_ID));
    await runTaskCallPasses(s.ctx, { lastSweep: 0 });
    const differs = s.logs.filter((l) => l.msg === "task-call agent differs from its spec; calls refused");
    assert.deepEqual(differs.map((l) => l.extra), [{ agent: "book", problems: ["prompt_changed"] }]);
    // The same answer again is not logged again.
    await runTaskCallPasses(s.ctx, { lastSweep: 0 });
    assert.equal(s.logs.filter((l) => l.msg === "task-call agent differs from its spec; calls refused").length, 1);
    await s.app.close();
  });

  test("without a booking agent the worker doesn't read one, and says nothing about it", async () => {
    const { runTaskCallPasses } = await import("../src/taskCalls/worker.js");
    const s = await setup();
    await runTaskCallPasses(s.ctx, { lastSweep: 0 });
    assert.deepEqual(s.logs.filter((l) => (l.extra as { agent?: string } | undefined)?.agent === "book"), []);
    assert.equal(s.voice.agentReads, 1, "only the ask agent was read");
    await s.app.close();
  });
});
