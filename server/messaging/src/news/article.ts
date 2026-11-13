// Reading a news article's own text from its web page, for the AI summary a person asks for by tapping a story in
// On my radar (owner, 13 Nov 2026). The page is fetched by the polite fetcher (robots.txt and `Content-Signal:
// ai-input=no` respected, HTTPS only, no private network, 10 s and 3 MB); this file only reads what came back.
//
// Linear-time scans only (src/htmlScan.ts): a fetched page is untrusted input. What is read: the schema.org
// `articleBody` the publisher gives search engines (JSON-LD), else the paragraphs of the page's <article> (or <main>,
// or the whole page) once menus, scripts and asides are dropped. A page the publisher marks as not free
// (`isAccessibleForFree: false`) is not read at all, and a page with too little text is not summarised: a teaser in
// front of a paywall would give a confident summary of half a story.
import { capHtml, elements, firstElement, replaceSpans, startTags } from "../htmlScan.js";
import { plainText } from "./feeds.js";

/** A page is read up to this many characters (the fetcher already stops at 3 MB). */
export const ARTICLE_HTML_MAX_CHARS = 2 * 1024 * 1024;
/** Less article text than this is a teaser, a video page or a wall: nothing is summarised. */
export const ARTICLE_MIN_CHARS = 400;
/** What the model is given at most (about 4,000 tokens): a long piece is cut at a paragraph near this length. */
export const ARTICLE_MAX_CHARS = 14_000;
/** A JSON-LD block longer than this is skipped unread. */
const JSON_LD_MAX_CHARS = 512 * 1024;
/** A paragraph shorter than this is a caption, a byline or a button, not article text. */
const MIN_PARAGRAPH_CHARS = 40;

export type ArticleReading =
  | { ok: true; text: string; title?: string; from: "json_ld" | "paragraphs" }
  | { ok: false; reason: "paywall" | "too_short" | "not_html" };

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
const isObj = (v: unknown): v is Record<string, Json> => typeof v === "object" && v !== null && !Array.isArray(v);

function types(node: Record<string, Json>): string[] {
  const t = node["@type"];
  const list = Array.isArray(t) ? t : [t];
  return list.flatMap((x) => (typeof x === "string" ? [x.replace(/^https?:\/\/schema\.org\//u, "").toLowerCase()] : []));
}

/** Every object in a JSON-LD document, @graph and nesting included (depth- and count-limited). */
function walk(value: Json, out: Record<string, Json>[], depth = 0) {
  if (depth > 6 || out.length > 500) return;
  if (Array.isArray(value)) { for (const v of value) walk(v, out, depth + 1); return; }
  if (!isObj(value)) return;
  out.push(value);
  for (const v of Object.values(value)) if (typeof v === "object" && v !== null) walk(v, out, depth + 1);
}

const isArticleType = (t: string) => t.endsWith("article") || t === "blogposting" || t === "liveblogposting" || t === "report";
const notFree = (v: Json | undefined) => v === false || (typeof v === "string" && v.trim().toLowerCase() === "false");

const LD_JSON_TYPE = /type\s*=\s*["']application\/ld\+json["']/iu;

/** The publisher's own article data (schema.org NewsArticle and kin), when the page has it. */
function fromJsonLd(html: string): { body?: string; headline?: string; paywalled: boolean } | undefined {
  const nodes: Record<string, Json>[] = [];
  for (const b of elements(html, /<script/giu, /<\/script>/giu, (tag) => LD_JSON_TYPE.test(tag.text))) {
    if (b.content.length > JSON_LD_MAX_CHARS) continue;
    const raw = b.content.trim().replace(/^<!--|-->$/gu, "");
    try { walk(JSON.parse(raw) as Json, nodes); } catch { /* a broken block is skipped */ }
  }
  const articles = nodes.filter((n) => types(n).some(isArticleType));
  if (articles.length === 0) return undefined;
  const paywalled = articles.some((a) => notFree(a.isAccessibleForFree));
  let body: string | undefined;
  let headline: string | undefined;
  for (const a of articles) {
    const b = typeof a.articleBody === "string" ? plainText(a.articleBody, ARTICLE_MAX_CHARS * 2) : "";
    if (b.length > (body?.length ?? 0)) body = b;
    if (!headline && typeof a.headline === "string") headline = plainText(a.headline, 300) || undefined;
  }
  return { body, headline, paywalled };
}

const DROPPED = ["script", "style", "noscript", "template", "svg", "iframe", "nav", "footer", "aside", "figcaption", "button", "select"];

/** The text of the page's paragraphs: in its largest <article>, else <main>, else anywhere. */
function fromParagraphs(html: string): string {
  let page = html;
  for (const tag of DROPPED) page = replaceSpans(page, new RegExp(`<${tag}\\b`, "giu"), new RegExp(`</${tag}>`, "giu"), " ");
  const paragraphs = (scope: string) => {
    const out: string[] = [];
    for (const p of elements(scope, /<p\b/giu, /<\/p>/giu)) {
      const t = plainText(p.content, 4000);
      if (t.length >= MIN_PARAGRAPH_CHARS) out.push(t);
    }
    return out.join("\n\n");
  };
  let best = "";
  for (const a of elements(page, /<article\b/giu, /<\/article>/giu)) {
    const t = paragraphs(a.content);
    if (t.length > best.length) best = t;
  }
  if (best.length >= ARTICLE_MIN_CHARS) return best;
  const main = firstElement(page, /<main\b/giu, /<\/main>/giu);
  const inMain = main ? paragraphs(main.content) : "";
  if (inMain.length >= ARTICLE_MIN_CHARS) return inMain;
  const all = paragraphs(page);
  return [best, inMain, all].reduce((a, b) => (b.length > a.length ? b : a), "");
}

/** og:title, else the <title>. */
function pageTitle(html: string): string | undefined {
  for (const tag of startTags(html, /<meta\b/giu)) {
    if (!/property\s*=\s*["']og:title["']/iu.test(tag.text)) continue;
    const content = /content\s*=\s*"([^"]*)"|content\s*=\s*'([^']*)'/iu.exec(tag.text);
    const t = plainText(content?.[1] ?? content?.[2] ?? "", 300);
    if (t) return t;
  }
  const title = firstElement(html, /<title\b/giu, /<\/title>/giu);
  return title ? plainText(title.content, 300) || undefined : undefined;
}

/** Cuts `text` at the last paragraph or sentence end before `max`, so the model never gets half a sentence. */
export function cutText(text: string, max = ARTICLE_MAX_CHARS): string {
  if (text.length <= max) return text;
  const head = text.slice(0, max);
  const para = head.lastIndexOf("\n\n");
  if (para > max * 0.6) return head.slice(0, para).trimEnd();
  const sentence = Math.max(head.lastIndexOf(". "), head.lastIndexOf("? "), head.lastIndexOf("! "));
  return (sentence > max * 0.6 ? head.slice(0, sentence + 1) : head).trimEnd();
}

/** The article's text and title from its page's HTML, or why there is nothing to summarise. */
export function readArticle(rawHtml: string): ArticleReading {
  const html = capHtml(rawHtml, ARTICLE_HTML_MAX_CHARS);
  const ld = fromJsonLd(html);
  if (ld?.paywalled) return { ok: false, reason: "paywall" };
  const title = ld?.headline ?? pageTitle(html);
  const inParagraphs = fromParagraphs(html);
  // The publisher's articleBody wins unless the page's paragraphs say much more (some give search engines a teaser).
  const ldBody = ld?.body ?? "";
  if (ldBody.length >= ARTICLE_MIN_CHARS && ldBody.length * 1.5 >= inParagraphs.length) {
    return { ok: true, text: cutText(ldBody), ...(title ? { title } : {}), from: "json_ld" };
  }
  if (inParagraphs.length < ARTICLE_MIN_CHARS) return { ok: false, reason: "too_short" };
  return { ok: true, text: cutText(inParagraphs), ...(title ? { title } : {}), from: "paragraphs" };
}

/** True when the answer is a web page: its type says HTML, or (with no type) it starts like one. */
export function looksLikeHtml(contentType: string, body: Buffer): boolean {
  const type = contentType.toLowerCase();
  if (type.includes("html")) return true;
  if (type.trim() !== "") return false;
  return /<!doctype html|<html[\s>]/iu.test(body.subarray(0, 2048).toString("latin1"));
}

/** The page's characters: the charset its header or its <meta> names (windows-1250, iso-8859-2…), else UTF-8. */
export function decodeHtml(body: Buffer, contentType: string): string {
  const declared = /charset\s*=\s*["']?([\w.:-]+)/iu.exec(contentType)?.[1]
    ?? /<meta[^>]{0,200}charset\s*=\s*["']?([\w.:-]+)/iu.exec(body.subarray(0, 4096).toString("latin1"))?.[1];
  if (declared && !/^utf-?8$/iu.test(declared)) {
    try { return new TextDecoder(declared.toLowerCase()).decode(body); } catch { /* an unknown charset: read as UTF-8 */ }
  }
  return body.toString("utf8");
}
