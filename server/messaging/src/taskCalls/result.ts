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

/**
 * Failed calls that may be tried again at a set time (a new approval of the same card): nobody
 * talked with Doddy about the question. The owner's list: no answer, voicemail, wrong number, IVR.
 * The app's `CallOutcome.isRetryable` mirrors this.
 */
export const RETRYABLE_OUTCOMES: readonly Outcome[] = [
  "no_answer", "busy", "failed", "not_placed", "voicemail", "ivr", "wrong_number", "voice_unavailable", "unknown",
];
export function isRetryableOutcome(outcome: string | null | undefined): boolean {
  return (RETRYABLE_OUTCOMES as readonly string[]).includes(outcome ?? "");
}
export type TranscriptSource = "elevenlabs" | "twilio_live" | "none";

/**
 * `possible_other_booking`: Doddy said yes (or its booking sentence) while the other side was offering a time, day,
 * price or condition that isn't on the card, so something other than the card may have been booked or agreed.
 */
export interface Warning { kind: "possible_commitment" | "unlisted_number" | "pesel_said" | "possible_other_booking"; line: number }
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
  /**
   * Booking calls only (decision 2026-11-12-book-agent): Doddy said the approved confirmation sentence.
   * A booking counts as made only with this, a "yes" from the writer and a quote from the transcript.
   */
  bookingConfirmed?: boolean;
}

/** What the optional model step may say. Everything is checked before use. */
export interface WriterInput {
  question: string; goal: string; transcript: Line[];
  /** Booking calls only: the approved booking, one detail per line. "yes" then means booked exactly this. */
  booking?: string;
}
export interface WriterOutput {
  answerLine: number | null;
  answerQuote: string | null;
  summary: string;
  nextStep: string;
  kind: "answered" | "ivr" | "voicemail" | "wrong_number" | "no_answer_given";
  /** Whether the answer to the question means yes or no (decision 2026-11-09-restaurant-calls-one-tap). Absent from older writers. */
  answer?: "yes" | "no" | "unclear";
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
  /** Booking calls only: the one sentence that accepts the booking. Doddy's lines holding it are not commitment warnings. */
  bookingConfirmLine?: string;
}

const IVR = ["nacisnij", "wcisnij", "wybierz", "aby polaczyc", "witamy w", "infolinia", "prosimy czekac", "prosze czekac",
  "polaczenie jest dla nas wazne", "nastepny wolny konsultant", "menu", "wewnetrzny"];
const WRONG = ["pomylka", "zly numer", "to nie jest", "nie ma tu", "nie znam", "nie wiem o co chodzi", "zle pan", "zle pani"];
const HEDGES = ["chyba", "nie wiem", "moze", "prawdopodobnie", "nie jestem pewn", "trudno powiedziec", "nie mam pewnosci", "sprawdze"];
const GREETINGS = new Set(["halo", "tak", "slucham", "dzien dobry", "prosze", "tak slucham", "slucham pana", "slucham pania", "no", "aha"]);
/** Agreement on any call, whatever was said before it (the approved booking sentence aside). */
const COMMIT_WORDS = ["potwierdzam", "zgadzam", "akceptuje", "rezerwuje", "zarezerwuje", "zamawiam", "zamowie", "zaplace",
  "oplace", "biore", "wezme", "umawiam", "umowie", "zlecam", "zgoda", "przyjmuje", "podpisze",
  "prosze zapisac", "prosze nas zapisac", "prosze mnie zapisac", "prosze ja zapisac", "prosze go zapisac", "niech bedzie",
  "umowmy sie", "jestesmy umowieni", "zarezerwujmy", "rezerwujemy"];
/**
 * Saying yes in Polish, short or long. Too common to be a commitment on its own ("Dobrze, dziękuję"), so it counts only
 * as a reply while the other side offers a time, day, price or condition that isn't on the card (`audit`).
 */
const ASSENT_WORDS = ["tak", "dobrze", "pasuje", "moze byc", "ok", "okej", "okay", "w porzadku", "zgoda", "niech bedzie",
  "swietnie", "super", "jasne", "oczywiscie", "poprosze", "prosze zapisac", "prosze nas zapisac", "zapisuje", "zapisze",
  "zgadzam", "potwierdzam", "akceptuje", "biore", "wezme", "rezerwuje", "zarezerwuje", "prosze o rezerwacje", "umowmy sie"];
const ASSENT = new RegExp(`\\b(?:${ASSENT_WORDS.join("|")})\\b`);

const has = (text: string, needles: string[]) => { const f = fold(text); return needles.some((n) => f.includes(n)); };
const isGreeting = (text: string) => GREETINGS.has(fold(text).replace(/[^a-z ]+/g, " ").replace(/\s+/g, " ").trim());
const norm = (s: string) => s.normalize("NFC").replace(/\s+/g, " ").trim();

export function buildCallResult(f: ResultFacts): CallResult {
  const transcript = f.transcript.map((l) => ({ ...l, text: norm(l.text) })).filter((l) => l.text.length > 0);
  const callee = transcript.map((l, i) => ({ ...l, i })).filter((l) => l.speaker === "callee");
  const warnings = audit(transcript, f.allowedTexts, f.bookingConfirmLine, f.callbackLine);
  const bookingConfirmed = f.bookingConfirmLine === undefined ? undefined
    : transcript.some((l) => l.speaker === "doddy" && saysLine(l.text, f.bookingConfirmLine!));
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
    nextStep: nextStepFor(outcome, quote, callbackPromised, f.writer, warnings), warnings, callbackPromised,
    takenOverAtSecs: f.takenOverAtSecs, durationSecs: f.durationSecs,
    ...(bookingConfirmed === undefined ? {} : { bookingConfirmed }),
  };
}

/** Whether a spoken line holds the given sentence, ignoring case, diacritics, spacing and punctuation. */
export function saysLine(spoken: string, sentence: string): boolean {
  const squash = (x: string) => fold(x).replace(/[^a-z0-9]+/g, " ").trim();
  const want = squash(sentence);
  return want.length > 0 && ` ${squash(spoken)} `.includes(` ${want} `);
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

/**
 * Doddy's own lines after the opening: commitment words, numbers it wasn't given, PESEL-like numbers, and a yes while the
 * other side offers terms that aren't on the card. An offer stays open until the other side comes back to the card's
 * own terms or Doddy says it will check with the person (`callbackLine`, which rule 3 of both prompts asks for); any
 * yes while it is open, the booking sentence included, is `possible_other_booking`.
 */
export function audit(transcript: Line[], allowedTexts: string[], bookingConfirmLine?: string, callbackLine?: string): Warning[] {
  const allowedDigits = new Set(allowedTexts.flatMap((t) => (t.match(/\d+/g) ?? [])));
  const card = termsIn(allowedTexts.join("\n"));
  const booking = bookingConfirmLine !== undefined;
  const deferral = callbackLine ? fold(callbackLine).slice(0, 24) : undefined;
  const warnings: Warning[] = [];
  let first = true;
  let offerOpen = false;
  transcript.forEach((l, i) => {
    if (l.speaker === "callee") {
      const said = termsIn(l.text);
      if (otherTerms(said, card, booking)) offerOpen = true;
      else if (anyTerms(said)) offerOpen = false; // back to the card's own time, day or price
      return;
    }
    if (first) { first = false; return; } // the first message is ours, spoken word for word
    // On a booking call the approved confirmation sentence is the one commitment allowed; any other commitment word still warns.
    const f = fold(bookingConfirmLine && saysLine(l.text, bookingConfirmLine) ? withoutLine(l.text, bookingConfirmLine) : l.text);
    if (COMMIT_WORDS.some((w) => new RegExp(`\\b${w}\\b`).test(f))) warnings.push({ kind: "possible_commitment", line: i });
    const digits = l.text.match(/\d(?:[ \-]?\d)*/g)?.map((d) => d.replace(/\D/g, "")) ?? [];
    if (digits.some((d) => d.length === 11)) warnings.push({ kind: "pesel_said", line: i });
    else if (digits.some((d) => d.length >= 3 && !allowedDigits.has(d))) warnings.push({ kind: "unlisted_number", line: i });
    const folded = fold(l.text);
    const defers = deferral !== undefined && folded.includes(deferral);
    if (offerOpen && !defers && ASSENT.test(folded)) warnings.push({ kind: "possible_other_booking", line: i });
    if (defers) offerOpen = false;
  });
  return warnings;
}

// ---------- times, days and prices in what was said ----------

/** Comparable terms in a text: times as "h%12:mm", days as "w<weekday>", "d<day>.<month>", "m<month>", prices in złoty. */
export interface Terms { times: Set<string>; days: Set<string>; prices: Set<string>; condition: boolean }

const MONTHS = ["stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca", "sierpnia", "wrzesnia", "pazdziernika", "listopada", "grudnia"];
const WEEKDAYS: [RegExp, number][] = [
  [/\bniedziel(?:a|e|i)\b/, 0], [/\bponiedzial(?:ek|ku)\b/, 1], [/\bwtor(?:ek|ku)\b/, 2], [/\bsrod(?:a|e|y|zie)\b/, 3],
  [/\bczwart(?:ek|ku)\b/, 4], [/\bpiat(?:ek|ku)\b/, 5], [/\bsobot(?:a|e|y)\b|\bsobocie\b/, 6],
];
/** Hours said as words, in the forms after "o" (-ej) and "na" (-ą, folded to -a). Longest first. */
const HOUR_WORDS: [string, number][] = [
  ["dwudziest(?:ej|a) pierwsz(?:ej|a)", 21], ["dwudziest(?:ej|a) drug(?:iej|a)", 22], ["dwudziest(?:ej|a) trzeci(?:ej|a)", 23],
  ["dwudziest(?:ej|a)", 20], ["dziewietnast(?:ej|a)", 19], ["osiemnast(?:ej|a)", 18], ["siedemnast(?:ej|a)", 17], ["szesnast(?:ej|a)", 16],
  ["pietnast(?:ej|a)", 15], ["czternast(?:ej|a)", 14], ["trzynast(?:ej|a)", 13], ["dwunast(?:ej|a)", 12], ["jedenast(?:ej|a)", 11],
  ["dziesiat(?:ej|a)", 10], ["dziewiat(?:ej|a)", 9], ["osm(?:ej|a)", 8], ["siodm(?:ej|a)", 7], ["szost(?:ej|a)", 6], ["piat(?:ej|a)", 5],
  ["czwart(?:ej|a)", 4], ["trzeci(?:ej|a)", 3], ["drugi(?:ej|a)", 2], ["pierwsz(?:ej|a)", 1],
];
const MINUTE_WORDS: [string, number][] = [["czterdziesci piec", 45], ["trzydziesci", 30], ["pietnascie", 15], ["dwadziescia", 20],
  ["dziesiec", 10], ["czterdziesci", 40], ["piecdziesiat", 50]];
/** Words that bring a time: "o 19", "na 20", "od 18", "po 21", "przed 9", "godz. 10". Never "do" (until). */
const AT = String.raw`\b(?:o|na|od|po|przed|godz\.?|godzina|godzinie|godzine)\s+`;
/** Paying first, a card or a transfer: a condition, never on a booking card. */
const CONDITIONS = /\b(?:zadat\w*|zaliczk\w*|przedplat\w*|kaucj\w*|oplat\w* rezerwacyjn\w*|numer\w* karty|przelew\w*|(?:platn|zaplac|wplac)\w* z gory|z gory (?:platn|zaplac|wplac)\w*)\b/;

const timeKey = (h: number, m: number) => `${h % 12}:${String(m).padStart(2, "0")}`;

export function termsIn(text: string): Terms {
  const t = fold(text);
  const times = new Set<string>();
  const days = new Set<string>();
  const prices = new Set<string>();
  const time = (h: number, m: number) => { if (h <= 24 && m < 60) times.add(timeKey(h, m)); };
  // 19:30; 19.30 (a date when the second part could be a month and no "o" comes before it).
  for (const m of t.matchAll(/(?<![\d.:])(?<!\bdo )(\d{1,2})([:.])(\d{2})(?:\.(\d{2,4}))?(?!\d)/g)) {
    const a = Number(m[1]); const b = Number(m[3]);
    const before = t.slice(Math.max(0, m.index - 8), m.index);
    if (m[2] === "." && (m[4] !== undefined || (b >= 1 && b <= 12 && a >= 1 && a <= 31 && !new RegExp(`${AT}$`).test(before)))) {
      days.add(`d${a}.${b}`); days.add(`m${b}`);
    } else {
      time(a, b);
    }
  }
  // "o 19", "na 20", "godz. 10": not a number of people, minutes or złoty.
  for (const m of t.matchAll(new RegExp(`${AT}(\\d{1,2})(?![\\d:]|[.,]\\d|\\s*(?:os|min|zl|pln|proc))`, "g"))) time(Number(m[1]), 0);
  // Longest first, each match blanked out, so "dwudziestej pierwszej" is 21 and not 20 as well.
  const minutes = MINUTE_WORDS.map(([w]) => w).join("|");
  let rest = t;
  for (const [word, h] of HOUR_WORDS) {
    const half = new RegExp(`\\bwpol do (?:${word})\\b`, "g");
    if (half.test(rest)) { time(h - 1, 30); rest = rest.replace(half, " "); }
    const at = new RegExp(`${AT}(?:${word})(?:\\s+(${minutes}))?\\b`, "g");
    for (const m of rest.matchAll(at)) time(h, MINUTE_WORDS.find(([w]) => w === m[1])?.[1] ?? 0);
    rest = rest.replace(at, " ");
  }
  // 14 listopada; listopad named on its own.
  MONTHS.forEach((month, i) => {
    for (const m of t.matchAll(new RegExp(`\\b(\\d{1,2})\\s+${month}\\b`, "g"))) days.add(`d${Number(m[1])}.${i + 1}`);
    if (new RegExp(`\\b${month}\\b`).test(t)) days.add(`m${i + 1}`);
  });
  for (const [re, day] of WEEKDAYS) if (re.test(t)) days.add(`w${day}`);
  for (const m of t.matchAll(/(\d+(?:[ .]\d{3})*)(?:[.,]\d{1,2})?\s*(?:zl|zlote|zlotych|zloty|pln)\b/g)) prices.add(m[1]!.replace(/\D/g, ""));
  return { times, days, prices, condition: CONDITIONS.test(t) };
}

const anyTerms = (t: Terms) => t.times.size + t.days.size + t.prices.size > 0 || t.condition;

/**
 * Whether the other side names terms the card doesn't have: another time or day (when the card names one; on a card
 * without a time, a time in the answer is the answer), any price or paying condition on a booking call, or a price
 * other than the card's. Relative days ("jutro") can't be compared with a date, so they are not offers.
 */
function otherTerms(said: Terms, card: Terms, booking: boolean): boolean {
  const outside = (a: Set<string>, b: Set<string>) => [...a].some((x) => !b.has(x));
  if (card.times.size > 0 && outside(said.times, card.times)) return true;
  if (card.days.size > 0 && outside(said.days, card.days)) return true;
  if ((booking || card.prices.size > 0) && outside(said.prices, card.prices)) return true;
  return booking && said.condition && !card.condition;
}

/** The spoken line with the given sentence taken out, compared as saysLine does. */
function withoutLine(spoken: string, sentence: string): string {
  const squash = (x: string) => fold(x).replace(/[^a-z0-9]+/g, " ").trim();
  return ` ${squash(spoken)} `.replace(` ${squash(sentence)} `, " ");
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

/** The next step when Doddy may have agreed to other terms than the card's: the person decides, by calling. */
export const OTHER_TERMS_NEXT_STEP: NextStep = {
  kind: "call_yourself",
  text: "Doddy mógł się zgodzić na inny termin albo warunki niż te z karty. Zadzwoń, żeby odwołać albo potwierdzić.",
};

function nextStepFor(outcome: Outcome, quote: CallResult["quote"], callbackPromised: boolean, writer?: WriterOutput, warnings: Warning[] = []): NextStep {
  if ((outcome === "answered" || outcome === "taken_over") && warnings.some((w) => w.kind === "possible_other_booking")) return OTHER_TERMS_NEXT_STEP;
  switch (outcome) {
    case "answered":
      if (callbackPromised) return { kind: "follow_up", text: "Rozmówca pytał o coś spoza karty, a Doddy obiecał oddzwonić. Sprawdź zapis i zdecyduj." };
      if (writer?.nextStep.trim()) return { kind: "follow_up", text: clip(writer.nextStep, 200) };
      if (quote && /\b(jutro|dzis|dzisiaj|pojutrze|poniedzialek|wtorek|sroda|czwartek|piatek|sobota|niedziela)\b|\d{1,2}[:.]\d{2}/.test(fold(quote.text))) {
        return { kind: "set_reminder", text: "W odpowiedzi jest termin: dodaj przypomnienie." };
      }
      return { kind: "save_note", text: "Zapisz odpowiedź w notatkach." };
    case "taken_over": return { kind: "none", text: "Po przejęciu Doddy nie brał już udziału w rozmowie." };
    case "no_answer": case "busy": case "failed": case "voice_unavailable": case "not_placed":
      return { kind: "retry", text: "Zadzwoń ponownie o wybranej godzinie." };
    case "voicemail": return { kind: "retry", text: "Spróbuj ponownie później, w godzinach pracy." };
    case "ivr": return { kind: "call_yourself", text: "To automat z menu: lepiej zadzwonić samemu." };
    case "wrong_number": return { kind: "check_number", text: "Sprawdź numer przed kolejną próbą." };
    default: return { kind: "none", text: "" };
  }
}
