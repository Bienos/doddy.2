// Komfort (home: flooring, carpets, doors, curtains, decor; observed 2026-10-30): komfort.pl/st/gazetka (www.komfort.pl
// answers 301 to komfort.pl) shows the current leaflet in
//   <div class="gazetka-view"><div class="publitas-container"><iframe … src="https://view.publitas.com/sklepy-komfort-sa/gazetka-black-weeks-2026/?publitas_embed=embedded">
// with a "Sprawdź naszą ofertę w gazetce" button to the same address. The page's other Publitas links are catalogues
// (carpets, kitchens, floors and doors) and are not read. sklepy-komfort-sa is Komfort's own group on Publitas; its
//   /{slug}/spreads.json → [{pages: [{number, text, images: {at2400, at2000, …}}]}]
// gave 50 pages, each with Komfort's own text: names, sizes, product codes ("kod: 100615880"), the crossed-out price and
// the price ("/szt.", "/m2", "/mb"), "Przekreślone ceny są najniższymi cenami z ostatnich 30 dni przed wprowadzeniem
// promocji." on every page, and on page 1 "Oferta ważna od 28.10 do 01.12.2026 r.", the leaflet's dates.
//
// Prices are NOT taken from that text, because it loses where the grosze start. The page prints grosze small and raised
// with no comma ("49⁹⁹ 39⁹⁹ /szt." on page 16, a 50 × 80 cm bath mat) and whole złoty without any ("1099 749 /szt." on
// page 4, a 200 × 290 cm carpet); the text has "4999 3999 /szt." and "1099 749 /szt.", so 49,99 zł and 1 099 zł look
// alike. Most products' big price box is also in text runs of its own, away from the name and code ("54", "97" for
// 54,97 zł/m² on the flooring pages), and one price line can serve several codes. So the text only picks the pages
// worth reading, as Żabka's and Lidl's do, and the price is read from the page image (at2000: a 1727 × 2316 JPEG on
// view.publitas.com), where the raised grosze can be seen.
// robots.txt: komfort.pl allows /st/gazetka to every agent (it disallows search, the cart, the account and `*klink=*`);
// view.publitas.com has none (404: no rules, RFC 9309).
import { currentWeek, decodeEntities, fetchOfficial, isObject, isoDay, officialUrl, parseJson } from "./common.js";
import type { ChainAdapter, ChainRead, LeafletPage, LeafletRead } from "../types.js";

export const KOMFORT_HOSTS = ["komfort.pl", "www.komfort.pl", "view.publitas.com"] as const;
export const KOMFORT_LISTING = "https://komfort.pl/st/gazetka";
/** Komfort's own group on Publitas: a leaflet in any other group on view.publitas.com isn't Komfort's. */
const GROUP = "sklepy-komfort-sa";
export const komfortLeafletUrl = (slug: string) => `https://view.publitas.com/${GROUP}/${slug}/`;
export const komfortSpreads = (slug: string) => `${komfortLeafletUrl(slug)}spreads.json`;

const LEAFLET = String.raw`https://view\.publitas\.com/${GROUP}/([a-z0-9][a-z0-9-]{1,100})(?=[/?"'])`;
const FRAME = new RegExp(String.raw`<iframe[^>]*\ssrc="${LEAFLET}`);
const BUTTON = new RegExp(String.raw`<a[^>]*\shref="${LEAFLET}[^"]*"[^>]*>\s*<button[^>]*class="gazetka-button"`);

/** The leaflet the page shows: the one in the "gazetka-view" frame, else the leaflet button's. */
export function findLeaflet(html: string): string | undefined {
  const view = html.indexOf('class="gazetka-view"');
  const framed = view >= 0 ? FRAME.exec(html.slice(view, view + 2000))?.[1] : undefined;
  return framed ?? BUTTON.exec(html)?.[1];
}

/** "Oferta ważna od 28.10 do 01.12.2026 r." in the leaflet's own text, first page first. A start without a year takes
 * the end's year, or the year before when its month comes after the end's ("od 28.12 do 10.01.2027"). */
export function leafletDates(texts: readonly string[]): { validFrom?: string; validTo?: string } {
  const pad = (s: string) => s.padStart(2, "0");
  for (const t of texts) {
    const both = /wa[żz]n[aey]\s+od\s+(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?\s*(?:r\.)?\s*do\s+(\d{1,2})\.(\d{1,2})\.(\d{4})/i.exec(t);
    if (both) {
      const [, fd, fm, fy, td, tm, ty] = both;
      const validTo = isoDay(`${ty}-${pad(tm!)}-${pad(td!)}`);
      const fromYear = fy ? Number(fy) : Number(fm) > Number(tm) ? Number(ty) - 1 : Number(ty);
      const validFrom = isoDay(`${fromYear}-${pad(fm!)}-${pad(fd!)}`);
      if (validFrom && validTo && validFrom <= validTo) return { validFrom, validTo };
      continue;
    }
    const end = /wa[żz]n[aey]\s+do\s+(\d{1,2})\.(\d{1,2})\.(\d{4})/i.exec(t);
    const validTo = end ? isoDay(`${end[3]}-${pad(end[2]!)}-${pad(end[1]!)}`) : undefined;
    if (validTo) return { validTo };
  }
  return {};
}

/** Pages from spreads.json with Komfort's own page text, images on Publitas's host only. */
export function komfortPages(json: unknown, slug: string): LeafletPage[] {
  if (!Array.isArray(json)) return [];
  const pages: LeafletPage[] = [];
  const seen = new Set<number>();
  for (const spread of json) {
    for (const p of isObject(spread) && Array.isArray(spread.pages) ? spread.pages : []) {
      if (!isObject(p) || typeof p.number !== "number" || !Number.isInteger(p.number) || p.number < 1 || p.number > 500 || seen.has(p.number)) continue;
      const images = isObject(p.images) ? p.images : {};
      const path = typeof images.at2000 === "string" ? images.at2000 : typeof images.at1600 === "string" ? images.at1600 : undefined;
      const img = path?.startsWith("/") ? officialUrl(`https://view.publitas.com${path}`, ["view.publitas.com"]) : undefined;
      if (!img) continue;
      seen.add(p.number);
      const text = typeof p.text === "string" ? decodeEntities(p.text).replace(/\s+/g, " ").trim().slice(0, 4000) : "";
      pages.push({ number: p.number, imageUrl: img.toString(), url: `${komfortLeafletUrl(slug)}page/${p.number}`, ...(text ? { text } : {}) });
    }
  }
  return pages.sort((a, b) => a.number - b.number);
}

/** The leaflet from its spreads.json: pages for the reader, chosen by their text, and the dates it prints. No products:
 * the text can't say where a price's grosze start (see the top of this file). */
export function komfortLeaflet(json: unknown, slug: string, today: string): LeafletRead | "not_current" | undefined {
  const pages = komfortPages(json, slug);
  if (pages.length === 0) return undefined;
  const { validFrom, validTo } = leafletDates(pages.map((p) => p.text ?? ""));
  if (!currentWeek(validFrom, validTo, today)) return "not_current";
  return {
    leaflet: { title: "Gazetka Komfort", url: komfortLeafletUrl(slug), ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}) },
    products: [], pages, strategy: "text",
  };
}

export const komfort: ChainAdapter = {
  chain: "komfort",
  hosts: KOMFORT_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const page = await fetchOfficial(ctx, KOMFORT_LISTING, KOMFORT_HOSTS, "text/html");
    if (!page.ok) return page.read;
    const slug = findLeaflet(page.body.toString("utf8"));
    if (!slug) return { kind: "no_leaflet" };
    const r = await fetchOfficial(ctx, komfortSpreads(slug), KOMFORT_HOSTS, "application/json");
    if (!r.ok) return r.read;
    const l = komfortLeaflet(parseJson(r.body), slug, ctx.today);
    if (l === "not_current") return { kind: "no_leaflet" };
    if (!l) return { kind: "failed", reason: "no_pages" };
    return { kind: "ok", leaflets: [l] };
  },
};
