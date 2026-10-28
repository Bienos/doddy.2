// Żabka (observed 2026-10-28): www.zabka.pl/gazetka-promocyjna/ shows each leaflet in a block
//   <div class="date-display-group" data-date-from="2026-10-21 00:00" data-date-to="2026-11-03 23:59"> … <iframe
//   src="https://gazetka.zabka.pl/gazetka-promocyjna-43-44-2026/?publitas_embed=maximized">
// (the next one is already there, hidden). gazetka.zabka.pl is Żabka's leaflet site on Publitas; its
//   /{slug}/spreads.json → [{pages: [{number, text, images: {at2000, at1600, …}}]}]
// carries Żabka's own text for every page (names, sizes, prices per kg, conditions, dates, with the big price split into
// digits), used only to find the pages worth reading, as Lidl's. Prices on those pages are read from the image, a
// path on view.publitas.com (1565 × 2555 JPEG at "at2000"). No robots.txt on gazetka.zabka.pl or view.publitas.com
// (404: no rules, RFC 9309). Unlike Rossmann's Publitas leaflet, which disallows every robot, nothing here says no.
// Pages carrying the legal beer warning ("… zawiera 25 gramów czystego alkoholu …") are skipped: no alcohol offers.
import { currentWeek, decodeEntities, fetchOfficial, isObject, isoDay, mapLimit, officialUrl, parseJson } from "./common.js";
import type { ChainAdapter, ChainRead, LeafletPage, LeafletRead } from "../types.js";

export const ZABKA_HOSTS = ["www.zabka.pl", "gazetka.zabka.pl", "view.publitas.com"] as const;
export const ZABKA_LISTING = "https://www.zabka.pl/gazetka-promocyjna/";
const leafletBase = (slug: string) => `https://gazetka.zabka.pl/${slug}/`;
export const zabkaSpreads = (slug: string) => `${leafletBase(slug)}spreads.json`;
const MAX_LEAFLETS = 2;
const ALCOHOL_WARNING = /czystego\s+alkoholu|alkohol\s+etylow/i;

export interface ListedLeaflet { slug: string; validFrom?: string; validTo?: string }

/** The leaflets on the list page, each with the dates of its block. */
export function parseListing(html: string): ListedLeaflet[] {
  const out: ListedLeaflet[] = [];
  const re = /<div class="date-display-group[^"]*"\s+data-date-from="([^"]*)"\s+data-date-to="([^"]*)"/g;
  const starts = [...html.matchAll(re)];
  starts.forEach((m, i) => {
    const block = html.slice(m.index! + m[0].length, starts[i + 1]?.index ?? html.length);
    const slug = /https:\/\/gazetka\.zabka\.pl\/([a-z0-9][a-z0-9-]{2,80})\//.exec(block)?.[1];
    if (!slug || out.some((l) => l.slug === slug)) return;
    const validFrom = isoDay(m[1]);
    const validTo = isoDay(m[2]);
    out.push({ slug, ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}) });
  });
  return out;
}

/** Pages from spreads.json with Żabka's own page text, on the chain's hosts only; alcohol pages left out. */
export function parseSpreads(json: unknown, slug: string): LeafletPage[] {
  if (!Array.isArray(json)) return [];
  const pages: LeafletPage[] = [];
  const seen = new Set<number>();
  for (const spread of json) {
    for (const p of isObject(spread) && Array.isArray(spread.pages) ? spread.pages : []) {
      if (!isObject(p) || typeof p.number !== "number" || !Number.isInteger(p.number) || p.number < 1 || p.number > 500 || seen.has(p.number)) continue;
      const text = typeof p.text === "string" ? decodeEntities(p.text).replace(/\s+/g, " ").trim().slice(0, 4000) : "";
      if (ALCOHOL_WARNING.test(text)) continue;
      const images = isObject(p.images) ? p.images : {};
      const path = typeof images.at2000 === "string" ? images.at2000 : typeof images.at1600 === "string" ? images.at1600 : undefined;
      const img = path?.startsWith("/") ? officialUrl(`https://view.publitas.com${path}`, ZABKA_HOSTS) : undefined;
      if (!img) continue;
      seen.add(p.number);
      pages.push({ number: p.number, imageUrl: img.toString(), url: `${leafletBase(slug)}page/${p.number}`, ...(text ? { text } : {}) });
    }
  }
  return pages.sort((a, b) => a.number - b.number);
}

export const zabka: ChainAdapter = {
  chain: "zabka",
  hosts: ZABKA_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const listing = await fetchOfficial(ctx, ZABKA_LISTING, ZABKA_HOSTS, "text/html");
    if (!listing.ok) return listing.read;
    const listed = parseListing(listing.body.toString("utf8"))
      .filter((l) => currentWeek(l.validFrom, l.validTo, ctx.today))
      .slice(0, MAX_LEAFLETS);
    if (listed.length === 0) return { kind: "no_leaflet" };
    const results = await mapLimit(listed, 2, async (l): Promise<LeafletRead | ChainRead> => {
      const r = await fetchOfficial(ctx, zabkaSpreads(l.slug), ZABKA_HOSTS, "application/json");
      if (!r.ok) return r.read;
      const pages = parseSpreads(parseJson(r.body), l.slug);
      if (pages.length === 0) return { kind: "failed", reason: "no_pages" };
      return {
        leaflet: {
          title: "Gazetka promocyjna Żabka", url: leafletBase(l.slug),
          ...(l.validFrom ? { validFrom: l.validFrom } : {}), ...(l.validTo ? { validTo: l.validTo } : {}),
        },
        products: [], pages, strategy: "text",
      };
    });
    const leaflets = results.filter((r): r is LeafletRead => "leaflet" in r);
    const failures = results.filter((r): r is ChainRead => "kind" in r);
    if (leaflets.length) return { kind: "ok", leaflets, ...(failures.length ? { incomplete: "some_leaflets_failed" } : {}) };
    return failures.find((f) => f.kind === "blocked") ?? failures[0] ?? { kind: "failed", reason: "no_pages" };
  },
};
