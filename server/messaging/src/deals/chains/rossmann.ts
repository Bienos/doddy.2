// Rossmann (observed 2026-10-24): the Publitas flipbook at gazetka.rossmann.pl disallows every robot in its
// robots.txt (`User-agent: *` / `Disallow: /`), so it is never fetched. rossmann.pl's own promotions page is
// allowed and carries the chain's product data in Next.js's __NEXT_DATA__:
//   www.rossmann.pl/promocje?Search={words} → props.pageProps.pageProps.dehydratedFilters.queries[queryKey[0] =
//   "syneriseProducts"].state.data.items = [{brand, name, caption, unit, price, oldPrice, pricePerUnit,
//   eanNumber[], navigateUrl, promotion {type}, promotionFrom, promotionTo, lastLowestPriceV2}]
// These are the prices rossmann.pl shows for its current promotions (name, EAN, price, regular and 30-day lowest
// price from the chain itself). The listing doesn't say which product's price needs the app ("Cena z apką" is
// only a filter count), so app conditions can't be shown for Rossmann.
// Privacy: unlike the other chains, this sends each item's words to rossmann.pl as the search term (no user id,
// no cookies; from Doddy's server).
import { currentWeek, decodeEntities, fetchOfficial, isObject, isoDay, mapLimit, moneyOf, str, validEan } from "./common.js";
import { normalize, terms } from "../match.js";
import type { ChainAdapter, ChainRead, DataProduct } from "../types.js";

export const ROSSMANN_HOSTS = ["www.rossmann.pl"] as const;
export const ROSSMANN_PROMOTIONS = "https://www.rossmann.pl/promocje";
const search = (words: string) => `${ROSSMANN_PROMOTIONS}?Search=${encodeURIComponent(words)}`;

/** A product page path on rossmann.pl ("/Produkt/…"), encoded, or undefined. */
function productPath(v: unknown): string | undefined {
  const p = str(v);
  if (!p || !p.startsWith("/Produkt/") || p.includes("//")) return undefined;
  try { return encodeURI(decodeURI(p)); } catch { return undefined; }
}

/** Promoted products on one /promocje page (only those whose promotion runs this week). */
export function parsePromotions(html: string, today: string): DataProduct[] | undefined {
  const m = /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/.exec(html);
  if (!m) return undefined;
  let data: unknown;
  try { data = JSON.parse(m[1]!); } catch { return undefined; }
  const props = isObject(data) && isObject(data.props) && isObject(data.props.pageProps) ? data.props.pageProps : undefined;
  const inner = props && isObject(props.pageProps) ? props.pageProps : undefined;
  const filters = inner && isObject(inner.dehydratedFilters) ? inner.dehydratedFilters : undefined;
  const queries = filters && Array.isArray(filters.queries) ? filters.queries : undefined;
  if (!queries) return undefined;
  const q = queries.find((x) => isObject(x) && Array.isArray(x.queryKey) && x.queryKey[0] === "syneriseProducts");
  const items = isObject(q) && isObject(q.state) && isObject(q.state.data) && Array.isArray(q.state.data.items) ? q.state.data.items : undefined;
  if (!items) return undefined;
  const out: DataProduct[] = [];
  for (const it of items) {
    if (!isObject(it)) continue;
    const validFrom = isoDay(it.promotionFrom);
    const validTo = isoDay(it.promotionTo);
    // Without promotion dates the product is only listed, not on promotion.
    if (!validFrom || !validTo || !currentWeek(validFrom, validTo, today)) continue;
    const price = moneyOf(it.price);
    const path = productPath(it.navigateUrl);
    if (!price || !path) continue;
    const unit = str(it.unit);
    const name = [str(it.brand), str(it.name), str(it.caption)].filter(Boolean).join(" ").replace(/\s+/g, " ");
    if (!name) continue;
    const regularPrice = moneyOf(it.oldPrice);
    const lowest30d = moneyOf(it.lastLowestPriceV2);
    const ean = Array.isArray(it.eanNumber) ? validEan(it.eanNumber[0]) : undefined;
    const perUnit = str(it.pricePerUnit);
    out.push({
      name: decodeEntities(unit ? `${name}, ${unit}` : name).slice(0, 160),
      price, url: `https://www.rossmann.pl${path}`, conditions: [], validFrom, validTo,
      ...(unit ? { sizeText: unit } : {}),
      ...(perUnit ? { printedUnitPrice: perUnit } : {}),
      ...(regularPrice ? { regularPrice } : {}),
      ...(lowest30d ? { lowest30d } : {}),
      ...(ean ? { ean } : {}),
    });
  }
  return out;
}

/** The words searched for an item: the item, then its first word if the item finds nothing. */
export function searchTerms(query: string): string[] {
  const words = normalize(query) ? query.trim().replace(/\s+/g, " ") : "";
  const first = terms(query).words[0]?.raw;
  const head = first ? query.trim().split(/\s+/).find((w) => normalize(w) === first) : undefined;
  return [words, ...(head && head !== words ? [head] : [])].filter(Boolean);
}

export const rossmann: ChainAdapter = {
  chain: "rossmann",
  hosts: ROSSMANN_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const failures: ChainRead[] = [];
    const byUrl = new Map<string, DataProduct>();
    let pagesRead = 0;
    let blocked = false;
    await mapLimit([...new Set(ctx.queries.map((q) => q.trim()))], 2, async (query) => {
      for (const words of searchTerms(query)) {
        // Once the chain has said no, nothing more is asked of it in this request.
        if (blocked || ctx.signal.aborted) { failures.push({ kind: "failed", reason: "not_asked" }); return; }
        const r = await fetchOfficial(ctx, search(words), ROSSMANN_HOSTS, "text/html");
        if (!r.ok) {
          if (r.read.kind === "blocked") blocked = true;
          failures.push(r.read);
          return;
        }
        const products = parsePromotions(r.body.toString("utf8"), ctx.today);
        if (!products) { failures.push({ kind: "failed", reason: "no_payload" }); return; }
        pagesRead++;
        for (const p of products) if (!byUrl.has(p.url)) byUrl.set(p.url, p);
        if (products.length) return;
      }
    });
    if (pagesRead === 0) return failures.find((f) => f.kind === "blocked") ?? failures[0] ?? { kind: "failed", reason: "no_queries" };
    return {
      kind: "ok",
      leaflets: [{ leaflet: { title: "Promocje Rossmann", url: ROSSMANN_PROMOTIONS }, products: [...byUrl.values()], pages: [], strategy: "none" }],
      ...(failures.length ? { incomplete: "some_searches_failed" } : {}),
    };
  },
};
