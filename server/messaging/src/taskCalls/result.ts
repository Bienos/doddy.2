// The answer card (ADR-504). Built in code from the call's facts; a model, if configured, may only
// point at which reply holds the answer and write the summary and next step. The quote shown on the
// card is always cut from the transcript itself, so it can't say anything the person didn't say.
import { fold } from "./brief.js";

export type Speaker = "doddy" | "callee";
export interface Line { speaker: Speaker; text: string; atSecs: number | null }

export type Outcome =
  | "answered" | "no_answer" | "busy" | "failed" | "not_placed" | "voicemail" | "ivr" | "wrong_number"
  | "no_conversation" | "taken_over" | "voice_unavailable" | "stopped" | "unknown";
export type Confidence = "high" | "medium" | "low" | "none";
export type TranscriptSource = "elevenlabs" | "twilio_live" | "none";

export interface Warning { kind: "possible_commitment" | "unlisted_number" | "pesel_said"; line: number }
export interface NextStep {
  kind: "save_note" | "set_reminder" | "retry" | "call_yourself" | "check_number" | "follow_up" | "none";
  text: string;
}

export interface CallResult {
  format: 1;
  outcome: Outcome;
  source: TranscriptSource;
  confidence: Confidence;
  /** Why confidence isn't high, as codes the app can explain. */
  confidenceReasons: string[];
  summary: string;
  summaryBy: "doddy_model" | "rules";
  /** Exactly as transcribed, with the line it came from. */
  quote: { text: string; line: number } | null;
  transcript: Line[];
  nextStep: NextStep;
  warnings: Warning[];
  callbackPromised: boolean;
  takenOverAtSecs: number | null;
  durationSecs: number | null;
}

/** What the optional model step may say. Everything is checked before use. */
export interface WriterInput { question: string; goal: string; transcript: Line[] }
export interface WriterOutput {
  answerLine: number | null;
  answerQuote: string | null;
  summary: string;
  nextStep: string;
  kind: "answered" | "ivr" | "voicemail" | "wrong_number" | "no_answer_given";
  usage?: { inputTokens: number; outputTokens: number };
}

export type EndReason =
  | "completed" | "no_answer" | "busy" | "failed" | "canceled" | "time_limit" | "voicemail" | "user_ended" | "kill_switch"
  | "voice_unavailable" | "gate_refused" | "account_deleted" | "twilio_refused" | "expired";

export interface ResultFacts {
  endReason: EndReason | null;
  answered: boolean;
  voiceConnected: boolean;
  takenOverAtSecs: number | null;
  durationSecs: number | null;
  question: string;
  callbackLine: string;
  /** Texts Doddy was allowed to say: the opening line, the question and the ticked facts. */
  allowedTexts: string[];
  transcript: Line[];
  source: TranscriptSource;
  voicemailToolUsed: boolean;
  writer?: WriterOutput;
}

const IVR = ["nacisnij", "wcisnij", "wybierz", "aby polaczyc", "witamy w", "infolinia", "prosimy czekac", "prosze czekac",
  "polaczenie jest dla nas wazne", "nastepny wolny konsultant", "menu", "wewnetrzny"];
const WRONG = ["pomylka", "zly numer", "to nie jest", "nie ma tu", "nie znam", "nie wiem o co chodzi", "zle pan", "zle pani"];
const HEDGES = ["chyba", "nie wiem", "moze", "prawdopodobnie", "nie jestem pewn", "trudno powiedziec", "nie mam pewnosci", "sprawdze"];
const GREETINGS = new Set(["halo", "tak", "slucham", "dzien dobry", "prosze", "tak slucham", "slucham pana", "slucham pania", "no", "aha"]);
const COMMIT_WORDS = ["potwierdzam", "zgadzam", "akceptuje", "rezerwuje", "zarezerwuje", "zamawiam", "zamowie", "zaplace",
  "oplace", "biore", "wezme", "umawiam", "umowie", "zlecam", "zgoda", "przyjmuje", "podpisze"];

const has = (text: string, needles: string[]) => { const f = fold(text); return needles.some((n) => f.includes(n)); };
const isGreeting = (text: string) => GREETINGS.has(fold(text).replace(/[^a-z ]+/g, " ").replace(/\s+/g, " ").trim());
const norm = (s: string) => s.normalize("NFC").replace(/\s+/g, " ").trim();

export function buildCallResult(f: ResultFacts): CallResult {
  const transcript = f.transcript.map((l) => ({ ...l, text: norm(l.text) })).filter((l) => l.text.length > 0);
  const callee = transcript.map((l, i) => ({ ...l, i })).filter((l) => l.speaker === "callee");
  const warnings = audit(transcript, f.allowedTexts);
  const callbackPromised = transcript.some((l) => l.speaker === "doddy" && fold(l.text).includes(fold(f.callbackLine).slice(0, 24)));
  const reasons: string[] = [];

  const outcome = classify(f, callee);
  let quote: CallResult["quote"] = null;
  let confidence: Confidence = "none";
  let summary: string;
  let summaryBy: CallResult["summaryBy"] = "rules";

  if (outcome === "answered" || outcome === "taken_over") {
    quote = pickQuote(transcript, callee, f.writer, reasons);
    confidence = quote ? "high" : "low";
    if (!quote) reasons.push("no_answer_found");
    const cap = (c: Confidence) => { if (rank(confidence) > rank(c)) confidence = c; };
    if (f.source === "twilio_live") { cap("medium"); reasons.push("live_transcript_only"); }
    if (quote && has(quote.text, HEDGES)) { cap("medium"); reasons.push("hedged_answer"); }
    if (callbackPromised) { cap("medium"); reasons.push("asked_outside_brief"); }
    if (outcome === "taken_over") { cap("medium"); reasons.push("taken_over"); }
    if (f.endReason === "time_limit") { cap("medium"); reasons.push("time_limit"); }
    if (warnings.length) { cap("low"); reasons.push("doddy_line_warnings"); }
    if (reasons.includes("model_quote_rejected")) cap("low");
    if (f.writer && outcome === "answered" && f.writer.summary.trim()) {
      summary = clip(f.writer.summary, 300);
      summaryBy = "doddy_model";
    } else {
      summary = quote ? `Odpowiedź: „${clip(quote.text, 240)}”` : "Rozmowa się odbyła, ale nie udało się wskazać odpowiedzi. Przeczytaj zapis.";
    }
  } else {
    summary = OUTCOME_SUMMARY[outcome];
  }

  return {
    format: 1, outcome, source: f.source, confidence, confidenceReasons: reasons, summary, summaryBy, quote, transcript,
    nextStep: nextStepFor(outcome, quote, callbackPromised, f.writer), warnings, callbackPromised,
    takenOverAtSecs: f.takenOverAtSecs, durationSecs: f.durationSecs,
  };
}

const rank = (c: Confidence) => ({ none: 0, low: 1, medium: 2, high: 3 })[c];
const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);

function classify(f: ResultFacts, callee: { text: string }[]): Outcome {
  switch (f.endReason) {
    case "twilio_refused": case "expired": case "gate_refused": return "not_placed";
    case "voice_unavailable": return "voice_unavailable";
    case "kill_switch": case "account_deleted": return f.voiceConnected && callee.length ? "answered" : "stopped";
    case "no_answer": return "no_answer";
    case "busy": return "busy";
    case "failed": return "failed";
    case "canceled": return "stopped";
    default: break;
  }
  if (f.takenOverAtSecs !== null) return "taken_over";
  if (!f.answered) return f.endReason === "user_ended" ? "stopped" : f.endReason === null ? "unknown" : "no_answer";
  if (f.voicemailToolUsed || f.endReason === "voicemail" || f.writer?.kind === "voicemail") return "voicemail";
  const said = callee.map((l) => l.text).join(" ");
  if (callee.length === 0) return "no_conversation";
  if (has(said, IVR) || f.writer?.kind === "ivr") return "ivr";
  if (has(said, WRONG) || f.writer?.kind === "wrong_number") return "wrong_number";
  return "answered";
}

/** The model may point at a line and words; the card always shows the transcript's own text. */
function pickQuote(transcript: Line[], callee: (Line & { i: number })[], writer: WriterOutput | undefined, reasons: string[]) {
  if (writer && writer.answerLine !== null && writer.answerQuote) {
    const line = transcript[writer.answerLine];
    const span = line?.speaker === "callee" ? findSpan(line.text, writer.answerQuote) : undefined;
    if (span) return { text: span, line: writer.answerLine };
    reasons.push("model_quote_rejected");
  }
  // Without a usable pointer: the person's first real reply after the question (Doddy's first line).
  const firstQuestion = transcript.findIndex((l) => l.speaker === "doddy");
  const reply = callee.find((l) => l.i > firstQuestion && !isGreeting(l.text));
  if (!reply) return null;
  if (callee.filter((l) => l.i > firstQuestion && !isGreeting(l.text)).length > 1) reasons.push("several_replies");
  return { text: reply.text, line: reply.i };
}

/** The exact substring of `text` matching `quote`, ignoring case and spacing; undefined if absent. */
export function findSpan(text: string, quote: string): string | undefined {
  const q = norm(quote).toLowerCase();
  if (q.length < 2) return undefined;
  const t = norm(text);
  const idx = t.toLowerCase().indexOf(q);
  return idx >= 0 ? t.slice(idx, idx + q.length) : undefined;
}

/** Doddy's own lines after the opening: commitment words, numbers it wasn't given, PESEL-like numbers. */
export function audit(transcript: Line[], allowedTexts: string[]): Warning[] {
  const allowedDigits = new Set(allowedTexts.flatMap((t) => (t.match(/\d+/g) ?? [])));
  const warnings: Warning[] = [];
  let first = true;
  transcript.forEach((l, i) => {
    if (l.speaker !== "doddy") return;
    if (first) { first = false; return; } // the first message is ours, spoken word for word
    const f = fold(l.text);
    if (COMMIT_WORDS.some((w) => new RegExp(`\\b${w}\\b`).test(f))) warnings.push({ kind: "possible_commitment", line: i });
    const digits = l.text.match(/\d(?:[ \-]?\d)*/g)?.map((d) => d.replace(/\D/g, "")) ?? [];
    if (digits.some((d) => d.length === 11)) warnings.push({ kind: "pesel_said", line: i });
    else if (digits.some((d) => d.length >= 3 && !allowedDigits.has(d))) warnings.push({ kind: "unlisted_number", line: i });
  });
  return warnings;
}

export const OUTCOME_SUMMARY: Record<Exclude<Outcome, "answered" | "taken_over">, string> = {
  no_answer: "Nikt nie odebrał.",
  busy: "Numer był zajęty.",
  failed: "Połączenie się nie udało.",
  not_placed: "Doddy nie zadzwonił: połączenie nie zostało wykonane.",
  voicemail: "Odezwała się poczta głosowa. Doddy rozłączył się bez nagrywania wiadomości.",
  ivr: "Odebrał automat z menu, nie człowiek. Doddy niczego nie wybierał i się rozłączył.",
  wrong_number: "Rozmówca powiedział, że to pomyłka.",
  no_conversation: "Ktoś odebrał, ale nic nie powiedział.",
  voice_unavailable: "Problem techniczny: głos Doddy’ego nie połączył się, rozmówca usłyszał przeprosiny.",
  stopped: "Rozmowa została przerwana.",
  unknown: "Nie wiadomo, czy połączenie się odbyło. Doddy nie dzwonił ponownie.",
};

function nextStepFor(outcome: Outcome, quote: CallResult["quote"], callbackPromised: boolean, writer?: WriterOutput): NextStep {
  switch (outcome) {
    case "answered":
      if (callbackPromised) return { kind: "follow_up", text: "Rozmówca pytał o coś spoza karty, a Doddy obiecał oddzwonić. Sprawdź zapis i zdecyduj." };
      if (writer?.nextStep.trim()) return { kind: "follow_up", text: clip(writer.nextStep, 200) };
      if (quote && /\b(jutro|dzis|dzisiaj|pojutrze|poniedzialek|wtorek|sroda|czwartek|piatek|sobota|niedziela)\b|\d{1,2}[:.]\d{2}/.test(fold(quote.text))) {
        return { kind: "set_reminder", text: "W odpowiedzi jest termin: dodaj przypomnienie." };
      }
      return { kind: "save_note", text: "Zapisz odpowiedź w notatkach." };
    case "taken_over": return { kind: "none", text: "Dalszą część rozmowy prowadziłeś Ty." };
    case "no_answer": case "busy": case "failed": case "voice_unavailable": case "not_placed":
      return { kind: "retry", text: "Zadzwoń ponownie o wybranej godzinie." };
    case "voicemail": return { kind: "retry", text: "Spróbuj ponownie później, w godzinach pracy." };
    case "ivr": return { kind: "call_yourself", text: "To automat z menu: lepiej zadzwonić samemu." };
    case "wrong_number": return { kind: "check_number", text: "Sprawdź numer przed kolejną próbą." };
    default: return { kind: "none", text: "" };
  }
}
