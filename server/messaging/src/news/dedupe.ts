import { words } from "./match.js";

// One story, many publishers (decision 2026-11-13-news-more-sources). With ten Polish publishers behind "Poland",
// "Orlen podnosi ceny paliw" arrives from RMF24, Onet and Interia within the hour. A digest or a feed should carry it
// once, from one publisher, naming the others. Two stories are the same when their links are the same once
// canonicalised (`storyKey`), or when their headlines share most of their words (`sameHeadline`), allowing for Polish
// endings ("Lewandowski" / "Lewandowskiego"). The rule leans towards keeping two stories apart: "Orlen obniża ceny
// paliw" and "Orlen podnosi ceny paliw" stay two. Not a semantic model; small, predictable and tested.

/** Words that carry no story on their own (Polish and English), compared folded. */
const STOP = new Set([
  // Polish
  "ale", "bez", "byc", "byl", "byla", "bylo", "beda", "bedzie", "czy", "dla", "gdy", "ich", "jak", "jego", "jej", "jest",
  "juz", "jeszcze", "kiedy", "ktora", "ktore", "ktory", "ktorzy", "lub", "moze", "nad", "nie", "oraz", "pod", "po", "przez",
  "przy", "sie", "tak", "tej", "ten", "tez", "tym", "tylko", "wiec", "oto", "tego", "tych", "jako", "albo", "aby", "zeby",
  "relacja", "wideo", "video", "zobacz",
  // English
  "the", "and", "for", "are", "was", "were", "with", "from", "after", "over", "into", "its", "this", "that", "has", "have",
  "had", "will", "can", "not", "but", "his", "her", "their", "they", "who", "what", "why", "how", "says", "said", "new",
  "news", "live", "latest", "update", "updates", "watch",
]);

/**
 * The words of a headline that can tell two stories apart: folded, without the words above, without letter words
 * shorter than 3 letters. Numbers stay ("90", "2026"): "Bitcoin poniżej 90 tys." is not "poniżej 80 tys.".
 */
export function headlineTokens(title: string): string[] {
  return words(title).filter((w) => (/^\d+$/.test(w) || w.length >= 3) && !STOP.has(w));
}

/**
 * Two folded headline words are the same word, allowing for a changed ending ("orlen"/"orlenu", "tesla"/"tesli"):
 * they share their first four letters, or all but the last three of the shorter one. A word of three letters or fewer
 * ("CPK", "PiS", a number) only as itself.
 */
export function sameWord(a: string, b: string): boolean {
  if (a === b) return true;
  if (/^\d+$/.test(a) || /^\d+$/.test(b)) return false;
  const shortest = Math.min(a.length, b.length);
  if (shortest <= 3) return false;
  const need = Math.max(4, shortest - 3);
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  return i >= need;
}

/** How many words of `a` have a match in `b`, each word of `b` used once. */
export function sharedWords(a: string[], b: string[]): number {
  const used = new Array<boolean>(b.length).fill(false);
  let n = 0;
  for (const w of a) {
    const j = b.findIndex((v, k) => !used[k] && sameWord(w, v));
    if (j >= 0) {
      used[j] = true;
      n++;
    }
  }
  return n;
}

/**
 * The same story by its headline: at least 4 shared words making up at least 60% of both headlines (Dice), or, for
 * short headlines, 3 shared words making up at least 80%. Two headlines that both carry numbers but no number in
 * common are two stories ("poniżej 90 tys." is not "poniżej 80 tys.").
 */
export function sameHeadline(a: string[], b: string[]): boolean {
  if (a.length === 0 || b.length === 0) return false;
  const numbersA = a.filter((w) => /^\d+$/.test(w));
  const numbersB = new Set(b.filter((w) => /^\d+$/.test(w)));
  if (numbersA.length > 0 && numbersB.size > 0 && !numbersA.some((n) => numbersB.has(n))) return false;
  const shared = sharedWords(a, b);
  const dice = (2 * shared) / (a.length + b.length);
  return (shared >= 4 && dice >= 0.6) || (shared >= 3 && dice >= 0.8);
}

const TRACKING = /^(utm_|fbclid$|gclid$|mc_|ref$|cmpid$|amp$|output$|outputtype$|at_medium$|at_campaign$|ocid$|src$|source$)/i;

/**
 * A story's link, canonical enough to see that two publishers' feeds point at the same article: https, no "www."
 * or "m.", no fragment, no tracking or AMP parameters, no "/amp" ending, no trailing slash. Used only to group
 * stories; the link a person opens is the publisher's own.
 */
export function storyKey(raw: string): string {
  try {
    const u = new URL(raw);
    const host = u.hostname.toLowerCase().replace(/^(www|m|amp)\./, "");
    for (const k of [...u.searchParams.keys()]) if (TRACKING.test(k)) u.searchParams.delete(k);
    u.searchParams.sort();
    const path = u.pathname.replace(/\/amp\/?$/i, "").replace(/\/+$/, "");
    const query = u.searchParams.toString();
    return `${host}${path}${query ? `?${query}` : ""}`;
  } catch {
    return raw;
  }
}

/**
 * Groups items into stories as they are added, looking only at earlier items that share a word's first four letters
 * (or a number), so a pass over a few thousand headlines stays fast.
 */
export class StoryIndex<T> {
  private readonly groups: { tokens: string[]; members: T[] }[] = [];
  private readonly byKey = new Map<string, number>();
  private readonly byTitle = new Map<string, number>();
  private readonly byWord = new Map<string, number[]>();

  /** Adds an item; returns the index of its story (an existing one when the link or headline matches). */
  add(item: T, title: string, url: string): number {
    const key = storyKey(url);
    const tokens = headlineTokens(title);
    const folded = words(title).join(" ");
    const found = this.byKey.get(key) ?? this.find(tokens, folded);
    if (found !== undefined) {
      this.groups[found]!.members.push(item);
      if (!this.byKey.has(key)) this.byKey.set(key, found);
      if (folded && !this.byTitle.has(folded)) this.byTitle.set(folded, found);
      return found;
    }
    const index = this.groups.length;
    this.groups.push({ tokens, members: [item] });
    this.byKey.set(key, index);
    if (folded) this.byTitle.set(folded, index);
    for (const p of new Set(tokens.map(prefix))) {
      const list = this.byWord.get(p);
      if (list) list.push(index);
      else this.byWord.set(p, [index]);
    }
    return index;
  }

  /** True when the headline is the same story as one already added. */
  has(title: string): boolean {
    return this.find(headlineTokens(title), words(title).join(" ")) !== undefined;
  }

  stories(): T[][] {
    return this.groups.map((g) => g.members);
  }

  private find(tokens: string[], folded: string): number | undefined {
    // The same headline word for word is the same story, however short (the only rule until 13 Nov 2026).
    const exact = folded ? this.byTitle.get(folded) : undefined;
    if (exact !== undefined) return exact;
    const seen = new Set<number>();
    for (const p of new Set(tokens.map(prefix))) {
      for (const g of this.byWord.get(p) ?? []) {
        if (seen.has(g)) continue;
        seen.add(g);
        if (sameHeadline(tokens, this.groups[g]!.tokens)) return g;
      }
    }
    return undefined;
  }
}

/** The bucket a headline word is looked up by: a number whole, a word by its first four letters. */
function prefix(w: string): string {
  return /^\d+$/.test(w) ? `#${w}` : w.slice(0, 4);
}
