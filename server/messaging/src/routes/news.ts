import { randomUUID } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { inTransaction } from "../db.js";
import { canPush, smsNumber } from "../outbox.js";
import { CATALOG, catalogById } from "../news/catalog.js";
import { buildDigest, MAX_FEEDS, MAX_TOPICS } from "../news/digest.js";
import { parseFeed } from "../news/feeds.js";
import { checkUrl, safeFetchText, UnsafeUrlError } from "../news/safeFetch.js";
import { isValidTimeZone, nextRunAt } from "../news/schedule.js";

const keyword = z.string().trim().min(2).max(40);
const topic = z.union([
  z.object({ catalogId: z.string().refine((id) => catalogById.has(id)) }),
  z.object({ label: z.string().trim().min(1).max(60), keywords: z.array(keyword).min(1).max(10) }),
]);
const settingsBody = z.object({
  enabled: z.boolean(),
  sendTime: z.string().regex(/^([01][0-9]|2[0-3]):[0-5][0-9]$/),
  timezone: z.string().max(64).refine(isValidTimeZone),
  // Empty = in the app only: the digest is kept for the app and nothing is sent (ADR-174).
  channels: z.array(z.enum(["push", "sms"])).max(2).refine((c) => new Set(c).size === c.length),
  language: z.enum(["en", "pl"]),
  topics: z.array(topic).max(MAX_TOPICS),
  feeds: z.array(z.string().url().max(500)).max(MAX_FEEDS),
});
const feedCheckBody = z.object({ url: z.string().max(500) });

export const newsRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const news = deps.news;

  app.get("/v1/news/catalog", { preHandler: auth }, async (req) => {
    const lang = (req.query as { lang?: string }).lang === "pl" ? "pl" : "en";
    return { topics: CATALOG.map((t) => ({ id: t.id, label: t.label[lang] })) };
  });

  app.get("/v1/news/settings", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const { rows } = await db.query<{
      enabled: boolean; send_time: string; timezone: string; channels: string[]; language: string; next_run_at: Date | null;
    }>(`SELECT enabled, to_char(send_time, 'HH24:MI') AS send_time, timezone, channels, language, next_run_at
        FROM news_settings WHERE account_id = $1`, [accountId]);
    const s = rows[0];
    const topics = await db.query(
      `SELECT catalog_id AS "catalogId", label, keywords FROM news_topics WHERE account_id = $1 ORDER BY position`, [accountId]);
    const feeds = await db.query<{ url: string; ok: boolean | null; title: string | null }>(
      `SELECT f.url, c.ok, c.title FROM news_feeds f LEFT JOIN news_cache c ON c.key = encode(sha256(convert_to('feed:' || f.url, 'UTF8')), 'hex')
       WHERE f.account_id = $1 ORDER BY f.url`, [accountId]);
    return {
      available: { writer: !!news?.writer, writerProvider: news?.writer?.provider ?? null, keywordSearch: !!news?.search },
      enabled: s?.enabled ?? false,
      sendTime: s?.send_time ?? "08:00",
      timezone: s?.timezone ?? "Europe/Warsaw",
      channels: s?.channels ?? ["push"],
      language: s?.language ?? "en",
      nextRunAt: s?.enabled ? s.next_run_at : null,
      topics: topics.rows,
      feeds: feeds.rows.map((f) => ({ url: f.url, title: f.title, failing: f.ok === false })),
    };
  });

  app.put("/v1/news/settings", { preHandler: auth }, async (req, reply) => {
    const body = parse(settingsBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    if (body.enabled && body.topics.length === 0 && body.feeds.length === 0) {
      return reply.code(400).send({ error: "no_topics" });
    }
    for (const ch of body.channels) {
      if (ch === "push" && !(await canPush(db, accountId))) return reply.code(409).send({ error: "push_not_enabled" });
      if (ch === "sms" && !(await smsNumber(db, accountId))) return reply.code(409).send({ error: "sms_not_enabled" });
    }
    for (const url of body.feeds) {
      try { checkUrl(url); } catch { return reply.code(400).send({ error: "unsafe_url", url }); }
    }
    const next = body.enabled ? nextRunAt(new Date(), body.sendTime, body.timezone) : null;
    await inTransaction(db, async (c) => {
      await c.query(
        `INSERT INTO news_settings (account_id, enabled, send_time, timezone, channels, language, next_run_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, now())
         ON CONFLICT (account_id) DO UPDATE SET enabled = $2, send_time = $3, timezone = $4, channels = $5,
           language = $6, next_run_at = $7, updated_at = now()`,
        [accountId, body.enabled, body.sendTime, body.timezone, body.channels, body.language, next]);
      await c.query("DELETE FROM news_topics WHERE account_id = $1", [accountId]);
      for (const [i, t] of body.topics.entries()) {
        const cat = "catalogId" in t ? catalogById.get(t.catalogId)! : undefined;
        await c.query(
          `INSERT INTO news_topics (id, account_id, catalog_id, label, keywords, position) VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT DO NOTHING`,
          [randomUUID(), accountId, cat?.id ?? null, cat ? cat.label[body.language] : (t as { label: string }).label,
            "keywords" in t ? t.keywords : [], i]);
      }
      await c.query("DELETE FROM news_feeds WHERE account_id = $1", [accountId]);
      for (const url of new Set(body.feeds)) {
        await c.query("INSERT INTO news_feeds (id, account_id, url) VALUES ($1, $2, $3)", [randomUUID(), accountId, url]);
      }
    });
    return { nextRunAt: next };
  });

  // Checks a feed the user wants to add (reachable, really a feed) before it is saved.
  app.post("/v1/news/feeds/check", { preHandler: auth, config: { rateLimit: { max: 20, timeWindow: "1 hour" } } }, async (req, reply) => {
    const body = parse(feedCheckBody, req.body, reply);
    if (!body) return;
    try {
      const feed = news?.feeds
        ? await news.feeds.fetchFeed(checkUrl(body.url).toString())
        : await (async () => {
          const res = await safeFetchText(body.url);
          return parseFeed(res.text, new URL(res.finalUrl).hostname);
        })();
      return { ok: true, title: feed.title, items: feed.items.length };
    } catch (err) {
      if (err instanceof UnsafeUrlError) return reply.code(400).send({ error: "unsafe_url" });
      return reply.code(422).send({ error: "not_a_feed" });
    }
  });

  app.post("/v1/news/send-now", { preHandler: auth, config: { rateLimit: { max: 3, timeWindow: "1 hour" } } }, async (req, reply) => {
    if (!news) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    const has = await db.query("SELECT 1 FROM news_settings WHERE account_id = $1", [accountId]);
    if (!has.rowCount) return reply.code(409).send({ error: "no_topics" });
    const r = await buildDigest(db, news, accountId, "manual");
    return { digestId: r.digestId ?? null, status: r.status, aiWritten: r.aiWritten ?? false, errorCode: r.errorCode ?? null };
  });

  app.get("/v1/news/digests", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const { rows: digests } = await db.query<{ id: string; status: string; ai_written: boolean; created_at: Date; error_code: string | null }>(
      `SELECT id, status, ai_written, created_at, error_code FROM news_digests WHERE account_id = $1
       ORDER BY created_at DESC LIMIT 7`, [accountId]);
    const ids = digests.map((d) => d.id);
    const { rows: items } = ids.length ? await db.query<{ digest_id: string; line: string; url: string; source: string }>(
      `SELECT digest_id, line, url, source FROM news_digest_items WHERE digest_id = ANY($1::uuid[]) ORDER BY position`, [ids])
      : { rows: [] };
    return {
      digests: digests.map((d) => ({
        id: d.id, status: d.status, aiWritten: d.ai_written, errorCode: d.error_code, createdAt: d.created_at,
        items: items.filter((i) => i.digest_id === d.id).map(({ line, url, source }) => ({ line, url, source })),
      })),
    };
  });
};
