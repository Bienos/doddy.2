import { XMLParser } from "fast-xml-parser";
import { capHtml, stripTags } from "../htmlScan.js";

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

/** A feed field is read up to this many characters: a title or a 300-character summary comes from its start. */
export const FEED_TEXT_MAX_CHARS = 256 * 1024;

/** Plain text from feed HTML/entities: tags dropped, entities decoded, whitespace collapsed. */
export function plainText(value: unknown, max = 400): string {
  let s = typeof value === "string" ? value : typeof value === "object" && value && "#text" in value ? String((value as { "#text": unknown })["#text"]) : "";
  s = stripTags(capHtml(s, FEED_TEXT_MAX_CHARS).replace(/<!\[CDATA\[|\]\]>/g, ""));
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

/** Longest item or picture address kept (`httpUrl`). Longer ones are not links anyone shares; an item whose link is
 * longer is dropped before it reaches the shared news cache, a picture that long is left out. */
export const MAX_URL_CHARS = 2048;

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
  const img = typeof html === "string" ? firstImgSrc(html.slice(0, FEED_TEXT_MAX_CHARS)) : undefined;
  if (img) candidates.push(img);
  for (const c of candidates) {
    const u = imageUrl(c);
    if (u) return u;
  }
  return undefined;
}

/**
 * The address of the first `<img … src="…">`: what `/<img[^>]+src=["']([^"']+)["']/i` finds, in linear time. As in
 * that regex, the last `src=` before the tag's first ">" that has a value and a closing quote wins, and the value
 * runs to the next quote of either kind.
 */
export function firstImgSrc(html: string): string | undefined {
  const img = /<img/gi;
  const src = /src=["']/gi;
  const quote = /["']/g;
  for (let from = 0; ;) {
    img.lastIndex = from;
    const m = img.exec(html);
    if (!m) return undefined;
    const gt = html.indexOf(">", m.index + 4);
    const tag = html.slice(m.index, gt < 0 ? html.length : gt);
    const starts: number[] = [];
    // `[^>]+` takes at least one character, so a src= right after "<img" doesn't count.
    src.lastIndex = 5;
    for (let s = src.exec(tag); s; s = src.exec(tag)) starts.push(m.index + s.index + s[0].length);
    for (let i = starts.length - 1; i >= 0; i--) {
      const value = starts[i]!;
      quote.lastIndex = value;
      const q = quote.exec(html);
      if (q && q.index > value) return html.slice(value, q.index);
    }
    // No "<img" before this tag's ">" can do better: its src= choices are a subset of these.
    if (gt < 0) return undefined;
    from = gt + 1;
  }
}

export function httpUrl(value: string): string | null {
  try {
    const u = new URL(value.trim());
    if (u.protocol !== "https:" && u.protocol !== "http:") return null;
    // At most MAX_URL_CHARS, normalised: an item with a longer link is dropped before it is cached.
    const s = u.toString();
    return s.length <= MAX_URL_CHARS ? s : null;
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
