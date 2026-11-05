// Delikatesy Centrum (observed 2026-10-29 and 2026-10-30): www.delikatesy.pl/gazetki is a Next.js page whose
// __NEXT_DATA__ carries every current leaflet as the chain's own data:
//   props.pageProps.booklets: [{id, name, date_from: "29.10.2026", date_to: "04.11.2026", requires_age_of_consent,
//   pages: [{src, thumb, title: "1"}], first_page, pdf_src, …}]
// Each page is a JPEG on static.delikatesy.pl ("…-flipbook.jpg", 593 × 1000, about 190–240 KB), the image the
// site's own flipbook shows. The data has no products, prices or page text, so, as with Biedronka, every price
// comes from reading page images (strategy "all": screened, then the flagged pages read).
// The site shows no name for a leaflet ("Franczyza DC44 Czwartek" is an internal name used only in its link
// builder), so the title is the chain's. The leaflet tile has no address of its own in the data (`url` null), so
// the leaflet and its pages link to the list page.
// Alcohol (ADR-609): a leaflet the chain flags `requires_age_of_consent` (on 30 Oct the 20-page "Delibarek"
// leaflet) is skipped, and so is a leaflet without the flag, which can't be told apart.
// robots.txt: www.delikatesy.pl answers 404 (no rules, RFC 9309). static.delikatesy.pl is an S3 bucket behind
// CloudFront that answers every missing object, robots.txt included, with 403 AccessDenied (no rules either; the
// polite fetcher treats a 4xx robots.txt as no file), and its page images answer 200 to DoddyBot.
import { currentWeek, fetchOfficial, isObject, isoDay, officialUrl, str } from "./common.js";
import type { ChainAdapter, ChainRead, LeafletPage, LeafletRead } from "../types.js";

export const DELIKATESY_HOSTS = ["www.delikatesy.pl", "static.delikatesy.pl"] as const;
export const DELIKATESY_LISTING = "https://www.delikatesy.pl/gazetki";
const IMAGE_HOSTS = ["static.delikatesy.pl"] as const;
const TITLE = "Gazetka Delikatesy Centrum";
const MAX_LEAFLETS = 2;
/** A second guard on the name, after the chain's own age flag ("Delibarek" is its alcohol leaflet). */
const ALCOHOL = /alkohol|\bpiw[ao]?\b|\bwin[ao]?\b|w[oó]dk|whisk|likier|delibar/i;

/** "29.10.2026", as the site writes dates, or an ISO day → "2026-10-29". */
export function bookletDay(v: unknown): string | undefined {
  if (typeof v !== "string") return undefined;
  const m = /^(\d{1,2})\.(\d{1,2})\.(\d{4})$/.exec(v.trim());
  return m ? isoDay(`${m[3]}-${m[2]!.padStart(2, "0")}-${m[1]!.padStart(2, "0")}`) : isoDay(v);
}

/** A leaflet's pages, in order, only https images on the chain's image host. */
export function bookletPages(raw: unknown): LeafletPage[] {
  if (!Array.isArray(raw)) return [];
  const pages: LeafletPage[] = [];
  const seen = new Set<number>();
  raw.forEach((p, i) => {
    if (!isObject(p)) return;
    const titled = str(p.title);
    const number = titled && /^\d{1,3}$/.test(titled) ? Number(titled) : i + 1;
    const img = officialUrl(p.src, IMAGE_HOSTS);
    if (!img || number < 1 || number > 500 || seen.has(number)) return;
    seen.add(number);
    pages.push({ number, imageUrl: img.toString(), url: DELIKATESY_LISTING });
  });
  return pages.sort((a, b) => a.number - b.number);
}

/** The booklets in the page's __NEXT_DATA__, or undefined when the payload isn't there. */
function payloadBooklets(html: string): unknown[] | undefined {
  const m = /<script id="__NEXT_DATA__" type="application\/json"[^>]*>([\s\S]*?)<\/script>/.exec(html);
  if (!m) return undefined;
  let data: unknown;
  try { data = JSON.parse(m[1]!); } catch { return undefined; }
  const props = isObject(data) && isObject(data.props) && isObject(data.props.pageProps) ? data.props.pageProps : undefined;
  return props && Array.isArray(props.booklets) ? props.booklets : undefined;
}

export interface DelikatesyListing {
  /** This week's leaflets to read, the earliest first. */
  leaflets: LeafletRead[];
  /** This week's leaflets left out: flagged for adults (alcohol), without the flag, or without a page image. */
  skipped: { adult: number; unflagged: number; noPages: number };
}

/** This week's readable leaflets on the list page; undefined when the page carries no leaflet data. */
export function parseGazetki(html: string, today: string): DelikatesyListing | undefined {
  const booklets = payloadBooklets(html);
  if (!booklets) return undefined;
  const skipped = { adult: 0, unflagged: 0, noPages: 0 };
  const leaflets: LeafletRead[] = [];
  for (const b of booklets) {
    if (!isObject(b)) continue;
    const validFrom = bookletDay(b.date_from);
    const validTo = bookletDay(b.date_to);
    if (!currentWeek(validFrom, validTo, today)) continue;
    if (b.requires_age_of_consent === true || ALCOHOL.test(str(b.name) ?? "")) { skipped.adult++; continue; }
    if (b.requires_age_of_consent !== false) { skipped.unflagged++; continue; }
    const pages = bookletPages(b.pages);
    if (pages.length === 0) { skipped.noPages++; continue; }
    leaflets.push({
      leaflet: { title: TITLE, url: DELIKATESY_LISTING, ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}) },
      products: [], pages, strategy: "all",
    });
  }
  // The leaflet already running comes before one that starts later in the week (pages are capped per chain).
  leaflets.sort((a, b) => (a.leaflet.validFrom ?? "").localeCompare(b.leaflet.validFrom ?? ""));
  return { leaflets, skipped };
}

export const delikatesy: ChainAdapter = {
  chain: "delikatesy",
  hosts: DELIKATESY_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const r = await fetchOfficial(ctx, DELIKATESY_LISTING, DELIKATESY_HOSTS, "text/html");
    if (!r.ok) return r.read;
    const listing = parseGazetki(r.body.toString("utf8"), ctx.today);
    if (!listing) return { kind: "failed", reason: "no_payload" };
    if (listing.leaflets.length) return { kind: "ok", leaflets: listing.leaflets.slice(0, MAX_LEAFLETS) };
    if (listing.skipped.noPages) return { kind: "failed", reason: "no_pages" };
    if (listing.skipped.unflagged) return { kind: "failed", reason: "no_age_flag" };
    return { kind: "no_leaflet" };
  },
};
