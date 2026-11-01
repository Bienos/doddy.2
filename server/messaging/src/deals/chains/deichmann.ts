// Deichmann (shoes; observed 30 Oct 2026). deichmann.com publishes no leaflet: its reductions are the "Wyprzedaż"
// category pages, rendered on the server (Angular), 24 products a page, with the shop's own facts on each tile:
//   <deich-lib-product-tile data-id>  <a href="/pl-pl/p/{slug}-{id}">  <h2 class="brandname"> brand  <h3 class="taglist"> model and kind
//   <span data-id="selling-price"> 127,99 zł </span>                   the shelf price
//   <div class="lowest-prior"> "Cena regularna:" 159,99 zł "-20%"       the crossed-out price (the shop's data: oldPriceType CROSSOUT)
//   <div class="lowest-prior"> "Najniższa cena:" 159,99 zł              the Omnibus price: the listing's text key for it is
//                                                                       plp.productPrice.lowestPriorInfo, and the product page
//                                                                       labels the same number "Najniższa cena z 30 dni przed obniżką"
//   <deich-lib-hydra-tag-list> <span> "SALE" | "-20%" | "Tylko online" | "kod: HALLO20" | "Nowość"
//   pagination "Strona 1 od 6"; the next pages are ?page=2, ?page=3…
// The shelf price is the offer's price. "Cena regularna" is kept as the regular price only when above it, the 30-day
// price as the 30-day price. A tag with a code or a basket discount is a condition; "Tylko online" is one too (the
// product is sold only in the online shop); "SALE" and "-20%" are not: the shelf price already holds them.
// "Promocja" (/pl-pl/c/promocja-1467, 1,832 products on 30 Oct) is not read: it is a coupon (HALLO20, 29 Oct to
// 1 Nov) on shoes that are not reduced, for Deichmann PLUS accounts, online only, above a basket amount, and it is
// split by gender only (promocja-promocja-damskie-2240…), so a kind there would need the shop's productType filter.
// robots.txt (User-agent: *) disallows only /search?q=; the shop's search is never used, and the person's words never
// reach Deichmann. The pages to read come from a fixed map of shoe and gender words to Deichmann's sale categories
// (each gender's "Wyprzedaż buty" menu of 30 Oct); at most three pages are read per search.
import { decodeEntities, fetchOfficial, mapLimit, officialUrl } from "./common.js";
import { stickerCondition, zloty } from "./ccc.js";
import { normalize } from "../match.js";
import type { ChainAdapter, ChainRead, Condition, DataProduct, Money } from "../types.js";

export const DEICHMANN_HOSTS = ["www.deichmann.com"] as const;
const DEICHMANN_ORIGIN = "https://www.deichmann.com";
const CATEGORY_BASE = `${DEICHMANN_ORIGIN}/pl-pl/c/`;
/** Deichmann's whole sale, the leaflet's link when more than one category was read. */
export const DEICHMANN_SALE = `${CATEGORY_BASE}wyprzedaz-477`;
/** Page requests to deichmann.com per search, robots.txt aside (as CCC's, ADR-667). */
export const DEICHMANN_MAX_PAGES = 3;

type Gender = "damskie" | "meskie" | "dzieciece";
const GENDERS: readonly Gender[] = ["damskie", "meskie", "dzieciece"];
const GENDER_LABEL: Record<Gender, string> = { damskie: "damskie", meskie: "męskie", dzieciece: "dziecięce" };
/** Words for each gender in an item, normalised (ł → l, no accents). */
const GENDER_WORDS: Record<Gender, RegExp> = {
  damskie: /^(damsk|kobie)/,
  meskie: /^(mesk|mezczyz)/,
  dzieciece: /^(dziec|dziewcz|chlop)/,
};

interface Kind {
  /** The kind as Deichmann's sale menu names it; it goes into each product's name so the matcher can find it. */
  label: string;
  /** True when the item's normalised words name this kind. */
  named: (words: readonly string[]) => boolean;
  /** The sale category's path under /pl-pl/c/ for each gender Deichmann has one for. */
  paths: Partial<Record<Gender, string>>;
}

const any = (re: RegExp) => (words: readonly string[]) => words.some((w) => re.test(w));
const shoes = (w: readonly string[]) => w.some((x) => /^(but(y|ow|ami|ach)?|obuwi[a-z]*)$/.test(x));
const kozaki = any(/^(kozak|kozacz|muszkiet)/);

/** Deichmann's shoe sale categories on 30 Oct 2026 (the "Wyprzedaż buty" menu of each gender). Men's kozaki and
 * children's are sold under "botki i kozaki"; shoes with no sale category there (trampki, tenisówki, mokasyny,
 * śniegowce, men's sandały) have no page to read. */
const KINDS: readonly Kind[] = [
  { label: "sneakersy", named: any(/^(sneaker|sniker)/),
    paths: { damskie: "damskie/wyprzedaz-sneakersy-570", meskie: "meskie/wyprzedaz-sneakersy-602", dzieciece: "dzieciece/wyprzedaz-sneakersy-634" } },
  { label: "buty sportowe", named: (w) => w.some((x) => /^sportow/.test(x)) && shoes(w),
    paths: { damskie: "damskie/wyprzedaz-buty-sportowe-576", meskie: "meskie/wyprzedaz-buty-sportowe-608", dzieciece: "dzieciece/wyprzedaz-buty-sportowe-640" } },
  { label: "botki", named: any(/^(botk|botek$|sztyblet)/),
    paths: { damskie: "damskie/wyprzedaz-botki-569", meskie: "meskie/wyprzedaz-botki-601", dzieciece: "dzieciece/wyprzedaz-botki-633" } },
  { label: "kozaki", named: kozaki, paths: { damskie: "damskie/wyprzedaz-kozaki-572" } },
  { label: "botki i kozaki", named: kozaki, paths: { meskie: "meskie/wyprzedaz-botki-i-kozaki-615", dzieciece: "dzieciece/wyprzedaz-botki-i-kozaki-647" } },
  { label: "półbuty", named: any(/^polbut/),
    paths: { damskie: "damskie/wyprzedaz-polbuty-574", meskie: "meskie/wyprzedaz-polbuty-606", dzieciece: "dzieciece/wyprzedaz-polbuty-638" } },
  { label: "czółenka", named: any(/^(czolen|szpil)/), paths: { damskie: "damskie/wyprzedaz-czolenka-577" } },
  { label: "baleriny", named: any(/^balerin/), paths: { damskie: "damskie/wyprzedaz-baleriny-575", dzieciece: "dzieciece/wyprzedaz-baleriny-639" } },
  { label: "kapcie", named: any(/^(kapc|kapec$|papuc)/),
    paths: { damskie: "damskie/wyprzedaz-kapcie-573", meskie: "meskie/wyprzedaz-kapcie-605", dzieciece: "dzieciece/wyprzedaz-kapcie-637" } },
  { label: "klapki", named: any(/^(klapk|klapek$)/),
    paths: { damskie: "damskie/wyprzedaz-klapki-580", meskie: "meskie/wyprzedaz-klapki-612", dzieciece: "dzieciece/wyprzedaz-klapki-644" } },
  { label: "sandały", named: any(/^sandal/), paths: { damskie: "damskie/wyprzedaz-sandaly-579", dzieciece: "dzieciece/wyprzedaz-sandaly-643" } },
  { label: "kalosze", named: any(/^kalosz/), paths: { dzieciece: "dzieciece/wyprzedaz-kalosze-650" } },
  { label: "eleganckie buty", named: (w) => w.some((x) => /^elegan/.test(x)) && shoes(w), paths: { meskie: "meskie/wyprzedaz-eleganckie-buty-616" } },
];

export interface DeichmannCategory { path: string; label: string; url: string }

/** The sale categories that fit the items, in the items' order, each once. Only Deichmann's fixed category pages:
 * the items' words choose among them and are never sent. An item naming no gender gets every gender's page. */
export function deichmannCategories(queries: readonly string[]): DeichmannCategory[] {
  const out = new Map<string, DeichmannCategory>();
  for (const q of queries) {
    const words = normalize(q).split(" ").filter(Boolean);
    const named = GENDERS.filter((g) => words.some((w) => GENDER_WORDS[g].test(w)));
    const genders = named.length ? named : GENDERS;
    for (const kind of KINDS) {
      if (!kind.named(words)) continue;
      for (const g of genders) {
        const path = kind.paths[g];
        if (path && !out.has(path)) out.set(path, { path, label: `${kind.label} ${GENDER_LABEL[g]}`, url: CATEGORY_BASE + path });
      }
    }
  }
  return [...out.values()];
}

const pageUrl = (c: DeichmannCategory, page: number) => (page > 1 ? `${c.url}?page=${page}` : c.url);

/** Text of an HTML fragment: tags out, entities decoded, spaces collapsed. */
const textOf = (html: string) => decodeEntities(html.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();

const PRICE = String.raw`(\d[\d\s  ]{0,8}(?:[.,]\d{2})?)\s*zł`;
/** "Cena regularna: 159,99 zł -20%" (and "Cena pierwsza", should Deichmann print it). */
const REGULAR = new RegExp(String.raw`^cena (?:regularna|pierwsza)\s*:\s*${PRICE}`, "i");
/** "Najniższa cena: 159,99 zł" on the listing, "Najniższa cena z 30 dni przed obniżką: …" on a product page. */
const LOWEST_30D = new RegExp(String.raw`^najniższa cena(?:\s+z\s+30\s+dni[^:]{0,40})?\s*:\s*${PRICE}`, "i");

/** A product's page on deichmann.com, without query or fragment, or undefined. */
function productUrl(href: string | undefined): string | undefined {
  const u = officialUrl(href ? decodeEntities(href) : undefined, DEICHMANN_HOSTS, DEICHMANN_ORIGIN);
  if (!u || !u.pathname.startsWith("/pl-pl/p/") || u.pathname.includes("//")) return undefined;
  return `${DEICHMANN_ORIGIN}${u.pathname}`;
}

/** One product tile as a data product, or undefined when it can't be read or shows no reduction. */
function tileProduct(tile: string, label: string): DataProduct | undefined {
  // The tile's own link comes first; the colour links further down point at other products.
  const url = productUrl(/<a\b[^>]*\bhref="([^"]*)"/.exec(tile)?.[1]);
  const brand = textOf(/<h2\b[^>]*\bclass="brandname"[^>]*>([\s\S]*?)<\/h2>/.exec(tile)?.[1] ?? "");
  const model = textOf(/<h3\b[^>]*\bclass="taglist"[^>]*>([\s\S]*?)<\/h3>/.exec(tile)?.[1] ?? "");
  if (!url || !(brand || model)) return undefined;
  const shelf = [...tile.matchAll(/<span\b[^>]*\bdata-id="selling-price"[^>]*>([\s\S]*?)<\/span>/g)].map((m) => zloty(textOf(m[1]!)));
  if (shelf.length !== 1 || !shelf[0]) return undefined; // no price, "od …", or two: which is paid isn't said, so nothing is guessed
  const price = shelf[0];
  let regular: Money | undefined;
  let lowest30d: Money | undefined;
  for (const m of tile.matchAll(/<div\b[^>]*\bclass="lowest-prior"[^>]*>([\s\S]*?)<\/div>/g)) {
    const t = textOf(m[1]!);
    regular ??= zloty(REGULAR.exec(t)?.[1]);
    lowest30d ??= zloty(LOWEST_30D.exec(t)?.[1]);
  }
  const discounts: Condition[] = [];
  let onlineOnly = false;
  const tags = /<deich-lib-hydra-tag-list\b[\s\S]*?<\/deich-lib-hydra-tag-list>/.exec(tile)?.[0] ?? "";
  for (const m of tags.matchAll(/<span\b[^>]*>([\s\S]*?)<\/span>/g)) {
    const t = textOf(m[1]!);
    if (/^tylko online$/i.test(t)) { onlineOnly = true; continue; }
    const c = stickerCondition(t);
    if (c && !discounts.some((x) => x.text === c.text)) discounts.push(c);
  }
  // Only what Deichmann shows as a reduction: a regular price above the shelf price, the 30-day price "przed
  // obniżką", or a discount with a code or at the basket. "Tylko online" alone is no promotion.
  const above = regular && regular.minor > price.minor ? regular : undefined;
  if (!above && !lowest30d && discounts.length === 0) return undefined;
  const name = `${[brand, model].filter(Boolean).join(" ")}, ${label}`.replace(/\s+/g, " ").slice(0, 160);
  return {
    name, price, url,
    conditions: [...discounts, ...(onlineOnly ? [{ kind: "other" as const, text: "tylko online" }] : [])],
    ...(above ? { regularPrice: above } : {}),
    ...(lowest30d ? { lowest30d } : {}),
  };
}

/** One category page: its reduced products, how many product tiles it had, and its number of pages when the
 * pagination says. Undefined when the page has no product tile at all (an unknown page or changed markup). */
export function parseDeichmannPage(html: string, label: string): { products: DataProduct[]; tiles: number; pages?: number } | undefined {
  const tiles = html.split(/<deich-lib-product-tile(?=[\s>])/).slice(1).map((t) => t.split("</deich-lib-product-tile>")[0]!);
  if (tiles.length === 0) return undefined;
  const byUrl = new Map<string, DataProduct>();
  for (const t of tiles) {
    const p = tileProduct(t, label);
    if (p && !byUrl.has(p.url)) byUrl.set(p.url, p);
  }
  const total = /<span\b[^>]*>\s*Strona\s*<\/span>\s*<span\b[^>]*>\s*\d{1,4}\s*<\/span>\s*<span\b[^>]*>\s*od\s*<\/span>\s*<span\b[^>]*>\s*(\d{1,4})\s*<\/span>/
    .exec(html)?.[1];
  const pages = total && Number(total) >= 1 ? Number(total) : undefined;
  return { products: [...byUrl.values()], tiles: tiles.length, ...(pages ? { pages } : {}) };
}

export const deichmann: ChainAdapter = {
  chain: "deichmann",
  hosts: DEICHMANN_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const categories = deichmannCategories(ctx.queries);
    if (categories.length === 0) return { kind: "no_leaflet" };
    const chosen = categories.slice(0, DEICHMANN_MAX_PAGES).map((c) => ({ c, read: 0, pages: 1, first: false }));
    const failures: ChainRead[] = [];
    const byUrl = new Map<string, DataProduct>();
    let blocked = false;
    const readPage = async (s: (typeof chosen)[number], page: number) => {
      // Once Deichmann has said no, nothing more is asked of it in this request.
      if (blocked || ctx.signal.aborted) { failures.push({ kind: "failed", reason: "not_asked" }); return; }
      const r = await fetchOfficial(ctx, pageUrl(s.c, page), DEICHMANN_HOSTS, "text/html");
      if (!r.ok) {
        if (r.read.kind === "blocked") blocked = true;
        failures.push(r.read);
        return;
      }
      const parsed = parseDeichmannPage(r.body.toString("utf8"), s.c.label);
      if (!parsed) { failures.push({ kind: "failed", reason: "no_products" }); return; }
      s.read++;
      if (page === 1) { s.first = true; s.pages = parsed.pages ?? 1; }
      for (const p of parsed.products) if (!byUrl.has(p.url)) byUrl.set(p.url, p);
    };
    // Each category's first page, then the next pages in turn while requests are left.
    await mapLimit(chosen, 2, (s) => readPage(s, 1));
    const more: [(typeof chosen)[number], number][] = [];
    for (let page = 2, left = DEICHMANN_MAX_PAGES - chosen.length; left > 0; page++) {
      const next = chosen.filter((s) => s.first && page <= s.pages);
      if (next.length === 0) break;
      for (const s of next.slice(0, left)) more.push([s, page]);
      left -= Math.min(next.length, left);
    }
    await mapLimit(more, 2, ([s, page]) => readPage(s, page));

    const read = chosen.filter((s) => s.first);
    if (read.length === 0) return failures.find((f) => f.kind === "blocked") ?? failures[0] ?? { kind: "failed", reason: "not_read" };
    const reasons = [
      ...(failures.length ? ["some_pages_failed"] : []),
      ...(categories.length > chosen.length ? ["some_categories_not_read"] : []),
      ...(chosen.some((s) => s.first && s.read < s.pages) ? ["some_pages_not_read"] : []),
    ];
    const incomplete = reasons.length ? reasons.join(",") : undefined;
    const products = [...byUrl.values()];
    if (products.length === 0) return incomplete ? { kind: "failed", reason: incomplete } : { kind: "no_leaflet" };
    const url = read.length === 1 ? read[0]!.c.url : DEICHMANN_SALE;
    return {
      kind: "ok",
      leaflets: [{ leaflet: { title: "Wyprzedaż Deichmann", url }, products, pages: [], strategy: "none" }],
      ...(incomplete ? { incomplete } : {}),
    };
  },
};
