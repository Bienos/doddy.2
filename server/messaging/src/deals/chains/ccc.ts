// CCC (shoes; observed 29 and 30 Oct 2026). ccc.eu publishes no leaflet: its promotions are sale category
// pages, rendered on the server (Angular), with the chain's own facts on each product tile:
//   <o-product-box data-product-id>  href "/pl/pl/p/{slug}"  <strong id="trademark-N"> brand  <span id="model-N"> model
//   <shared-atoms-pricing id="price-N"> <span> 149,99 zł </span>      the shelf price (no struck price on 30 Oct)
//   <shared-atoms-omnibus-pricing> "Najniższa cena z 30 dni przed obniżką: 199,99 zł" "Cena pierwsza: 259,99 zł"
//   <shared-molecules-sticker> <span class="text"> "-30% w koszyku" | "Okazja" | "Nowa kolekcja" | "AI"
// "-30% w koszyku" is taken off at the basket: the tile's and the product page's price stay the shelf price, so
// the shelf price is the offer's price and the basket discount a condition. "Cena pierwsza" (the price CCC first
// sold the product at) is printed plainly, not struck, on the tile and the product page; like Aldi's "cena sprzed
// pierwszej obniżki" it is kept as the regular price, and only when it is above the shelf price.
// robots.txt (User-agent: *) allows /pl/pl/c/ and disallows `*/search`, so CCC's own search is never used: the
// person's words never reach CCC. The pages to read come from a fixed map of shoe words to CCC's sale categories
// (the "Promocje" menu of 30 Oct; the top-level /wyprzedaz answers 404). A page lists 25 products, or 100 with
// CCC's own `pageSize=100` (1.8 MB, under the fetcher's 3 MB cap); at most four pages are read per search.
import { decodeEntities, fetchOfficial, mapLimit, officialUrl } from "./common.js";
import { normalize } from "../match.js";
import type { ChainAdapter, ChainRead, Condition, DataProduct, Money } from "../types.js";

export const CCC_HOSTS = ["ccc.eu"] as const;
const CCC_ORIGIN = "https://ccc.eu";
const CATEGORY_BASE = `${CCC_ORIGIN}/pl/pl/c/`;
/** CCC's whole seasonal sale, the leaflet's link when more than one category was read. */
export const CCC_SALE = `${CATEGORY_BASE}promo/wyprzedaz-sezonowa`;
/** Page requests to ccc.eu per search, robots.txt aside. */
export const CCC_MAX_PAGES = 3; // ADR-667: three pages of 100 (each gender's first) keep a search near 6 to 9 s; four took 9 to 13 s of the 25 s budget
const PAGE_SIZE = 100;

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
  /** The kind as CCC's sale menu names it; it goes into each product's name so the matcher can find it. */
  label: string;
  /** True when the item's normalised words name this kind. */
  named: (words: readonly string[]) => boolean;
  /** The sale category's path under /pl/pl/c/ for each gender CCC has one for. */
  paths: Partial<Record<Gender, string>>;
}

const any = (re: RegExp) => (words: readonly string[]) => words.some((w) => re.test(w));

/** CCC's shoe sale categories on 30 Oct 2026 ("Kupuj na promocji według kategorii" in each gender's menu). Shoes
 * with no sale category there (kozaki, botki, półbuty, mokasyny, baleriny, śniegowce, kalosze, women's or men's
 * kapcie) have no page to read. */
const KINDS: readonly Kind[] = [
  { label: "sneakersy", named: any(/^(sneaker|sniker)/),
    paths: { damskie: "damskie/wyprzedaz/sneakersy", meskie: "meskie/wyprzedaz/sneakersy", dzieciece: "dzieciece/wyprzedaz/sneakersy" } },
  { label: "trampki", named: any(/^(trampk|trampek$)/),
    paths: { damskie: "damskie/wyprzedaz/trampki", meskie: "meskie/wyprzedaz/trampki", dzieciece: "dzieciece/wyprzedaz/trampki" } },
  { label: "klapki", named: any(/^(klapk|klapek$)/),
    paths: { damskie: "damskie/wyprzedaz/klapki", meskie: "meskie/wyprzedaz/klapki", dzieciece: "dzieciece/wyprzedaz/klapki" } },
  { label: "sandały", named: any(/^sandal/),
    paths: { damskie: "damskie/wyprzedaz/sandaly", meskie: "meskie/wyprzedaz/sandaly", dzieciece: "dzieciece/wyprzedaz/sandaly" } },
  { label: "szpilki i czółenka", named: any(/^(szpil|czolen)/), paths: { damskie: "damskie/wyprzedaz/szpilki-czolenka" } },
  { label: "buty sportowe", named: (w) => w.some((x) => /^sportow/.test(x)) && w.some((x) => /^(but(y|ow|ami|ach)?|obuwi)$/.test(x)),
    paths: { meskie: "meskie/wyprzedaz/buty-sportowe", dzieciece: "dzieciece/wyprzedaz/buty-sportowe" } },
  { label: "kapcie", named: any(/^(kapc|kapec$)/), paths: { dzieciece: "dzieciece/wyprzedaz/kapcie" } },
];

export interface CccCategory { path: string; label: string; url: string }

/** The sale categories that fit the items, in the items' order, each once. Only CCC's fixed category pages: the
 * items' words choose among them and are never sent. An item naming no gender gets every gender's page. */
export function cccCategories(queries: readonly string[]): CccCategory[] {
  const out = new Map<string, CccCategory>();
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

const pageUrl = (c: CccCategory, page: number) => `${c.url}?pageSize=${PAGE_SIZE}${page > 1 ? `&page=${page}` : ""}`;

/** Text of an HTML fragment: tags out, entities decoded, spaces collapsed. */
const textOf = (html: string) => decodeEntities(html.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();

/** "149,99 zł", "1 299,99 zł" (a space, no-break or narrow space between thousands). */
export function zloty(text: string | undefined): Money | undefined {
  if (!text) return undefined;
  const t = decodeEntities(text).replace(/z[łl]/i, "").replace(/[\s  ]/g, "");
  const m = /^(\d{1,6})(?:[.,](\d{2}))?$/.exec(t);
  if (!m) return undefined;
  const minor = Number(m[1]) * 100 + Number(m[2] ?? "0");
  return minor > 0 && minor < 1_000_000 ? { minor, currency: "PLN" } : undefined;
}

const PRICE = String.raw`(\d[\d\s  ]{0,8}(?:[.,]\d{2})?)\s*zł`;
const LOWEST_30D = new RegExp(String.raw`najniższa cena z 30 dni[^:]{0,40}:\s*${PRICE}`, "i");
const FIRST_PRICE = new RegExp(String.raw`cena pierwsza:\s*${PRICE}`, "i");

/** A discount CCC takes off at the basket or with a code, from a sticker's text, in the code's words. A sticker
 * that names neither ("Okazja", "Nowa kolekcja", a bare "-30%") is no condition: the shelf price already holds it.
 * Like the page reader's conditions, it never states an amount of money. */
export function stickerCondition(sticker: string): Condition | undefined {
  const t = sticker.replace(/\s+/g, " ").trim();
  const percent = /(?:^|[^\d])(\d{1,2})\s?%/.exec(t)?.[1];
  const basket = /\bw\s+koszyku\b/i.test(t);
  // "z kodem JESIEN20", "Kod: JESIEN20": the code as printed, capitals and digits only.
  const keyword = /\bkod(?:em|u)?\b\s*:?\s*/i.exec(t);
  const code = keyword ? /^([A-Z0-9][A-Z0-9_-]{2,19})\b/.exec(t.slice(keyword.index + keyword[0].length))?.[1] : undefined;
  if (!basket && !code) return undefined;
  const parts = [percent ? `−${Number(percent)}%` : "rabat", ...(basket ? ["w koszyku"] : []), ...(code ? [`z kodem ${code}`] : [])];
  return { kind: "other", text: parts.join(" ").slice(0, 80) };
}

/** A product's page on ccc.eu, without query or fragment, or undefined. */
function productUrl(href: string | undefined): string | undefined {
  const u = officialUrl(href ? decodeEntities(href) : undefined, CCC_HOSTS, CCC_ORIGIN);
  if (!u || !u.pathname.startsWith("/pl/pl/p/") || u.pathname.includes("//")) return undefined;
  return `${CCC_ORIGIN}${u.pathname}`;
}

/** One product tile as a data product, or undefined when it can't be read or shows no promotion. */
function tileProduct(tile: string, label: string): DataProduct | undefined {
  const url = productUrl(/href="(\/pl\/pl\/p\/[^"]+)"/.exec(tile)?.[1]);
  const brand = textOf(/id="trademark-\d+"[^>]*>([\s\S]*?)<\/strong>/.exec(tile)?.[1] ?? "");
  const model = textOf(/id="model-\d+"[^>]*>([\s\S]*?)<\/span>/.exec(tile)?.[1] ?? "");
  const pricing = /<shared-atoms-pricing\b[\s\S]*?<\/shared-atoms-pricing>/.exec(tile)?.[0];
  if (!url || !(brand || model) || !pricing) return undefined;
  // Every price printed in the price block: one shelf price, and a struck one if CCC ever shows it.
  const prices = [...pricing.matchAll(/<span([^>]*)>([^<]*)<\/span>/g)]
    .map((m) => ({ struck: /line-through/.test(m[1]!), money: zloty(m[2]) }))
    .filter((p): p is { struck: boolean; money: Money } => !!p.money);
  const shelf = prices.filter((p) => !p.struck);
  if (shelf.length !== 1) return undefined; // two unstruck prices: which is paid isn't said, so nothing is guessed
  const price = shelf[0]!.money;
  const struck = prices.filter((p) => p.struck).map((p) => p.money);
  const omnibus = textOf(/<shared-atoms-omnibus-pricing\b[\s\S]*?<\/shared-atoms-omnibus-pricing>/.exec(tile)?.[0] ?? "");
  const lowest30d = zloty(LOWEST_30D.exec(omnibus)?.[1]);
  const first = zloty(FIRST_PRICE.exec(omnibus)?.[1]);
  const regular = (struck.length === 1 ? struck[0] : undefined) ?? first;
  const conditions: Condition[] = [];
  for (const m of tile.matchAll(/<shared-molecules-sticker\b[\s\S]*?<\/shared-molecules-sticker>/g)) {
    const c = stickerCondition(textOf(m[0]));
    if (c && !conditions.some((x) => x.text === c.text)) conditions.push(c);
  }
  // Only what CCC shows as a promotion: a reduction it announces (the 30-day price "przed obniżką", a struck
  // price) or a discount at the basket or with a code.
  if (!lowest30d && struck.length === 0 && conditions.length === 0) return undefined;
  const name = `${[brand, model].filter(Boolean).join(" ")}, ${label}`.replace(/\s+/g, " ").slice(0, 160);
  return {
    name, price, url, conditions,
    ...(regular && regular.minor > price.minor ? { regularPrice: regular } : {}),
    ...(lowest30d ? { lowest30d } : {}),
  };
}

/** One category page: its promoted products, how many product tiles it had, and its number of pages when the
 * pagination says. Undefined when the page has no product tile at all (an unknown page or changed markup). */
export function parseCccPage(html: string, label: string): { products: DataProduct[]; tiles: number; pages?: number } | undefined {
  const tiles = html.split(/<o-product-box\b/).slice(1).map((t) => t.split("</o-product-box>")[0]!);
  if (tiles.length === 0) return undefined;
  const byUrl = new Map<string, DataProduct>();
  for (const t of tiles) {
    const p = tileProduct(t, label);
    if (p && !byUrl.has(p.url)) byUrl.set(p.url, p);
  }
  const selector = /<m-pagination-page-selector\b[\s\S]*?<\/m-pagination-page-selector>/.exec(html)?.[0] ?? "";
  const total = />\s*z\s*<\/div>\s*<div[^>]*>\s*(\d{1,4})\s*<\/div>/.exec(selector)?.[1];
  const pages = total && Number(total) >= 1 ? Number(total) : undefined;
  return { products: [...byUrl.values()], tiles: tiles.length, ...(pages ? { pages } : {}) };
}

export const ccc: ChainAdapter = {
  chain: "ccc",
  hosts: CCC_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const categories = cccCategories(ctx.queries);
    if (categories.length === 0) return { kind: "no_leaflet" };
    const chosen = categories.slice(0, CCC_MAX_PAGES).map((c) => ({ c, read: 0, pages: 1, first: false }));
    const failures: ChainRead[] = [];
    const byUrl = new Map<string, DataProduct>();
    let blocked = false;
    const readPage = async (s: (typeof chosen)[number], page: number) => {
      // Once CCC has said no, nothing more is asked of it in this request.
      if (blocked || ctx.signal.aborted) { failures.push({ kind: "failed", reason: "not_asked" }); return; }
      const r = await fetchOfficial(ctx, pageUrl(s.c, page), CCC_HOSTS, "text/html");
      if (!r.ok) {
        if (r.read.kind === "blocked") blocked = true;
        failures.push(r.read);
        return;
      }
      const parsed = parseCccPage(r.body.toString("utf8"), s.c.label);
      if (!parsed) { failures.push({ kind: "failed", reason: "no_products" }); return; }
      s.read++;
      if (page === 1) { s.first = true; s.pages = parsed.pages ?? 1; }
      for (const p of parsed.products) if (!byUrl.has(p.url)) byUrl.set(p.url, p);
    };
    // Each category's first page, then the next pages in turn while requests are left.
    await mapLimit(chosen, 2, (s) => readPage(s, 1));
    const more: [(typeof chosen)[number], number][] = [];
    for (let page = 2, left = CCC_MAX_PAGES - chosen.length; left > 0; page++) {
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
    const url = read.length === 1 ? read[0]!.c.url : CCC_SALE;
    return {
      kind: "ok",
      leaflets: [{ leaflet: { title: "Promocje CCC", url }, products, pages: [], strategy: "none" }],
      ...(incomplete ? { incomplete } : {}),
    };
  },
};
