// Lexical search over a user's decrypted memory copy, mirroring the app's rules
// (case- and diacritic-insensitive, prefix terms, no invention).

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

export interface SearchableMemory { id: string; text: string; capturedAt: Date | null }
export interface MemoryHit { id: string; text: string; capturedAt: Date | null; matched: string[] }

/** Ranked by number of matched terms, then most recent. Only memories that match are returned. */
export function searchMemories(memories: SearchableMemory[], query: string, limit = 5): MemoryHit[] {
  const terms = queryTerms(query);
  if (terms.length === 0) return [];
  const hits: MemoryHit[] = [];
  for (const m of memories) {
    const words = fold(m.text).split(/[^\p{L}\p{N}]+/u);
    const matched = terms.filter((t) => words.some((w) => w.startsWith(t)));
    if (matched.length) hits.push({ ...m, matched });
  }
  return hits
    .sort((a, b) => b.matched.length - a.matched.length
      || (b.capturedAt?.getTime() ?? 0) - (a.capturedAt?.getTime() ?? 0))
    .slice(0, limit);
}
