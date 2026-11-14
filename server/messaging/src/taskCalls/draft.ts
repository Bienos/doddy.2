// "Who and why" in one field (decision docs/decisions/2026-11-13-calls-one-field-brief.md). The user writes one
// sentence; a model PROPOSES the brief's words (who, the goal, the one question, details copied from the sentence);
// this module checks every proposed field in code, drops what fails, and lists what is missing instead of guessing.
// The phone number never comes from the model: it is read from the user's own words here, or the app adds the number
// of the contact the user picked. Nothing is stored and nothing is dialled from a draft: the app shows it in the
// editor, the user sends the brief to POST /v1/call-cases, and the card made from that is what the user approves
// (DOD-07). The words go to the model with the phone numbers taken out, and are never logged (DOD-11).
import { z } from "zod";
import { clean, commits, digitGroups, fold, isBankAccount, isCardNumber, isPesel, looksLikeAddress, type FactKind } from "./brief.js";
import { classifyDestination, type DestinationRefusal } from "./phone.js";

export const DRAFT_TEXT_MAX = 400;
/** What the model sees in place of each phone number in the user's words. */
export const NUMBER_PLACEHOLDER = "[numer]";
/** The fact kinds the model may propose. PESEL is refused before the model sees the words; an address is marked by code. */
export const DRAFT_FACT_KINDS = ["general", "reference", "date", "device", "contact"] as const;

const text = (max: number, min = 1) => z.string().min(min).max(max * 2).transform(clean).pipe(z.string().min(min).max(max));

/** The body of POST /v1/call-cases/draft. Strict: a number, a fact list or a duration can't ride along. */
export const draftRequestSchema = z.strictObject({
  /** The user's one sentence: who Doddy calls and why. */
  text: text(DRAFT_TEXT_MAX, 8),
  /** The name of the contact the user picked on the iPhone, if any. Its number stays on the iPhone. */
  contactName: text(80).optional(),
});
export type DraftRequest = z.infer<typeof draftRequestSchema>;

/** What the model proposes. Every field may be null: a missing field is reported, never guessed. */
export interface ProposedBrief {
  calleeName: string | null;
  goal: string | null;
  question: string | null;
  facts: { kind: string; text: string }[];
}

/** The model step (ClaudeBriefDrafter in production, a fake in tests). It only proposes; `checkDraft` decides. */
export interface BriefDrafter {
  readonly provider: "anthropic";
  readonly model: string;
  /** `text` has its phone numbers replaced by NUMBER_PLACEHOLDER. Throws an Error whose message is a `drafter_…` code. */
  draft(input: { text: string; contactName?: string }): Promise<ProposedBrief>;
}

export type DraftField = "callee.name" | "callee.phone" | "goal" | "question";
export type DropReason =
  | "braces" | "pesel_not_ticked" | "address_not_ticked" | "bank_account" | "card_number" | "question_commits"
  | "too_long" | "too_short"
  | "not_from_text"    // a name or a detail the user didn't write
  | "not_a_question"   // the question doesn't end with "?"
  | "duplicate_fact" | "too_many_facts"
  | "several_numbers"  // more than one phone number in the words: the user picks
  | DestinationRefusal | "own_number" | "doddy_number";

/** What the endpoint returns: the editor's starting point, not a card and not an approval. */
export interface BriefDraft {
  callee: { name: string | null; phone: string | null; source: "typed" | null };
  goal: string | null;
  question: string | null;
  facts: { kind: FactKind; text: string }[];
  /** Fields the user still has to fill in. */
  missing: DraftField[];
  /** What the model proposed that code refused, as codes only. */
  dropped: { field: string; reason: DropReason }[];
}

export type TextRefusal = "pesel_not_ticked" | "bank_account" | "card_number";

export interface ReadNumbers {
  /** The words with every phone number replaced by NUMBER_PLACEHOLDER: what the model sees. */
  redacted: string;
  /** The one number Doddy may call, read from the words, as +48…; null when there is none or more than one. */
  phone: string | null;
  /** Why the number in the words can't be used, when there was one. */
  phoneDropped?: DropReason;
  /** The words hold a PESEL, a bank account or a card number: nothing goes to the model. */
  refusal?: TextRefusal;
}

// A run that may be a phone number: digits with the separators people type ("600 100 200", "+48 (22) 123-45-67").
const NUMBER_RUN = /(?:\+\s?)?\(?\d[\d\s\-().\/]{5,30}\d/g;

/**
 * Finds the phone numbers in the user's words without any model. A run counts as a number when it starts with
 * + or 00, or has 9 digits (or 11 starting 48). Exactly one number Doddy may call becomes the draft's number;
 * two or more, or one Doddy may not call, leave the number for the user to type.
 */
export function readNumbers(words: string, own: { own?: string; doddy?: string } = {}): ReadNumbers {
  const found: { raw: string; e164?: string; refusal?: DropReason }[] = [];
  let peselRun = false;
  const redacted = words.replace(NUMBER_RUN, (raw) => {
    const compact = raw.replace(/[\s\-().\/]/g, "");
    const digits = compact.replace(/\D/g, "");
    const international = compact.startsWith("+") || compact.startsWith("00");
    const looksLikePhone = international || digits.length === 9 || (digits.length === 11 && digits.startsWith("48"));
    if (!looksLikePhone) return raw;
    // A PESEL written without + is a PESEL, even when its digits would also read as +48 and a number.
    if (!international && isPesel(digits)) { peselRun = true; return raw; }
    const dest = classifyDestination(compact);
    if (!dest.ok) found.push({ raw, refusal: dest.reason });
    else if (dest.e164 === own.own) found.push({ raw, refusal: "own_number" });
    else if (dest.e164 === own.doddy) found.push({ raw, refusal: "doddy_number" });
    else found.push({ raw, e164: dest.e164 });
    return NUMBER_PLACEHOLDER;
  });
  if (peselRun) return { redacted, phone: null, refusal: "pesel_not_ticked" };
  const refusal = refuseWords(redacted);
  if (refusal) return { redacted, phone: null, refusal };
  const distinct = new Set(found.map((f) => f.e164 ?? `refused:${f.raw}`));
  if (found.length === 0) return { redacted, phone: null };
  if (distinct.size > 1) return { redacted, phone: null, phoneDropped: "several_numbers" };
  const only = found[0]!;
  return only.e164 ? { redacted, phone: only.e164 } : { redacted, phone: null, phoneDropped: only.refusal };
}

/** A PESEL, bank account or card number outside a phone number: such words are refused before any model sees them. */
export function refuseWords(value: string): TextRefusal | undefined {
  const groups = digitGroups(value);
  if (groups.some(isPesel)) return "pesel_not_ticked";
  if (groups.some(isBankAccount) || /\bPL\s?\d{2}(?:\s?\d{4}){6}\b/i.test(value)) return "bank_account";
  if (groups.some(isCardNumber)) return "card_number";
  return undefined;
}

/** Lower-case words without diacritics. */
function words(value: string): string[] {
  return fold(value).split(/[^\p{L}\d]+/u).filter(Boolean);
}

/**
 * Whether every word of 3+ letters in `value` is one the user wrote, allowing for Polish endings: "Fryzjer Anna"
 * from "do fryzjera Anna", "Serwis Bajt" from "do serwisu Bajt". A word the user never wrote ("Salon") fails.
 */
export function wordsFromText(value: string, sources: string[]): boolean {
  const pool = sources.flatMap(words);
  const stem = (w: string) => w.slice(0, Math.max(3, Math.min(5, w.length - 2)));
  return words(value).filter((w) => w.length >= 3).every((w) => pool.some((p) => p.startsWith(stem(w))));
}

/** Whether `fact` appears in the user's words as written (case, diacritics and spacing aside). */
export function copiedFromText(fact: string, text: string): boolean {
  const norm = (v: string) => fold(clean(v));
  const f = norm(fact);
  return f.length > 0 && norm(text).includes(f);
}

/**
 * Whether every number in `value` is one the user wrote: a model can't add an hour, a date, a price or a number
 * ("o 15:00" when the user wrote "o 10"). Numbers the user wrote ("o 10:00", "zlecenie 12345") stay.
 */
export function numbersFromText(value: string, text: string): boolean {
  const written = new Set(text.match(/\d+/g) ?? []);
  return (value.match(/\d+/g) ?? []).every((n) => written.has(n));
}

/** The checks every proposed field gets: the same rules the brief itself is held to on POST /v1/call-cases. */
function contentProblem(value: string, opts: { addressAllowed?: boolean } = {}): DropReason | undefined {
  if (/[{}]/.test(value)) return "braces";
  if (value.includes(NUMBER_PLACEHOLDER)) return "not_from_text";
  const groups = digitGroups(value);
  if (groups.some(isBankAccount)) return "bank_account";
  if (groups.some(isCardNumber)) return "card_number";
  if (groups.some(isPesel)) return "pesel_not_ticked";
  if (!opts.addressAllowed && looksLikeAddress(value)) return "address_not_ticked";
  return undefined;
}

function sized(value: string | null, min: number, max: number): { value?: string; reason?: DropReason } {
  if (value === null) return {};
  const v = clean(value);
  if (v.length === 0) return {};
  if (v.length < min) return { reason: "too_short" };
  if (v.length > max) return { reason: "too_long" };
  return { value: v };
}

/**
 * Checks the model's proposal field by field. A field that fails is dropped (with its reason) and reported as
 * missing; nothing is repaired or guessed. The number is the one `readNumbers` found, never the model's.
 */
export function checkDraft(
  proposal: ProposedBrief,
  input: { text: string; contactName?: string; phone: string | null; phoneDropped?: DropReason },
): BriefDraft {
  const dropped: BriefDraft["dropped"] = [];
  const keep = (field: string, value: string | null, min: number, max: number, extra?: (v: string) => DropReason | undefined) => {
    const s = sized(value, min, max);
    if (s.reason) { dropped.push({ field, reason: s.reason }); return null; }
    if (s.value === undefined) return null;
    const reason = contentProblem(s.value) ?? (numbersFromText(s.value, input.text) ? undefined : "not_from_text") ?? extra?.(s.value);
    if (reason) { dropped.push({ field, reason }); return null; }
    return s.value;
  };
  const sources = [input.text, ...(input.contactName ? [input.contactName] : [])];
  const name = keep("callee.name", proposal.calleeName, 1, 80, (v) => (wordsFromText(v, sources) ? undefined : "not_from_text"));
  const goal = keep("goal", proposal.goal, 3, 160);
  const question = keep("question", proposal.question, 5, 200, (v) => {
    if (commits(v)) return "question_commits";
    return v.endsWith("?") ? undefined : "not_a_question";
  });
  if (input.phoneDropped) dropped.push({ field: "callee.phone", reason: input.phoneDropped });

  const facts: BriefDraft["facts"] = [];
  const seen = new Set<string>();
  for (const [i, f] of proposal.facts.entries()) {
    const field = `facts.${i}`;
    const s = sized(f.text, 1, 160);
    if (s.reason) { dropped.push({ field, reason: s.reason }); continue; }
    if (s.value === undefined) continue;
    const reason = contentProblem(s.value, { addressAllowed: true }) ?? (copiedFromText(s.value, input.text) ? undefined : "not_from_text");
    if (reason) { dropped.push({ field, reason }); continue; }
    const key = fold(s.value);
    if (seen.has(key)) { dropped.push({ field, reason: "duplicate_fact" }); continue; }
    if (facts.length >= 5) { dropped.push({ field, reason: "too_many_facts" }); continue; }
    seen.add(key);
    // An address is only ever sent as a fact marked as one; the app leaves such a fact unticked.
    const kind: FactKind = looksLikeAddress(s.value) ? "address"
      : (DRAFT_FACT_KINDS as readonly string[]).includes(f.kind) ? (f.kind as FactKind) : "general";
    facts.push({ kind, text: s.value });
  }

  const missing: DraftField[] = [];
  if (name === null) missing.push("callee.name");
  if (input.phone === null) missing.push("callee.phone");
  if (goal === null) missing.push("goal");
  if (question === null) missing.push("question");
  return {
    callee: { name, phone: input.phone, source: input.phone ? "typed" : null },
    goal, question, facts, missing, dropped,
  };
}

/** A drafter error as a code for the log: never its message text from a provider. */
export function drafterErrorCode(err: unknown): string {
  return err instanceof Error && /^drafter_[a-z0-9_]{1,40}$/.test(err.message) ? err.message : "drafter_error";
}
