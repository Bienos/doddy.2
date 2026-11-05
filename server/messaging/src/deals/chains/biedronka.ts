// Biedronka (observed 2026-10-24): biedronka.pl publishes its leaflets as image flipbooks only; neither the
// leaflet pages nor biedronka.pl carry product tiles, prices or schema.org data, so every price comes from
// reading page images.
//   /pl/w-tym-tygodniu  → 307/301 → /pl/press,id,{id},title,{slug}   ("this week's" main leaflet)
//   the press page      → window.galleryLeaflet.init("{uuid}") and <title>… - oferta od DD.MM - Gazetka - Biedronka.pl
//   leaflet-api.prod.biedronka.cloud/api/leaflets/{uuid}?ctx=web → {images_mobile: [{page, image}], …} (PNG pages,
//   1146 × 1800 on 2026-10-24) on images.biedronka.cloud. The API gives no dates.
// If the redirect stops working, /pl/gazetki is read for the slot named "…_W_TYM_TYGODNIU".
import { addDays, dayMonth, decodeEntities, fetchOfficial, isObject, officialUrl, parseJson } from "./common.js";
import type { ChainAdapter, ChainContext, ChainRead, LeafletInfo, LeafletPage } from "../types.js";

export const BIEDRONKA_HOSTS = ["www.biedronka.pl", "leaflet-api.prod.biedronka.cloud", "images.biedronka.cloud"] as const;
const THIS_WEEK = "https://www.biedronka.pl/pl/w-tym-tygodniu";
const LISTING = "https://www.biedronka.pl/pl/gazetki";
const leafletApi = (uuid: string) => `https://leaflet-api.prod.biedronka.cloud/api/leaflets/${uuid}?ctx=web`;
const isPress = (u: URL) => u.hostname === "www.biedronka.pl" && /^\/pl\/press,id,[a-z0-9]+,title,[a-z0-9-]+$/i.test(u.pathname);

/** The leaflet id and title on a press page. */
export function parsePressPage(html: string): { uuid: string; title?: string } | undefined {
  const m = /galleryLeaflet\.init\(\s*["']([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})["']\s*\)/i.exec(html);
  if (!m) return undefined;
  const t = /<title>([^<]*)<\/title>/i.exec(html);
  const title = t ? decodeEntities(t[1]!).replace(/\s*-\s*Gazetka\s*-\s*Biedronka\.pl\s*$/i, "").replace(/\s+/g, " ").trim() : undefined;
  return { uuid: m[1]!.toLowerCase(), ...(title ? { title } : {}) };
}

/** The main leaflet's press link on /pl/gazetki (the slot whose id ends in W_TYM_TYGODNIU). */
export function findThisWeekOnListing(html: string): string | undefined {
  const m = /data-slot-id="[^"]*W_TYM_TYGODNIU"[\s\S]{0,400}?href="([^"]*\/pl\/press,id,[^"#]*)/i.exec(html);
  return m?.[1];
}

/** "Codziennie niskie ceny P - oferta od 22.10" → validFrom; "… od 23.10 do 26.10" → both. */
export function datesFromTitle(title: string | undefined, today: string): Pick<LeafletInfo, "validFrom" | "validTo"> {
  if (!title) return {};
  const from = /\bod\s+(\d{1,2})\.(\d{1,2})\b/i.exec(title);
  const to = /\bdo\s+(\d{1,2})\.(\d{1,2})\b/i.exec(title);
  const validFrom = from ? dayMonth(Number(from[1]), Number(from[2]), today) : undefined;
  let validTo = to ? dayMonth(Number(to[1]), Number(to[2]), today) : undefined;
  if (validFrom && validTo && validTo < validFrom) validTo = dayMonth(Number(to![1]), Number(to![2]), addDays(validFrom, 180));
  return { ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}) };
}

/** Pages from the leaflet API (single pages, in order), only on the chain's image host. */
export function parseLeafletApi(json: unknown, pageUrl: string): LeafletPage[] {
  if (!isObject(json) || !Array.isArray(json.images_mobile)) return [];
  const pages: LeafletPage[] = [];
  const seen = new Set<number>();
  for (const e of json.images_mobile) {
    if (!isObject(e) || typeof e.page !== "number" || !Number.isInteger(e.page) || e.page < 0 || e.page > 500) continue;
    const img = officialUrl(e.image, ["images.biedronka.cloud"]);
    if (!img || seen.has(e.page)) continue;
    seen.add(e.page);
    pages.push({ number: e.page + 1, imageUrl: img.toString(), url: pageUrl });
  }
  return pages.sort((a, b) => a.number - b.number);
}

async function findPressPage(ctx: ChainContext): Promise<{ url: URL; html: string } | ChainRead> {
  const r = await fetchOfficial(ctx, THIS_WEEK, BIEDRONKA_HOSTS, "text/html");
  if (r.ok && isPress(r.finalUrl)) return { url: r.finalUrl, html: r.body.toString("utf8") };
  if (!r.ok && r.read.kind === "blocked") return r.read;
  const listing = await fetchOfficial(ctx, LISTING, BIEDRONKA_HOSTS, "text/html");
  if (!listing.ok) return listing.read;
  const href = findThisWeekOnListing(listing.body.toString("utf8"));
  const pressUrl = href ? officialUrl(href, BIEDRONKA_HOSTS, LISTING) : undefined;
  if (!pressUrl) return { kind: "no_leaflet" };
  const press = await fetchOfficial(ctx, pressUrl.toString(), BIEDRONKA_HOSTS, "text/html");
  if (!press.ok) return press.read;
  return { url: press.finalUrl, html: press.body.toString("utf8") };
}

export const biedronka: ChainAdapter = {
  chain: "biedronka",
  hosts: BIEDRONKA_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const press = await findPressPage(ctx);
    if (!("html" in press)) return press;
    const parsed = parsePressPage(press.html);
    if (!parsed) return { kind: "failed", reason: "no_leaflet_id" };
    const api = await fetchOfficial(ctx, leafletApi(parsed.uuid), BIEDRONKA_HOSTS, "application/json");
    if (!api.ok) return api.read;
    const pageUrl = press.url.toString();
    const pages = parseLeafletApi(parseJson(api.body), pageUrl);
    if (pages.length === 0) return { kind: "failed", reason: "no_pages" };
    const leaflet: LeafletInfo = {
      ...(parsed.title ? { title: parsed.title } : {}),
      url: pageUrl,
      ...datesFromTitle(parsed.title, ctx.today),
    };
    return { kind: "ok", leaflets: [{ leaflet, products: [], pages, strategy: "all" }] };
  },
};
