import type { Db } from "../db.js";
import type { NewsItem } from "./feeds.js";
import { validator } from "./safeFetch.js";
import { cacheKey, fitForCache, type FeedSource, type FetchedFeed } from "./sources.js";

// Reading publishers' feeds for Daily news, On my radar's feed and its alert worker (decision
// 2026-11-13-news-more-sources). Until 13 Nov 2026 each caller read the shared cache one feed and one query at a
// time and fetched every stale feed at once, unconditionally. Now:
// - one query reads the cache rows of every feed a caller needs (a word follow looks through every catalog feed);
// - a feed is fetched once per pass, however many follows, digests or alerts in that pass read it (`FeedReader`), and
//   once in this process at a time, whoever asks (Daily news and the radar worker share the answer);
// - at most FEED_FETCH_CONCURRENCY fetches run at once in this process, so sockets and memory stay bounded
//   (each body is at most 2 MB, safeFetch);
// - a stale feed is asked "changed since?" with the publisher's own validators (ETag, Last-Modified, migration
//   036), and an unchanged one answers 304 with no body;
// - a cached feed keeps only stories from the last FEED_KEEP_HOURS (and undated ones), at most
//   NEWS_CACHE_MAX_ROW_BYTES of them: nothing reads further back than 48 hours.
// A reader counts what it did (`stats`) so callers can log counts and timings, never a word of a feed or an address.

/** How long a fetched feed is used before it is asked again, in minutes. */
export const FEED_CACHE_MINUTES = 30;
/** Feeds fetched at once by this process, whoever asks. */
export const FEED_FETCH_CONCURRENCY = 8;
/** Stories older than this (by their own date) are not kept in the cache; every reader looks at most 48 h back. */
export const FEED_KEEP_HOURS = 72;

export interface ReadFeed { ok: boolean; title?: string; items: NewsItem[] }

/** What a reader did, counts only. `feeds` = distinct feeds read; the rest say how each was answered. */
export interface ReaderStats {
  feeds: number;
  /** Fresh in the shared cache: no request to the publisher. */
  fromCache: number;
  /** Fetched and parsed. */
  fetched: number;
  /** Asked "changed since?" and the publisher said no (304). */
  notModified: number;
  /** The publisher didn't answer with a feed (the last good stories, if any, are used). */
  failed: number;
  /** Another caller in this process was already fetching it; its answer was used. */
  shared: number;
}

interface CacheRow {
  key: string; fresh: boolean; ok: boolean; title: string | null; items: NewsItem[]; etag: string | null; last_modified: string | null;
}

type Outcome = "fetched" | "notModified" | "failed";

// ── One fetch at a time per feed, and a bounded number in all ─────────────────────────────────────

const inflight = new Map<string, Promise<{ feed: ReadFeed; outcome: Outcome }>>();
let active = 0;
const waiting: (() => void)[] = [];

/** Runs `fn` when one of FEED_FETCH_CONCURRENCY slots is free; a finished fetch hands its slot to the next in line. */
async function withSlot<T>(fn: () => Promise<T>): Promise<T> {
  if (active < FEED_FETCH_CONCURRENCY) active++;
  else await new Promise<void>((resolve) => waiting.push(resolve));
  try {
    return await fn();
  } finally {
    const next = waiting.shift();
    if (next) next();
    else active--;
  }
}

/** For tests: fetches running and waiting in this process. */
export function fetchSlots(): { active: number; waiting: number } {
  return { active, waiting: waiting.length };
}

/** Stories dated within the last FEED_KEEP_HOURS before `now`, or undated, in their order. */
export function keepRecent(items: NewsItem[], now: Date): NewsItem[] {
  const from = now.getTime() - FEED_KEEP_HOURS * 3_600_000;
  return items.filter((i) => !i.publishedAt || Date.parse(i.publishedAt) >= from);
}

async function refresh(db: Db, source: FeedSource, url: string, key: string, row: CacheRow | undefined, now: Date): Promise<{ feed: ReadFeed; outcome: Outcome }> {
  // "Changed since?" only when there is a good answer to keep.
  const conditional = row?.ok && row.items.length > 0 && (row.etag || row.last_modified)
    ? { etag: row.etag ?? undefined, lastModified: row.last_modified ?? undefined } : undefined;
  let got: FetchedFeed | undefined;
  try {
    got = await withSlot(() => source.fetchFeed(url, conditional));
  } catch {
    got = undefined;
  }
  if (!got || (got.notModified && !conditional)) {
    await db.query(
      `INSERT INTO news_cache (key, fetched_at, ok) VALUES ($1, now(), false)
       ON CONFLICT (key) DO UPDATE SET fetched_at = now(), ok = false`, [key]);
    return { feed: { ok: false, title: row?.title ?? undefined, items: row?.items ?? [] }, outcome: "failed" };
  }
  if (got.notModified) {
    await db.query("UPDATE news_cache SET fetched_at = now(), ok = true WHERE key = $1", [key]);
    return { feed: { ok: true, title: row!.title ?? undefined, items: row!.items }, outcome: "notModified" };
  }
  const items = fitForCache(keepRecent(got.items, now));
  await db.query(
    `INSERT INTO news_cache (key, fetched_at, ok, title, items, etag, last_modified) VALUES ($1, now(), true, $2, $3, $4, $5)
     ON CONFLICT (key) DO UPDATE SET fetched_at = now(), ok = true, title = EXCLUDED.title, items = EXCLUDED.items,
       etag = EXCLUDED.etag, last_modified = EXCLUDED.last_modified`,
    [key, got.title || null, JSON.stringify(items), validator(got.etag) ?? null, validator(got.lastModified) ?? null]);
  return { feed: { ok: true, title: got.title || undefined, items }, outcome: "fetched" };
}

/**
 * Reads feeds through the shared cache for one request or one worker pass. Each feed is read once per reader;
 * `preload` reads many cache rows in one query. Not linked to any account: the cache key is a hash of the address.
 */
export class FeedReader {
  readonly stats: ReaderStats = { feeds: 0, fromCache: 0, fetched: 0, notModified: 0, failed: 0, shared: 0 };
  private readonly memo = new Map<string, Promise<ReadFeed>>();
  private readonly now: Date;
  private readonly maxAgeMinutes: number;

  constructor(private readonly db: Db, private readonly source: FeedSource, options: { now?: Date; maxAgeMinutes?: number } = {}) {
    this.now = options.now ?? new Date();
    this.maxAgeMinutes = options.maxAgeMinutes ?? FEED_CACHE_MINUTES;
  }

  /** Starts reading every given feed not read yet: one query for their cache rows, then the stale ones are fetched. */
  preload(urls: Iterable<string>): void {
    const todo = [...new Set(urls)].filter((u) => !this.memo.has(u));
    if (todo.length === 0) return;
    const keys = todo.map((u) => cacheKey(`feed:${u}`));
    const rows = this.db.query<CacheRow>(
      `SELECT key, fetched_at > now() - make_interval(mins => $2) AS fresh, ok, title, items, etag, last_modified
         FROM news_cache WHERE key = ANY($1::text[])`, [keys, this.maxAgeMinutes])
      .then((r) => new Map(r.rows.map((row) => [row.key, row])));
    todo.forEach((url, i) => {
      this.stats.feeds++;
      const p = rows.then((m) => this.answer(url, keys[i]!, m.get(keys[i]!)));
      p.catch(() => {}); // the caller that reads it gets the error; nobody else should crash on it
      this.memo.set(url, p);
    });
  }

  read(url: string): Promise<ReadFeed> {
    this.preload([url]);
    return this.memo.get(url)!;
  }

  private async answer(url: string, key: string, row: CacheRow | undefined): Promise<ReadFeed> {
    if (row?.fresh) {
      this.stats.fromCache++;
      return { ok: row.ok, title: row.title ?? undefined, items: row.items };
    }
    let pending = inflight.get(key);
    if (pending) {
      this.stats.shared++;
      return (await pending).feed;
    }
    pending = refresh(this.db, this.source, url, key, row, this.now).finally(() => inflight.delete(key));
    inflight.set(key, pending);
    const r = await pending;
    this.stats[r.outcome]++;
    return r.feed;
  }
}
