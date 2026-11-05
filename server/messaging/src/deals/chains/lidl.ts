// Lidl (observed 2026-10-24): the leaflet list on lidl.pl links each leaflet as /l/pl/gazetki/{slug}/ar/0, and
// Schwarz's leaflet endpoint returns it as JSON:
//   endpoints.leaflets.schwarz/v4/flyer?flyer_identifier={slug}&region_id=0 → {success, flyer: {name, title,
//   startDate, endDate, offerStartDate, offerEndDate, flyerUrlAbsolute, pages: [{number, keyWords, altText,
//   image (1200 px fit), zoom (2400 px fit), links}], products: {id: {title, price, url}}}}
// `keyWords` and `altText` are Lidl's own text for each page (product names with bare digits for prices), used
// only to find the pages worth reading; prices on those pages are read from the image. `products` are the few
// items the leaflet links to the shop (non-food on 2026-10-24) with the chain's price.
// Alcohol catalogues are skipped.
import { currentWeek, decodeEntities, fetchOfficial, isObject, isoDay, mapLimit, moneyOf, officialUrl, parseJson, str } from "./common.js";
import type { ChainAdapter, ChainRead, DataProduct, LeafletPage, LeafletRead } from "../types.js";

export const LIDL_HOSTS = ["www.lidl.pl", "endpoints.leaflets.schwarz", "imgproxy.leaflets.schwarz"] as const;
const LISTING = "https://www.lidl.pl/c/nasze-gazetki/s10008614";
const flyerApi = (slug: string) => `https://endpoints.leaflets.schwarz/v4/flyer?flyer_identifier=${encodeURIComponent(slug)}&region_id=0`;
const MAX_LEAFLETS = 4;
const ALCOHOL = /alkohol|\bwin[ao]?\b|\bpiw[ao]?\b/i;

export interface ListedFlyer { slug: string; name: string; title: string; section: string }

/** The leaflets on lidl.pl's list, in page order, with the section each sits in. */
export function parseOverview(html: string): ListedFlyer[] {
  const out: ListedFlyer[] = [];
  const seen = new Set<string>();
  let section = "";
  const re = /<div class="section-head">([^<]*)<\/div>|<a\s+href="https:\/\/www\.lidl\.pl\/l\/pl\/gazetki\/([a-z0-9-]+)\/ar\/\d+[^"]*"[^>]*class="flyer"[\s\S]*?<\/a>/gi;
  for (const m of html.matchAll(re)) {
    if (m[1] !== undefined) { section = decodeEntities(m[1]).trim(); continue; }
    const slug = m[2]!;
    if (seen.has(slug)) continue;
    seen.add(slug);
    const block = m[0];
    const name = /class="flyer__name">\s*([^<]*?)\s*</.exec(block)?.[1] ?? "";
    const title = /class="flyer__title">\s*([^<]*?)\s*</.exec(block)?.[1] ?? "";
    out.push({ slug, name: decodeEntities(name), title: decodeEntities(title), section });
  }
  return out;
}

/** One leaflet from the flyer endpoint: pages to read (with Lidl's own page text) and the linked products. */
export function parseFlyer(json: unknown, slug: string, today: string): LeafletRead | "not_current" | undefined {
  if (!isObject(json) || json.success !== true || !isObject(json.flyer)) return undefined;
  const f = json.flyer;
  const validFrom = isoDay(f.offerStartDate) ?? isoDay(f.startDate);
  const validTo = isoDay(f.offerEndDate) ?? isoDay(f.endDate);
  if (!currentWeek(validFrom, validTo, today)) return "not_current";
  const base = `https://www.lidl.pl/l/pl/gazetki/${slug}`;
  const pageUrl = (n: number) => `${base}/view/flyer/page/${n}`;
  const pages: LeafletPage[] = [];
  const productPage = new Map<string, number>();
  for (const p of Array.isArray(f.pages) ? f.pages : []) {
    if (!isObject(p) || typeof p.number !== "number" || !Number.isInteger(p.number) || p.number < 1 || p.number > 1000) continue;
    // `zoom` is 1420 × 2400 (about 4,400 visual tokens, inside Claude's limit); `image` is half that.
    const img = officialUrl(p.zoom, LIDL_HOSTS) ?? officialUrl(p.image, LIDL_HOSTS);
    const text = [str(p.altText), str(p.keyWords)].filter(Boolean).join(" ").slice(0, 4000);
    if (img) pages.push({ number: p.number, imageUrl: img.toString(), url: pageUrl(p.number), ...(text ? { text } : {}) });
    for (const l of Array.isArray(p.links) ? p.links : []) {
      if (isObject(l) && l.displayType === "product" && typeof l.id === "string") productPage.set(l.id, p.number);
    }
  }
  const products: DataProduct[] = [];
  if (isObject(f.products)) {
    for (const [id, p] of Object.entries(f.products)) {
      if (!isObject(p)) continue;
      const name = str(p.title);
      const price = moneyOf(p.price);
      const url = officialUrl(p.url, ["www.lidl.pl"]);
      if (!name || !price || !url || (str(p.currencyText) && p.currencyText !== "PLN")) continue;
      const page = productPage.get(id);
      products.push({
        name: decodeEntities(name).slice(0, 160), price, url: url.toString(), conditions: [],
        ...(page ? { page } : {}), ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}),
      });
    }
  }
  const name = [str(f.name), str(f.title)].filter(Boolean).join(" ");
  return {
    leaflet: {
      ...(name ? { title: decodeEntities(name) } : {}),
      url: `${base}/ar/0`,
      ...(validFrom ? { validFrom } : {}),
      ...(validTo ? { validTo } : {}),
    },
    products,
    pages: pages.sort((a, b) => a.number - b.number),
    strategy: "text",
  };
}

export const lidl: ChainAdapter = {
  chain: "lidl",
  hosts: LIDL_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const listing = await fetchOfficial(ctx, LISTING, LIDL_HOSTS, "text/html");
    if (!listing.ok) return listing.read;
    const flyers = parseOverview(listing.body.toString("utf8"))
      .filter((f) => !ALCOHOL.test(f.section) && !ALCOHOL.test(f.name))
      .slice(0, MAX_LEAFLETS);
    if (flyers.length === 0) return { kind: "no_leaflet" };
    const results = await mapLimit(flyers, 2, async (f) => {
      const r = await fetchOfficial(ctx, flyerApi(f.slug), LIDL_HOSTS, "application/json");
      if (!r.ok) return r.read;
      return parseFlyer(parseJson(r.body), f.slug, ctx.today) ?? ({ kind: "failed", reason: "unreadable_flyer" } as ChainRead);
    });
    const leaflets = results.filter((r): r is LeafletRead => typeof r === "object" && "leaflet" in r);
    const failures = results.filter((r): r is ChainRead => typeof r === "object" && "kind" in r);
    if (leaflets.length) return { kind: "ok", leaflets, ...(failures.length ? { incomplete: "some_leaflets_failed" } : {}) };
    if (results.every((r) => r === "not_current")) return { kind: "no_leaflet" };
    return failures.find((r) => r.kind === "blocked") ?? failures[0] ?? { kind: "failed", reason: "unreadable_flyer" };
  },
};
