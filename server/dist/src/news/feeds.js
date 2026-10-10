import { XMLParser } from "fast-xml-parser";
const parser = new XMLParser({
    ignoreAttributes: false,
    attributeNamePrefix: "@",
    processEntities: true,
    htmlEntities: true,
    // Feeds are untrusted input; keep parsing bounded.
    isArray: (name) => name === "item" || name === "entry" || name === "link",
});
const NAMED = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", hellip: "…", ndash: "–", mdash: "—", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“" };
/** Plain text from feed HTML/entities: tags dropped, entities decoded, whitespace collapsed. */
export function plainText(value, max = 400) {
    let s = typeof value === "string" ? value : typeof value === "object" && value && "#text" in value ? String(value["#text"]) : "";
    s = s.replace(/<!\[CDATA\[|\]\]>/g, "").replace(/<[^>]*>/g, " ");
    s = s.replace(/&#x([0-9a-f]+);/gi, (_, h) => safeChar(parseInt(h, 16)))
        .replace(/&#(\d+);/g, (_, d) => safeChar(Number(d)))
        .replace(/&([a-z]+);/gi, (m, n) => NAMED[n.toLowerCase()] ?? m);
    s = s.replace(/\s+/g, " ").trim();
    return s.length > max ? s.slice(0, max - 1).trimEnd() + "…" : s;
}
function safeChar(code) {
    return code > 0 && code < 0x110000 && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : "";
}
function isoDate(value) {
    const t = Date.parse(plainText(value, 100));
    return Number.isNaN(t) ? null : new Date(t).toISOString();
}
function httpUrl(value) {
    try {
        const u = new URL(value.trim());
        return u.protocol === "https:" || u.protocol === "http:" ? u.toString() : null;
    }
    catch {
        return null;
    }
}
/** Parses RSS 2.0, RSS 1.0 (RDF) and Atom. Returns the feed title and up to `limit` items. */
export function parseFeed(xml, fallbackSource, limit = 60) {
    const doc = parser.parse(xml);
    const rss = doc.rss?.channel ?? doc["rdf:RDF"]?.channel;
    if (rss || doc["rdf:RDF"]) {
        const title = plainText(rss?.title, 80) || fallbackSource;
        const raw = doc.rss?.channel?.item ?? doc["rdf:RDF"]?.item ?? [];
        const items = raw.slice(0, limit).flatMap((it) => {
            const link = Array.isArray(it.link) ? it.link[0] : it.link;
            const url = httpUrl(plainText(link, 500) || (typeof it.guid === "string" ? it.guid : plainText(it.guid, 500)));
            const t = plainText(it.title, 200);
            if (!url || !t)
                return [];
            return [{ title: t, url, source: title, summary: plainText(it.description ?? it["content:encoded"], 300),
                    publishedAt: isoDate(it.pubDate ?? it["dc:date"]) }];
        });
        return { title, items };
    }
    if (doc.feed) {
        const title = plainText(doc.feed.title, 80) || fallbackSource;
        const items = (doc.feed.entry ?? []).slice(0, limit).flatMap((e) => {
            const links = e.link ?? [];
            const alt = links.find((l) => !l["@rel"] || l["@rel"] === "alternate") ?? links[0];
            const url = alt ? httpUrl(String(alt["@href"] ?? "")) : null;
            const t = plainText(e.title, 200);
            if (!url || !t)
                return [];
            return [{ title: t, url, source: title, summary: plainText(e.summary ?? e.content, 300),
                    publishedAt: isoDate(e.published ?? e.updated) }];
        });
        return { title, items };
    }
    throw new Error("not a feed");
}
//# sourceMappingURL=feeds.js.map