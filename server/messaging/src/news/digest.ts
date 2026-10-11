import { randomUUID } from "node:crypto";
import { inTransaction, type Db } from "../db.js";
import { canPush, enqueue, smsNumber, type Channel } from "../outbox.js";
import { catalogById } from "./catalog.js";
import { pushBody, smsBody } from "./compose.js";
import type { NewsItem } from "./feeds.js";
import { shortlist, type TopicItems } from "./rank.js";
import { localDate, nextRunAt } from "./schedule.js";
import { cached, searchQuery, type FeedSource, type NewsSearch } from "./sources.js";
import { shorten, validateLines, type DigestWriter } from "./writer.js";

export interface NewsDeps {
  feeds: FeedSource;
  search?: NewsSearch;
  writer?: DigestWriter;
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
    if (news.writer) {
      try {
        picks = validateLines(await news.writer.write({
          language: settings.language, topics: topics.map((t) => t.label), candidates,
        }), candidates);
        aiWritten = picks.length > 0;
      } catch (err) {
        // A code only (writer_*, or the HTTP status), never story text or keys.
        const code = err instanceof Error && /^writer_[a-z0-9_]+$/.test(err.message) ? err.message
          : `writer_error${typeof (err as { status?: unknown })?.status === "number" ? `_${(err as { status: number }).status}` : ""}`;
        console.log(JSON.stringify({ time: new Date().toISOString(), msg: "news writer failed, plain headlines used", code }));
        picks = []; // fall back to plain headlines below
      }
    }
    if (picks.length === 0) picks = candidates.slice(0, 3).map((c) => ({ candidate: c, line: shorten(c.title, 140) }));

    const channels: Channel[] = [];
    for (const ch of settings.channels) {
      if (ch === "push" && await canPush(db, accountId)) channels.push(ch);
      if (ch === "sms" && await smsNumber(db, accountId)) channels.push(ch);
    }

    const entries = picks.map((p) => ({ line: p.line, url: p.candidate.url, source: p.candidate.source }));
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
        await enqueue(c, accountId, [ch], body, now, `news:${digestId}`);
      }
    });
    if (channels.length === 0) {
      // Kept for the app. no_channel only when the user chose a channel that can't be used now.
      return finish({ status: "ready", aiWritten, errorCode: settings.channels.length > 0 ? "no_channel" : undefined });
    }
    return finish({ status: "queued", aiWritten });
  } catch {
    return finish({ status: "failed", errorCode: "build_error" });
  }
}

async function gatherTopics(db: Db, news: NewsDeps, accountId: string, language: "en" | "pl", now: Date): Promise<TopicItems[]> {
  const { rows: topics } = await db.query<{ catalog_id: string | null; label: string; keywords: string[] }>(
    "SELECT catalog_id, label, keywords FROM news_topics WHERE account_id = $1 ORDER BY position", [accountId]);
  const { rows: feeds } = await db.query<{ url: string }>("SELECT url FROM news_feeds WHERE account_id = $1", [accountId]);
  const feed = async (url: string) => (await cached(db, `feed:${url}`, 30, () => news.feeds.fetchFeed(url))).items;

  const out: TopicItems[] = [];
  const pool: NewsItem[] = [];
  for (const t of topics) {
    const cat = t.catalog_id ? catalogById.get(t.catalog_id) : undefined;
    if (!cat) continue;
    const items = (await Promise.all(cat.feeds.map(feed))).flat();
    pool.push(...items);
    out.push({ label: t.label, keywords: t.keywords, curated: true, items });
  }
  if (feeds.length) {
    const items = (await Promise.all(feeds.map((f) => feed(f.url)))).flat();
    pool.push(...items);
    out.push({ label: language === "pl" ? "Twoje źródła" : "Your feeds", keywords: [], curated: true, items });
  }
  // The user's own keyword topics: a news search when configured, plus matches in every feed loaded above.
  let searches = 0;
  for (const t of topics.filter((x) => !x.catalog_id && x.keywords.length)) {
    let found: NewsItem[] = [];
    const q = searchQuery(t.keywords);
    if (news.search && q && searches < MAX_SEARCHES) {
      searches++;
      const since = new Date(now.getTime() - 36 * 3_600_000);
      found = (await cached(db, `search:${language}:${q}`, 60, async () => ({ items: await news.search!.search(q, language, since) }))).items;
    }
    out.push({ label: t.label, keywords: t.keywords, curated: true, items: found });
    out.push({ label: t.label, keywords: t.keywords, curated: false, items: pool });
  }
  return out;
}

/**
 * Scheduler pass: claims accounts whose digest time has come, moves their next run to tomorrow
 * first (so a crash can't cause a repeat), then builds each digest.
 */
export async function runDueDigests(db: Db, news: NewsDeps, batch = 5, now = new Date()): Promise<number> {
  const client = await db.connect();
  let due: string[] = [];
  try {
    await client.query("BEGIN");
    const { rows } = await client.query<{ account_id: string; send_time: string; timezone: string }>(
      `SELECT account_id, to_char(send_time, 'HH24:MI') AS send_time, timezone FROM news_settings
       WHERE enabled AND next_run_at <= $2 ORDER BY next_run_at LIMIT $1 FOR UPDATE SKIP LOCKED`, [batch, now]);
    for (const r of rows) {
      await client.query("UPDATE news_settings SET next_run_at = $2 WHERE account_id = $1",
        [r.account_id, nextRunAt(now, r.send_time, r.timezone)]);
    }
    await client.query("COMMIT");
    due = rows.map((r) => r.account_id);
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
