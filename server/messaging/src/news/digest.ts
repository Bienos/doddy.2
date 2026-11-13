import { randomUUID } from "node:crypto";
import type { TextCipher } from "../crypto.js";
import { inTransaction, type Db } from "../db.js";
import { log } from "../log.js";
import { EncryptionNotConfigured, enqueue, SmsDailyLimit, usableChannels, type Channel } from "../outbox.js";
import { ALL_CATALOG_FEEDS, catalogById, type CatalogFeed } from "./catalog.js";
import { pushBody, smsBody } from "./compose.js";
import type { NewsItem } from "./feeds.js";
import { shortlist, type TopicItems } from "./rank.js";
import { localDate, nextRunAt } from "./schedule.js";
import { cached, searchQuery, type FeedSource, type NewsSearch } from "./sources.js";
import type { NewsSummaryDeps } from "./summary.js";
import { reserveWriter, type NewsWriterCaps } from "./usage.js";
import { shorten, validateLines, type DigestWriter } from "./writer.js";

export interface NewsDeps {
  feeds: FeedSource;
  search?: NewsSearch;
  writer?: DigestWriter;
  /** Encrypts queued digest text at rest when the server has the key. */
  cipher?: TextCipher;
  /** Texts queued per UTC day, per account and for the server (ADR-704). Default DEFAULT_ABUSE_LIMITS. */
  smsCaps?: { perAccount: number; perServer: number };
  /** Digests the writer may write per UTC day: per account, for the server, for new accounts. Default DEFAULT_NEWS_WRITER_CAPS. */
  writerCaps?: NewsWriterCaps;
  /** The AI summary of a story the person taps (POST /v1/news/summary, src/news/summary.ts). Absent: 503 not_configured. */
  summaries?: NewsSummaryDeps;
}

export const MAX_TOPICS = 10;
export const MAX_FEEDS = 10;
const MAX_SEARCHES = 3;

export interface DigestResult {
  digestId?: string;
  /** queued = sent through at least one channel; ready = kept for the app only, nothing sent. */
  status: "queued" | "ready" | "empty" | "failed" | "skipped";
  aiWritten?: boolean;
  errorCode?: string;
}

interface Settings { timezone: string; language: "en" | "pl"; channels: Channel[] }

/**
 * Builds today's digest for one account, keeps it for the app, and hands it to the outbox for the
 * chosen channels. Every link and source comes from a fetched feed or search result; the AI only
 * chooses and phrases. With no channel (none chosen, or the chosen ones aren't set up any more)
 * the digest is still kept and readable in the app (ADR-174).
 */
export async function buildDigest(db: Db, news: NewsDeps, accountId: string, kind: "scheduled" | "manual", now = new Date()): Promise<DigestResult> {
  const { rows: st } = await db.query<Settings>(
    "SELECT timezone, language, channels FROM news_settings WHERE account_id = $1", [accountId]);
  const settings = st[0];
  if (!settings) return { status: "failed", errorCode: "no_settings" };

  const digestId = randomUUID();
  const inserted = await db.query(
    `INSERT INTO news_digests (id, account_id, kind, local_date, status) VALUES ($1, $2, $3, $4, 'building')
     ON CONFLICT DO NOTHING`,
    [digestId, accountId, kind, localDate(now, settings.timezone)]);
  if (!inserted.rowCount) return { status: "skipped" }; // today's scheduled digest already exists
  const finish = async (r: DigestResult) => {
    await db.query("UPDATE news_digests SET status = $2, ai_written = $3, error_code = $4 WHERE id = $1",
      [digestId, r.status, r.aiWritten ?? false, r.errorCode ?? null]);
    return { ...r, digestId };
  };

  try {
    const topics = await gatherTopics(db, news, accountId, settings.language, now);
    if (topics.length === 0) return finish({ status: "empty", errorCode: "no_topics" });
    const { rows: sent } = await db.query<{ hex: string }>(
      `SELECT encode(url_hash, 'hex') AS hex FROM news_sent WHERE account_id = $1 AND sent_at > now() - interval '14 days'`,
      [accountId]);
    const candidates = shortlist(topics, new Set(sent.map((s) => s.hex)), now);
    if (candidates.length === 0) return finish({ status: "empty" });

    let picks: { candidate: (typeof candidates)[number]; line: string }[] = [];
    let aiWritten = false;
    // Counted before the writer is asked (src/news/usage.ts). Past a daily cap: plain headlines, as when it is down.
    const reserved = news.writer ? await reserveWriter(db, accountId, news.writerCaps, now) : undefined;
    if (reserved && reserved !== "ok") log("news writer skipped, daily limit", { scope: reserved });
    if (news.writer && reserved === "ok") {
      try {
        picks = validateLines(await news.writer.write({
          language: settings.language, topics: topics.map((t) => t.label), candidates,
        }), candidates);
        aiWritten = picks.length > 0;
      } catch (err) {
        // A code only (writer_*, or the HTTP status), never story text or keys.
        const code = err instanceof Error && /^writer_[a-z0-9_]+$/.test(err.message) ? err.message
          : `writer_error${typeof (err as { status?: unknown })?.status === "number" ? `_${(err as { status: number }).status}` : ""}`;
        log("news writer failed, plain headlines used", { code });
        picks = []; // fall back to plain headlines below
      }
    }
    if (picks.length === 0) picks = candidates.slice(0, 3).map((c) => ({ candidate: c, line: shorten(c.title, 140) }));

    const channels = await usableChannels(db, accountId, settings.channels);

    const entries = picks.map((p) => ({ line: p.line, url: p.candidate.url, source: p.candidate.source }));
    const queued: Channel[] = [];
    // One transaction: stories count as sent only if the digest was really kept and queued.
    await inTransaction(db, async (c) => {
      for (const [i, p] of picks.entries()) {
        await c.query(
          `INSERT INTO news_digest_items (digest_id, position, title, line, url, source, published_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [digestId, i, p.candidate.title, p.line, p.candidate.url, p.candidate.source, p.candidate.publishedAt]);
        await c.query(
          `INSERT INTO news_sent (account_id, url_hash) VALUES ($1, $2)
           ON CONFLICT (account_id, url_hash) DO UPDATE SET sent_at = now()`, [accountId, p.candidate.urlHash]);
      }
      for (const ch of channels) {
        const body = ch === "push" ? pushBody(entries, settings.language) : smsBody(entries, settings.language);
        try {
          await enqueue(c, accountId, [ch], body, now, `news:${digestId}`, { cipher: news.cipher, smsCaps: news.smsCaps });
          queued.push(ch);
        } catch (err) {
          // A channel that can't take the digest now (the day's cap on texts, ADR-704; production without the
          // encryption key, ADR-706) is skipped. The digest is still kept for the app, like one with no channel.
          if (!(err instanceof SmsDailyLimit || err instanceof EncryptionNotConfigured)) throw err;
          log("news digest channel skipped", { channel: ch, reason: err instanceof SmsDailyLimit ? "daily_limit" : "not_configured" });
        }
      }
    });
    // writer_daily_limit: plain headlines because a daily cap on the writer was reached (the app says "headlines only").
    const capped = reserved && reserved !== "ok" ? "writer_daily_limit" : undefined;
    if (queued.length === 0) {
      // Kept for the app. no_channel only when the user chose a channel that can't be used now; it wins, as the app reads it.
      return finish({ status: "ready", aiWritten, errorCode: settings.channels.length > 0 ? "no_channel" : capped });
    }
    return finish({ status: "queued", aiWritten, errorCode: capped });
  } catch {
    return finish({ status: "failed", errorCode: "build_error" });
  }
}

async function gatherTopics(db: Db, news: NewsDeps, accountId: string, language: "en" | "pl", now: Date): Promise<TopicItems[]> {
  const { rows: topics } = await db.query<FollowedTopic>(
    "SELECT catalog_id, label, keywords FROM news_topics WHERE account_id = $1 ORDER BY position", [accountId]);
  const { rows: feeds } = await db.query<{ url: string }>("SELECT url FROM news_feeds WHERE account_id = $1", [accountId]);
  return gatherItems(db, news, topics, feeds.map((f) => f.url), language, now);
}

export interface FollowedTopic {
  catalog_id: string | null;
  label: string;
  keywords: string[];
  /** On my radar: the person's own RSS or Atom feed (checked by checkUrl before it gets here). */
  feed_url?: string | null;
}

/** What one follow read: its publishers, and whether each answered (On my radar shows them). */
export interface FollowSources {
  /** The publishers behind a catalog topic or the person's own feed. Empty for the person's own words. */
  sources: { name: string; ok: boolean }[];
  /** The person's own words: how many publishers' feeds were looked through for them. */
  searchedFeeds?: number;
}

export interface GatherOptions {
  /**
   * Where the person's own words are looked for, besides a news search when the server has one:
   * "follows" (the daily digest, as before): the stories of their other topics;
   * "catalog" (On my radar): every feed in the catalog and their own feeds, so "Tesla" finds stories
   * even when they follow nothing else (the live server has no news search key, read 10 Nov 2026).
   */
  keywordPool?: "follows" | "catalog";
  /** Filled with each follow's sources, by label. */
  report?: Map<string, FollowSources>;
}

const hostOf = (url: string) => {
  try { return new URL(url).hostname; } catch { return url; }
};

/**
 * Fetches (through the shared cache) what the given topics and feeds carry right now. Used by the
 * daily digest with the account's saved topics, by the feed (ADR-656) with the follows the iPhone
 * sends along, which are never stored, and by radar alerts (decision 2026-11-10-radar-alerts).
 * A catalog story carries the publisher's short name ("CoinDesk"), not its feed's long title.
 */
export async function gatherItems(
  db: Db, news: NewsDeps, topics: FollowedTopic[], feedUrls: string[], language: "en" | "pl", now: Date,
  options: GatherOptions = {},
): Promise<TopicItems[]> {
  // One fetch per address per call, however many follows share it.
  const fetched = new Map<string, Promise<{ ok: boolean; title?: string; items: NewsItem[] }>>();
  const load = (url: string) => {
    let pending = fetched.get(url);
    if (!pending) {
      pending = cached(db, `feed:${url}`, 30, () => news.feeds.fetchFeed(url));
      fetched.set(url, pending);
    }
    return pending;
  };
  const named = async (f: CatalogFeed) => {
    const r = await load(f.url);
    return { name: f.name, ok: r.ok, items: r.items.map((i) => ({ ...i, source: f.name })) };
  };

  const out: TopicItems[] = [];
  const pool: NewsItem[] = [];
  const read = new Set<string>(feedUrls);
  for (const t of topics) {
    if (t.feed_url) {
      const r = await load(t.feed_url);
      read.add(t.feed_url);
      pool.push(...r.items);
      out.push({ label: t.label, keywords: t.keywords, curated: t.keywords.length === 0, items: r.items });
      options.report?.set(t.label, { sources: [{ name: r.title || hostOf(t.feed_url), ok: r.ok }] });
      continue;
    }
    const cat = t.catalog_id ? catalogById.get(t.catalog_id) : undefined;
    if (!cat) continue;
    const answers = await Promise.all(cat.feeds.map(named));
    for (const f of cat.feeds) read.add(f.url);
    const items = answers.flatMap((r) => r.items);
    pool.push(...items);
    out.push({ label: t.label, keywords: t.keywords, curated: true, items });
    options.report?.set(t.label, { sources: answers.map((r) => ({ name: r.name, ok: r.ok })) });
  }
  if (feedUrls.length) {
    const items = (await Promise.all(feedUrls.map(load))).flatMap((r) => r.items);
    pool.push(...items);
    out.push({ label: language === "pl" ? "Twoje źródła" : "Your feeds", keywords: [], curated: true, items });
  }
  const keywordTopics = topics.filter((x) => !x.catalog_id && !x.feed_url && x.keywords.length);
  let searchPool = pool;
  if (options.keywordPool === "catalog" && keywordTopics.length) {
    const everything = await Promise.all(ALL_CATALOG_FEEDS.map(named));
    for (const f of ALL_CATALOG_FEEDS) read.add(f.url);
    searchPool = [...pool, ...everything.flatMap((r) => r.items)];
  }
  // The user's own keyword topics: a news search when configured, plus matches in the pool above.
  let searches = 0;
  for (const t of keywordTopics) {
    let found: NewsItem[] = [];
    const q = searchQuery(t.keywords);
    if (news.search && q && searches < MAX_SEARCHES) {
      searches++;
      const since = new Date(now.getTime() - 36 * 3_600_000);
      found = (await cached(db, `search:${language}:${q}`, 60, async () => ({ items: await news.search!.search(q, language, since) }))).items;
    }
    out.push({ label: t.label, keywords: t.keywords, curated: true, items: found });
    out.push({ label: t.label, keywords: t.keywords, curated: false, items: searchPool });
    options.report?.set(t.label, { sources: [], searchedFeeds: read.size });
  }
  return out;
}

/** A digest more than this late is not sent: the server slept through its time (free plan). */
export const DIGEST_MAX_LATE_MS = 2 * 3_600_000;

/**
 * Scheduler pass: claims accounts whose digest time has come, moves their next run to tomorrow
 * first (so a crash can't cause a repeat), then builds each digest. One that is more than two hours
 * late is skipped, not sent at a random hour: tomorrow's comes at its usual time.
 */
export async function runDueDigests(db: Db, news: NewsDeps, batch = 5, now = new Date()): Promise<number> {
  const client = await db.connect();
  const due: string[] = [];
  try {
    await client.query("BEGIN");
    const { rows } = await client.query<{ account_id: string; send_time: string; timezone: string; next_run_at: Date }>(
      `SELECT account_id, to_char(send_time, 'HH24:MI') AS send_time, timezone, next_run_at FROM news_settings
       WHERE enabled AND next_run_at <= $2 ORDER BY next_run_at LIMIT $1 FOR UPDATE SKIP LOCKED`, [batch, now]);
    for (const r of rows) {
      await client.query("UPDATE news_settings SET next_run_at = $2 WHERE account_id = $1",
        [r.account_id, nextRunAt(now, r.send_time, r.timezone)]);
    }
    await client.query("COMMIT");
    for (const r of rows) {
      const lateMs = now.getTime() - r.next_run_at.getTime();
      if (lateMs > DIGEST_MAX_LATE_MS) log("news digest skipped, too late", { accountId: r.account_id, lateMinutes: Math.round(lateMs / 60_000) });
      else due.push(r.account_id);
    }
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
  for (const accountId of due) await buildDigest(db, news, accountId, "scheduled", now);
  // Housekeeping: interrupted builds, old dedupe rows, old digests.
  await db.query("UPDATE news_digests SET status = 'failed', error_code = 'interrupted' WHERE status = 'building' AND created_at < now() - interval '15 minutes'");
  await db.query("DELETE FROM news_sent WHERE sent_at < now() - interval '14 days'");
  await db.query("DELETE FROM news_digests WHERE created_at < now() - interval '30 days'");
  return due.length;
}
