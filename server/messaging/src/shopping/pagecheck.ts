// check_offer_page (docs/implementation/SHOPPING.md 1): the code, not the model, reads a shop page's
// price. It fetches the page through the polite fetcher (robots.txt, honest user agent, blocks never
// worked around) and reads the schema.org Product/Offer data the shop publishes for search engines
// (JSON-LD first, then microdata and Open Graph price tags). No structured price means no price: the
// page's prose is never parsed for a number.
import { amountFromData, type Money } from "./money.js";

/** The fetcher both shopping parts use (the deals module's polite fetcher has this shape). */
export type FetchOutcome =
  | { kind: "ok"; status: number; contentType: string; body: Buffer; finalUrl: string }
  | { kind: "blocked" | "disallowed" | "failed"; reason: string };
export interface PageFetcher {
  fetchPage(url: string, options?: { accept?: string; signal?: AbortSignal }): Promise<FetchOutcome>;
}

export interface PageOffer {
  name?: string;
  price: Money;
  availability?: "in_stock" | "out_of_stock" | "preorder" | "other";
  gtin?: string;
  seller?: string;
  finalUrl: string;
  source: "json_ld" | "microdata" | "open_graph";
}

export type PageCheck =
  | { kind: "ok"; offer: PageOffer }
  | { kind: "blocked" | "disallowed" | "failed" | "no_price" | "not_html"; reason: string };

type Json = null | boolean | number | string | Json[] | { [k: string]: Json };
const isObj = (v: unknown): v is Record<string, Json> => typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown): string | undefined => (typeof v === "string" && v.trim() ? v.trim() : undefined);

function types(node: Record<string, Json>): string[] {
  const t = node["@type"];
  const list = Array.isArray(t) ? t : [t];
  return list.flatMap((x) => (typeof x === "string" ? [x.replace(/^https?:\/\/schema\.org\//u, "").toLowerCase()] : []));
}

/** Every object in a JSON-LD document, @graph and nesting included (depth-limited). */
function walk(value: Json, out: Record<string, Json>[], depth = 0) {
  if (depth > 8) return;
  if (Array.isArray(value)) { for (const v of value) walk(v, out, depth + 1); return; }
  if (!isObj(value)) return;
  out.push(value);
  for (const v of Object.values(value)) if (typeof v === "object" && v !== null) walk(v, out, depth + 1);
}

function availabilityOf(v: unknown): PageOffer["availability"] {
  const s = typeof v === "string" ? v.toLowerCase() : "";
  if (!s) return undefined;
  if (s.includes("instock") || s.includes("in_stock") || s.includes("limitedavailability") || s.includes("onlineonly")) return "in_stock";
  if (s.includes("outofstock") || s.includes("soldout") || s.includes("discontinued")) return "out_of_stock";
  if (s.includes("preorder") || s.includes("presale") || s.includes("backorder")) return "preorder";
  return "other";
}

const GTIN = /^\d{8}$|^\d{12,14}$/u;
function gtinOf(node: Record<string, Json>): string | undefined {
  for (const k of ["gtin13", "gtin", "gtin14", "gtin12", "gtin8", "ean"]) {
    const v = node[k];
    const s = typeof v === "number" ? String(v) : str(v);
    if (s && GTIN.test(s)) return s;
  }
  return undefined;
}

function sellerOf(offer: Record<string, Json>): string | undefined {
  const s = offer.seller;
  if (isObj(s)) return str(s.name);
  return str(s);
}

interface Candidate { price: Money; availability?: PageOffer["availability"]; seller?: string; gtin?: string }

function offerCandidate(offer: Record<string, Json>): Candidate | undefined {
  const t = types(offer);
  const spec = isObj(offer.priceSpecification) ? offer.priceSpecification : undefined;
  let minor = amountFromData(offer.price ?? spec?.price);
  let currency = str(offer.priceCurrency) ?? str(spec?.priceCurrency);
  if (minor === undefined && t.includes("aggregateoffer")) {
    // An aggregate's low price is the cheapest of several sellers, not this page's offer: only
    // accepted when there is a single offer.
    if (Number(offer.offerCount) === 1) minor = amountFromData(offer.lowPrice);
  }
  if (minor === undefined || !currency) return undefined;
  currency = currency.toUpperCase();
  if (!/^[A-Z]{3}$/u.test(currency)) return undefined;
  return { price: { minor, currency }, availability: availabilityOf(offer.availability), seller: sellerOf(offer), gtin: gtinOf(offer) };
}

/** The product's offer from JSON-LD blocks, or undefined when there isn't exactly one price. */
export function fromJsonLd(html: string): Omit<PageOffer, "finalUrl"> | undefined {
  const blocks = [...html.matchAll(/<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/giu)];
  const nodes: Record<string, Json>[] = [];
  for (const b of blocks) {
    const raw = (b[1] ?? "").trim().replace(/^<!--|-->$/gu, "");
    try { walk(JSON.parse(raw) as Json, nodes); } catch { /* a broken block is skipped */ }
  }
  const products = nodes.filter((n) => types(n).some((t) => t === "product" || t === "productgroup" || t === "individualproduct"));
  for (const p of products) {
    const offers = Array.isArray(p.offers) ? p.offers : p.offers !== undefined ? [p.offers] : [];
    const cands = offers.flatMap((o) => (isObj(o) ? [offerCandidate(o)].filter((c): c is Candidate => !!c) : []));
    const distinct = new Set(cands.map((c) => `${c.price.minor}:${c.price.currency}`));
    if (cands.length && distinct.size === 1 && cands[0]) {
      const c = cands[0];
      return { name: str(p.name), price: c.price, availability: c.availability, gtin: c.gtin ?? gtinOf(p), seller: c.seller, source: "json_ld" };
    }
  }
  return undefined;
}

const attr = (tag: string, name: string) => new RegExp(String.raw`${name}\s*=\s*["']([^"']*)["']`, "iu").exec(tag)?.[1];

/** Microdata `itemprop="price"` with `itemprop="priceCurrency"`, when each appears exactly once. */
export function fromMicrodata(html: string): Omit<PageOffer, "finalUrl"> | undefined {
  const priceTags = [...html.matchAll(/<[^>]*itemprop\s*=\s*["']price["'][^>]*>/giu)].map((m) => m[0]);
  const curTags = [...html.matchAll(/<[^>]*itemprop\s*=\s*["']priceCurrency["'][^>]*>/giu)].map((m) => m[0]);
  if (priceTags.length !== 1 || curTags.length !== 1 || !priceTags[0] || !curTags[0]) return undefined;
  const minor = amountFromData(attr(priceTags[0], "content"));
  const currency = attr(curTags[0], "content")?.toUpperCase();
  if (minor === undefined || !currency || !/^[A-Z]{3}$/u.test(currency)) return undefined;
  return { price: { minor, currency }, source: "microdata" };
}

/** `product:price:amount` / `og:price:amount` with their currency tag. */
export function fromOpenGraph(html: string): Omit<PageOffer, "finalUrl"> | undefined {
  const meta = (prop: string) => {
    const tags = [...html.matchAll(new RegExp(String.raw`<meta[^>]*property\s*=\s*["']${prop}["'][^>]*>`, "giu"))].map((m) => m[0]);
    return tags.length === 1 && tags[0] ? attr(tags[0], "content") : undefined;
  };
  const amount = meta("product:price:amount") ?? meta("og:price:amount");
  const currency = (meta("product:price:currency") ?? meta("og:price:currency"))?.toUpperCase();
  const minor = amountFromData(amount);
  if (minor === undefined || !currency || !/^[A-Z]{3}$/u.test(currency)) return undefined;
  return { price: { minor, currency }, source: "open_graph" };
}

/** Fetches one shop page and reads its price from structured data only. */
export async function checkOfferPage(url: string, fetcher: PageFetcher, signal?: AbortSignal): Promise<PageCheck> {
  let parsed: URL;
  try { parsed = new URL(url); } catch { return { kind: "failed", reason: "not a valid address" }; }
  if (parsed.protocol !== "https:") return { kind: "failed", reason: "only https pages are read" };
  const r = await fetcher.fetchPage(parsed.toString(), { accept: "text/html,application/xhtml+xml", signal });
  if (r.kind !== "ok") return { kind: r.kind, reason: r.reason };
  if (!/html/iu.test(r.contentType)) return { kind: "not_html", reason: "the page isn't HTML" };
  const html = r.body.toString("utf8");
  const found = fromJsonLd(html) ?? fromMicrodata(html) ?? fromOpenGraph(html);
  if (!found) return { kind: "no_price", reason: "the page publishes no structured price" };
  return { kind: "ok", offer: { ...found, finalUrl: r.finalUrl } };
}
