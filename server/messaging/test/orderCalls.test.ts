// Food orders by phone (decision docs/decisions/2026-11-12-food-by-phone.md): a separate agent that
// may accept exactly the order on the approved card, by saying one server-built sentence. Payment is
// on delivery or at pickup only; the delivery address is typed on the card and erased with the task.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { bodyAad } from "../src/outbox.js";
import { twilioSignature } from "../src/providers/twilio.js";
import { checkAgentSafety } from "../src/taskCalls/agentSafety.js";
import { TASK_ORDER_AGENT_SPEC } from "../src/taskCalls/agentSpec.js";
import { briefSchema, checkBriefContent } from "../src/taskCalls/brief.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { forbiddenList } from "../src/taskCalls/opening.js";
import { orderConfirmLine, orderLines, orderQuestion, orderSchema, type Order } from "../src/taskCalls/order.js";
import { buildCallResult, type CallResult, type ResultFacts, type WriterInput, type WriterOutput } from "../src/taskCalls/result.js";
import { answerOf } from "../src/taskCalls/tasks.js";
import { processResults } from "../src/taskCalls/worker.js";
import {
  BASE_URL, compliantAgent, dbSkip, DODDY_FROM, EL_WEBHOOK_SECRET, freshDb, ORDER_PROMPT, TASK_ACCOUNT_SID, TASK_AGENT_ID, TASK_AUTH_TOKEN,
  TASK_ORDER_AGENT_ID, taskTestApp, testCipher, type TaskTestOptions,
} from "./helpers.js";

const delivery: Order = {
  name: "Anna Kowalska",
  lines: [{ quantity: 2, name: "pizza margherita", note: "bez cebuli" }, { quantity: 1, name: "cola" }],
  delivery: { street: "ul. Długa 5", apartment: "12", postcode: "00-001", city: "Warszawa", phone: "600 000 000" },
  maxTotalPln: 150,
};
const pickup: Order = { name: "Jan Nowak", lines: [{ quantity: 1, name: "pad thai" }], pickup: true, maxTotalPln: 80 };

// ---------- the sentences, built in code ----------

test("the order's question, confirmation and lines are built in code, in Polish", () => {
  assert.equal(orderQuestion(delivery), "Czy mogą Państwo przyjąć zamówienie z dostawą?");
  assert.equal(orderQuestion(pickup), "Czy mogą Państwo przyjąć zamówienie na odbiór osobisty?");
  assert.equal(orderConfirmLine(delivery),
    "Dobrze, proszę o zamówienie: 2 × pizza margherita (bez cebuli), 1 × cola, dostawa na ul. Długa 5 m. 12, 00-001 Warszawa, płatność gotówką lub kartą przy odbiorze, na nazwisko Anna Kowalska.");
  assert.equal(orderConfirmLine(pickup),
    "Dobrze, proszę o zamówienie: 1 × pad thai, odbiór osobisty, płatność gotówką lub kartą przy odbiorze, na nazwisko Jan Nowak.");
  assert.equal(orderLines(pickup), [
    "- Zamówienie: 1 × pad thai", "- Odbiór osobisty", "- Płatność: gotówką lub kartą przy odbiorze",
    "- Najwyższa łączna kwota: 80 zł", "- Na nazwisko: Jan Nowak"].join("\n"));
  assert.match(orderLines(delivery), /- Dostawa na adres: ul\. Długa 5 m\. 12, 00-001 Warszawa\n- Telefon dla kuriera: 600 000 000\n/);
  assert.ok(!orderQuestion(delivery).includes("Długa"), "the address is not in the question: it is said only after they agree");
});

const brief = (over: object) => ({
  callee: { name: "Pizzeria Demo", phone: "+48322000001", source: "places" },
  principal: { name: "Anna", genitive: "Anny" },
  goal: "Zamówić kolację.",
  facts: [],
  ...over,
});
const fields = (b: object) => { const r = briefSchema.safeParse(b); return r.success ? [] : r.error.issues.map((i) => i.path.join(".")); };

test("the brief: an order needs its details; its question is never written by anyone but the server", () => {
  const ok = briefSchema.safeParse(brief({ kind: "order", order: delivery }));
  assert.ok(ok.success);
  assert.equal(ok.data.question, orderQuestion(delivery));
  assert.equal(checkBriefContent(ok.data), undefined, "the address typed on the card needs no ticked address fact");
  assert.deepEqual(fields(brief({ kind: "order" })), ["order"]);
  assert.deepEqual(fields(brief({ kind: "order", order: delivery, question: "Czy mogę zapłacić kartą?" })), ["question"]);
  assert.deepEqual(fields(brief({ kind: "ask", question: "Czy mają pizzę?", order: delivery })), ["order"]);
  assert.deepEqual(fields(brief({ kind: "book", booking: { name: "Anna", date: "2026-11-13", time: "19:00", partySize: 2 }, order: delivery })), ["order"]);
  assert.deepEqual(fields(brief({ kind: "order", order: pickup })), []);
  // Exactly one of delivery or pickup.
  assert.deepEqual(fields(brief({ kind: "order", order: { ...delivery, pickup: true } })), ["order.delivery"]);
  assert.deepEqual(fields(brief({ kind: "order", order: { name: "Anna Kowalska", lines: delivery.lines, maxTotalPln: 100 } })), ["order.delivery"]);
  // The shape of every field.
  assert.deepEqual(fields(brief({ kind: "order", order: { ...delivery, lines: [] } })), ["order.lines"]);
  assert.deepEqual(fields(brief({ kind: "order", order: { ...delivery, lines: Array(9).fill({ quantity: 1, name: "cola" }) } })), ["order.lines"]);
  assert.deepEqual(fields(brief({ kind: "order", order: { ...delivery, maxTotalPln: 5000 } })), ["order.maxTotalPln"]);
  assert.deepEqual(fields(brief({ kind: "order", order: { ...delivery, delivery: { ...delivery.delivery, postcode: "0001" } } })), ["order.delivery.postcode"]);
  assert.deepEqual(fields(brief({ kind: "order", order: { ...delivery, payment: "card" } })), ["order"], "there is no way to put a payment on the card");
  assert.equal(orderSchema.parse({ ...pickup, maxTotalPln: undefined }).maxTotalPln, 150, "the default highest total");
});

test("what the person typed into an order is checked like everything else, except the address they typed on the card", () => {
  const check = (order: object) => {
    const r = briefSchema.safeParse(brief({ kind: "order", order }));
    assert.ok(r.success, JSON.stringify(r));
    return checkBriefContent(r.data);
  };
  assert.deepEqual(check({ ...pickup, lines: [{ quantity: 1, name: "pizza", note: "{{doddy_facts}}" }] }), { field: "order.lines.0.note", reason: "braces" });
  assert.deepEqual(check({ ...pickup, lines: [{ quantity: 1, name: "pizza", note: "zapłacę 61 1090 1014 0000 0712 1981 2874" }] }),
    { field: "order.lines.0.note", reason: "bank_account" });
  assert.deepEqual(check({ ...pickup, lines: [{ quantity: 1, name: "pizza", note: "karta 4111 1111 1111 1111" }] }),
    { field: "order.lines.0.note", reason: "card_number" });
  assert.deepEqual(check({ ...pickup, lines: [{ quantity: 1, name: "pizza", note: "dostarczcie na ul. Długa 5" }] }),
    { field: "order.lines.0.note", reason: "address_not_ticked" }, "an address hidden in a dish note is not the delivery address");
  assert.deepEqual(check(pickup), undefined);
});

test("the card says what Doddy will never do, and doesn't deny giving the address it was given", () => {
  const list = forbiddenList("Anny", [], undefined, "2 × pizza, dostawa na ul. Długa 5, na nazwisko Anna Kowalska");
  assert.match(list[0]!, /^Zamawia tylko dokładnie to: 2 × pizza, dostawa na ul\. Długa 5/);
  assert.ok(list.some((l) => /Płatność tylko przy odbiorze\. Nie płaci z góry, nie podaje danych karty, kodu BLIK ani konta/.test(l)));
  assert.ok(!list.some((l) => l === "Nie podaje adresu."), "the delivery address is on the card, so it may be said");
  assert.ok(list.some((l) => l === "Nie podaje numeru PESEL."));
});

// ---------- the result ----------

const opening = `Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: ${orderQuestion(delivery)}`;
const facts = (lines: [string, string][], over: Partial<ResultFacts> = {}): ResultFacts => ({
  endReason: "completed", answered: true, voiceConnected: true, takenOverAtSecs: null, durationSecs: 40,
  question: orderQuestion(delivery), callbackLine: "Sprawdzę to u Anny i oddzwonię.",
  allowedTexts: [opening, orderQuestion(delivery), orderConfirmLine(delivery), orderLines(delivery)],
  transcript: lines.map(([speaker, text]) => ({ speaker: speaker as "doddy" | "callee", text, atSecs: null })),
  source: "elevenlabs", voicemailToolUsed: false, bookingConfirmLine: orderConfirmLine(delivery), ...over,
});

test("the order's confirmation sentence is the one commitment allowed; paying in advance still warns", () => {
  const ok = buildCallResult(facts([["doddy", opening], ["callee", "Tak, przyjmujemy."], ["doddy", `${orderConfirmLine(delivery)} Dziękuję.`], ["callee", "Będzie za 40 minut."]]));
  assert.equal(ok.bookingConfirmed, true);
  assert.deepEqual(ok.warnings, []);
  const prepay = buildCallResult(facts([["doddy", opening], ["callee", "Tak."], ["doddy", `${orderConfirmLine(delivery)} Zapłacę kartą z góry.`]]));
  assert.equal(prepay.bookingConfirmed, true);
  assert.deepEqual(prepay.warnings.map((w) => w.kind), ["possible_commitment"], "the sentence doesn't cover what follows it");
  const other = buildCallResult(facts([["doddy", opening], ["callee", "Tylko jedna pizza."], ["doddy", "Zgoda, biorę jedną."]]));
  assert.equal(other.bookingConfirmed, false);
  assert.deepEqual(other.warnings.map((w) => w.kind), ["possible_commitment"]);
});

test("after they take the order Doddy may give the address and the courier's phone, and nothing else with digits", () => {
  const ok = buildCallResult(facts([["doddy", opening], ["callee", "Tak. Adres i telefon?"],
    ["doddy", `${orderConfirmLine(delivery)} Dostawa na ulicę Długą 5 mieszkanie 12, 00-001 Warszawa, telefon dla kuriera 600 000 000.`], ["callee", "Dziękuję."]]));
  assert.deepEqual(ok.warnings, [], "a postcode and a phone number that are on the card are not numbers Doddy wasn't given");
  const wrong = buildCallResult(facts([["doddy", opening], ["callee", "Tak. Jaki telefon?"], ["doddy", "Telefon to 601 222 333."]]));
  assert.deepEqual(wrong.warnings.map((w) => w.kind), ["unlisted_number"], "a number that isn't on the card still warns");
});

test("the courier's phone is a Polish number kept as nine digits, so it is never read as a PESEL", () => {
  const phoneOf = (phone: string) => orderSchema.safeParse({ ...delivery, delivery: { ...delivery.delivery, phone } });
  for (const typed of ["600 000 000", "+48 600 000 000", "0048600000000", "600-000-000", "600000000"]) {
    const r = phoneOf(typed);
    assert.ok(r.success, typed);
    assert.equal(r.data.delivery!.phone, "600 000 000");
  }
  for (const typed of ["12345", "+49 600 000 000", "6000000001", "abc"]) assert.equal(phoneOf(typed).success, false, typed);
});

const result = (over: Partial<CallResult>): CallResult => ({
  format: 1, outcome: "answered", source: "elevenlabs", confidence: "high", confidenceReasons: [], summary: "", summaryBy: "rules",
  quote: { text: "Tak, przyjmujemy.", line: 1 }, transcript: [], nextStep: { kind: "none", text: "" }, warnings: [], callbackPromised: false,
  takenOverAtSecs: null, durationSecs: 30, ...over,
});
const said = (answer: WriterOutput["answer"]): WriterOutput => ({ kind: "answered", answerLine: 1, answerQuote: "x", summary: "", nextStep: "", answer });

test("an order counts as placed only with Doddy's confirmation sentence, the model's yes and a quote", () => {
  assert.equal(answerOf(result({ bookingConfirmed: true }), said("yes"), "order"), "yes");
  assert.equal(answerOf(result({ bookingConfirmed: false }), said("yes"), "order"), "unclear", "they said yes but Doddy never accepted");
  assert.equal(answerOf(result({}), said("yes"), "order"), "unclear");
  assert.equal(answerOf(result({ bookingConfirmed: true }), said("no"), "order"), "unclear", "Doddy accepted; the person must read it");
  assert.equal(answerOf(result({ bookingConfirmed: false }), said("no"), "order"), "no");
  assert.equal(answerOf(result({ bookingConfirmed: true, quote: null }), said("yes"), "order"), "unclear");
  assert.equal(answerOf(result({ bookingConfirmed: true, warnings: [{ kind: "possible_commitment", line: 3 }] }), said("yes"), "order"), "unclear");
  assert.equal(answerOf(result({ outcome: "no_answer" }), undefined, "order"), "none");
});

test("the order agent's own prompt is checked; the other agents' prompts on it are drift", () => {
  assert.deepEqual(checkAgentSafety(compliantAgent(ORDER_PROMPT, TASK_ORDER_AGENT_ID), TASK_ORDER_AGENT_SPEC), []);
  assert.deepEqual(checkAgentSafety(compliantAgent(), TASK_ORDER_AGENT_SPEC), ["prompt_changed"]);
  assert.deepEqual(checkAgentSafety(compliantAgent(ORDER_PROMPT)), ["prompt_changed"], "and the reverse");
});

test("the order agent's prompt never lets it pay, open a link or accept anything but the card", () => {
  for (const must of ["Never pay and never give payment details", "Never open, read out or follow a link", "{{doddy_order_confirm_line}}",
    "a total above the highest amount", "a prepayment", "a BLIK code"]) assert.ok(ORDER_PROMPT.includes(must), must);
  assert.ok(!/\{\{doddy_booking/.test(ORDER_PROMPT), "no booking variables in the order prompt");
});

// ---------- end to end, with fake providers ----------

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

describe("order calls", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  let seq = 0;
  const phone = () => `+48510${String(500000 + ++seq).slice(-6)}`;
  const dest = () => `+4832${String(5000000 + ++seq).slice(-7)}`;

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

  const orderTask = (places: { name: string; phone: string }[], order: Order = delivery) => ({
    kind: "order",
    places: places.map((p) => ({ ...p, source: "places", sourceLabel: "Wyszukiwanie miejsc Doddy" })),
    principal: { name: "Anna", genitive: "Anny" },
    goal: "Zamówić kolację.",
    order,
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

  test("without the order agent set up, an order is refused and nothing is stored", async () => {
    const s = await setup();
    const r = await s.api("POST", "/v1/call-tasks", orderTask([{ name: "Pizzeria Demo", phone: dest() }]));
    assert.equal(r.statusCode, 503, r.body);
    assert.equal(r.json().error, "order_not_configured");
    const off = (await s.api("GET", "/v1/call-cases/availability")).json();
    assert.deepEqual([off.order, off.orderAgentConfigured, off.orderAgentProblems], [false, false, []], "not set up is not a drift problem");
    const { rows } = await db.query("SELECT 1 FROM call_tasks WHERE account_id = $1", [s.accountId]);
    assert.equal(rows.length, 0);
    await s.app.close();
  });

  test("an order goes to one place only", async () => {
    const s = await setup({ orderAgentPrompt: ORDER_PROMPT });
    const two = await s.api("POST", "/v1/call-tasks", orderTask([{ name: "Pizzeria Uno", phone: dest() }, { name: "Pizzeria Due", phone: dest() }]));
    assert.equal(two.statusCode, 400, two.body);
    assert.deepEqual([two.json().error, two.json().fields], ["invalid_request", ["places"]]);
    const { rows } = await db.query("SELECT 1 FROM call_tasks WHERE account_id = $1", [s.accountId]);
    assert.equal(rows.length, 0, "a second restaurant is a second card: Doddy can't order twice");
    await s.app.close();
  });

  test("one tap orders: the order agent talks, Doddy says the approved sentence, the text says it's taken", async () => {
    seen.length = 0;
    const s = await setup({ orderAgentPrompt: ORDER_PROMPT });
    const ready = (await s.api("GET", "/v1/call-cases/availability")).json();
    assert.deepEqual([ready.order, ready.orderAgentConfigured, ready.orderAgentProblems], [true, true, []]);
    const created = await s.api("POST", "/v1/call-tasks", orderTask([{ name: "Pizzeria Uno", phone: dest() }]));
    assert.equal(created.statusCode, 201, created.body);
    const p = created.json();
    assert.equal(p.kind, "order");
    const card = p.places[0];
    assert.deepEqual(card.order, delivery, "the card shows exactly what may be ordered and where it goes");
    assert.equal(card.question, orderQuestion(delivery));
    assert.equal(card.confirmLine, orderConfirmLine(delivery));
    assert.match(card.forbidden[0], /^Zamawia tylko dokładnie to: 2 × pizza margherita \(bez cebuli\), 1 × cola, dostawa na ul\. Długa 5 m\. 12/);
    assert.ok(card.forbidden.some((f: string) => /Płatność tylko przy odbiorze/.test(f)));

    const tap = await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    assert.equal(tap.statusCode, 202, tap.body);
    await placeCall(s, card.caseId, TASK_ORDER_AGENT_ID,
      [["doddy", card.openingLine], ["callee", "Tak, proszę podać zamówienie."], ["doddy", orderConfirmLine(delivery)], ["callee", "Tak, przyjęte, będzie za godzinę."]], "conv_o1");
    const registered = s.voice.registered.at(-1)!;
    assert.equal(registered.agentId, TASK_ORDER_AGENT_ID, "an order is talked by the order agent, never the ask or booking agent");
    assert.equal(registered.variables.doddy_order_confirm_line, orderConfirmLine(delivery));
    assert.equal(registered.variables.doddy_order, orderLines(delivery));
    assert.equal(registered.variables.doddy_booking, undefined);
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome, t.outcomePosition], ["finished", "yes", 1]);
    assert.deepEqual(await texts(s, p.taskId), ["Doddy: Pizzeria Uno przyjmuje zamówienie: „Tak, przyjęte, będzie za godzinę.”. Szczegóły w aplikacji Doddy."]);
    assert.equal(seen.at(-1)!.order, orderLines(delivery), "the result step is told exactly what was to be ordered");
    // The delivery address and phone are erased with the task.
    const { rows } = await db.query<{ payload_ciphertext: Buffer | null }>("SELECT payload_ciphertext FROM call_cases WHERE task_id = $1", [p.taskId]);
    assert.ok(rows.every((r) => r.payload_ciphertext === null), "the brief, with the address, is gone once the task is over");
    await s.app.close();
  });

  test("a yes Doddy never accepted is not an order: the task stops for the person to read", async () => {
    const s = await setup({ orderAgentPrompt: ORDER_PROMPT });
    const p = (await s.api("POST", "/v1/call-tasks", orderTask([{ name: "Bar Demo", phone: dest() }], pickup))).json();
    await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    await placeCall(s, p.places[0].caseId, TASK_ORDER_AGENT_ID,
      [["doddy", p.places[0].openingLine], ["callee", "Tak, może być."]], "conv_o2");
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome], ["finished", "unclear"]);
    assert.match((await texts(s, p.taskId))[0]!, /nie wiem na pewno, czy zamówienie jest przyjęte/);
    await s.app.close();
  });

  test("a refusal ends the task as not ordered, in the text too", async () => {
    const s = await setup({ orderAgentPrompt: ORDER_PROMPT });
    const p = (await s.api("POST", "/v1/call-tasks", orderTask([{ name: "Bar Demo", phone: dest() }], pickup))).json();
    await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    await placeCall(s, p.places[0].caseId, TASK_ORDER_AGENT_ID,
      [["doddy", p.places[0].openingLine], ["callee", "Nie, kuchnia już zamknięta."], ["doddy", "Dziękuję, w takim razie nie zamawiam."]], "conv_o3");
    const t = (await s.api("GET", `/v1/call-tasks/${p.taskId}`)).json();
    assert.deepEqual([t.state, t.outcome], ["finished", "none"]);
    assert.deepEqual(await texts(s, p.taskId), ["Doddy: Bar Demo: zamówienie nie zostało przyjęte. Szczegóły w aplikacji Doddy."]);
    await s.app.close();
  });

  test("the order agent drifting stops orders, not questions or bookings", async () => {
    const s = await setup({ orderAgentPrompt: ORDER_PROMPT });
    s.voice.agentsById.set(TASK_ORDER_AGENT_ID, compliantAgent("changed in the dashboard", TASK_ORDER_AGENT_ID));
    await s.ctx.driftFor("order").refresh();
    const drifted = (await s.api("GET", "/v1/call-cases/availability")).json();
    assert.deepEqual([drifted.order, drifted.orderAgentConfigured, drifted.orderAgentProblems], [false, true, ["prompt_changed"]]);
    assert.deepEqual(drifted.agentProblems, [], "the ask agent is unaffected");
    assert.equal(drifted.available, true, "ask calls still work");
    const p = (await s.api("POST", "/v1/call-tasks", orderTask([{ name: "Pizzeria Demo", phone: dest() }]))).json();
    const tap = await s.api("POST", `/v1/call-tasks/${p.taskId}/approve`, { digest: p.digest });
    assert.equal(tap.statusCode, 409, tap.body);
    assert.deepEqual([tap.json().error, tap.json().gate], ["gate_refused", "agent_drift"]);
    assert.equal(s.telephony.created.length, 0);
    await s.app.close();
  });

  test("the worker checks the order agent too, and the log says whether the live agent matches its spec", async () => {
    const { runTaskCallPasses } = await import("../src/taskCalls/worker.js");
    const s = await setup({ orderAgentPrompt: ORDER_PROMPT });
    assert.deepEqual(s.ctx.driftFor("order").cached(), ["unreadable"], "unknown until read: fails closed");
    await runTaskCallPasses(s.ctx, { lastSweep: 0 });
    assert.deepEqual(s.ctx.driftFor("order").cached(), []);
    const agents = s.logs.filter((l) => l.msg === "task-call agent matches its spec").map((l) => (l.extra as { agent: string }).agent).sort();
    assert.deepEqual(agents, ["ask", "order"]);
    s.voice.agentsById.set(TASK_ORDER_AGENT_ID, compliantAgent("changed in the dashboard", TASK_ORDER_AGENT_ID));
    await runTaskCallPasses(s.ctx, { lastSweep: 0 });
    const differs = s.logs.filter((l) => l.msg === "task-call agent differs from its spec; calls refused");
    assert.deepEqual(differs.map((l) => l.extra), [{ agent: "order", problems: ["prompt_changed"] }]);
    await s.app.close();
  });
});
