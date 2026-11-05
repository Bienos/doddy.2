import { XMLParser } from "fast-xml-parser";

export interface NewsItem {
  title: string;
  url: string;
  source: string;
  summary: string;
  publishedAt: string | null; // ISO
  /** A picture the publisher put in the feed (enclosure, media:content/thumbnail or the first <img>), https only. Absent when there is none. */
  imageUrl?: string;
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@",
  processEntities: true,
  htmlEntities: true,
  // Feeds are untrusted input; keep parsing bounded.
  isArray: (name) => name === "item" || name === "entry" || name === "link",
});

const NAMED: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", hellip: "…", ndash: "–", mdash: "—", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“" };

/** Plain text from feed HTML/entities: tags dropped, entities decoded, whitespace collapsed. */
export function plainText(value: unknown, max = 400): string {
  let s = typeof value === "string" ? value : typeof value === "object" && value && "#text" in value ? String((value as { "#text": unknown })["#text"]) : "";
  s = s.replace(/<!\[CDATA\[|\]\]>/g, "").replace(/<[^>]*>/g, " ");
  s = s.replace(/&#x([0-9a-f]+);/gi, (_, h) => safeChar(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => safeChar(Number(d)))
    .replace(/&([a-z]+);/gi, (m, n: string) => NAMED[n.toLowerCase()] ?? m);
  s = s.replace(/\s+/g, " ").trim();
  return s.length > max ? s.slice(0, max - 1).trimEnd() + "…" : s;
}

function safeChar(code: number): string {
  return code > 0 && code < 0x110000 && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : "";
}

function isoDate(value: unknown): string | null {
  const t = Date.parse(plainText(value, 100));
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

/** An https image address from the feed, or undefined. Only https: the app shows pictures over a secure connection only. */
export function imageUrl(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const u = httpUrl(value);
  return u && u.startsWith("https:") ? u : undefined;
}

const MEDIA_TYPES = /^image\//i;

/** The first picture an RSS item or Atom entry carries, if any. Attributes are read as strings only. */
export function itemImage(it: Record<string, any>, html: unknown): string | undefined {
  const candidates: unknown[] = [];
  const attr = (node: unknown, name: string): unknown =>
    node && typeof node === "object" ? (node as Record<string, unknown>)[name] : undefined;
  for (const node of [it["media:content"], it["media:thumbnail"], it.enclosure].flat()) {
    if (!node) continue;
    const type = attr(node, "@type");
    const medium = attr(node, "@medium");
    if (typeof type === "string" && !MEDIA_TYPES.test(type)) continue;
    if (typeof medium === "string" && medium !== "image") continue;
    candidates.push(attr(node, "@url") ?? attr(node, "@href")); // Atom enclosures say href
  }
  const img = typeof html === "string" ? /<img[^>]+src=["']([^"']+)["']/i.exec(html) : null;
  if (img) candidates.push(img[1]);
  for (const c of candidates) {
    const u = imageUrl(c);
    if (u) return u;
  }
  return undefined;
}

export function httpUrl(value: string): string | null {
  try {
    const u = new URL(value.trim());
    return u.protocol === "https:" || u.protocol === "http:" ? u.toString() : null;
  } catch { return null; }
}

/** Parses RSS 2.0, RSS 1.0 (RDF) and Atom. Returns the feed title and up to `limit` items. */
export function parseFeed(xml: string, fallbackSource: string, limit = 60): { title: string; items: NewsItem[] } {
  const doc = parser.parse(xml) as Record<string, any>;
  const rss = doc.rss?.channel ?? doc["rdf:RDF"]?.channel;
  if (rss || doc["rdf:RDF"]) {
    const title = plainText(rss?.title, 80) || fallbackSource;
    const raw: any[] = doc.rss?.channel?.item ?? doc["rdf:RDF"]?.item ?? [];
    const items = raw.slice(0, limit).flatMap((it): NewsItem[] => {
      const link = Array.isArray(it.link) ? it.link[0] : it.link;
      const url = httpUrl(plainText(link, 500) || (typeof it.guid === "string" ? it.guid : plainText(it.guid, 500)));
      const t = plainText(it.title, 200);
      if (!url || !t) return [];
      const image = itemImage(it, it["content:encoded"] ?? it.description);
      return [{ title: t, url, source: title, summary: plainText(it.description ?? it["content:encoded"], 300),
        publishedAt: isoDate(it.pubDate ?? it["dc:date"]), ...(image ? { imageUrl: image } : {}) }];
    });
    return { title, items };
  }
  if (doc.feed) {
    const title = plainText(doc.feed.title, 80) || fallbackSource;
    const items = (doc.feed.entry ?? []).slice(0, limit).flatMap((e: any): NewsItem[] => {
      const links: any[] = e.link ?? [];
      const alt = links.find((l) => !l["@rel"] || l["@rel"] === "alternate") ?? links[0];
      const url = alt ? httpUrl(String(alt["@href"] ?? "")) : null;
      const t = plainText(e.title, 200);
      if (!url || !t) return [];
      const enclosure = links.find((l) => l["@rel"] === "enclosure");
      const image = itemImage({ ...e, enclosure }, e.content ?? e.summary);
      return [{ title: t, url, source: title, summary: plainText(e.summary ?? e.content, 300),
        publishedAt: isoDate(e.published ?? e.updated), ...(image ? { imageUrl: image } : {}) }];
    });
    return { title, items };
  }
  throw new Error("not a feed");
}
