import { randomUUID } from "node:crypto";
import type pg from "pg";
import { z } from "zod";
import type { TextCipher } from "../crypto.js";
import { inTransaction, type Db } from "../db.js";
import { canPush, EncryptionNotConfigured, enqueue } from "../outbox.js";
import type { PushSender } from "../providers/types.js";
import { inQuietHours, QUIET_HOURS_DEFAULT, type QuietHours } from "../quietHours.js";
import { catalogById } from "./catalog.js";
import { StoryIndex } from "./dedupe.js";
import { gatherItems, type FollowedTopic, type NewsDeps } from "./digest.js";
import { matchedKeywords } from "./match.js";
import { shortlist, type Candidate } from "./rank.js";
import { FeedReader } from "./reader.js";
import { checkUrl } from "./safeFetch.js";
import { isValidTimeZone, nextRunAt } from "./schedule.js";
import { reserveWriter } from "./usage.js";
import { shorten, validateLines } from "./writer.js";

// On my radar alerts (owner, 10 Nov 2026; decision 2026-11-10-radar-alerts). A follow stays on the iPhone
// unless the person turns on "Let Doddy's server check this for you" for it; then the server keeps that one
// follow, the words to look out for and how to tell them. A worker pass reads the follow's feeds through the
// shared cache, records each new matching story once (the app lists them, so nothing depends on a push) and
// queues at most one push: as it happens (headline and publisher, outside quiet hours, a few a day at most)
// or once a day at the person's time (a short summary; lines by the news writer only when the server has
// one, checked by validateLines, otherwise the headlines). Feed text is data, never instructions; a push
// quotes the publisher's headline and names the publisher. Behind RADAR_ALERTS_ENABLED (off by default).

export const MAX_ALERTS = 10;
/** An "as it happens" alert looks this often (the feeds behind it are cached for 30 minutes). */
export const CHECK_EVERY_MS = 20 * 60_000;
/** A daily alert collects this often between summaries, so a busy feed can't scroll a story away unseen. */
export const DAILY_COLLECT_EVERY_MS = 2 * 3_600_000;
/** Pushes from radar alerts per account in any 24 hours; past it, stories are listed in the app only. */
export const PUSHES_PER_DAY = 8;
/** A story first seen more than this long after it was published is listed in the app, never pushed. */
export const PUSH_FRESH_MS = 6 * 3_600_000;
/** A daily summary more than this late (the server slept) is not sent; its stories stay in the app. */
export const DAILY_MAX_LATE_MS = 2 * 3_600_000;
export const KEEP_HITS_DAYS = 14;
/** New stories recorded per alert per check, at most. */
const HITS_PER_CHECK = 20;
const BATCH = 10;
const WINDOW_HOURS = 48;
/** A new story whose headline matches one found for the account this recently (from another publisher) is not a new hit. */
const KNOWN_HITS_HOURS = 72;
const KNOWN_HITS_MAX = 300;

const word = z.string().trim().min(2).max(40);

/** An own feed for On my radar: https only, a public address (safeFetch checks again at every hop). */
export const httpsFeedUrl = z.string().trim().max(500).refine((u) => {
  try {
    return checkUrl(u).protocol === "https:";
  } catch {
    return false;
  }
}, "https_public_feed_only");

const alertBody = z.object({
  followKey: z.string().trim().min(1).max(120),
  label: z.string().trim().min(1).max(60),
  catalogId: z.string().refine((id) => catalogById.has(id)).optional(),
  keywords: z.array(word).max(10).default([]),
  feedUrl: httpsFeedUrl.optional(),
  alertWords: z.array(word).max(10).default([]),
  mode: z.enum(["instant", "daily"]),
  dailyTime: z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/).optional(),
}).superRefine((a, ctx) => {
  if (a.catalogId && a.feedUrl) ctx.addIssue({ code: "custom", path: ["feedUrl"], message: "one_source" });
  if (!a.catalogId && !a.feedUrl && a.keywords.length === 0) ctx.addIssue({ code: "custom", path: ["keywords"], message: "nothing_to_follow" });
  if (a.mode === "daily" && !a.dailyTime) ctx.addIssue({ code: "custom", path: ["dailyTime"], message: "time_needed" });
  // A whole topic "as it happens" would be a push per story: it needs words to look out for.
  if (a.mode === "instant" && a.alertWords.length === 0 && (a.catalogId || a.keywords.length === 0)) {
    ctx.addIssue({ code: "custom", path: ["alertWords"], message: "words_needed" });
  }
});

export const radarBody = z.object({
  language: z.enum(["en", "pl"]),
  timeZone: z.string().max(64).refine(isValidTimeZone),
  alerts: z.array(alertBody).max(MAX_ALERTS)
    .refine((list) => new Set(list.map((a) => a.followKey)).size === list.length, "duplicate_follow"),
});
export type RadarBody = z.infer<typeof radarBody>;

/**
 * Replaces the account's alerts with the list the iPhone sent (the iPhone is the source of truth, so a
 * retry is harmless). An alert kept from before keeps its start: only stories after it was first turned
 * on count. A changed alert is checked again within a pass.
 */
export async function saveAlerts(db: Db, accountId: string, body: RadarBody, now: Date): Promise<void> {
  await inTransaction(db, async (c) => {
    await c.query("DELETE FROM radar_alerts WHERE account_id = $1 AND NOT (follow_key = ANY($2::text[]))",
      [accountId, body.alerts.map((a) => a.followKey)]);
    for (const a of body.alerts) {
      const nextTell = a.mode === "daily" ? nextRunAt(now, a.dailyTime!, body.timeZone) : null;
      await c.query(
        `INSERT INTO radar_alerts (id, account_id, follow_key, label, catalog_id, keywords, feed_url, alert_words, mode,
           daily_time, time_zone, language, watch_from, next_check_at, next_tell_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $13, $14)
         ON CONFLICT (account_id, follow_key) DO UPDATE SET label = EXCLUDED.label, catalog_id = EXCLUDED.catalog_id,
           keywords = EXCLUDED.keywords, feed_url = EXCLUDED.feed_url, alert_words = EXCLUDED.alert_words, mode = EXCLUDED.mode,
           daily_time = EXCLUDED.daily_time, time_zone = EXCLUDED.time_zone, language = EXCLUDED.language,
           next_check_at = EXCLUDED.next_check_at, next_tell_at = EXCLUDED.next_tell_at, updated_at = now()`,
        [randomUUID(), accountId, a.followKey, a.label, a.catalogId ?? null, a.catalogId ? [] : a.keywords, a.feedUrl ?? null, a.alertWords, a.mode, a.dailyTime ?? null, body.timeZone, body.language, now, nextTell]);
    }
  });
}

export interface RadarState {
  alerts: { followKey: string; label: string; mode: "instant" | "daily"; dailyTime: string | null; alertWords: string[]; lastCheckedAt: Date | null }[];
  hits: {
    id: string; followKey: string; label: string; title: string; summary: string; url: string; source: string;
    publishedAt: Date; matched: string[]; foundAt: Date; toldBy: "push" | "app" | null; seen: boolean;
  }[];
}

/** What the server holds for the account: its alerts, and the stories found in the last 14 days (newest first, at most 60). */
export async function radarState(db: Db, accountId: string): Promise<RadarState> {
  const { rows: alerts } = await db.query<{
    follow_key: string; label: string; mode: "instant" | "daily"; daily_time: string | null; alert_words: string[]; last_checked_at: Date | null;
  }>(`SELECT follow_key, label, mode, to_char(daily_time, 'HH24:MI') AS daily_time, alert_words, last_checked_at
      FROM radar_alerts WHERE account_id = $1 ORDER BY created_at`, [accountId]);
  const { rows: hits } = await db.query<{
    id: string; follow_key: string; label: string; title: string; summary: string; url: string; source: string; published_at: Date;
    matched: string[]; found_at: Date; told_by: "push" | "app" | null; seen_at: Date | null;
  }>(`SELECT h.id, a.follow_key, a.label, h.title, h.summary, h.url, h.source, h.published_at, h.matched, h.found_at, h.told_by, h.seen_at
      FROM radar_hits h JOIN radar_alerts a ON a.id = h.alert_id
      WHERE h.account_id = $1 ORDER BY h.found_at DESC, h.published_at DESC LIMIT 60`, [accountId]);
  return {
    alerts: alerts.map((a) => ({
      followKey: a.follow_key, label: a.label, mode: a.mode, dailyTime: a.daily_time, alertWords: a.alert_words, lastCheckedAt: a.last_checked_at,
    })),
    hits: hits.map((h) => ({
      id: h.id, followKey: h.follow_key, label: h.label, title: h.title, summary: h.summary, url: h.url, source: h.source,
      publishedAt: h.published_at, matched: h.matched, foundAt: h.found_at, toldBy: h.told_by, seen: h.seen_at !== null,
    })),
  };
}

export async function markSeen(db: Db, accountId: string, ids: string[] | undefined, now: Date): Promise<number> {
  const r = ids
    ? await db.query("UPDATE radar_hits SET seen_at = $3 WHERE account_id = $1 AND id = ANY($2::uuid[]) AND seen_at IS NULL", [accountId, ids, now])
    : await db.query("UPDATE radar_hits SET seen_at = $2 WHERE account_id = $1 AND seen_at IS NULL", [accountId, now]);
  return r.rowCount ?? 0;
}

// ── The worker ──────────────────────────────────────────────────────────────────────────────────────

export interface RadarContext {
  db: Db;
  news: NewsDeps;
  push?: PushSender;
  cipher?: TextCipher;
  quietHours?: QuietHours;
  now: () => Date;
  log: (msg: string, extra?: object) => void;
}

interface AlertRow {
  id: string; account_id: string; label: string; catalog_id: string | null; keywords: string[]; feed_url: string | null;
  alert_words: string[]; mode: "instant" | "daily"; daily_time: string | null; time_zone: string; language: "en" | "pl";
  watch_from: Date; next_tell_at: Date | null;
}

interface Claimed extends AlertRow {
  /** Daily: the summary is due in this pass (its time, `dueAt`, has come). */
  tell: boolean;
  dueAt: Date | null;
}

/**
 * One pass: claims the alerts that are due and moves their next check (and a daily alert's next summary)
 * forward first, so a crash can't repeat a push; then checks each. The pass reads each feed once, however many
 * alerts look at it (reader.ts). Returns counts only (feeds read, how each was answered, and the time taken).
 */
export async function runRadarPass(ctx: RadarContext): Promise<Record<string, number>> {
  const now = ctx.now();
  const started = Date.now();
  const reader = new FeedReader(ctx.db, ctx.news.feeds, { now });
  const counts: Record<string, number> = {};
  const add = (k: string, n = 1) => { if (n) counts[k] = (counts[k] ?? 0) + n; };
  const due = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<AlertRow>(
      `SELECT id, account_id, label, catalog_id, keywords, feed_url, alert_words, mode, to_char(daily_time, 'HH24:MI') AS daily_time,
              time_zone, language, watch_from, next_tell_at
         FROM radar_alerts WHERE next_check_at <= $1 ORDER BY next_check_at LIMIT ${BATCH} FOR UPDATE SKIP LOCKED`, [now]);
    const out: Claimed[] = [];
    for (const r of rows) {
      let nextTell = r.next_tell_at;
      let tell = false;
      if (r.mode === "daily" && r.next_tell_at && r.next_tell_at <= now) {
        tell = true;
        nextTell = nextRunAt(now, r.daily_time!, r.time_zone);
      }
      const nextCheck = r.mode === "instant"
        ? new Date(now.getTime() + CHECK_EVERY_MS)
        : new Date(Math.min(now.getTime() + DAILY_COLLECT_EVERY_MS, nextTell!.getTime()));
      await c.query("UPDATE radar_alerts SET next_check_at = $2, next_tell_at = $3, last_checked_at = $4 WHERE id = $1",
        [r.id, nextCheck, nextTell, now]);
      out.push({ ...r, tell, dueAt: tell ? r.next_tell_at : null });
    }
    return out;
  });
  add("claimed", due.length);
  for (const alert of due) {
    try {
      const got = await collect(ctx, alert, now, reader);
      add("found", got.found);
      add("same_story", got.sameStory);
      if (alert.mode === "instant") add(await tellInstant(ctx, alert, now));
      else if (alert.tell) add(await tellDaily(ctx, alert, now));
    } catch (err) {
      // Codes only (the error's class and a database SQLSTATE): never a word of the follow or of a story.
      add("failed");
      const code = (err as { code?: unknown })?.code;
      ctx.log("radar check failed", { error: err instanceof Error ? err.name : "unknown", ...(typeof code === "string" && /^[0-9A-Z]{5}$/.test(code) ? { code } : {}) });
    }
  }
  const pruned = await ctx.db.query("DELETE FROM radar_hits WHERE found_at < $1", [new Date(now.getTime() - KEEP_HITS_DAYS * 86_400_000)]);
  add("pruned", pruned.rowCount ?? 0);
  if (due.length) {
    // Counts only: how many feeds the pass read and how each was answered, and how long it took.
    add("feeds", reader.stats.feeds);
    add("feeds_from_cache", reader.stats.fromCache);
    add("feeds_fetched", reader.stats.fetched);
    add("feeds_not_modified", reader.stats.notModified);
    add("feeds_failed", reader.stats.failed);
    add("feeds_shared", reader.stats.shared);
    add("ms", Math.max(1, Date.now() - started));
  }
  return counts;
}

/**
 * The stories of the alert's follow that are new since it was turned on and mention its words: in the headline or
 * summary, or in another publisher's headline for the same story (`alsoFrom`).
 */
export function matchingStories(alert: Pick<AlertRow, "keywords" | "alert_words" | "watch_from">, candidates: Candidate[]) {
  return candidates.flatMap((c) => {
    if (!c.publishedAt || Date.parse(c.publishedAt) <= alert.watch_from.getTime()) return [];
    const text = [c.title, c.summary, ...(c.alsoFrom ?? []).map((a) => a.title)].join("\n");
    const matched = matchedKeywords(text, alert.alert_words.length ? alert.alert_words : alert.keywords);
    if (alert.alert_words.length && matched.length === 0) return [];
    return [{ candidate: c, matched }];
  });
}

/**
 * Reads the follow's feeds (the pass's reader, over the shared cache) and records new matching stories once per
 * account: once per link (the table's own rule) and, since 13 Nov 2026, once per story: a headline that matches one
 * found for the account in the last KNOWN_HITS_HOURS, from another publisher, is counted as `sameStory` and not
 * recorded, so "as it happens" never pushes the same news twice.
 */
async function collect(ctx: RadarContext, alert: Claimed, now: Date, reader: FeedReader): Promise<{ found: number; sameStory: number }> {
  const topic: FollowedTopic = { catalog_id: alert.catalog_id, label: alert.label, keywords: alert.keywords, feed_url: alert.feed_url };
  const gathered = await gatherItems(ctx.db, ctx.news, [topic], [], alert.language, now, { keywordPool: "catalog", reader });
  const candidates = shortlist(gathered, new Set(), now, { limit: 80, perSource: 30, windowHours: WINDOW_HOURS, language: alert.language });
  const matching = matchingStories(alert, candidates).slice(0, HITS_PER_CHECK);
  if (matching.length === 0) return { found: 0, sameStory: 0 };
  const { rows: known } = await ctx.db.query<{ title: string; hex: string }>(
    `SELECT title, encode(url_hash, 'hex') AS hex FROM radar_hits WHERE account_id = $1 AND found_at > $2
      ORDER BY found_at DESC LIMIT ${KNOWN_HITS_MAX}`, [alert.account_id, new Date(now.getTime() - KNOWN_HITS_HOURS * 3_600_000)]);
  const knownLinks = new Set(known.map((k) => k.hex));
  const stories = new StoryIndex<number>();
  known.forEach((k, i) => stories.add(i, k.title, `hit:${k.hex}`));
  let found = 0;
  let sameStory = 0;
  for (const { candidate: c, matched } of matching) {
    if (knownLinks.has(c.urlHash.toString("hex"))) continue; // recorded before: nothing new
    if (stories.has(c.title) || c.alsoFrom.some((a) => stories.has(a.title))) {
      sameStory++;
      continue;
    }
    const r = await ctx.db.query(
      `INSERT INTO radar_hits (id, account_id, alert_id, url_hash, title, summary, url, source, published_at, matched, found_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) ON CONFLICT (account_id, url_hash) DO NOTHING`,
      [randomUUID(), alert.account_id, alert.id, c.urlHash, c.title.slice(0, 300), c.summary.slice(0, 400), c.url.slice(0, 2000),
        c.source.slice(0, 120), c.publishedAt, matched, now]);
    found += r.rowCount ?? 0;
    stories.add(-1, c.title, c.url);
  }
  return { found, sameStory };
}

interface HitRow { id: string; title: string; summary: string; url: string; source: string; published_at: Date }

async function untold(c: pg.PoolClient, alertId: string): Promise<HitRow[]> {
  const { rows } = await c.query<HitRow>(
    `SELECT id, title, summary, url, source, published_at FROM radar_hits WHERE alert_id = $1 AND told_at IS NULL
     ORDER BY published_at DESC FOR UPDATE`, [alertId]);
  return rows;
}

async function markTold(c: pg.PoolClient, ids: string[], by: "push" | "app", now: Date) {
  if (ids.length) await c.query("UPDATE radar_hits SET told_at = $2, told_by = $3 WHERE id = ANY($1::uuid[])", [ids, now, by]);
}

/** Radar pushes queued for the account in the last 24 hours. */
async function pushesLastDay(c: pg.PoolClient, accountId: string, now: Date): Promise<number> {
  const { rows } = await c.query<{ n: string }>(
    `SELECT count(*) AS n FROM outbound_messages WHERE account_id = $1 AND channel = 'push' AND idempotency_key LIKE 'radar:%'
     AND created_at > $2`, [accountId, new Date(now.getTime() - 86_400_000)]);
  return Number(rows[0]!.n);
}

/** Queues one push, or says why it can't: no sender on this server, no device, the day's cap, or no encryption key in production. */
async function queuePush(ctx: RadarContext, c: pg.PoolClient, accountId: string, body: string, key: string, now: Date): Promise<"push" | "no_push" | "cap"> {
  if (!ctx.push || !(await canPush(c, accountId))) return "no_push";
  if (await pushesLastDay(c, accountId, now) >= PUSHES_PER_DAY) return "cap";
  try {
    await enqueue(c, accountId, ["push"], body, now, key, { cipher: ctx.cipher });
    return "push";
  } catch (err) {
    if (err instanceof EncryptionNotConfigured) return "no_push";
    throw err;
  }
}

/** As it happens: one push for the alert's fresh untold stories, outside quiet hours. Older ones go to the app list. */
async function tellInstant(ctx: RadarContext, alert: Claimed, now: Date): Promise<string> {
  return inTransaction(ctx.db, async (c) => {
    const waiting = await untold(c, alert.id);
    if (waiting.length === 0) return "nothing_new";
    const stale = waiting.filter((h) => now.getTime() - h.published_at.getTime() > PUSH_FRESH_MS);
    const fresh = waiting.filter((h) => !stale.includes(h));
    await markTold(c, stale.map((h) => h.id), "app", now);
    if (fresh.length === 0) return "app_only";
    // Inside quiet hours the stories wait; past PUSH_FRESH_MS they are listed in the app only.
    if (inQuietHours(now, alert.time_zone, ctx.quietHours ?? QUIET_HOURS_DEFAULT)) return "held_quiet_hours";
    const outcome = await queuePush(ctx, c, alert.account_id, instantBody(alert.label, fresh, alert.language), `radar:${alert.id}:${fresh[0]!.id}`, now);
    await markTold(c, fresh.map((h) => h.id), outcome === "push" ? "push" : "app", now);
    return outcome === "push" ? "pushed" : outcome === "cap" ? "over_cap" : "app_only";
  });
}

/** Once a day: a short summary of the day's untold stories, at the person's time (not if the server slept through it). */
async function tellDaily(ctx: RadarContext, alert: Claimed, now: Date): Promise<string> {
  const late = alert.dueAt ? now.getTime() - alert.dueAt.getTime() : 0;
  const waiting = await inTransaction(ctx.db, async (c) => {
    const rows = await untold(c, alert.id);
    if (late > DAILY_MAX_LATE_MS) await markTold(c, rows.map((h) => h.id), "app", now);
    return rows;
  });
  if (late > DAILY_MAX_LATE_MS) return "daily_too_late";
  if (waiting.length === 0) return "nothing_new";
  const lines = await summaryLines(ctx, alert, waiting, now);
  return inTransaction(ctx.db, async (c) => {
    const still = new Set((await untold(c, alert.id)).map((h) => h.id));
    const covered = waiting.filter((h) => still.has(h.id));
    if (covered.length === 0) return "nothing_new";
    const outcome = await queuePush(ctx, c, alert.account_id, dailyBody(alert.label, covered.length, lines.lines, lines.aiWritten, alert.language),
      `radar:${alert.id}:${covered[0]!.id}`, now);
    await markTold(c, covered.map((h) => h.id), outcome === "push" ? "push" : "app", now);
    return outcome === "push" ? "summarised" : outcome === "cap" ? "over_cap" : "app_only";
  });
}

/**
 * The summary's lines. With a news writer on the server it picks and phrases up to five stories from their
 * headline and summary only, and validateLines keeps only lines for stories that exist; otherwise, or if it
 * fails, the newest headlines word for word. Each line names its publisher. The writer counts against the same daily
 * caps as the digests (src/news/usage.ts); past one, the headlines.
 */
async function summaryLines(ctx: RadarContext, alert: Claimed, hits: HitRow[], now: Date): Promise<{ lines: string[]; aiWritten: boolean }> {
  const candidates: Candidate[] = hits.slice(0, 25).map((h, i) => ({
    id: `s${i + 1}`, title: h.title, summary: h.summary, url: h.url, source: h.source, publishedAt: h.published_at.toISOString(),
    topics: [alert.label], score: 0, urlHash: Buffer.alloc(0), alsoFrom: [],
  }));
  const reserved = ctx.news.writer ? await reserveWriter(ctx.db, alert.account_id, ctx.news.writerCaps, now) : undefined;
  if (reserved && reserved !== "ok") ctx.log("radar summary writer skipped, daily limit", { scope: reserved });
  if (ctx.news.writer && reserved === "ok") {
    try {
      const picks = validateLines(await ctx.news.writer.write({ language: alert.language, topics: [alert.label], candidates }), candidates);
      if (picks.length) return { lines: picks.slice(0, 3).map((p) => `${p.line} (${p.candidate.source})`), aiWritten: true };
    } catch {
      ctx.log("radar summary writer failed, headlines used");
    }
  }
  return { lines: candidates.slice(0, 3).map((c) => `${shorten(c.title, 140)} (${c.source})`), aiWritten: false };
}

const PUSH_MAX = 600;

/** "On my radar · Tesla: “headline” (Reuters)" and "+2 more in Doddy". The headline is the publisher's, quoted. */
export function instantBody(label: string, hits: Pick<HitRow, "title" | "source">[], language: "en" | "pl"): string {
  const first = hits[0]!;
  const title = shorten(first.title, 200);
  let body = language === "pl"
    ? `Na radarze · ${label}: „${title}” (${first.source})`
    : `On your radar · ${label}: “${title}” (${first.source})`;
  if (hits.length > 1) body += language === "pl" ? `\n+${hits.length - 1} więcej w Doddy` : `\n+${hits.length - 1} more in Doddy`;
  return body.slice(0, PUSH_MAX);
}

/** "On my radar · Tesla, today: 4 stories" and up to three lines; says when an AI wrote the lines. */
export function dailyBody(label: string, count: number, lines: string[], aiWritten: boolean, language: "en" | "pl"): string {
  const head = language === "pl"
    ? `Na radarze · ${label}, dziś: ${count} ${count === 1 ? "artykuł" : count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 12 || count % 100 > 14) ? "artykuły" : "artykułów"}`
    : `On your radar · ${label}, today: ${count} ${count === 1 ? "story" : "stories"}`;
  const out = [head];
  let used = head.length;
  for (const l of lines) {
    const line = `• ${l}`;
    if (used + line.length + 1 > PUSH_MAX - 60) break;
    out.push(line);
    used += line.length + 1;
  }
  const rest = count - (out.length - 1);
  if (rest > 0) out.push(language === "pl" ? `+${rest} więcej w Doddy` : `+${rest} more in Doddy`);
  if (aiWritten) out.push(language === "pl" ? "Zdania napisała AI z nagłówków wydawców." : "Lines written by AI from the publishers' headlines.");
  return out.join("\n");
}
