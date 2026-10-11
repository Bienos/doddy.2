import { createHash } from "node:crypto";
import type { Db } from "../db.js";
import { httpUrl, parseFeed, plainText, type NewsItem } from "./feeds.js";
import { safeFetchText } from "./safeFetch.js";

export interface FeedSource {
  /** Throws when the feed can't be fetched or parsed. */
  fetchFeed(url: string): Promise<{ title: string; items: NewsItem[] }>;
}

export interface NewsSearch {
  search(query: string, lang: "en" | "pl", since: Date): Promise<NewsItem[]>;
}

export class HttpFeedSource implements FeedSource {
  async fetchFeed(url: string) {
    const res = await safeFetchText(url);
    if (res.status < 200 || res.status >= 300) throw new Error(`feed HTTP ${res.status}`);
    return parseFeed(res.text, new URL(res.finalUrl).hostname);
  }
}

/** GNews search (https://docs.gnews.io/endpoints/search-endpoint). Paid plans for commercial use. */
export class GNewsSearch implements NewsSearch {
  constructor(private readonly apiKey: string, private readonly timeoutMs = 10_000, private readonly baseURL = "https://gnews.io") {}

  async search(query: string, lang: "en" | "pl", since: Date): Promise<NewsItem[]> {
    const url = new URL("/api/v4/search", this.baseURL);
    url.searchParams.set("q", query.slice(0, 200));
    url.searchParams.set("lang", lang);
    url.searchParams.set("max", "10");
    url.searchParams.set("sortby", "publishedAt");
    url.searchParams.set("from", since.toISOString().replace(/\.\d{3}Z$/, "Z"));
    const res = await fetch(url, { headers: { "X-Api-Key": this.apiKey }, signal: AbortSignal.timeout(this.timeoutMs) });
    if (!res.ok) throw new Error(`gnews HTTP ${res.status}`);
    const json = (await res.json()) as { articles?: { title: string; description: string | null; url: string; publishedAt: string; source: { name: string } }[] };
    // Same rule as feed links: only http(s) URLs reach the app as tappable links.
    return (json.articles ?? []).flatMap((a) => {
      const link = typeof a.url === "string" ? httpUrl(a.url) : null;
      const title = plainText(a.title, 200);
      if (!link || !title) return [];
      return [{
        title, url: link, source: plainText(a.source?.name, 80) || "GNews",
        summary: plainText(a.description, 300), publishedAt: a.publishedAt ?? null,
      }];
    });
  }
}

/** Builds a GNews query from a topic's keywords: "exact phrase" OR "another". */
export function searchQuery(keywords: string[]): string {
  return keywords.map((k) => `"${k.replace(/"/g, "").trim()}"`).filter((k) => k.length > 2).join(" OR ").slice(0, 200);
}

/**
 * The cache's row key: a hash, so a user's private feed URL (which can carry a token) is never
 * stored outside their own news_feeds rows, which go when the account is deleted (ADR-175).
 */
export function cacheKey(key: string): string {
  return createHash("sha256").update(key).digest("hex");
}

/** Drops cache rows nobody has refreshed for a day (worker, about hourly). */
export async function pruneNewsCache(db: Db): Promise<number> {
  const r = await db.query("DELETE FROM news_cache WHERE fetched_at < now() - interval '24 hours'");
  return r.rowCount ?? 0;
}

/**
 * Shared cache in front of feeds and searches (not linked to any account). A failed refresh
 * keeps the last good items so one flaky publisher doesn't empty a digest.
 */
export async function cached(
  db: Db, key: string, maxAgeMinutes: number, load: () => Promise<{ title?: string; items: NewsItem[] }>,
): Promise<{ ok: boolean; title?: string; items: NewsItem[] }> {
  key = cacheKey(key);
  const { rows } = await db.query<{ fresh: boolean; ok: boolean; title: string | null; items: NewsItem[] }>(
    `SELECT fetched_at > now() - make_interval(mins => $2) AS fresh, ok, title, items FROM news_cache WHERE key = $1`,
    [key, maxAgeMinutes]);
  const hit = rows[0];
  if (hit?.fresh) return { ok: hit.ok, title: hit.title ?? undefined, items: hit.items };
  try {
    const fresh = await load();
    await db.query(
      `INSERT INTO news_cache (key, fetched_at, ok, title, items) VALUES ($1, now(), true, $2, $3)
       ON CONFLICT (key) DO UPDATE SET fetched_at = now(), ok = true, title = EXCLUDED.title, items = EXCLUDED.items`,
      [key, fresh.title ?? null, JSON.stringify(fresh.items)]);
    return { ok: true, ...fresh };
  } catch {
    await db.query(
      `INSERT INTO news_cache (key, fetched_at, ok) VALUES ($1, now(), false)
       ON CONFLICT (key) DO UPDATE SET fetched_at = now(), ok = false`, [key]);
    return { ok: false, title: hit?.title ?? undefined, items: hit?.items ?? [] };
  }
}
