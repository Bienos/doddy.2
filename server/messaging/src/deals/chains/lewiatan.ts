// Lewiatan (a franchise, about 3,255 shops; observed 2026-10-29 and 2026-10-30). The chain's national leaflet
// ("Gazetka ogólnopolska" on the home page, "Gazetka MAMY TO W LEWIATANIE" on /gazetka/gazetka-mamy-w-lewiatanie,
// which shows it in an iframe) is a FlowPaper publication on the chain's own site:
//   www.lewiatan.pl/publikacje/gazetki/egazetka/index.html → <title>10 Gazetka Mamy TO w Lewiatanie _22 10</title> and
//   $('#documentViewer').FlowPaperViewer({ config: { "IMGFiles": "docs/{name}.pdf_{page}.jpg?reload=…",
//   "JSONFile": "docs/{name}.pdf_{page}.bin?reload=…", "JSONDataType": "lz", "PDFFile": "docs/{name}.pdf?…", … } })
// The page count is not in the HTML. The viewer (js/FlowPaperViewer.js) learns it from the first chunk of its JSON
// file: JSONFile with {page} = 10, FlowPaper's chunk size. That chunk is a zlib stream (what FlowPaper calls "lz")
// of [{"number":1,"pages":12,"width":1022,"height":1513,"fonts":[],"text":[]}, …], and the viewer takes `pages`
// from the first entry. This reader makes the same two requests (the HTML page, then that chunk).
// Every "text" array was empty and the PDFFile answered 404, so the leaflet is images only: JPEG pages (1022 × 1513,
// 220–290 KB) on www.lewiatan.pl. As with Biedronka, every price comes from reading page images (strategy "all":
// screened, then the flagged pages read).
// Dates: the viewer's title gives only the first day ("_22 10"). The end date is printed only on the page image
// ("OFERTA OBOWIĄZUJE: 22-31.10.2026" on 30 Oct, a 10-day run) and not in any HTML (home page, leaflet page,
// viewer), so the code leaves validTo out and doesn't guess it. A leaflet whose title gives only a first day
// counts as this week for OPEN_RUN_DAYS after that day; once that has passed, the site has failed to replace it,
// and it is not read (no_leaflet).
// National only: the regional companies' leaflets (listed from /aktualna-gazetka) are not read, because they would
// need the person's region, which is never guessed. Like Biedronka's and Delikatesy's main leaflets, the national
// leaflet also carries beer offers with the legal warning (page 1 on 30 Oct); with no text layer those pages
// can't be left out by code. A leaflet whose title names alcohol is skipped.
// robots.txt: www.lewiatan.pl and lewiatan.pl serve the same Drupal default file (User-agent: *; Disallow /core/,
// /profiles/, /admin/, /search/, /user/…), so /publikacje/ may be read. The viewer, the chunk and the page images
// answered 200 to DoddyBot.
import zlib from "node:zlib";
import { addDays, currentWeek, dayMonth, decodeEntities, fetchOfficial, isObject, officialUrl } from "./common.js";
import type { ChainAdapter, ChainRead, LeafletInfo, LeafletPage } from "../types.js";

export const LEWIATAN_HOSTS = ["www.lewiatan.pl", "lewiatan.pl"] as const;
export const LEWIATAN_VIEWER = "https://www.lewiatan.pl/publikacje/gazetki/egazetka/index.html";
/** The site's own words for it; the viewer's title is the PDF's file name ("10 Gazetka Mamy TO w Lewiatanie _22 10"). */
const TITLE = "Gazetka ogólnopolska Lewiatan";
/** FlowPaper's JSON chunk size (FLOWPAPER.CHUNK_SIZE, 10 by default): the first chunk is JSONFile with {page} = 10. */
export const FLOWPAPER_CHUNK = 10;
/** Pages listed at most. The service screens at most 120 pages a chain and reads at most 40. */
export const LEWIATAN_MAX_PAGES = 80;
/** Days after its first day that a leaflet with only a first day still counts: the 22 Oct leaflet ran 22 to 31 Oct, so
 * day 9 is its last. Longer would show offers that have ended (no end date reaches the answer to warn); a longer run
 * only means Lewiatan says "no current leaflet" for its last days (ADR-669). */
export const OPEN_RUN_DAYS = 9;
/** The chunk inflated is at most this big (a 10-page chunk without text was 793 bytes). */
const CHUNK_MAX_BYTES = 4 * 1024 * 1024;
const ALCOHOL = /alkohol|\bwin[ao]?\b|\bpiw(?:o|a|ny|ne|na)?\b|w[oó]dk|whisk|likier|\bgin\b|\brum\b|szampan|prosecco|\btrunk/i;

export interface FlowPaperViewer {
  /** The page's own title, as published. */
  title?: string;
  /** The page image address with "{page}" in it, as the config gives it (relative to the viewer page). */
  images: string;
  /** The JSON file the viewer reads the page count from, with "{page}" when it comes in chunks. */
  json?: string;
}

/** A string value in the viewer's config: "Key" : "value", with either quote, the key quoted or not. */
function configValue(html: string, key: string): string | undefined {
  const m = new RegExp(`["']?\\b${key}["']?\\s*:\\s*(["'])((?:(?!\\1)[^\\n\\\\])*)\\1`).exec(html);
  return m && m[2]!.trim() ? m[2]!.trim() : undefined;
}

/** The FlowPaper viewer's config on the page, or undefined when the page carries none. */
export function parseViewer(html: string): FlowPaperViewer | undefined {
  if (!/FlowPaperViewer\s*\(/.test(html)) return undefined;
  // flowpaper.js: PageImagePattern, when set, wins over IMGFiles.
  const images = configValue(html, "PageImagePattern") ?? configValue(html, "IMGFiles");
  if (!images || !images.includes("{page}")) return undefined;
  const json = configValue(html, "JSONFile");
  const t = /<title>([^<]*)<\/title>/i.exec(html) ?? /<meta\s+property="og:title"\s+content="([^"]*)"/i.exec(html);
  const title = t ? decodeEntities(t[1]!).replace(/\s+/g, " ").trim() : undefined;
  return { images, ...(json ? { json } : {}), ...(title ? { title } : {}) };
}

/** The address with {page} filled in, only https on the chain's hosts. */
export function pageAddress(pattern: string, page: number, base: string): URL | undefined {
  return officialUrl(pattern.split("{page}").join(String(page)), LEWIATAN_HOSTS, base);
}

/**
 * Dates in the viewer's title. "… _22 10" (as on 30 Oct) gives the first day only; a range, "22-31.10.2026" (as the
 * page prints it) or "22.10-04.11.2026", gives both. A day and month without a year is put in the year nearest today.
 */
export function datesFromTitle(title: string | undefined, today: string): Pick<LeafletInfo, "validFrom" | "validTo"> {
  if (!title) return {};
  const y = (s: string | undefined) => (s ? Number(s) : undefined);
  let from: string | undefined;
  let to: string | undefined;
  const across = /(?<![\d.])(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?\s*[-–—]\s*(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?(?![\d])/.exec(title);
  const within = /(?<![\d.])(\d{1,2})\s*[-–—]\s*(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?(?![\d])/.exec(title);
  const first = /(?:^|[\s_])(?:od\s+)?(\d{1,2})[\s._](\d{1,2})(?:[\s._](\d{4}))?[\s_]*$/i.exec(title);
  if (across) {
    from = dayMonth(Number(across[1]), Number(across[2]), today, y(across[3]));
    to = dayMonth(Number(across[4]), Number(across[5]), today, y(across[6]));
  } else if (within) {
    from = dayMonth(Number(within[1]), Number(within[3]), today, y(within[4]));
    to = dayMonth(Number(within[2]), Number(within[3]), today, y(within[4]));
  } else if (first) {
    from = dayMonth(Number(first[1]), Number(first[2]), today, y(first[3]));
  }
  if (from && to && to < from) to = undefined;
  return { ...(from ? { validFrom: from } : {}), ...(to ? { validTo: to } : {}) };
}

/** This week's leaflet: its dates touch today or the six days after it, and one with only a first day is recent. */
export function isCurrent(dates: Pick<LeafletInfo, "validFrom" | "validTo">, today: string): boolean {
  if (!currentWeek(dates.validFrom, dates.validTo, today)) return false;
  return !(dates.validFrom && !dates.validTo && addDays(dates.validFrom, OPEN_RUN_DAYS) < today);
}

/**
 * The page count the viewer reads: `pages` of the first entry of the JSON chunk, inflated when it is a zlib stream
 * ("lz") and read as it is when it is plain JSON. Undefined for anything else (an encrypted chunk, `{"e": …}`, too).
 */
export function pageCountFromChunk(body: Buffer): number | undefined {
  let text: string;
  try {
    const plain = /^\s*\[/.test(body.subarray(0, 16).toString("latin1"));
    text = plain ? body.toString("utf8") : zlib.inflateSync(body, { maxOutputLength: CHUNK_MAX_BYTES }).toString("utf8");
  } catch { return undefined; }
  let data: unknown;
  try { data = JSON.parse(text); } catch { return undefined; }
  if (!Array.isArray(data) || !isObject(data[0])) return undefined;
  const raw = data[0].pages;
  const pages = typeof raw === "number" ? raw : typeof raw === "string" && /^\d{1,4}$/.test(raw) ? Number(raw) : NaN;
  return Number.isInteger(pages) && pages >= 1 && pages <= 1000 ? pages : undefined;
}

export const lewiatan: ChainAdapter = {
  chain: "lewiatan",
  hosts: LEWIATAN_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const r = await fetchOfficial(ctx, LEWIATAN_VIEWER, LEWIATAN_HOSTS, "text/html");
    if (!r.ok) return r.read;
    const viewer = parseViewer(r.body.toString("utf8"));
    if (!viewer) return { kind: "failed", reason: "no_viewer_config" };
    const base = r.finalUrl.toString();
    if (ALCOHOL.test(`${viewer.title ?? ""} ${viewer.images}`)) return { kind: "no_leaflet" };
    const dates = datesFromTitle(viewer.title, ctx.today);
    if (!isCurrent(dates, ctx.today)) return { kind: "no_leaflet" };
    if (!viewer.json) return { kind: "failed", reason: "no_page_list" };
    const chunkUrl = pageAddress(viewer.json, FLOWPAPER_CHUNK, base);
    if (!chunkUrl) return { kind: "failed", reason: "not_official_host" };
    const chunk = await fetchOfficial(ctx, chunkUrl.toString(), LEWIATAN_HOSTS, "application/octet-stream, application/json;q=0.9, */*;q=0.5");
    if (!chunk.ok) return chunk.read;
    const count = pageCountFromChunk(chunk.body);
    if (!count) return { kind: "failed", reason: "no_page_count" };
    const pages: LeafletPage[] = [];
    for (let n = 1; n <= Math.min(count, LEWIATAN_MAX_PAGES); n++) {
      const img = pageAddress(viewer.images, n, base);
      if (!img) return { kind: "failed", reason: "no_pages" };
      pages.push({ number: n, imageUrl: img.toString(), url: base });
    }
    const leaflet: LeafletInfo = { title: TITLE, url: base, ...dates };
    return { kind: "ok", leaflets: [{ leaflet, products: [], pages, strategy: "all" }], ...(count > LEWIATAN_MAX_PAGES ? { incomplete: "page_cap" } : {}) };
  },
};
