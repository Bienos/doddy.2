import assert from "node:assert/strict";
import { test } from "node:test";
import { buildCallReport, groundedNarrative } from "../src/taskCalls/report.js";
import { buildCallResult, normalizedTranscript, type ResultFacts } from "../src/taskCalls/result.js";
import { answerOf } from "../src/taskCalls/tasks.js";

const transcript = [
  { speaker: "doddy" as const, text: "Potwierdzam wizytę w piątek za 100 zł.", atSecs: 1 },
  { speaker: "callee" as const, text: "Może w piątek o 14:30. Cena wynosi 120 zł. Zadzwonię po sprawdzeniu grafiku.", atSecs: 8 },
];
const candidate = { kind: "time" as const, value: "14:30", quote: "w piątek o 14:30", line: 1, uncertain: false };

test("report preserves spoken dates, prices, evidence indexes and actual timestamps; uncertainty uses the whole line", () => {
  const report = buildCallReport("Termin wizyty u dentysty", "answered", transcript, [candidate,
    { kind: "price", value: "120 zł", quote: "Cena wynosi 120 zł.", line: 1, uncertain: false }]);
  assert.equal(report.domain, "appointment");
  assert.deepEqual(report.facts.map((f) => f.value), ["14:30", "120 zł"]);
  assert.equal(report.facts[0]!.certainty, "uncertain", "cropping 'maybe' out of the quote cannot hide it");
  assert.equal(report.facts[0]!.evidence.atSecs, 8);
  assert.equal(report.verification.rejected, 0);
  assert.deepEqual(report.verification.uncoveredLines, []);
});

test("fabricated prices, normalized dates, assistant commitments and false agreement labels are rejected", () => {
  const report = buildCallReport("Dentist", "answered", transcript, [
    { ...candidate, kind: "price", value: "100 zł" },
    { ...candidate, kind: "date", value: "2026-11-20" },
    { kind: "commitment", value: "Potwierdzam", quote: transcript[0]!.text, line: 0, uncertain: false },
    { ...candidate, kind: "commitment" },
    { ...candidate, line: 999 },
  ]);
  assert.equal(report.facts.length, 0);
  assert.equal(report.verification.rejected, 5);
  assert.deepEqual(report.verification.uncoveredLines, [1]);
});

test("only an explicit callee commitment is reported, never upgraded to a booking receipt", () => {
  const lines = [{ speaker: "callee" as const, text: "Potwierdzam termin na piątek.", atSecs: 14 }];
  const report = buildCallReport("Appointment", "answered", lines, [
    { kind: "commitment", value: "termin na piątek", quote: lines[0]!.text, line: 0, uncertain: false }]);
  assert.equal(report.facts[0]!.certainty, "reported");
  assert.equal(report.outcome, "answered");
  assert.equal("bookingConfirmed" in report, false);
});

test("unverified free-form summaries cannot replace a source excerpt", () => {
  assert.equal(groundedNarrative("The appointment is booked for Friday for 100 zł", transcript), undefined);
  const facts: ResultFacts = { endReason: null, answered: true, voiceConnected: true, takenOverAtSecs: null,
    durationSecs: 20, question: "Kiedy są terminy?", callbackLine: "Sprawdzę to u Anny i oddzwonię.",
    allowedTexts: [], transcript, source: "elevenlabs", voicemailToolUsed: false,
    writer: { kind: "answered", answerLine: 1, answerQuote: "w piątek o 14:30", summary: "Rezerwacja za 100 zł potwierdzona.", nextStep: "Zapłać 100 zł.", answer: "yes" } };
  const result = buildCallResult(facts);
  assert.equal(result.summaryBy, "rules");
  assert.equal(result.summary.includes("100 zł"), false);
  assert.notEqual(result.nextStep.text, "Zapłać 100 zł.");
  assert.ok(result.confidenceReasons.includes("hedged_answer"));
  assert.ok(result.confidenceReasons.includes("model_summary_unverified"));
});

test("normalization produces stable model/report indexes, and reports have bounded source-only content", () => {
  const lines = normalizedTranscript([{ speaker: "callee", text: "   ", atSecs: 1 }, ...transcript]);
  assert.equal(lines[1]!.text, transcript[1]!.text);
  const report = buildCallReport("Restaurant availability", "answered", lines, Array.from({ length: 40 }, () => candidate));
  assert.equal(report.domain, "restaurant");
  assert.equal(report.facts.length, 1);
  assert.ok(report.verification.rejected >= 24);
});

test("an uncertain yes or ungrounded no cannot complete a task or trigger the next call", () => {
  const writer = { kind: "answered" as const, answerLine: 1, answerQuote: "w piątek", summary: "w piątek", nextStep: "", answer: "yes" as const };
  const f: ResultFacts = { endReason: "completed", answered: true, voiceConnected: true, takenOverAtSecs: null,
    durationSecs: 20, question: "Czy jest termin?", callbackLine: "Oddzwonię po sprawdzeniu.", allowedTexts: ["Czy jest termin?"],
    transcript: [{ speaker: "doddy", text: "Czy jest termin?", atSecs: 0 }, { speaker: "callee", text: "Może w piątek, muszę sprawdzić.", atSecs: 4 }],
    source: "elevenlabs", voicemailToolUsed: false, writer };
  assert.equal(answerOf(buildCallResult(f), writer), "unclear");
  const falseNo = { ...writer, answer: "no" as const, answerQuote: "Nie ma terminów" };
  assert.equal(answerOf(buildCallResult({ ...f, writer: falseNo }), falseNo), "unclear");
  const hedgedNo = { ...writer, answer: "no" as const, answerQuote: "Może w piątek" };
  assert.equal(answerOf(buildCallResult({ ...f, writer: hedgedNo }), hedgedNo), "unclear", "uncertain source evidence cannot advance the chain either");
});
