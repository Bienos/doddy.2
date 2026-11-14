// "Who and why" in one field (decision docs/decisions/2026-11-13-calls-one-field-brief.md): the model only proposes,
// code checks every field, the number comes from the user's words, and nothing is stored, dialled or logged in words.
// The model is a fake here; nothing reaches Anthropic.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { DEFAULT_TASK_CALL_SETTINGS, type TaskCallSettings } from "../src/config.js";
import type { Db } from "../src/db.js";
import {
  checkDraft, copiedFromText, drafterErrorCode, NUMBER_PLACEHOLDER, numbersFromText, readNumbers, wordsFromText,
  type BriefDrafter, type ProposedBrief,
} from "../src/taskCalls/draft.js";
import {
  dbSkip, DODDY_FROM, EL_WEBHOOK_SECRET, FakeTelephony, FakeVoice, freshDb, TASK_ACCOUNT_SID, TASK_AGENT_ID, TASK_AUTH_TOKEN, testApp,
  VALID_PESEL,
} from "./helpers.js";

const SENTENCE = "Zadzwoń do fryzjera Anna na Długiej, 600 100 200, i zapytaj, czy mają wolne w sobotę o 10:00";

const proposal = (over: Partial<ProposedBrief> = {}): ProposedBrief => ({
  calleeName: "Fryzjer Anna na Długiej",
  goal: "Sprawdzić, czy fryzjer ma wolny termin w sobotę.",
  question: "Czy mają Państwo wolny termin w sobotę o 10:00?",
  facts: [],
  ...over,
});

describe("one-field brief: the number comes from the user's words, never the model", () => {
  test("one number Doddy may call is read and taken out of what the model sees", () => {
    const r = readNumbers(SENTENCE);
    assert.equal(r.phone, "+48600100200");
    assert.equal(r.refusal, undefined);
    assert.ok(r.redacted.includes(NUMBER_PLACEHOLDER));
    assert.ok(!/600|100 200/.test(r.redacted), r.redacted);
    // The hour stays: it's not a number to call.
    assert.ok(r.redacted.includes("10:00"));
  });

  test("however it is typed", () => {
    for (const typed of ["+48 600 100 200", "0048600100200", "600-100-200", "(22) 123 45 67", "+48 (22) 123-45-67", "800 123 456"]) {
      assert.ok(readNumbers(`Zadzwoń pod ${typed} i zapytaj o zamówienie`).phone, typed);
    }
  });

  test("no number: nothing is guessed", () => {
    const r = readNumbers("Zadzwoń do fryzjera Anna i zapytaj o sobotę");
    assert.equal(r.phone, null);
    assert.equal(r.phoneDropped, undefined);
  });

  test("two different numbers: the user picks", () => {
    const r = readNumbers("Zadzwoń pod 600 100 200 albo 22 123 45 67 i zapytaj");
    assert.equal(r.phone, null);
    assert.equal(r.phoneDropped, "several_numbers");
    assert.equal(readNumbers("600100200, czyli 600 100 200").phone, "+48600100200", "the same number twice is one number");
  });

  test("a number Doddy may not call is never the draft's number", () => {
    assert.equal(readNumbers("Zadzwoń pod +44 20 7946 0958").phoneDropped, "foreign");
    assert.equal(readNumbers("Zadzwoń pod 701 234 567").phoneDropped, "premium");
    assert.equal(readNumbers("Zadzwoń pod 600 100 200", { own: "+48600100200" }).phoneDropped, "own_number");
    assert.equal(readNumbers(`Zadzwoń pod ${DODDY_FROM}`, { doddy: DODDY_FROM }).phoneDropped, "doddy_number");
    // Short numbers aren't even read as numbers to call.
    const r = readNumbers("Zadzwoń na 112");
    assert.equal(r.phone, null);
    assert.equal(r.phoneDropped, undefined);
  });

  test("order numbers and dates stay as the user wrote them", () => {
    const r = readNumbers("Zapytaj serwis Bajt o zlecenie 12345 z 14.11.2026");
    assert.equal(r.phone, null);
    assert.ok(r.redacted.includes("12345") && r.redacted.includes("14.11.2026"));
  });

  test("a PESEL, card or account number stops the draft before any model sees the words", () => {
    assert.equal(readNumbers(`Zadzwoń do przychodni, mój PESEL to ${VALID_PESEL}`).refusal, "pesel_not_ticked");
    assert.equal(readNumbers("Zapłać kartą 4111 1111 1111 1111").refusal, "card_number");
    assert.equal(readNumbers("Konto PL61 1090 1014 0000 0712 1981 2874").refusal, "bank_account");
  });
});

describe("one-field brief: code checks every proposed field", () => {
  const input = { text: SENTENCE, phone: "+48600100200" };

  test("a good proposal passes unchanged, with the number from the words", () => {
    const d = checkDraft(proposal(), input);
    assert.deepEqual(d.callee, { name: "Fryzjer Anna na Długiej", phone: "+48600100200", source: "typed" });
    assert.equal(d.question, "Czy mają Państwo wolny termin w sobotę o 10:00?");
    assert.deepEqual(d.missing, []);
    assert.deepEqual(d.dropped, []);
  });

  test("missing fields are reported as missing, not filled in", () => {
    const d = checkDraft({ calleeName: null, goal: null, question: null, facts: [] }, { text: "Zadzwoń i zapytaj", phone: null });
    assert.deepEqual(d.missing, ["callee.name", "callee.phone", "goal", "question"]);
    assert.deepEqual(d.callee, { name: null, phone: null, source: null });
  });

  test("a name made of words the user didn't write is dropped", () => {
    const d = checkDraft(proposal({ calleeName: "Salon Fryzjerski Anna" }), input);
    assert.equal(d.callee.name, null);
    assert.deepEqual(d.dropped, [{ field: "callee.name", reason: "not_from_text" }]);
    assert.ok(d.missing.includes("callee.name"));
    // The picked contact's name counts as the user's words.
    const picked = checkDraft(proposal({ calleeName: "Anna Kowalska" }), { text: "Zapytaj Annę, czy jutro pracuje", contactName: "Anna Kowalska", phone: null });
    assert.equal(picked.callee.name, "Anna Kowalska");
  });

  test("Polish endings are the user's words", () => {
    assert.ok(wordsFromText("Fryzjer Anna na Długiej", [SENTENCE]));
    assert.ok(wordsFromText("Serwis Bajt", ["zapytaj w serwisie Bajt"]));
    assert.ok(!wordsFromText("Gabinet Ząbek", ["zadzwoń do dentysty Ząbek"]));
  });

  test("a question that agrees, books or pays is dropped; Doddy only asks", () => {
    const d = checkDraft(proposal({ question: "Proszę zarezerwować termin w sobotę o 10:00?" }), input);
    assert.equal(d.question, null);
    assert.deepEqual(d.dropped, [{ field: "question", reason: "question_commits" }]);
    assert.equal(checkDraft(proposal({ question: "Mają Państwo wolne w sobotę." }), input).dropped[0]?.reason, "not_a_question");
  });

  test("a number, hour or date the user didn't write is dropped", () => {
    assert.ok(numbersFromText("o 10:00", SENTENCE));
    assert.ok(!numbersFromText("o 15:00", SENTENCE));
    const d = checkDraft(proposal({ question: "Czy mają Państwo wolny termin w sobotę o 15:00?" }), input);
    assert.deepEqual(d.dropped, [{ field: "question", reason: "not_from_text" }]);
    const placeholder = checkDraft(proposal({ goal: `Zadzwonić pod ${NUMBER_PLACEHOLDER}.` }), input);
    assert.deepEqual(placeholder.dropped, [{ field: "goal", reason: "not_from_text" }]);
  });

  test("the brief's own rules hold: braces, length, an address outside a fact", () => {
    assert.equal(checkDraft(proposal({ goal: "Sprawdzić {{termin}}." }), input).dropped[0]?.reason, "braces");
    assert.equal(checkDraft(proposal({ goal: "a".repeat(161) }), input).dropped[0]?.reason, "too_long");
    assert.equal(checkDraft(proposal({ calleeName: "Fryzjer Anna, ul. Długa" }), { ...input, text: "fryzjer Anna ul. Długa" }).dropped[0]?.reason,
      "address_not_ticked");
  });

  test("details must be copied from the words; an address is marked as one", () => {
    const text = "Zapytaj serwis Bajt, czy laptop ze zlecenia 12345 jest gotowy, odbiór ul. Polna 3";
    const d = checkDraft(proposal({
      calleeName: "Serwis Bajt", question: "Czy laptop jest gotowy?", goal: "Sprawdzić laptop.",
      facts: [
        { kind: "reference", text: "zlecenia 12345" },
        { kind: "general", text: "ul. Polna 3" },
        { kind: "general", text: "klient VIP" },
        { kind: "reference", text: "Zlecenia 12345" },
      ],
    }), { text, phone: null });
    assert.deepEqual(d.facts, [{ kind: "reference", text: "zlecenia 12345" }, { kind: "address", text: "ul. Polna 3" }]);
    assert.deepEqual(d.dropped, [{ field: "facts.2", reason: "not_from_text" }, { field: "facts.3", reason: "duplicate_fact" }]);
    assert.ok(copiedFromText("ZLECENIA  12345", text));
  });

  test("at most five details", () => {
    const text = "a1 b2 c3 d4 e5 f6 zadzwoń";
    const facts = ["a1", "b2", "c3", "d4", "e5", "f6"].map((t) => ({ kind: "general", text: t }));
    const d = checkDraft(proposal({ calleeName: null, goal: null, question: null, facts }), { text, phone: null });
    assert.equal(d.facts.length, 5);
    assert.deepEqual(d.dropped, [{ field: "facts.5", reason: "too_many_facts" }]);
  });

  test("a number Doddy can't call is reported with its reason", () => {
    const d = checkDraft(proposal(), { text: SENTENCE, phone: null, phoneDropped: "premium" });
    assert.deepEqual(d.dropped, [{ field: "callee.phone", reason: "premium" }]);
    assert.ok(d.missing.includes("callee.phone"));
  });

  test("a drafter error is logged as a code, never a provider's text", () => {
    assert.equal(drafterErrorCode(new Error("drafter_api_529")), "drafter_api_529");
    assert.equal(drafterErrorCode(new Error("Could not parse: Zadzwoń do fryzjera…")), "drafter_error");
    assert.equal(drafterErrorCode("boom"), "drafter_error");
  });
});

class FakeDrafter implements BriefDrafter {
  readonly provider = "anthropic" as const;
  readonly model = "fake";
  seen: { text: string; contactName?: string }[] = [];
  next: ProposedBrief | Error = proposal();
  async draft(input: { text: string; contactName?: string }): Promise<ProposedBrief> {
    this.seen.push(input);
    if (this.next instanceof Error) throw this.next;
    return this.next;
  }
}

describe("POST /v1/call-cases/draft against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  let phoneSeq = 0;

  async function world(opts: { drafter?: BriefDrafter; settings?: Partial<TaskCallSettings> } = {}) {
    const settings: TaskCallSettings = { ...DEFAULT_TASK_CALL_SETTINGS, ...opts.settings };
    const logs: { msg: string; extra?: object }[] = [];
    const { app } = await testApp(db, {
      taskCalls: {
        telephony: new FakeTelephony(), voice: new FakeVoice(), settings, drafter: opts.drafter,
        config: {
          twilioAccountSid: TASK_ACCOUNT_SID, twilioAuthToken: TASK_AUTH_TOKEN, fromNumber: DODDY_FROM,
          elevenLabsApiKey: "test", agentId: TASK_AGENT_ID, webhookSecret: EL_WEBHOOK_SECRET,
        },
      },
      taskCallLog: (msg, extra) => logs.push({ msg, extra }),
    });
    return { app, logs };
  }

  async function user(app: Awaited<ReturnType<typeof world>>["app"], verified = true) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    if (verified) {
      const phone = `+48510${String(100000 + ++phoneSeq).slice(-6)}`;
      const v = await app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone, code: "123456" } });
      assert.equal(v.statusCode, 200);
    }
    return { accountId, h };
  }

  const post = (app: Awaited<ReturnType<typeof world>>["app"], h: object, payload: unknown) =>
    app.inject({ method: "POST", url: "/v1/call-cases/draft", headers: h as Record<string, string>, payload: payload as never });

  test("returns a checked draft; the model never sees the number; nothing is stored or dialled; logs have no words", async () => {
    const drafter = new FakeDrafter();
    const { app, logs } = await world({ drafter });
    const { accountId, h } = await user(app);
    const r = await post(app, h, { text: SENTENCE });
    assert.equal(r.statusCode, 200, r.body);
    const body = r.json();
    assert.deepEqual(body.callee, { name: "Fryzjer Anna na Długiej", phone: "+48600100200", source: "typed" });
    assert.deepEqual(body.missing, []);
    assert.equal(drafter.seen.length, 1);
    assert.ok(!/\d{3}\s?\d{3}\s?\d{3}/.test(drafter.seen[0]!.text), "no phone number reaches the model");
    const { rows } = await db.query("SELECT 1 FROM call_cases WHERE account_id = $1", [accountId]);
    assert.equal(rows.length, 0, "a draft is not a case");
    const logged = JSON.stringify(logs);
    assert.ok(logs.some((l) => l.msg === "call brief drafted"));
    for (const word of ["fryzjer", "Długiej", "sobotę", "600", "Anna"]) assert.ok(!logged.includes(word), `log holds "${word}"`);
    await app.close();
  });

  test("a model that proposes something code refuses gets it dropped, not sent", async () => {
    const drafter = new FakeDrafter();
    drafter.next = proposal({ calleeName: "Salon Anna", question: "Proszę zarezerwować sobotę o 10:00?" });
    const { app } = await world({ drafter });
    const { h } = await user(app);
    const body = (await post(app, h, { text: SENTENCE, contactName: "Anna Fryzjer" })).json();
    assert.equal(body.callee.name, null);
    assert.equal(body.question, null);
    assert.deepEqual(body.missing, ["callee.name", "question"]);
    assert.deepEqual(drafter.seen[0]!.contactName, "Anna Fryzjer");
    await app.close();
  });

  test("a PESEL in the words is refused before the model is asked", async () => {
    const drafter = new FakeDrafter();
    const { app, logs } = await world({ drafter });
    const { h } = await user(app);
    const r = await post(app, h, { text: `Zadzwoń do przychodni, PESEL ${VALID_PESEL}` });
    assert.equal(r.statusCode, 400);
    assert.deepEqual(r.json(), { error: "brief_refused", field: "text", reason: "pesel_not_ticked" });
    assert.equal(drafter.seen.length, 0);
    assert.ok(!JSON.stringify(logs).includes(VALID_PESEL));
    await app.close();
  });

  test("a failed model answers 502 and logs a code only", async () => {
    const drafter = new FakeDrafter();
    drafter.next = new Error("drafter_api_529");
    const { app, logs } = await world({ drafter });
    const { h } = await user(app);
    const r = await post(app, h, { text: SENTENCE });
    assert.equal(r.statusCode, 502);
    assert.deepEqual(r.json(), { error: "draft_failed" });
    assert.deepEqual(logs.find((l) => l.msg === "call brief draft failed")?.extra, { error: "drafter_api_529" });
    await app.close();
  });

  test("strict body: a number, facts or anything else can't ride along", async () => {
    const { app } = await world({ drafter: new FakeDrafter() });
    const { h } = await user(app);
    assert.equal((await post(app, h, { text: SENTENCE, phone: "+48600100200" })).statusCode, 400);
    assert.equal((await post(app, h, { text: "hej" })).statusCode, 400, "too short to be who and why");
    assert.equal((await post(app, h, { text: "a".repeat(401) })).statusCode, 400);
    await app.close();
  });

  test("off, unconfigured or unverified: no model call", async () => {
    const drafter = new FakeDrafter();
    const off = await world({ drafter, settings: { killSwitch: true } });
    assert.deepEqual((await post(off.app, (await user(off.app)).h, { text: SENTENCE })).json(), { error: "calls_disabled" });
    await off.app.close();

    const noModel = await world();
    const r = await post(noModel.app, (await user(noModel.app)).h, { text: SENTENCE });
    assert.equal(r.statusCode, 503);
    assert.deepEqual(r.json(), { error: "drafter_not_configured" });
    await noModel.app.close();

    const unverified = await world({ drafter });
    const u = await post(unverified.app, (await user(unverified.app, false)).h, { text: SENTENCE });
    assert.equal(u.statusCode, 409);
    assert.deepEqual(u.json(), { error: "no_verified_phone" });
    await unverified.app.close();

    const { app } = await testApp(db);
    const anon = await app.inject({ method: "POST", url: "/v1/accounts" });
    const token = (anon.json() as { deviceToken: string }).deviceToken;
    assert.equal((await post(app, { authorization: `Bearer ${token}` }, { text: SENTENCE })).statusCode, 503, "no task calls: not_configured");
    await app.close();
    assert.equal(drafter.seen.length, 0);
  });

  test("needs a device token", async () => {
    const { app } = await world({ drafter: new FakeDrafter() });
    assert.equal((await post(app, {}, { text: SENTENCE })).statusCode, 401);
    await app.close();
  });
});
