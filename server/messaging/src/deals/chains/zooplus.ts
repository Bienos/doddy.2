// zooplus (observed 2026-10-30), an online-only pet shop that delivers across Poland. www.zooplus.pl's promotions per
// animal ("Promocje dla psa", …) are Next.js pages whose flight data (<script>self.__next_f.push([1, "…"])</script>,
// rows of "id:JSON") carries the listing as the shop's own data, so no page is read by a model:
//   {initialStoreState: {pagination: {current: 1, count: 12} | null, products: [{title, path, variantUrl:
//   "/shop/psy/…/429858?activeVariant=429858.0", isSponsored, petTypes: ["DOGS"], promotionText, variant: {description:
//   "50 g", brands: ["DIBO"], available, whileStockLasts, priceType: "REGULAR" | "SET" | "OFFER", tooltipText,
//   percentageDiscountLabel: "-16.67%", price: {price: {value: "13,96 zł"}, beforePricePrefix, beforePrice, unitPrice:
//   "279,20 zł", unit: "kg"}, articleDiscount: {discountLabel: "-5%"}, abdPrice}}]}}
// and the header's category tree ({path: "/shop/psy/karma_dla_psa_sucha", title: "Karma sucha dla psa", type: "ANIMAL"}).
// Each tile is one variant of a product (its size or flavour in `variant.description`).
// What the tile prints next to the price, and how it is kept (30 Oct):
//   OFFER, "wcześniej" with "Najniższa cena w ciągu 30 dni przed obniżką" (and the footer: "wcześniej" = the lowest price
//     in the last 30 days), the old price struck through: the 30-day lowest price (Omnibus).
//   SET, "pojedynczo" with "Całkowita cena tych samych produktów, gdyby zostały zakupione osobno", not struck: a bundle
//     ("2 x 14 kg", "12,5 kg + 2,5 kg gratis!", "3 + 1 gratis! 4x Felix …") whose price covers everything in it. The
//     price of the same things bought separately is not a regular price: the bundle saving is a condition, in the
//     code's words and without an amount of money. Never a multi-buy mechanic (the price is already the bundle's).
//   "-5% Extra Rabat - Aktywuj": a checkbox the shopper ticks; the price shown is the price before it. It is a condition.
//   "Tylko do wyczerpania zapasów" (`whileStockLasts`): while stocks last.
// Dates: none shown. Every product gets "tylko w sklepie internetowym zooplus.pl", since zooplus has no shops.
// Pages (robots.txt, `User-agent: *`, disallows /specials/, /ov?, /recommendation/, … and allows /shop/):
//   /shop/psy/oferty_specjalne_psy (12 pages of 48 on 30 Oct), /shop/koty/oferty_specjalne_koty (10 pages),
//   /shop/gryzonie/oferty_specjalne_gryzonie (9 products, one page), /shop/ptaki/oferty_specjalne_ptaki (10, one page).
//   The site's menu has no promotions page for fish or horses, so an item about them reads no page.
// Only the FIRST page of each listing is read (48 products, the shop's default "Popularność" order) and at most three
// pages per search; when a listing has more pages, or an animal's page wasn't read, the read says `incomplete`.
// A page decodes to about 2.7 MB (the fetcher's cap is 3 MB). Nothing of the person's words reaches zooplus.
import { decodeEntities, fetchOfficial, isObject, mapLimit, officialUrl, str } from "./common.js";
import { zloty } from "./ccc.js";
import { MAXIZOO_PAGES, type MaxiZooAnimal } from "./maxizoo.js";
import { normalize, parsePrintedUnitPrice, parseSize, unitPrice, unitPricesAgree } from "../match.js";
import type { ChainAdapter, ChainRead, Condition, DataProduct, Money, SizeUnit, UnitPrice } from "../types.js";

export const ZOOPLUS_HOSTS = ["www.zooplus.pl"] as const;
const ORIGIN = "https://www.zooplus.pl";
/** Page requests per search, at most (robots.txt aside). */
export const ZOOPLUS_MAX_PAGES = 3;
/** On every zooplus product: it is bought online and delivered, never in a shop. */
export const ONLINE_ONLY = "tylko w sklepie internetowym zooplus.pl";

const L = "a-ząćęłńóśźż";
/** Whole words only: Polish letters count as letters (JS's \b doesn't know them). */
const words = (alternatives: string) => new RegExp(`(?<![${L}])(?:${alternatives})(?![${L}])`, "i");
/** The same animal words as Maxi Zoo's pages: one Polish vocabulary for dogs, cats and small pets. */
const maxiZooWords = (animal: MaxiZooAnimal): RegExp => MAXIZOO_PAGES.find((p) => p.animal === animal)!.words;

export type ZooplusAnimal = "psy" | "koty" | "gryzonie" | "ptaki";
/** The shop's promotions pages, in the order they are read, with the words (as people say them) that pick each. */
export const ZOOPLUS_PAGES: readonly { animal: ZooplusAnimal; url: string; words: RegExp }[] = [
  { animal: "psy", url: `${ORIGIN}/shop/psy/oferty_specjalne_psy`, words: maxiZooWords("pies") },
  { animal: "koty", url: `${ORIGIN}/shop/koty/oferty_specjalne_koty`, words: maxiZooWords("kot") },
  { animal: "gryzonie", url: `${ORIGIN}/shop/gryzonie/oferty_specjalne_gryzonie`, words: maxiZooWords("male-zwierzeta") },
  { animal: "ptaki", url: `${ORIGIN}/shop/ptaki/oferty_specjalne_ptaki`, words: words(`pta(?:k|si|sz)[${L}]*|papu(?:g|ż)[${L}]*|kanar(?:ek|k[${L}]*)|nierozłącz[${L}]*`) },
];
/** Animals without a promotions page: an item naming only them reads no page, not dog and cat. */
const NO_PAGE = words(`dla ryb[${L}]*|rybk[${L}]*|rybek|akwar[${L}]*|terrar[${L}]*|żółw[${L}]*|gad(?:y|ów|om|ami)|koń|koni(?:a|e|u|em|om|owi|ach)?|końmi|konik[${L}]*`);
const DEFAULT_ANIMALS: readonly ZooplusAnimal[] = ["psy", "koty"];

/** Every promotions page these items want, in reading order: the animals they name; dog and cat for an item naming
 * none. The adapter reads the first ZOOPLUS_MAX_PAGES of them. */
export function animalPages(queries: readonly string[]): string[] {
  const want = new Set<ZooplusAnimal>();
  for (const q of queries.length ? queries : [""]) {
    const text = q.toLowerCase();
    const named = ZOOPLUS_PAGES.filter((p) => p.words.test(text));
    if (named.length) for (const p of named) want.add(p.animal);
    else if (!NO_PAGE.test(text)) for (const a of DEFAULT_ANIMALS) want.add(a);
  }
  return ZOOPLUS_PAGES.filter((p) => want.has(p.animal)).map((p) => p.url);
}

// ---------- the page's own data ----------

/** The rows of a Next.js page's flight data ("id:JSON"), parsed; rows that aren't JSON (text, imports) are skipped. */
export function flightRows(html: string): unknown[] {
  let flight = "";
  // Next escapes "<" inside the pushed strings, so a script ends at the first "])</script>".
  for (const m of html.matchAll(/<script[^>]*>\s*self\.__next_f\.push\((\[[\s\S]*?\])\)\s*;?\s*<\/script>/g)) {
    try {
      const v: unknown = JSON.parse(m[1]!);
      if (Array.isArray(v) && v[0] === 1 && typeof v[1] === "string") flight += v[1];
    } catch { /* not a data push */ }
  }
  const rows: unknown[] = [];
  for (const line of flight.split("\n")) {
    const id = /^[0-9a-z]{1,8}:(?=[[{])/.exec(line);
    if (!id) continue;
    try { rows.push(JSON.parse(line.slice(id[0].length))); } catch { /* a line of a text row */ }
  }
  return rows;
}

interface PageData { store?: Record<string, unknown>; categories: Map<string, string> }

/** The listing's store state and the header's category titles by path, wherever they sit in the rows. */
function pageData(rows: unknown[]): PageData {
  const found: PageData = { categories: new Map() };
  const stack: unknown[] = [...rows];
  while (stack.length) {
    const v = stack.pop();
    if (Array.isArray(v)) { for (const x of v) stack.push(x); continue; }
    if (!isObject(v)) continue;
    const s = v.initialStoreState;
    if (!found.store && isObject(s) && Array.isArray(s.products)) found.store = s;
    if (v.type === "ANIMAL" && typeof v.path === "string" && /^\/shop\/[a-z0-9_/]+$/.test(v.path) && typeof v.title === "string" && v.title.trim()
      && !found.categories.has(v.path)) found.categories.set(v.path, v.title.replace(/\s+/g, " ").trim());
    for (const x of Object.values(v)) if (typeof x === "object" && x !== null) stack.push(x);
  }
  return found;
}

/** A product variant's page on the shop's host: the path under /shop/ and its `activeVariant`, nothing else. */
function productUrl(v: unknown): string | undefined {
  const u = officialUrl(v, ZOOPLUS_HOSTS, ORIGIN);
  if (!u || !/^\/shop\/[a-z0-9_]+\/[a-z0-9_/.-]*[0-9]$/.test(u.pathname) || u.pathname.includes("//")) return undefined;
  const variant = u.searchParams.get("activeVariant");
  return `${ORIGIN}${u.pathname}${variant && /^\d{1,12}(?:\.\d{1,4})?$/.test(variant) ? `?activeVariant=${variant}` : ""}`;
}

/** Text from the shop's data: no tags, entities decoded, spaces collapsed. */
const clean = (s: string) => decodeEntities(s.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
/** A price as the tile prints it ("13,96 zł"); only złoty. */
const shownPrice = (v: unknown): Money | undefined => {
  const s = str(v);
  return s && /z[łl]\s*$/i.test(s) ? zloty(s) : undefined;
};

/** Title, the variant ("50 g", "Adult, jagnięcina i ryż") unless the title already says it, and the brand in front
 * when neither names it ("Gaun" + "Pojnik dla królików 2,0 l"). Not yet cut to length (the size is read from all of it). */
function productName(title: string, variant: string | undefined, brands: unknown): string {
  const t = clean(title);
  const d = variant ? clean(variant) : "";
  const padded = (s: string) => ` ${normalize(s)} `;
  let name = d && !padded(t).includes(padded(d)) ? `${t}, ${d}` : t;
  const brand = Array.isArray(brands) ? brands.map((b) => (typeof b === "string" ? clean(b) : "")).find(Boolean) : undefined;
  const first = brand ? normalize(brand).split(" ")[0] : undefined;
  if (brand && first && !padded(name).includes(` ${first} `)) name = `${brand} ${name}`;
  return name;
}

/** At most 160 characters, cut between words. */
function shortName(name: string): string {
  if (name.length <= 160) return name;
  const cut = name.slice(0, 160);
  const space = cut.lastIndexOf(" ");
  return (space > 100 ? cut.slice(0, space) : cut).replace(/[\s,(–-]+$/, "");
}

// A size not after a digit, a separator, a dash or a comparison, optionally a multipack ("24 x 85 g").
const SIZE = new RegExp(String.raw`(?<![\d.,\-–/<>+])(?:\d{1,3}\s*[x×]\s*)?\d+(?:[.,]\d+)?\s*(?:kg|g|ml|l|szt\.?|sztuk[ia]?)(?![${L}])`, "gi");
// zooplus writes four boxes of 24 tins as "4 x (24 x 85 g)": 96 x 85 g.
const NESTED = /(?<![\d.,])(\d{1,2})\s*[x×]\s*\(\s*(\d{1,3})\s*[x×]\s*(\d+(?:[.,]\d+)?\s*(?:kg|g|ml|l))\s*\)/gi;

/** Every pack size written in a name, in order ("4 x (24 x 85 g)" read as "96 x 85 g"). */
export function sizesIn(name: string): string[] {
  const flat = name.replace(NESTED, (_all, a: string, b: string, each: string) => `${Number(a) * Number(b)} x ${each}`);
  return [...flat.matchAll(SIZE)].map((m) => m[0].replace(/\s+/g, " ").trim()).filter((s) => !!parseSize(s));
}

const BASE: Record<SizeUnit, UnitPrice["per"]> = { g: "kg", kg: "kg", ml: "l", l: "l", szt: "szt" };
/** The unit the shop prices the product by ("kg", "l", "szt."), as a unit price's base. */
const declaredBase = (unit: string | undefined): UnitPrice["per"] | undefined =>
  !unit ? undefined : /^k?g$/i.test(unit) ? "kg" : /^m?l$/i.test(unit) ? "l" : /^szt/i.test(unit) ? "szt" : undefined;

/** "96 x 85 g Megapakiet + … 48 x 45 g gratis!": every size in the name added up ("10,32 kg"), when they weigh (or
 * hold) the same kind of thing. Used only when the shop's own unit price says the price covers all of them. */
function totalOf(sizes: readonly string[]): string | undefined {
  const parsed = sizes.map((s) => parseSize(s));
  const first = parsed[0];
  if (parsed.length < 2 || !first || BASE[first.unit] === "szt" || parsed.some((s) => !s || BASE[s.unit] !== BASE[first.unit])) return undefined;
  const small = parsed.reduce((sum, s) => sum + (s!.unit === "kg" || s!.unit === "l" ? s!.value * 1000 : s!.value), 0);
  const big = BASE[first.unit] === "kg" ? "kg" : "l";
  return small >= 1000 ? `${String(Math.round(small) / 1000).replace(".", ",")} ${big}` : `${Math.round(small)} ${big === "kg" ? "g" : "ml"}`;
}

/**
 * The pack size, and the shop's unit price when the size is known and in the same unit. Of the sizes in the name the
 * last one whose price per unit agrees with the shop's unit price is taken ("12,5 kg + 2,5 kg gratis! … 15 kg"), then
 * all of them added up when that agrees, then the last one in the unit the shop prices by ("1 szt. (67 g)" sold per
 * piece), then the last one. When nothing agrees the shop's unit price still goes with the size, so the offer is
 * marked for checking rather than given a wrong unit price quietly.
 */
export function sizeAndUnit(name: string, price: Money, unitPriceText?: string, unitName?: string): { sizeText?: string; printedUnitPrice?: string } {
  const sizes = sizesIn(name);
  const printed = unitPriceText && unitName ? `${unitPriceText}/${unitName}` : undefined;
  const unit = parsePrintedUnitPrice(printed);
  const declared = unit?.per ?? declaredBase(unitName);
  const agrees = (s: string | undefined) => {
    const computed = s ? unitPrice(price, parseSize(s)) : undefined;
    return !!unit && !!computed && unitPricesAgree(computed, unit);
  };
  const lastFirst = [...sizes].reverse();
  const total = totalOf(sizes);
  const sizeText = lastFirst.find(agrees) ?? (agrees(total) ? total : undefined)
    ?? lastFirst.find((s) => { const z = parseSize(s); return !!z && BASE[z.unit] === declared; }) ?? lastFirst[0];
  if (!sizeText) return {};
  const size = parseSize(sizeText);
  return { sizeText, ...(printed && unit && size && BASE[size.unit] === unit.per ? { printedUnitPrice: printed } : {}) };
}

/** "-16.67%" → 16 (down, so a saving is never overstated); undefined below 1%. */
function percentOf(label: unknown): number | undefined {
  const m = typeof label === "string" ? /(\d{1,2})(?:[.,]\d+)?\s*%/.exec(label) : null;
  const n = m ? Number(m[1]) : 0;
  return n >= 1 && n <= 99 ? n : undefined;
}

/** A bundle's saving against buying the same things separately, in the code's words, without an amount of money. */
export function bundleCondition(percentLabel: unknown): Condition {
  const p = percentOf(percentLabel);
  return { kind: "other", text: p ? `pakiet o ${p}% taniej niż osobno` : "pakiet taniej niż osobno" };
}

/** The "Extra Rabat" a shopper activates on the product, in the code's words. */
export function extraDiscountCondition(label: unknown): Condition | undefined {
  const p = percentOf(label);
  return p ? { kind: "other", text: `dodatkowe −${p}% (Extra Rabat) po aktywacji w sklepie` } : undefined;
}

const ANIMAL_WORDS: Record<string, string> = { DOGS: "dla psa", CATS: "dla kota", RODENTS: "dla gryzoni", BIRDS: "dla ptaków" };
const PAGE_ANIMAL_WORDS: Record<ZooplusAnimal, string> = { psy: "dla psa", koty: "dla kota", gryzonie: "dla gryzoni", ptaki: "dla ptaków" };

/** Words the matcher reads with a product's name (ADR-667), never shown: the shop's own category titles along the
 * product's path ("Karma sucha dla psa", "Josera"), the category's address words ("gryzaki dla psa") and the animals
 * the shop says it is for, or the page's animal. Names often leave the kind out ("Dibo, skóra łososia – 50 g"). */
function matchText(path: string, petTypes: unknown, categories: ReadonlyMap<string, string>, animal: ZooplusAnimal | undefined): string | undefined {
  const titles = [...categories].filter(([p]) => path.startsWith(`${p}/`)).sort((a, b) => a[0].length - b[0].length).map(([, t]) => t);
  const slug = path.split("/")[3];
  const animals = Array.isArray(petTypes) ? petTypes.map((t) => (typeof t === "string" ? ANIMAL_WORDS[t] : undefined)).filter((w): w is string => !!w) : [];
  const parts = [...titles, ...(slug ? [slug.replace(/_/g, " ")] : []), ...(animals.length ? animals : animal ? [PAGE_ANIMAL_WORDS[animal]] : [])];
  const text = [...new Set(parts)].join(" ").slice(0, 200).trim();
  return text || undefined;
}

/** One tile as a data product, or undefined (sponsored, sold out, free, no price in złoty or no product page). */
function tileProduct(raw: unknown, categories: ReadonlyMap<string, string>, animal: ZooplusAnimal | undefined): DataProduct | undefined {
  if (!isObject(raw) || raw.isSponsored === true) return undefined;
  const v = isObject(raw.variant) ? raw.variant : undefined;
  const pricing = v && isObject(v.price) ? v.price : undefined;
  if (!v || !pricing || v.available === false) return undefined;
  const price = shownPrice(isObject(pricing.price) ? pricing.price.value : undefined);
  const url = productUrl(raw.variantUrl) ?? productUrl(raw.path);
  const title = str(raw.title);
  if (!price || !url || !title) return undefined;
  const fullName = productName(title, str(v.description), v.brands);
  const size = sizeAndUnit(fullName, price, str(pricing.unitPrice), str(pricing.unit));
  const name = shortName(fullName);

  const conditions: Condition[] = [{ kind: "other", text: ONLINE_ONLY }];
  const before = shownPrice(pricing.beforePrice);
  const prefix = str(pricing.beforePricePrefix)?.toLowerCase() ?? "";
  const tooltip = str(v.tooltipText) ?? "";
  let lowest30d: Money | undefined;
  let regularPrice: Money | undefined;
  if (before) {
    if (/^wcze[sś]niej$/.test(prefix) || /30\s*dni/i.test(tooltip)) lowest30d = before;
    else if (/^pojedynczo$/.test(prefix) || /osobno/i.test(tooltip)) { if (before.minor > price.minor) conditions.push(bundleCondition(v.percentageDiscountLabel)); }
    // Struck through without a label the code knows: a regular price, never the 30-day lowest.
    else if (before.minor > price.minor) regularPrice = before;
  }
  const extra = isObject(v.articleDiscount) && v.articleDiscount.isEnabled !== false ? extraDiscountCondition(v.articleDiscount.discountLabel) : undefined;
  if (extra) conditions.push(extra);
  if (v.whileStockLasts === true) conditions.push({ kind: "stock" });
  const path = new URL(url).pathname;
  const words = matchText(path, raw.petTypes, categories, animal);
  return {
    name, price, url, conditions, ...size,
    ...(regularPrice ? { regularPrice } : {}),
    ...(lowest30d ? { lowest30d } : {}),
    ...(words ? { matchText: words } : {}),
  };
}

export interface ZooplusListing { products: DataProduct[]; totalPages: number }

/** The products on one promotions page and how many pages its listing has, or undefined without the shop's data. */
export function parseZooplusPage(html: string, animal?: ZooplusAnimal): ZooplusListing | undefined {
  const { store, categories } = pageData(flightRows(html));
  if (!store || !Array.isArray(store.products)) return undefined;
  const count = isObject(store.pagination) ? store.pagination.count : undefined;
  const byUrl = new Map<string, DataProduct>();
  for (const raw of store.products) {
    const p = tileProduct(raw, categories, animal);
    if (p && !byUrl.has(p.url)) byUrl.set(p.url, p);
  }
  return { products: [...byUrl.values()], totalPages: typeof count === "number" && Number.isInteger(count) && count > 0 ? count : 1 };
}

type PageRead = { url: string; listing: ZooplusListing };

export const zooplus: ChainAdapter = {
  chain: "zooplus",
  hosts: ZOOPLUS_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const wanted = animalPages(ctx.queries);
    if (wanted.length === 0) return { kind: "no_leaflet" };
    const urls = wanted.slice(0, ZOOPLUS_MAX_PAGES);
    let blocked = false;
    const results = await mapLimit(urls, 2, async (url): Promise<PageRead | ChainRead> => {
      // Once the shop has said no, nothing more is asked of it in this request.
      if (blocked || ctx.signal.aborted) return { kind: "failed", reason: "not_asked" };
      const r = await fetchOfficial(ctx, url, ZOOPLUS_HOSTS, "text/html");
      if (!r.ok) {
        if (r.read.kind === "blocked") blocked = true;
        return r.read;
      }
      const listing = parseZooplusPage(r.body.toString("utf8"), ZOOPLUS_PAGES.find((p) => p.url === url)?.animal);
      return listing ? { url, listing } : { kind: "failed", reason: "no_payload" };
    });
    const read = results.filter((x): x is PageRead => "listing" in x);
    const failures = results.filter((x): x is ChainRead => !("listing" in x));
    // A product on two animals' pages (wipes for dogs and cats) is one product.
    const byUrl = new Map<string, DataProduct>();
    for (const p of read) for (const product of p.listing.products) if (!byUrl.has(product.url)) byUrl.set(product.url, product);
    if (byUrl.size === 0) return failures.find((f) => f.kind === "blocked") ?? failures[0] ?? { kind: "no_leaflet" };
    const incomplete = [
      ...(read.some((p) => p.listing.totalPages > 1) ? ["first_page_only"] : []),
      ...(failures.length ? ["some_pages_failed"] : []),
      ...(wanted.length > urls.length ? ["page_cap"] : []),
    ];
    return {
      kind: "ok",
      leaflets: [{ leaflet: { title: "Promocje zooplus", url: read[0]!.url }, products: [...byUrl.values()], pages: [], strategy: "none" }],
      ...(incomplete.length ? { incomplete: incomplete.join(",") } : {}),
    };
  },
};
