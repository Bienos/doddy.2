import { sha256 } from "../crypto.js";
import { StoryIndex } from "./dedupe.js";
import type { NewsItem } from "./feeds.js";
import { matchesKeyword } from "./match.js";

export interface TopicItems {
  label: string;
  keywords: string[];
  /** true: every item already belongs to the topic (curated feed or keyword search). */
  curated: boolean;
  items: NewsItem[];
}

/** The same story from another publisher: its name, its own link and headline. */
export interface AlsoFrom { source: string; url: string; title: string }

export interface Candidate extends NewsItem {
  id: string;
  topics: string[];
  score: number;
  urlHash: Buffer;
  /** The same story from other publishers, one per publisher, best first, at most ALSO_FROM_MAX (dedupe.ts). */
  alsoFrom: AlsoFrom[];
}

const TRACKING = /^(utm_|fbclid$|gclid$|mc_|ref$|cmpid$)/i;

export function normalizeUrl(raw: string): string {
  try {
    const u = new URL(raw);
    u.hash = "";
    u.hostname = u.hostname.toLowerCase();
    for (const k of [...u.searchParams.keys()]) if (TRACKING.test(k)) u.searchParams.delete(k);
    return u.toString();
  } catch { return raw; }
}

/** The hash a story is remembered by (news_sent, radar_hits, a card's id). Unchanged on 13 Nov 2026, so nothing stored moves. */
export function urlHash(raw: string): Buffer {
  return sha256(normalizeUrl(raw));
}

// Allows for Polish and English word endings ("kryptowaluty" finds "kryptowalut"), news/match.ts.
const matches = (text: string, keyword: string): boolean => matchesKeyword(text, keyword);

/** Other publishers named with a story, at most. */
export const ALSO_FROM_MAX = 3;
/** Each story already picked from the same publisher costs a candidate this much, so the list mixes publishers. */
export const DIVERSITY_PENALTY = 0.35;
/** A story in the reader's own language (catalog.ts `lang`) gains this much: Polish first for a Polish reader. */
export const LANGUAGE_BONUS = 0.3;
/** Each other publisher carrying the same story (up to two) gains it this much: a story many report matters more. */
export const CORROBORATION_BONUS = 0.15;

/**
 * Deterministic shortlist before any AI: recent (36 h), not sent before, one entry per story (the same link, or the
 * same headline from several publishers, dedupe.ts, keeps the best one and names the others), scored by topic fit,
 * freshness, the reader's language and how many publishers carry it, then picked so publishers alternate, at most 3
 * per publisher. The AI only ever picks from this list, and links always come from it.
 */
export interface ShortlistOptions {
  /** How many stories at most (digest: 25). */
  limit?: number;
  /** Stories per publisher at most (digest: 3). */
  perSource?: number;
  /** How old a story may be, in hours (digest: 36). */
  windowHours?: number;
  /** The reader's language: stories in it rank a little higher (LANGUAGE_BONUS). */
  language?: "en" | "pl";
  /** Headlines the person was already told (a digest's last days): the same story from another publisher is not told again. */
  sentTitles?: readonly string[];
}

interface Entry {
  item: NewsItem;
  hash: Buffer;
  hex: string;
  age: number;
  /** Fit per follow label. */
  fit: Map<string, number>;
  order: number;
}

const total = (e: Entry) => [...e.fit.values()].reduce((s, n) => s + n, 0);

export function shortlist(topics: TopicItems[], alreadySent: Set<string>, now: Date, options: number | ShortlistOptions = {}): Candidate[] {
  const opts = typeof options === "number" ? { limit: options } : options;
  const limit = opts.limit ?? 25;
  const perSourceMax = opts.perSource ?? 3;
  const windowMs = (opts.windowHours ?? 36) * 3_600_000;

  // 1. One entry per link (normalised), with its fit for each follow it belongs to.
  const byUrl = new Map<string, Entry>();
  for (const topic of topics) {
    for (const item of topic.items) {
      if (!item.publishedAt) continue;
      const age = now.getTime() - Date.parse(item.publishedAt);
      if (!(age <= windowMs && age >= -3_600_000)) continue; // too old, too far in the future, or not a date
      const hash = urlHash(item.url);
      const hex = hash.toString("hex");
      const kw = topic.keywords.reduce((s, k) => s + (matches(item.title, k) ? 3 : matches(item.summary, k) ? 1 : 0), 0);
      if (!topic.curated && kw === 0) continue;
      const fit = (topic.curated ? 1 : 0) + kw;
      const existing = byUrl.get(hex);
      if (existing) {
        existing.fit.set(topic.label, (existing.fit.get(topic.label) ?? 0) + fit);
        continue;
      }
      byUrl.set(hex, { item, hash, hex, age, fit: new Map([[topic.label, fit]]), order: byUrl.size });
    }
  }

  // 2. One story per group of links and near-same headlines; a story already sent (by any of its links, or by a
  //    headline the person was told) is left out.
  const index = new StoryIndex<Entry>();
  for (const e of byUrl.values()) index.add(e, e.item.title, e.item.url);
  const told = new StoryIndex<number>();
  (opts.sentTitles ?? []).forEach((t, i) => told.add(i, t, `told:${i}`));
  const rank = (a: Entry, b: Entry) =>
    total(b) - total(a)
    || Number(b.item.lang === opts.language) - Number(a.item.lang === opts.language)
    || Number(!!b.item.imageUrl) - Number(!!a.item.imageUrl)
    || a.order - b.order;
  const stories = index.stories().flatMap((members) => {
    if (members.some((m) => alreadySent.has(m.hex))) return [];
    if (opts.sentTitles?.length && members.some((m) => told.has(m.item.title))) return [];
    const sorted = [...members].sort(rank);
    const fit = new Map<string, number>();
    for (const m of sorted) for (const [label, n] of m.fit) fit.set(label, Math.max(fit.get(label) ?? 0, n));
    const newest = Math.min(...members.map((m) => Math.max(m.age, 0)));
    const others = new Set(members.map((m) => m.item.source)).size - 1;
    const score = [...fit.values()].reduce((s, n) => s + n, 0) + (windowMs - newest) / windowMs
      + Math.min(others, 2) * CORROBORATION_BONUS
      + (opts.language && sorted.some((m) => m.item.lang === opts.language) ? LANGUAGE_BONUS : 0);
    // Follows in the order the stories first named them.
    const labels = [...new Set([...members].sort((a, b) => a.order - b.order).flatMap((m) => [...m.fit.keys()]))];
    return [{ members: sorted, score, labels }];
  }).sort((a, b) => b.score - a.score);

  // 3. Picked best first, each publisher's next story costing DIVERSITY_PENALTY more, at most perSourceMax each. A
  //    story carried by several publishers is told from a copy that fits the follows best (so a word follow's card
  //    keeps the word in its headline), from the publisher used least so far among those, its best-ranked on a tie.
  const perSource = new Map<string, number>();
  const used = (s: string) => perSource.get(s) ?? 0;
  const left = new Set(stories.keys());
  const picked: { story: (typeof stories)[number]; rep: Entry }[] = [];
  while (picked.length < limit && left.size > 0) {
    let best: { i: number; member: Entry; value: number } | undefined;
    for (const i of left) {
      const story = stories[i]!;
      if (best && story.score <= best.value) break; // sorted: nothing later can beat it
      const open = story.members.filter((m) => used(m.item.source) < perSourceMax);
      if (open.length === 0) {
        left.delete(i);
        continue;
      }
      const bestFit = Math.max(...open.map(total));
      const member = open.filter((m) => total(m) === bestFit).reduce((a, b) => (used(b.item.source) < used(a.item.source) ? b : a));
      const value = story.score - DIVERSITY_PENALTY * used(member.item.source);
      if (!best || value > best.value) best = { i, member, value };
    }
    if (!best) break;
    left.delete(best.i);
    perSource.set(best.member.item.source, used(best.member.item.source) + 1);
    picked.push({ story: stories[best.i]!, rep: best.member });
  }

  // 4. A story several publishers carry is told by one that has nothing else in the list, when one fits as well
  //    (the same fit for the follows), so "Orlen" from RMF24 and "Sejm" from TVN24, not both from TVN24.
  for (const p of picked) {
    if (used(p.rep.item.source) <= 1) continue;
    const swap = p.story.members.find((m) => used(m.item.source) === 0 && total(m) === total(p.rep));
    if (!swap) continue;
    perSource.set(p.rep.item.source, used(p.rep.item.source) - 1);
    perSource.set(swap.item.source, 1);
    p.rep = swap;
  }

  return picked.map(({ story, rep }, i) => {
    const seen = new Set([rep.item.source]);
    const alsoFrom: AlsoFrom[] = [];
    for (const m of story.members) {
      if (seen.has(m.item.source) || alsoFrom.length >= ALSO_FROM_MAX) continue;
      seen.add(m.item.source);
      alsoFrom.push({ source: m.item.source, url: m.item.url, title: m.item.title });
    }
    return { ...rep.item, id: `s${i + 1}`, topics: story.labels, score: story.score, urlHash: rep.hash, alsoFrom };
  });
}
