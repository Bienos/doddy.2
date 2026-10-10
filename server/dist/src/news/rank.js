import { createHash } from "node:crypto";
import { fold } from "../memorySearch.js";
const TRACKING = /^(utm_|fbclid$|gclid$|mc_|ref$|cmpid$)/i;
export function normalizeUrl(raw) {
    try {
        const u = new URL(raw);
        u.hash = "";
        u.hostname = u.hostname.toLowerCase();
        for (const k of [...u.searchParams.keys()])
            if (TRACKING.test(k))
                u.searchParams.delete(k);
        return u.toString();
    }
    catch {
        return raw;
    }
}
export function urlHash(raw) {
    return createHash("sha256").update(normalizeUrl(raw)).digest();
}
function matches(text, keyword) {
    const k = fold(keyword).trim();
    return k.length > 1 && fold(text).includes(k);
}
/**
 * Deterministic shortlist before any AI: recent (36 h), not sent before, deduplicated by URL
 * and title, scored by topic fit and freshness, at most 3 per source. The AI only ever picks
 * from this list, and links always come from it.
 */
export function shortlist(topics, alreadySent, now, limit = 25) {
    const byUrl = new Map();
    const seenTitles = new Set();
    const windowMs = 36 * 3_600_000;
    for (const topic of topics) {
        for (const item of topic.items) {
            if (!item.publishedAt)
                continue;
            const age = now.getTime() - Date.parse(item.publishedAt);
            if (age > windowMs || age < -3_600_000)
                continue;
            const hash = urlHash(item.url);
            const hex = hash.toString("hex");
            if (alreadySent.has(hex))
                continue;
            const kw = topic.keywords.reduce((s, k) => s + (matches(item.title, k) ? 3 : matches(item.summary, k) ? 1 : 0), 0);
            if (!topic.curated && kw === 0)
                continue;
            const fit = (topic.curated ? 1 : 0) + kw;
            const existing = byUrl.get(hex);
            if (existing) {
                existing.score += fit;
                if (!existing.topics.includes(topic.label))
                    existing.topics.push(topic.label);
                continue;
            }
            const titleKey = fold(item.title).replace(/[^\p{L}\p{N}]+/gu, " ").trim();
            if (seenTitles.has(titleKey))
                continue;
            seenTitles.add(titleKey);
            byUrl.set(hex, { ...item, id: "", topics: [topic.label], score: fit + (windowMs - Math.max(age, 0)) / windowMs, urlHash: hash });
        }
    }
    const perSource = new Map();
    return [...byUrl.values()]
        .sort((a, b) => b.score - a.score)
        .filter((c) => {
        const n = perSource.get(c.source) ?? 0;
        perSource.set(c.source, n + 1);
        return n < 3;
    })
        .slice(0, limit)
        .map((c, i) => ({ ...c, id: `s${i + 1}` }));
}
//# sourceMappingURL=rank.js.map