// Maxi Zoo (observed 2026-10-30), a pet shop: www.maxizoo.pl's promotions per animal are Nuxt pages whose payload
// (<script id="__NUXT_DATA__">, devalue's flat JSON, rebuilt with Dino's `unflatten`) carries the listing as the
// shop's own data, so no page is read by a model:
//   pinia.main.productListingData.productList = {pagination: {currentPage, pageSize: 48, totalPages, totalResults},
//   products: [{tileType: "ProductTile", sponsored, brandName, name, url: "/p/…-{code}/", badges: [{type, name}],
//   pricing: {current: {value, currencyIso}, former: {value}, savingsRelative, perUnit?: {formattedValue: "24,12 zł/kg"}},
//   analytics?: {ean}, stock}]}
// The tile shows "Oszczędność 30%", the price, the unit price and the former price struck through, with no words
// saying what the former price is: it is kept as the regular price, never as the 30-day lowest (Omnibus).
// On 30 Oct no product carried dates, or an app, card ("Friends") or multi-buy mechanic: every price was
// priceType "BUY" and the badges were "Specjalna oferta", "Wyłącznie" and "Opakowania zbiorcze". A badge that names
// a mechanic is read as a condition. The pack size is only in the name ("… 12 kg", "24 x 85 g"); the last one there
// is kept ("Adult Maxi >25 kg z drobiem i warzywami 12 kg": the first is the dog's weight).
// Pages (robots.txt, `User-agent: *`, allows /c/ and disallows */search, *sort=*, /*?q=%3AtopSeller, …):
//   /c/pies/promocje/ (304 products in 7 pages), /c/kot/promocje/ (61 in 2), /c/male-zwierzeta/promocje/ (11 in 1).
//   /c/ptaki/promocje/ and /c/akwarystyka/promocje/ answered 404 ("Strona nie została znaleziona"), so an item about
//   birds or fish has no page to read. The site also links small pets' offers as /promocje-oferty/oferty/?q=%3AtopSeller…,
//   which robots.txt disallows; /c/male-zwierzeta/promocje/ is the shop's own page for them and is allowed.
// Only the FIRST page of each listing is read: 48 products, the biggest discounts first (the shop's default order).
// When a listing has more pages the read says `incomplete`, so finding nothing there is never "no match".
// The animal pages read are picked by what the items name (dog and cat for an item naming no animal), at most four.
import { decodeEntities, fetchOfficial, isObject, mapLimit, moneyOf, officialUrl, str, validEan } from "./common.js";
import { unflatten } from "./dino.js";
import { parsePrintedUnitPrice, parseSize } from "../match.js";
import type { ChainAdapter, ChainRead, Condition, DataProduct, SizeUnit, UnitPrice } from "../types.js";

export const MAXIZOO_HOSTS = ["www.maxizoo.pl"] as const;
const ORIGIN = "https://www.maxizoo.pl";
/** Page requests per search, at most. */
export const MAXIZOO_MAX_PAGES = 4;

const L = "a-ząćęłńóśźż";
/** Whole words only: Polish letters count as letters (JS's \b doesn't know them). */
const words = (alternatives: string) => new RegExp(`(?<![${L}])(?:${alternatives})(?![${L}])`, "i");

export type MaxiZooAnimal = "pies" | "kot" | "male-zwierzeta";
/** The shop's promotions pages, in the order they are read, with the words (as people say them) that pick each. */
export const MAXIZOO_PAGES: readonly { animal: MaxiZooAnimal; url: string; words: RegExp }[] = [
  {
    animal: "pies", url: `${ORIGIN}/c/pies/promocje/`,
    words: words(`pies(?:ek|ka|ki|kiem|ków)?|ps(?:a|u|em|ie|y|ów|om|ami|ach)|psi(?:a|ą|ej|ego|ch|m|mi)?|psiak[${L}]*|szczeni[${L}]*`),
  },
  { animal: "kot", url: `${ORIGIN}/c/kot/promocje/`, words: words(`kot(?:a|u|em|y|ów|om|ami|ach|ek|ka|ki|ków|kiem)?|koci[${L}]*|kocur[${L}]*`) },
  {
    animal: "male-zwierzeta", url: `${ORIGIN}/c/male-zwierzeta/promocje/`,
    words: words(`gryzo[nń][${L}]*|króli(?:k|cz)[${L}]*|chomi(?:k|cz)[${L}]*|świn(?:k[${L}]*|ek)|szynszyl[${L}]*|fret(?:k[${L}]*|ek)|koszatnicz[${L}]*|myszoskocz[${L}]*|szczur[${L}]*|mał(?:e|ych|ym|ymi) zwierz[${L}]*`),
  },
];
/** Animals without a promotions page (404 on 30 Oct): an item naming only them reads no page, not dog and cat. */
const NO_PAGE = words(`pta(?:k|si|sz)[${L}]*|papu(?:g|ż)[${L}]*|kanar(?:ek|k[${L}]*)|nierozłącz[${L}]*|dla ryb[${L}]*|rybk[${L}]*|rybek|akwar[${L}]*`);
const DEFAULT_ANIMALS: readonly MaxiZooAnimal[] = ["pies", "kot"];

/** The promotions pages to read for these items: the animals they name; dog and cat for an item naming none. */
export function animalPages(queries: readonly string[]): string[] {
  const want = new Set<MaxiZooAnimal>();
  for (const q of queries.length ? queries : [""]) {
    const text = q.toLowerCase();
    const named = MAXIZOO_PAGES.filter((p) => p.words.test(text));
    if (named.length) for (const p of named) want.add(p.animal);
    else if (!NO_PAGE.test(text)) for (const a of DEFAULT_ANIMALS) want.add(a);
  }
  return MAXIZOO_PAGES.filter((p) => want.has(p.animal)).map((p) => p.url).slice(0, MAXIZOO_MAX_PAGES);
}

// A size not after a digit, a separator, a dash or a comparison (">25 kg" is the dog's weight), optionally a multipack.
const SIZE = new RegExp(String.raw`(?<![\d.,\-–/<>+])(?:\d{1,3}\s*[x×]\s*)?\d+(?:[.,]\d+)?\s*(?:kg|g|ml|l|szt\.?|sztuk[ia]?)(?![${L}])`, "gi");

/** The pack size in a Maxi Zoo name: the last size written there ("Szczenię 12 x 200 g … 12x200 g" → "12x200 g"). */
export function packSize(name: string): string | undefined {
  const all = [...name.matchAll(SIZE)];
  const last = all[all.length - 1]?.[0].replace(/\s+/g, " ").trim();
  return last && parseSize(last) ? last : undefined;
}

const BASE: Record<SizeUnit, UnitPrice["per"]> = { g: "kg", kg: "kg", ml: "l", l: "l", szt: "szt" };
/** The shop's unit price is a cross-check only when it is per the size's own unit ("2x4 szt" priced per kg isn't). */
function sameBase(sizeText: string, printed: string): boolean {
  const size = parseSize(sizeText);
  const unit = parsePrintedUnitPrice(printed);
  return !!size && !!unit && BASE[size.unit] === unit.per;
}

/** A product page on the shop's host ("/p/…/"), without query or fragment. */
function productUrl(v: unknown): string | undefined {
  const u = officialUrl(v, MAXIZOO_HOSTS, ORIGIN);
  return u && u.pathname.startsWith("/p/") && !u.pathname.includes("//") ? `${u.origin}${u.pathname}` : undefined;
}

const fold = (s: string) => s.toLowerCase().replace(/[’`]/g, "'");
/** "Brand name", unless the name already starts with the brand ("Butcher's" + "Butcher’s Kitten …"). */
function withBrand(brand: string | undefined, name: string): string {
  if (!brand) return name;
  const b = fold(brand);
  const n = fold(name);
  return n === b || n.startsWith(`${b} `) ? name : `${brand} ${name}`;
}

/** Mechanics a badge names: "2+1", "przy zakupie 2 szt.", the app, the Friends card. */
export function badgeConditions(badges: unknown): Condition[] {
  const out = new Map<string, Condition>();
  for (const b of Array.isArray(badges) ? badges : []) {
    if (!isObject(b)) continue;
    const text = [str(b.name), str(b.type)].filter(Boolean).join(" ");
    const multi = /(?<!\d)(\d)\s*\+\s*(\d)(?!\d)/.exec(text);
    if (multi) out.set("multi_buy", { kind: "multi_buy", text: `${multi[1]}+${multi[2]}` });
    const qty = /przy\s+zakupie\s+(\d{1,2})|od\s+(\d{1,2})\s*szt/i.exec(text);
    const n = qty ? Number(qty[1] ?? qty[2]) : 0;
    if (n >= 2) out.set("min_quantity", { kind: "min_quantity", quantity: n });
    if (/aplikac/i.test(text)) out.set("app", { kind: "app" });
    if (/friends|\bkart[aąęy]\b/i.test(text)) out.set("card", { kind: "card" });
  }
  return [...out.values()];
}

const pln = (v: Record<string, unknown>) => v.currencyIso === undefined || v.currencyIso === "PLN";

/** One product tile as a data product, or undefined (a teaser, a sponsored tile, no price or no product page). */
/** Words the matcher reads with a product's name (ADR-667): the shop's own category path ("Pies › Karma dla psów ›
 * Karma sucha") and the page's animal, because the shop's names leave the kind out ("Farmina N&D Adult 12 kg"). */
const ANIMAL_WORDS: Record<MaxiZooAnimal, string> = { pies: "dla psa", kot: "dla kota", "male-zwierzeta": "dla gryzoni" };

function matchText(raw: Record<string, unknown>, animal: MaxiZooAnimal | undefined): string | undefined {
  const names = isObject(raw.analytics) && Array.isArray(raw.analytics.categoryNames)
    ? raw.analytics.categoryNames.filter((c): c is string => typeof c === "string").map((c) => c.trim()).filter(Boolean)
    : [];
  const text = [...names, ...(animal ? [ANIMAL_WORDS[animal]] : [])].join(" ").slice(0, 200);
  return text || undefined;
}

function tileProduct(raw: unknown, animal?: MaxiZooAnimal): DataProduct | undefined {
  if (!isObject(raw) || raw.tileType !== "ProductTile" || raw.sponsored === true) return undefined;
  const pricing = isObject(raw.pricing) ? raw.pricing : undefined;
  const current = pricing && isObject(pricing.current) && pln(pricing.current) ? pricing.current : undefined;
  const price = current ? moneyOf(current.value) : undefined;
  const url = productUrl(raw.url);
  const title = str(raw.name);
  if (!pricing || !price || !url || !title) return undefined;
  const name = decodeEntities(withBrand(str(raw.brandName), title)).replace(/\s+/g, " ").trim().slice(0, 160);
  const former = isObject(pricing.former) && pln(pricing.former) ? moneyOf(pricing.former.value) : undefined;
  const size = packSize(name);
  const perUnit = isObject(pricing.perUnit) ? str(pricing.perUnit.formattedValue) : undefined;
  const ean = isObject(raw.analytics) ? validEan(raw.analytics.ean) : undefined;
  return {
    name, price, url, conditions: badgeConditions(raw.badges),
    ...(size ? { sizeText: size } : {}),
    ...(size && perUnit && sameBase(size, perUnit) ? { printedUnitPrice: perUnit } : {}),
    // Struck through without a label: a regular price, not the 30-day lowest.
    ...(former && former.minor > price.minor ? { regularPrice: former } : {}),
    ...(ean ? { ean } : {}),
    ...(() => { const t = matchText(raw, animal); return t ? { matchText: t } : {}; })(),
  };
}

export interface MaxiZooListing { products: DataProduct[]; totalPages: number }

/** The products on one promotions page and how many pages its listing has, or undefined without the payload. */
export function parseMaxiZooPage(html: string, animal?: MaxiZooAnimal): MaxiZooListing | undefined {
  const m = /<script[^>]*\bid="__NUXT_DATA__"[^>]*>([\s\S]*?)<\/script>/i.exec(html);
  if (!m) return undefined;
  let flat: unknown;
  try { flat = JSON.parse(m[1]!); } catch { return undefined; }
  const root = unflatten(flat);
  const main = isObject(root) && isObject(root.pinia) && isObject(root.pinia.main) ? root.pinia.main : undefined;
  const data = main && isObject(main.productListingData) ? main.productListingData : undefined;
  const list = data && isObject(data.productList) ? data.productList : undefined;
  if (!list || !Array.isArray(list.products)) return undefined;
  const pages = isObject(list.pagination) ? list.pagination.totalPages : undefined;
  return {
    products: list.products.map((raw) => tileProduct(raw, animal)).filter((p): p is DataProduct => !!p),
    totalPages: typeof pages === "number" && Number.isInteger(pages) && pages > 0 ? pages : 1,
  };
}

type PageRead = { url: string; listing: MaxiZooListing };

export const maxizoo: ChainAdapter = {
  chain: "maxizoo",
  hosts: MAXIZOO_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const urls = animalPages(ctx.queries);
    if (urls.length === 0) return { kind: "no_leaflet" };
    let blocked = false;
    const results = await mapLimit(urls, 2, async (url): Promise<PageRead | ChainRead> => {
      // Once the shop has said no, nothing more is asked of it in this request.
      if (blocked || ctx.signal.aborted) return { kind: "failed", reason: "not_asked" };
      const r = await fetchOfficial(ctx, url, MAXIZOO_HOSTS, "text/html");
      if (!r.ok) {
        if (r.read.kind === "blocked") blocked = true;
        return r.read;
      }
      const listing = parseMaxiZooPage(r.body.toString("utf8"), MAXIZOO_PAGES.find((p) => p.url === url)?.animal);
      return listing ? { url, listing } : { kind: "failed", reason: "no_payload" };
    });
    const read = results.filter((x): x is PageRead => "listing" in x);
    const failures = results.filter((x): x is ChainRead => !("listing" in x));
    // A product on two animals' pages (a fountain for dogs and cats) is one product.
    const byUrl = new Map<string, DataProduct>();
    for (const p of read) for (const product of p.listing.products) if (!byUrl.has(product.url)) byUrl.set(product.url, product);
    if (byUrl.size === 0) return failures.find((f) => f.kind === "blocked") ?? failures[0] ?? { kind: "no_leaflet" };
    const incomplete = [
      ...(read.some((p) => p.listing.totalPages > 1) ? ["first_page_only"] : []),
      ...(failures.length ? ["some_pages_failed"] : []),
    ];
    return {
      kind: "ok",
      leaflets: [{ leaflet: { title: "Promocje Maxi Zoo", url: read[0]!.url }, products: [...byUrl.values()], pages: [], strategy: "none" }],
      ...(incomplete.length ? { incomplete: incomplete.join(",") } : {}),
    };
  },
};
