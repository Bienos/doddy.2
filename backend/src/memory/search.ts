import type { Turn } from "./contract.js";

/**
 * Lexical search over the notes and conversations a person keeps (ADR-595). The same rules as the
 * app's note search and the messaging server's memory copy: case and diacritics don't matter,
 * every term matches the start of a word (loosely, so inflected forms match), and nothing is invented: only what matches is returned.
 */

const EXTRA: Record<string, string> = { ł: "l", ß: "ss", æ: "ae", ø: "o", đ: "d", œ: "oe", þ: "th" };

export function fold(text: string): string {
  return text
    .toLowerCase()
    .replace(/[łßæøđœþ]/g, (c) => EXTRA[c] ?? c)
    .normalize("NFD")
    .replace(/\p{M}/gu, "");
}

const STOPWORDS = new Set([
  "a", "an", "the", "is", "are", "was", "what", "where", "when", "who", "my", "me", "i", "did", "do",
  "to", "of", "in", "on", "at", "for", "and", "or", "about", "you", "tell",
  "co", "gdzie", "kiedy", "kto", "jest", "mi", "moj", "moja", "moje", "to", "i", "w", "na", "o", "z",
]);

export function queryTerms(query: string): string[] {
  const terms = fold(query).split(/[^\p{L}\p{N}]+/u).filter((t) => t.length >= 2 && !STOPWORDS.has(t));
  return [...new Set(terms)].slice(0, 12);
}

const wordsOf = (text: string) => fold(text).split(/[^\p{L}\p{N}]+/u);

/**
 * The part of a term that has to start a word. A term of four letters or more loses its last one,
 * so an inflected form still matches ("Anna" finds "Anny" and "Annie", "Łukasz" finds "Łukasza",
 * "urodziny" finds "urodzin"). A wider net than the app's own note search on purpose: this feeds a
 * model that reads the matches, where a miss costs more than an extra note.
 */
const stem = (term: string) => (term.length >= 4 ? term.slice(0, -1) : term);

/** Which of `terms` start a word of `text` (loosely: see `stem`). */
export function matched(text: string, terms: string[]): string[] {
  const words = wordsOf(text);
  return terms.filter((term) => words.some((word) => word.startsWith(stem(term))));
}

/** Notes that match at least one term, most terms first, then newest. `pick` says where an item's text and time are. */
export function rankNotes<T>(items: T[], query: string, limit: number, pick: (item: T) => { text: string; capturedAt: number | null }): T[] {
  const terms = queryTerms(query);
  if (terms.length === 0) return [];
  return items
    .map((item) => ({ item, hits: matched(pick(item).text, terms).length, at: pick(item).capturedAt ?? 0 }))
    .filter((entry) => entry.hits > 0)
    .sort((a, b) => b.hits - a.hits || b.at - a.at)
    .slice(0, limit)
    .map((entry) => entry.item);
}

export interface SearchableConversation {
  id: string;
  /** Epoch milliseconds. */
  startedAt: number;
  turns: Turn[];
}

export interface ConversationExcerpt {
  id: string;
  startedAt: number;
  /** The best-matching turn with the turn before and after it. */
  turns: Turn[];
}

const EXCERPT_CHARS = 1_200;

/**
 * Conversations with at least one matching turn, best first (most distinct terms across the whole
 * conversation, then newest), each cut to the best turn and its neighbours.
 */
export function rankConversations(conversations: SearchableConversation[], query: string, limit: number): ConversationExcerpt[] {
  const terms = queryTerms(query);
  if (terms.length === 0) return [];
  const scored: { excerpt: ConversationExcerpt; hits: number }[] = [];
  for (const conversation of conversations) {
    const perTurn = conversation.turns.map((turn) => matched(turn.text, terms));
    const hits = new Set(perTurn.flat()).size;
    if (hits === 0) continue;
    let best = 0;
    perTurn.forEach((found, index) => {
      if (found.length > (perTurn[best]?.length ?? 0)) best = index;
    });
    // The matching turn is always in the excerpt (cut if it alone is too long); its neighbours join
    // only while they fit, so a long neighbour can never push out the turn that matched.
    const chars = (text: string) => [...text].length;
    const match = conversation.turns[best]!;
    const turns: Turn[] = [chars(match.text) > EXCERPT_CHARS ? { ...match, text: [...match.text].slice(0, EXCERPT_CHARS).join("") } : match];
    let size = chars(turns[0]!.text);
    const before = conversation.turns[best - 1];
    if (before && size + chars(before.text) <= EXCERPT_CHARS) {
      turns.unshift(before);
      size += chars(before.text);
    }
    const after = conversation.turns[best + 1];
    if (after && size + chars(after.text) <= EXCERPT_CHARS) turns.push(after);
    scored.push({ excerpt: { id: conversation.id, startedAt: conversation.startedAt, turns }, hits });
  }
  return scored.sort((a, b) => b.hits - a.hits || b.excerpt.startedAt - a.excerpt.startedAt).slice(0, limit).map((entry) => entry.excerpt);
}
