// Action (observed 2026-10-30), a non-food discounter that also sells sweets, snacks and household goods (about 190+
// shops in Poland): www.action.com/pl-pl/promocja-tygodnia/ is a Next.js page whose React Server Components payload
// (<script>self.__next_f.push([1, "…"])</script> chunks; joined, one row per line, "id:json") carries the week's
// products as the shop's own data, so no page is read by a model:
//   {product: {id, title, description: "8 sztuk | 320 gramów", brand, href: "https://www.action.com/pl-pl/p/{id}/{slug}/",
//   isDeal, price: {currencyCode: "PLN", current: {amount}, original: {amount}, unitInfo: {formatted: "10,59 zł/kg"},
//   discount: {percentage: "-15%", footnote: "Najniższa cena z 30 dni przed obniżką"}, anchoredPrice, priceRange},
//   stickers: [{code: "IS_DEAL", value: "Promocja tygodnia", valueAddition, subValue: "28.10 – 03.11"}, …]}}
// and the listing's {pagination: {currentPage, numberOfPages, numberOfItems, limitPerPage}}.
// On 30 Oct: 169 products in 8 pages of 23 (the first page, then ?page=2 … ?page=8). Every one had isDeal, an IS_DEAL
// sticker dated "28.10 – 03.11" and an original price footnoted "Najniższa cena z 30 dni przed obniżką", so the
// original price is the 30-day lowest (Omnibus); without that footnote it would be kept as the regular price. No
// product carried a multi-buy, app or card mechanic, an anchoredPrice, a priceRange, a category, an EAN, or alcohol.
// The pack size is in the description, among sizes in clothes or centimetres ("Rozmiar M | 2 sztuki"); the part whose
// size agrees with the shop's unit price is kept. A "zł/szt." equal to the price is per article, not per piece.
// robots.txt (User-agent: *, 30 Oct) allows /pl-pl/promocja-tygodnia/ and its ?page=N; it disallows filters, sorts,
// search and the product pages' ?page=. Product pages are only linked, never fetched.
// Every page is read (at most ACTION_MAX_PAGES), the first alone (it says how many there are), the rest two at a time.
// The pages come from the shop's cache at different ages, so a read can see one product twice and another never (seen
// live on 30 Oct: 168 of 169); fewer distinct products than the listing's count makes the read `incomplete`.
// Alcohol is skipped.
import { currentWeek, dayMonth, fetchOfficial, isObject, mapLimit, moneyOf, officialUrl, str } from "./common.js";
import { parsePrintedUnitPrice, parseSize, unitPrice, unitPricesAgree } from "../match.js";
import type { ChainAdapter, ChainRead, Condition, DataProduct, LeafletInfo, Money, Size, SizeUnit, UnitPrice } from "../types.js";

export const ACTION_HOSTS = ["www.action.com"] as const;
const ORIGIN = "https://www.action.com";
export const ACTION_PROMO = `${ORIGIN}/pl-pl/promocja-tygodnia/`;
/** Page requests per search, at most (8 on 30 Oct). */
export const ACTION_MAX_PAGES = 8;

export const actionPageUrl = (n: number): string => (n <= 1 ? ACTION_PROMO : `${ACTION_PROMO}?page=${n}`);

const L = "a-ząćęłńóśźż";
// Drinks, as whole words; not glasses or openers for them ("Kieliszki do wina").
const ALCOHOL = new RegExp(
  `(?<![${L}])(?<!do\\s)(?:piw[aoe]?|win[ao]|w[oó]dk[${L}]*|whisk(?:y|ey)|likier[${L}]*|gin|rum|szampan[${L}]*|prosecco|nalewk[${L}]*|alkoholow[${L}]*)(?![${L}])`,
  "i",
);

// ---------- the page's payload ----------

/** The JSON rows of a Next.js page's server components payload (rows that aren't JSON are left out). */
export function flightRows(html: string): unknown[] {
  let text = "";
  for (const m of html.matchAll(/<script[^>]*>\s*self\.__next_f\.push\((\[[\s\S]*?\])\)\s*;?\s*<\/script>/g)) {
    let chunk: unknown;
    try { chunk = JSON.parse(m[1]!); } catch { continue; }
    if (Array.isArray(chunk) && chunk[0] === 1 && typeof chunk[1] === "string") text += chunk[1];
  }
  const rows: unknown[] = [];
  for (const line of text.split("\n")) {
    const m = /^[0-9a-f]{1,8}:([[{][\s\S]*)$/.exec(line);
    if (!m) continue;
    try { rows.push(JSON.parse(m[1]!)); } catch { /* not a JSON row */ }
  }
  return rows;
}

/** Every product object in the rows, in the page's order, and the listing's pagination. */
function collect(rows: unknown[]): { tiles: Record<string, unknown>[]; pagination?: Record<string, unknown> } {
  const tiles: Record<string, unknown>[] = [];
  let pagination: Record<string, unknown> | undefined;
  const stack: unknown[] = [...rows].reverse();
  const push = (xs: unknown[]) => { for (let i = xs.length - 1; i >= 0; i--) if (typeof xs[i] === "object" && xs[i] !== null) stack.push(xs[i]); };
  while (stack.length) {
    const v = stack.pop();
    if (Array.isArray(v)) { push(v); continue; }
    if (!isObject(v)) continue;
    if (isObject(v.product) && isObject(v.product.price)) { tiles.push(v.product); continue; }
    if (!pagination && typeof v.numberOfPages === "number" && typeof v.currentPage === "number") pagination = v;
    push(Object.values(v));
  }
  return { tiles, pagination };
}

// ---------- one product ----------

/** A product page on the shop's host ("/pl-pl/p/…/"), without query or fragment. */
function productUrl(v: unknown): string | undefined {
  const u = officialUrl(v, ACTION_HOSTS, ORIGIN);
  return u && u.pathname.startsWith("/pl-pl/p/") && !u.pathname.includes("//") ? `${u.origin}${u.pathname}` : undefined;
}

const fold = (s: string) => s.toLowerCase().replace(/[’`]/g, "'");
/** The title, with the brand after it (as Action writes it: "Bokserki Ziki") when the title leaves it out. */
function withBrand(brand: string | undefined, title: string): string {
  return brand && !fold(title).includes(fold(brand)) ? `${title} ${brand}` : title;
}

/** The deal's dates from its IS_DEAL sticker ("28.10 – 03.11"), each in the year nearest today. */
export function dealDates(stickers: unknown, today: string): { validFrom?: string; validTo?: string } {
  const deal = (Array.isArray(stickers) ? stickers : []).find((s) => isObject(s) && s.code === "IS_DEAL");
  const text = isObject(deal) ? str(deal.subValue) : undefined;
  const m = text ? /(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?\s*[–—-]\s*(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?/.exec(text) : null;
  if (!m) return {};
  const from = dayMonth(Number(m[1]), Number(m[2]), today, m[3] ? Number(m[3]) : undefined);
  const to = dayMonth(Number(m[4]), Number(m[5]), today, m[6] ? Number(m[6]) : undefined);
  if (!from || !to || to < from) return {};
  return { validFrom: from, validTo: to };
}

// Polish unit words the size parser doesn't read: "320 gramów", "1 kilogram", "500 mililitrów", "1 litr".
const UNIT_WORDS: [RegExp, string][] = [
  [new RegExp(`(\\d)\\s*kilogram(?:y|ów|a)?(?![${L}])`, "gi"), "$1 kg"],
  [new RegExp(`(\\d)\\s*gram(?:y|ów|a)?(?![${L}])`, "gi"), "$1 g"],
  [new RegExp(`(\\d)\\s*mililitr(?:y|ów|a)?(?![${L}])`, "gi"), "$1 ml"],
  [new RegExp(`(\\d)\\s*litr(?:y|ów|a)?(?![${L}])`, "gi"), "$1 l"],
];
const BASE: Record<SizeUnit, UnitPrice["per"]> = { g: "kg", kg: "kg", ml: "l", l: "l", szt: "szt" };

/**
 * The pack size from the description's parts ("21 sztuk | 500 g"), and the shop's unit price when it can cross-check
 * it: the part whose size agrees with the unit price; else a weight or volume; else a count. The unit price is kept
 * only per the size's own unit, and not when it is "zł/szt." equal to the price for a pack of several (that is the
 * price per article: "10 sztuk | 24,99 zł/szt." for a 24,99 zł set of ten pens).
 */
export function sizeAndUnit(description: string | undefined, price: Money, unitText: string | undefined): { sizeText?: string; printedUnitPrice?: string } {
  const parts = (description ?? "").split("|")
    .map((p) => UNIT_WORDS.reduce((t, [re, to]) => t.replace(re, to), p.replace(/\s+/g, " ").trim()))
    .filter((p) => p && p.length <= 40);
  const sized = parts.map((text) => ({ text, size: parseSize(text) })).filter((c): c is { text: string; size: Size } => !!c.size);
  const printed = parsePrintedUnitPrice(unitText);
  const agrees = printed ? sized.find((c) => { const u = unitPrice(price, c.size); return !!u && unitPricesAgree(u, printed); }) : undefined;
  const chosen = agrees ?? sized.find((c) => c.size.unit !== "szt") ?? sized[0];
  if (!chosen) return {};
  const perArticle = printed?.per === "szt" && printed.minor === price.minor && chosen.size.value > 1;
  const keepUnit = !!printed && !!unitText && BASE[chosen.size.unit] === printed.per && (!!agrees || !perArticle);
  return { sizeText: chosen.text, ...(keepUnit ? { printedUnitPrice: unitText!.trim().slice(0, 40) } : {}) };
}

const PLAIN_CUT = /^[-−–]?\s*\d{1,2}\s*%$/;

/** Mechanics in the discount or the stickers: "1+1", "przy zakupie 2 szt.", the app, while stocks last, some shops.
 * A discount that isn't a plain "-25%" and names none of these is kept in the shop's words. */
export function actionConditions(discount: string | undefined, stickers: unknown): Condition[] {
  const texts = (Array.isArray(stickers) ? stickers : []).filter(isObject)
    .flatMap((s) => [str(s.value), str(s.valueAddition), s.code === "IS_DEAL" ? undefined : str(s.subValue)])
    .filter((t): t is string => !!t);
  const mechanic = discount && !PLAIN_CUT.test(discount) ? discount : undefined;
  const out = new Map<string, Condition>();
  for (const text of mechanic ? [mechanic, ...texts] : texts) {
    const multi = /(?<!\d)(\d)\s*\+\s*(\d)(?!\d)/.exec(text);
    if (multi) out.set("multi_buy", { kind: "multi_buy", text: `${multi[1]}+${multi[2]}` });
    const qty = /przy\s+zakupie\s+(\d{1,2})|od\s+(\d{1,2})\s*szt/i.exec(text);
    const n = qty ? Number(qty[1] ?? qty[2]) : 0;
    if (n >= 2) out.set("min_quantity", { kind: "min_quantity", quantity: n });
    if (/aplikac/i.test(text)) out.set("app", { kind: "app" });
    if (/do\s+wyczerpania/i.test(text)) out.set("stock", { kind: "stock" });
    if (new RegExp(`wybran[${L}]*\\s+sklep`, "i").test(text)) out.set("selected_stores", { kind: "selected_stores" });
  }
  if (mechanic && !out.has("multi_buy") && !out.has("min_quantity")) out.set("other", { kind: "other", text: mechanic.slice(0, 80) });
  return [...out.values()];
}

const pln = (v: Record<string, unknown>) => v.currencyCode === undefined || v.currencyCode === "PLN";
const THIRTY_DAYS = new RegExp(`najni[żz]sz[${L}]*\\s+cen[${L}]*\\s+z\\s+(?:ostatnich\\s+)?30\\s+dni`, "i");

/** One product as a data product, or undefined: not a deal, no price in złoty, a price range, no product page, alcohol,
 * or dates outside this week. */
export function actionProduct(raw: Record<string, unknown>, today: string): DataProduct | undefined {
  if (raw.isDeal === false) return undefined;
  const pricing = isObject(raw.price) && pln(raw.price) ? raw.price : undefined;
  if (!pricing || (pricing.priceRange !== undefined && pricing.priceRange !== null)) return undefined;
  const price = isObject(pricing.current) ? moneyOf(pricing.current.amount) : undefined;
  const url = productUrl(raw.href);
  const title = str(raw.title);
  if (!price || !url || !title) return undefined;
  const name = withBrand(str(raw.brand), title).replace(/\s+/g, " ").trim().slice(0, 160);
  if (ALCOHOL.test(name)) return undefined;
  const { validFrom, validTo } = dealDates(raw.stickers, today);
  if (!currentWeek(validFrom, validTo, today)) return undefined;

  const original = isObject(pricing.original) ? moneyOf(pricing.original.amount) : undefined;
  const discount = isObject(pricing.discount) ? pricing.discount : {};
  // The footnote says what the original price is; only "the lowest price of the 30 days before the cut" is the 30-day price.
  const thirty = THIRTY_DAYS.test(str(discount.footnote) ?? "");
  const unitText = isObject(pricing.unitInfo) ? str(pricing.unitInfo.formatted) : undefined;
  return {
    name, price, url, conditions: actionConditions(str(discount.percentage), raw.stickers),
    ...sizeAndUnit(str(raw.description), price, unitText),
    ...(original && thirty ? { lowest30d: original } : {}),
    ...(original && !thirty && original.minor > price.minor ? { regularPrice: original } : {}),
    ...(validFrom ? { validFrom } : {}),
    ...(validTo ? { validTo } : {}),
  };
}

export interface ActionPage {
  products: DataProduct[];
  /** The page the listing says this is, and how many it has (1 when it doesn't say). */
  page: number;
  pages: number;
  /** How many products the whole listing says it has, when it says. */
  items?: number;
  /** Every product tile's id on this page, kept or not: the read compares them with `items`. */
  ids: string[];
}

/** The products on one page of the weekly promotions and its place in the listing, or undefined without the payload. */
export function parseActionPage(html: string, today: string): ActionPage | undefined {
  const rows = flightRows(html);
  if (rows.length === 0) return undefined;
  const { tiles, pagination } = collect(rows);
  if (!pagination && tiles.length === 0) return undefined;
  const int = (v: unknown, min = 1) => (typeof v === "number" && Number.isInteger(v) && v >= min && v < 100_000 ? v : undefined);
  const byUrl = new Map<string, DataProduct>();
  for (const raw of tiles) {
    const p = actionProduct(raw, today);
    if (p && !byUrl.has(p.url)) byUrl.set(p.url, p);
  }
  const items = int(pagination?.numberOfItems, 0);
  return {
    products: [...byUrl.values()], page: int(pagination?.currentPage) ?? 1, pages: Math.min(int(pagination?.numberOfPages) ?? 1, 999),
    ...(items !== undefined ? { items } : {}),
    ids: tiles.map((t) => str(t.id) ?? str(t.href)).filter((id): id is string => !!id),
  };
}

/** The leaflet row: the promotions page, from the earliest start to the latest end among its products. */
function leafletOf(products: readonly DataProduct[]): LeafletInfo {
  const froms = products.map((p) => p.validFrom).filter((d): d is string => !!d).sort();
  const tos = products.map((p) => p.validTo).filter((d): d is string => !!d).sort();
  return {
    title: "Promocja tygodnia Action", url: ACTION_PROMO,
    ...(froms[0] ? { validFrom: froms[0] } : {}), ...(tos.length ? { validTo: tos[tos.length - 1] } : {}),
  };
}

type PageRead = { ok: true; page: ActionPage } | { ok: false; read: ChainRead };

export const action: ChainAdapter = {
  chain: "action",
  hosts: ACTION_HOSTS,
  async read(ctx): Promise<ChainRead> {
    let blocked = false;
    const readPage = async (n: number): Promise<PageRead> => {
      // Once the shop has said no, nothing more is asked of it in this request.
      if (blocked || ctx.signal.aborted) return { ok: false, read: { kind: "failed", reason: "not_asked" } };
      const r = await fetchOfficial(ctx, actionPageUrl(n), ACTION_HOSTS, "text/html");
      if (!r.ok) {
        if (r.read.kind === "blocked") blocked = true;
        return { ok: false, read: r.read };
      }
      const page = parseActionPage(r.body.toString("utf8"), ctx.today);
      if (!page) return { ok: false, read: { kind: "failed", reason: "no_payload" } };
      // A later page that comes back as another (the first, say) isn't that page: its products may be missing.
      if (n > 1 && page.page !== n) return { ok: false, read: { kind: "failed", reason: "wrong_page" } };
      return { ok: true, page };
    };

    const first = await readPage(1);
    if (!first.ok) return first.read;
    const last = Math.min(first.page.pages, ACTION_MAX_PAGES);
    const rest = await mapLimit(Array.from({ length: Math.max(0, last - 1) }, (_, i) => i + 2), 2, readPage);
    const failures = rest.filter((r): r is Extract<PageRead, { ok: false }> => !r.ok);
    const byUrl = new Map<string, DataProduct>();
    const ids = new Set<string>();
    for (const r of [first, ...rest]) {
      if (!r.ok) continue;
      for (const id of r.page.ids) ids.add(id);
      for (const p of r.page.products) if (!byUrl.has(p.url)) byUrl.set(p.url, p);
    }
    const reasons = [
      ...(failures.length ? ["some_pages_failed"] : []),
      ...(first.page.pages > ACTION_MAX_PAGES ? ["pages_capped"] : []),
    ];
    // Every page read, yet fewer products than the listing says: the pages came from different moments (the shop's
    // cache), so one product was on two pages and another on none. Finding nothing can't be claimed.
    if (reasons.length === 0 && first.page.items !== undefined && ids.size < first.page.items) reasons.push("listing_changed");
    const incomplete = reasons.length ? reasons.join(",") : undefined;
    const products = [...byUrl.values()];
    if (products.length === 0) return incomplete ? { kind: "failed", reason: incomplete } : { kind: "no_leaflet" };
    return {
      kind: "ok",
      leaflets: [{ leaflet: leafletOf(products), products, pages: [], strategy: "none" }],
      ...(incomplete ? { incomplete } : {}),
    };
  },
};
