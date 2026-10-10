import { parseFeed, plainText } from "./feeds.js";
import { safeFetchText } from "./safeFetch.js";
export class HttpFeedSource {
    async fetchFeed(url) {
        const res = await safeFetchText(url);
        if (res.status < 200 || res.status >= 300)
            throw new Error(`feed HTTP ${res.status}`);
        return parseFeed(res.text, new URL(res.finalUrl).hostname);
    }
}
/** GNews search (https://docs.gnews.io/endpoints/search-endpoint). Paid plans for commercial use. */
export class GNewsSearch {
    apiKey;
    timeoutMs;
    constructor(apiKey, timeoutMs = 10_000) {
        this.apiKey = apiKey;
        this.timeoutMs = timeoutMs;
    }
    async search(query, lang, since) {
        const url = new URL("https://gnews.io/api/v4/search");
        url.searchParams.set("q", query.slice(0, 200));
        url.searchParams.set("lang", lang);
        url.searchParams.set("max", "10");
        url.searchParams.set("sortby", "publishedAt");
        url.searchParams.set("from", since.toISOString().replace(/\.\d{3}Z$/, "Z"));
        const res = await fetch(url, { headers: { "X-Api-Key": this.apiKey }, signal: AbortSignal.timeout(this.timeoutMs) });
        if (!res.ok)
            throw new Error(`gnews HTTP ${res.status}`);
        const json = (await res.json());
        return (json.articles ?? []).map((a) => ({
            title: plainText(a.title, 200), url: a.url, source: plainText(a.source?.name, 80) || "GNews",
            summary: plainText(a.description, 300), publishedAt: a.publishedAt ?? null,
        }));
    }
}
/** Builds a GNews query from a topic's keywords: "exact phrase" OR "another". */
export function searchQuery(keywords) {
    return keywords.map((k) => `"${k.replace(/"/g, "").trim()}"`).filter((k) => k.length > 2).join(" OR ").slice(0, 200);
}
/**
 * Shared cache in front of feeds and searches (not linked to any account). A failed refresh
 * keeps the last good items so one flaky publisher doesn't empty a digest.
 */
export async function cached(db, key, maxAgeMinutes, load) {
    const { rows } = await db.query(`SELECT fetched_at > now() - make_interval(mins => $2) AS fresh, ok, title, items FROM news_cache WHERE key = $1`, [key, maxAgeMinutes]);
    const hit = rows[0];
    if (hit?.fresh)
        return { ok: hit.ok, title: hit.title ?? undefined, items: hit.items };
    try {
        const fresh = await load();
        await db.query(`INSERT INTO news_cache (key, fetched_at, ok, title, items) VALUES ($1, now(), true, $2, $3)
       ON CONFLICT (key) DO UPDATE SET fetched_at = now(), ok = true, title = EXCLUDED.title, items = EXCLUDED.items`, [key, fresh.title ?? null, JSON.stringify(fresh.items)]);
        return { ok: true, ...fresh };
    }
    catch {
        await db.query(`INSERT INTO news_cache (key, fetched_at, ok) VALUES ($1, now(), false)
       ON CONFLICT (key) DO UPDATE SET fetched_at = now(), ok = false`, [key]);
        return { ok: false, title: hit?.title ?? undefined, items: hit?.items ?? [] };
    }
}
//# sourceMappingURL=sources.js.map