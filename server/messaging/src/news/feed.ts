import type { NewsItem } from "./feeds.js";
import { shortlist, type TopicItems } from "./rank.js";

// The feed (ADR-656): the stories behind what the person follows, as cards the app scrolls like a
// photo feed. Nothing here is written by an AI: a card is the publisher's headline, summary, picture
// and link, as they came from the feed. The follows come with each request and are not stored.

export interface FeedCard {
  /** Stable for one story across requests: the hash of its normalised link. */
  id: string;
  title: string;
  summary: string;
  url: string;
  source: string;
  publishedAt: string;
  imageUrl?: string;
  /** The follows this story belongs to, by label, in the order the person listed them. */
  follows: string[];
  /** The same story from other publishers (name and their own link), when there are any (13 Nov 2026). */
  alsoFrom?: { source: string; url: string }[];
}

export const FEED_LIMIT = 40;
export const FEED_WINDOW_HOURS = 48;
export const FEED_PER_SOURCE = 6;
/** Each follow's best stories that make the cut before the rest are filled by fit (On my radar, 10 Nov 2026). */
export const FEED_PER_FOLLOW = 4;

/**
 * Picks the cards: the last two days, one card per story (the same link, or the same headline from several
 * publishers, which the card then names), at most six per publisher, a keyword follow only where the words
 * really appear, the reader's language a little first. Every follow first gets its best few, so a busy topic
 * such as Poland (nine publishers) can't crowd a quiet one out of the 40; the rest are the best-fitting stories
 * (`shortlist`). They are shown newest first, the way a feed reads.
 */
export function buildFeed(topics: TopicItems[], now: Date, limit = FEED_LIMIT, language?: "en" | "pl"): FeedCard[] {
  const all = shortlist(topics, new Set(), now, { limit: 10 * FEED_LIMIT, perSource: FEED_PER_SOURCE, windowHours: FEED_WINDOW_HOURS, language });
  const chosen = new Set<string>();
  for (const label of new Set(topics.map((t) => t.label))) {
    let n = 0;
    for (const c of all) {
      if (n >= FEED_PER_FOLLOW || chosen.size >= limit) break;
      if (!c.topics.includes(label)) continue;
      chosen.add(c.id);
      n++;
    }
  }
  for (const c of all) {
    if (chosen.size >= limit) break;
    chosen.add(c.id);
  }
  const picked = all.filter((c) => chosen.has(c.id));
  const order = new Map(topics.map((t, i) => [t.label, i] as const));
  return picked
    .filter((c): c is typeof c & { publishedAt: string } => typeof c.publishedAt === "string")
    .sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt))
    .map((c) => ({
      id: c.urlHash.toString("hex"),
      title: c.title,
      summary: c.summary,
      url: c.url,
      source: c.source,
      publishedAt: c.publishedAt,
      ...(c.imageUrl ? { imageUrl: c.imageUrl } : {}),
      follows: [...new Set(c.topics)].sort((a, b) => (order.get(a) ?? 99) - (order.get(b) ?? 99)),
      ...(c.alsoFrom.length ? { alsoFrom: c.alsoFrom.map(({ source, url }) => ({ source, url })) } : {}),
    }));
}

/** Items a test or a fixture may hand in without a date are left out: a feed card always says when. */
export function datedOnly(items: NewsItem[]): NewsItem[] {
  return items.filter((i) => i.publishedAt);
}
