import type { DocumentKind } from "./claude.js";

/**
 * Is a make_document request too thin to start (decision 2026-11-10-files-ask-for-details)?
 *
 * Doddy's voice agent is told to ask one or two short questions before it makes a file. This is the
 * code behind that: a bare topic ("Iława", "prezentacja o Iławie") is turned away at `prepare`, before
 * the ask card, before any single-use approval, any daily cap or any model call, with the list of what
 * is missing, so the agent asks the user and sends the request again with the answers in it.
 *
 * It is deliberately CAUTIOUS. It refuses only a request that has neither a purpose nor an audience and
 * is short. It never refuses one that gives material, states a purpose, names an audience, or is long
 * enough to be specific. A wrong "ok" costs one file the user can redo; a wrong refusal costs a
 * question the user did not need. To tune it, change the two constants and the cue lists below.
 */

/** The fixed set of things that can be missing. */
export const DETAIL_ITEMS = ["audience", "purpose", "length"] as const;
export type DetailItem = (typeof DETAIL_ITEMS)[number];

/** Title plus request with fewer words than this, and no purpose or audience cue, is a bare topic. */
export const THIN_WORDS = 9;
/** Material of at least this many characters (the user's own words, or what the conversation found) counts as enough. */
export const MATERIAL_ENOUGH_CHARS = 40;

/** Whole words or phrases that give a purpose. Polish and English. */
const PURPOSE_CUES = [
  "na potrzeby", "w celu", "po to", "żeby", "zeby", "aby", "ponieważ", "bo", "cel", "celem", "przekonać", "wyjaśnić", "przedstawić", "zaprezentować",
  "na lekcję", "na lekcje", "na spotkanie", "na zajęcia", "na zajecia", "na konferencję", "na konferencje",
  "so that", "in order to", "to explain", "to show", "to pitch", "to teach", "to persuade", "to present", "to introduce", "to summarize", "to summarise",
  "because", "purpose", "goal", "for a pitch", "for a talk", "for a lesson", "for a meeting", "for a class",
];
/** Whole words that name who it is for. */
const AUDIENCE_CUES = [
  "dla", "for", "klient", "klienta", "klientów", "uczniów", "uczniow", "klasy", "klasa", "studentów", "studentow", "zespołu", "zespolu", "zarządu", "zarzadu", "dzieci", "szefa", "rodziców", "rodzicow",
  "audience", "customers", "customer", "students", "teachers", "kids", "children", "team", "board", "investors", "client", "boss", "parents",
];
/** Whole words (or, when ending in "*", word starts) that give a length. */
const LENGTH_CUES = [
  "slajd*", "slajdów", "slides", "slide", "stron*", "page", "pages", "minut*", "minutes", "minute", "słów", "words", "wierszy", "rows",
  "krótk*", "short", "brief", "long", "dług*", "dlug*", "jedna strona", "one page",
];

const WORD = /[\p{L}\p{N}]+/gu;
const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** Whole-word (or word-start, for "stem*") match, case-insensitive, Unicode-aware ("dla" is not found in "podlać"). */
function hasCue(text: string, cues: readonly string[]): boolean {
  const lower = text.toLocaleLowerCase();
  return cues.some((cue) => {
    const stem = cue.endsWith("*");
    const body = escape(stem ? cue.slice(0, -1) : cue);
    return new RegExp(`(?<![\\p{L}\\p{N}])${body}${stem ? "" : "(?![\\p{L}\\p{N}])"}`, "u").test(lower);
  });
}

export const wordCount = (text: string): number => (text.match(WORD) ?? []).length;

export interface DocumentRequest {
  kind: DocumentKind;
  title: string;
  request: string;
  material?: string | undefined;
}

export type DetailsVerdict = { ok: true } | { ok: false; missing: DetailItem[] };

export function judgeDocumentRequest(input: DocumentRequest): DetailsVerdict {
  if ((input.material ?? "").trim().length >= MATERIAL_ENOUGH_CHARS) return { ok: true };
  const text = `${input.title} ${input.request}`;
  if (hasCue(text, PURPOSE_CUES) || hasCue(text, AUDIENCE_CUES)) return { ok: true };
  if (wordCount(text) >= THIN_WORDS) return { ok: true };
  const missing: DetailItem[] = ["audience", "purpose"];
  // A spreadsheet's size is its data, not a length the user would state, so only the other kinds ask for it.
  if (input.kind !== "spreadsheet" && !hasCue(text, LENGTH_CUES)) missing.push("length");
  return { ok: false, missing };
}

/** The one line that says what is missing; the app adds the instruction to ask and call again. */
export const needDetailsMessage = (missing: readonly DetailItem[]): string => `Missing details: ${missing.join(", ")}.`;
