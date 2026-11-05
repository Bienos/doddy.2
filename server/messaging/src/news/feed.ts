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
}

export const FEED_LIMIT = 40;
export const FEED_WINDOW_HOURS = 48;
export const FEED_PER_SOURCE = 6;

/**
 * Picks the cards: the last two days, deduplicated by link and title, at most six per publisher,
 * a keyword follow only where the words really appear; the best-fitting stories make the cut
 * (`shortlist`), then they are shown newest first, the way a feed reads.
 */
export function buildFeed(topics: TopicItems[], now: Date, limit = FEED_LIMIT): FeedCard[] {
  const picked = shortlist(topics, new Set(), now, { limit, perSource: FEED_PER_SOURCE, windowHours: FEED_WINDOW_HOURS });
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
    }));
}

/** Items a test or a fixture may hand in without a date are left out: a feed card always says when. */
export function datedOnly(items: NewsItem[]): NewsItem[] {
  return items.filter((i) => i.publishedAt);
}
