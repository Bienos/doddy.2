// The brief the user approves before Doddy dials (ADR-501). Only ticked facts are ever sent by the
// app; this module checks them again on the server, because the app is not a security boundary.
import { z } from "zod";

export const FACT_KINDS = ["general", "reference", "date", "device", "contact", "pesel", "address"] as const;
export type FactKind = (typeof FACT_KINDS)[number];

const NAME = /^[\p{L}][\p{L}\p{M} '’\-]{0,39}$/u;
const text = (max: number, min = 1) => z.string().min(min).max(max * 2).transform(clean).pipe(z.string().min(min).max(max));

/** Strict: an unknown field is a 400, never silently ignored. */
export const briefSchema = z.strictObject({
  kind: z.literal("ask"),
  callee: z.strictObject({
    name: text(80),
    phone: z.string().min(3).max(40),
    source: z.enum(["contacts", "typed", "note"]),
    // Shown on the card next to the number ("Kontakty: Serwis Laptop"); never sent to a provider.
    sourceLabel: text(80).optional(),
  }),
  principal: z.strictObject({
    // The user's first name, and its genitive for "w imieniu …" / "u …" (the app suggests one; the user can edit it).
    name: text(40).pipe(z.string().regex(NAME)),
    genitive: text(40).pipe(z.string().regex(NAME)),
  }),
  goal: text(160, 3),
  question: text(200, 5),
  facts: z.array(z.strictObject({ kind: z.enum(FACT_KINDS), text: text(160) })).max(5),
  maxDurationSecs: z.number().int().min(60).max(300).default(240),
});

export type BriefInput = z.input<typeof briefSchema>;
export type Brief = z.infer<typeof briefSchema>;

/** Collapses whitespace and removes control and format characters (including bidi overrides). */
export function clean(value: string): string {
  return value.normalize("NFC").replace(/[\p{Cc}\p{Cf}]/gu, " ").replace(/\s+/g, " ").trim();
}

export type ContentRefusal =
  | "braces"             // {{ }} would be read as a template variable
  | "pesel_not_ticked"   // a PESEL outside a fact ticked as PESEL
  | "pesel_invalid"      // a fact ticked as PESEL that holds no valid PESEL
  | "address_not_ticked" // looks like an address outside a fact ticked as an address
  | "bank_account"       // Doddy never gives bank account numbers
  | "card_number"        // nor card numbers
  | "question_commits"   // an ASK call only asks: no confirming, booking, ordering or paying
  | "duplicate_fact";

export interface ContentProblem { field: string; reason: ContentRefusal }

/** Every field a person wrote, with where it is, for the checks below. */
function fields(b: Brief): { field: string; value: string; factKind?: FactKind }[] {
  return [
    { field: "callee.name", value: b.callee.name },
    ...(b.callee.sourceLabel ? [{ field: "callee.sourceLabel", value: b.callee.sourceLabel }] : []),
    { field: "goal", value: b.goal },
    { field: "question", value: b.question },
    ...b.facts.map((f, i) => ({ field: `facts.${i}`, value: f.text, factKind: f.kind })),
  ];
}

/** Checks a parsed brief; returns the first problem, or nothing when it may be sent. */
export function checkBriefContent(b: Brief): ContentProblem | undefined {
  for (const f of [...fields(b), { field: "principal.name", value: b.principal.name }, { field: "principal.genitive", value: b.principal.genitive }]) {
    if (/[{}]/.test(f.value)) return { field: f.field, reason: "braces" };
  }
  for (const f of fields(b)) {
    const numbers = digitGroups(f.value);
    if (numbers.some(isBankAccount) || /\bPL\s?\d{2}(?:\s?\d{4}){6}\b/i.test(f.value)) return { field: f.field, reason: "bank_account" };
    if (numbers.some(isCardNumber)) return { field: f.field, reason: "card_number" };
    const hasPesel = numbers.some(isPesel);
    if (f.factKind === "pesel") {
      if (!hasPesel) return { field: f.field, reason: "pesel_invalid" };
    } else if (hasPesel) {
      return { field: f.field, reason: "pesel_not_ticked" };
    }
    if (f.factKind !== "address" && looksLikeAddress(f.value)) return { field: f.field, reason: "address_not_ticked" };
  }
  if (commits(b.question)) return { field: "question", reason: "question_commits" };
  const seen = new Set<string>();
  for (const [i, f] of b.facts.entries()) {
    const key = fold(f.text);
    if (seen.has(key)) return { field: `facts.${i}`, reason: "duplicate_fact" };
    seen.add(key);
  }
  return undefined;
}

/** Runs of digits, joined across single spaces or hyphens ("4111 1111-1111 1111" → one group). */
export function digitGroups(value: string): string[] {
  return (value.match(/\d(?:[ \-]?\d)*/g) ?? []).map((g) => g.replace(/\D/g, ""));
}

/** PESEL: 11 digits, valid checksum, and a month/day that can exist. */
export function isPesel(d: string): boolean {
  if (!/^\d{11}$/.test(d)) return false;
  const w = [1, 3, 7, 9, 1, 3, 7, 9, 1, 3];
  const sum = w.reduce((s, x, i) => s + x * Number(d[i]), 0);
  if ((10 - (sum % 10)) % 10 !== Number(d[10])) return false;
  const month = Number(d.slice(2, 4)) % 20;
  const day = Number(d.slice(4, 6));
  return month >= 1 && month <= 12 && day >= 1 && day <= 31;
}

/** Polish account number (26 digits) with a valid IBAN check (PL prefix assumed). */
export function isBankAccount(d: string): boolean {
  if (!/^\d{26}$/.test(d)) return false;
  // IBAN: move "PL" + check digits to the end, letters as numbers (P=25, L=21), mod 97 must be 1.
  const rearranged = d.slice(2) + "2521" + d.slice(0, 2);
  let rem = 0;
  for (const ch of rearranged) rem = (rem * 10 + Number(ch)) % 97;
  return rem === 1;
}

/** Card numbers: 15–16 digits starting 3–6 that pass the Luhn check. */
export function isCardNumber(d: string): boolean {
  if (!/^[3-6]\d{14,15}$/.test(d)) return false;
  let sum = 0;
  for (let i = 0; i < d.length; i++) {
    let n = Number(d[d.length - 1 - i]);
    if (i % 2 === 1) { n *= 2; if (n > 9) n -= 9; }
    sum += n;
  }
  return sum % 10 === 0;
}

/** Street words or a Polish postal code (00-000). Coarse on purpose: a false alarm only asks to tick "address". */
export function looksLikeAddress(value: string): boolean {
  const f = fold(value);
  return /\b\d{2}-\d{3}\b/.test(value) || /\b(ul|al|os|pl)\.\s*\p{L}/u.test(f) || /\b(ulica|ulicy|aleja|alei|osiedle|mieszkania|mieszkanie)\b/.test(f);
}

// A question becomes a commitment when Doddy would agree or act ("potwierdzam", "zamawiam") or
// ask to act ("chciałbym zamówić", "proszę zarezerwować"). Asking about something stays allowed:
// "Czy zamówienie jest gotowe?", "Czy można zarezerwować stolik?", "Czy mogą Państwo potwierdzić…?".
// Folded words (no diacritics). Coarse: the prompt and the after-call check do the rest.
const FIRST_PERSON = new Set(["potwierdzam", "zgadzam", "zgodze", "akceptuje", "rezerwuje", "zarezerwuje", "zamawiam",
  "zamowie", "zaplace", "place", "oplace", "kupuje", "kupie", "biore", "wezme", "zlecam", "zlece", "podpisze", "podpisuje",
  "umowie", "umawiam", "przeleje", "odwoluje", "odwolam", "rezygnuje", "zrezygnuje"]);
const ACT_VERBS = new Set(["zarezerwowac", "rezerwowac", "zamowic", "zamawiac", "kupic", "kupowac", "umowic", "umawiac",
  "zaplacic", "oplacic", "placic", "wplacic", "przelac", "zlecic", "odwolac", "zrezygnowac", "podpisac", "potwierdzic"]);
const REQUESTERS = new Set(["chcialbym", "chcialabym", "chce", "chcemy", "prosze", "prosimy", "zamierzam"]);

export function commits(question: string): boolean {
  const words = fold(question).split(/[^a-z]+/).filter(Boolean);
  if (words.some((w) => FIRST_PERSON.has(w))) return true;
  return words.some((w, i) => REQUESTERS.has(w) && words.slice(i + 1, i + 4).some((n) => ACT_VERBS.has(n)));
}

/** Lower case without Polish diacritics, for matching words. */
export function fold(value: string): string {
  return value.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "").replace(/ł/g, "l");
}
