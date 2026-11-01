// E.Leclerc (observed 2026-10-29 and 30): leclerc.pl is a WordPress multisite (www.leclerc.pl redirects to it;
// e-leclerc.pl is not used: 502 and a certificate for another name on 29 Oct). leclerc.pl/gazetki/ lists the
// network's leaflets, each as
//   <article class="post-{id} gazetki …" id="newspaper-{id}"> … <div class="entry-content"><p>od 26.10. do 02.11.2026 r.</p>
//   … <script> $("#newspaper-{id}").flipBook({ pages: (function () { var pagesDesktop = [{src: "…-1047x1600.jpg",
//   thumb: "…"}, …]; var pagesMobile = […]; … })(), … })
// Image flipbooks only: JPEG pages (1047 × 1600 at "src", about 290 KB, no text layer) on leclerc.pl/wp-content/uploads/,
// no product data and no titles (the list prints only the dates), so every price comes from reading page images.
// National or per shop: each hypermarket (many franchised) has its own site, {city}.leclerc.pl, whose /gazetki/ shows
// the network's posts it carries (same post ids and images; on 30 Oct Gdańsk had all eight, Ursynów seven) plus its
// own leaflets on {city}.leclerc.pl/wp-content/uploads/sites/{n}/. Only the network's list is read here; a shop's own
// leaflets would need the person's shop, which is never guessed.
// Alcohol: the list carries an age gate for alcohol catalogues (#adultModal, blurred `.inactive-newspaper` covers).
// None was listed on 30 Oct, so a leaflet is skipped on any sign of one: an age-gate marker in its own block, or an
// alcohol word in its text, an image's alt text or its page file names.
import { currentWeek, dayMonth, decodeEntities, fetchOfficial, officialUrl } from "./common.js";
import type { ChainAdapter, ChainRead, LeafletInfo, LeafletRead } from "../types.js";

export const LECLERC_HOSTS = ["leclerc.pl", "www.leclerc.pl"] as const;
export const LECLERC_LISTING = "https://leclerc.pl/gazetki/";
/** Pages handed to the service per request, all leaflets together (its screening reads at most 120). */
export const LECLERC_MAX_PAGES = 120;
const ALCOHOL = /alkohol|\bwin[ao]?\b|\bpiw(?:o|a|ny|ne|na)?\b|w[oó]dk|whisk|likier|\bgin\b|\brum\b|szampan|prosecco|\btrunk/i;
const AGE_GATE = /adult|inactive-newspaper|pe[łl]noletn/i;

export interface ListedLeaflet {
  /** The post id ("35464"); its block on the list is #newspaper-{id}. */
  id: string;
  validFrom?: string;
  validTo?: string;
  alcohol: boolean;
  /** Page images in order, https on the chain's hosts under /wp-content/uploads/ only. */
  images: string[];
}

const dm = (day: string) => `${day.slice(8, 10)}.${day.slice(5, 7)}`;
const fileWords = (u: string) => {
  const name = new URL(u).pathname.split("/").pop() ?? "";
  try { return decodeURIComponent(name).replace(/[_\-.]+/g, " "); } catch { return name.replace(/[_\-.]+/g, " "); }
};

/** "od 03.11. do 14.11.2026 r." → both days; "od 29.12. do 10.01.2027" puts the start in 2026. */
export function datesFromText(text: string, today: string): Pick<LeafletInfo, "validFrom" | "validTo"> {
  const t = text.replace(/\s+/g, " ");
  const range = /(\d{1,2})\.(\d{1,2})\.?(?:(\d{4})\s*(?:r\.?)?)?\s*(?:do|[-–])\s*(\d{1,2})\.(\d{1,2})\.?(\d{4})?/i.exec(t);
  const from = range ? [range[1], range[2], range[3]] : /\bod\s+(\d{1,2})\.(\d{1,2})\.?(\d{4})?/i.exec(t)?.slice(1, 4);
  const to = range ? [range[4], range[5], range[6]] : /\bdo\s+(\d{1,2})\.(\d{1,2})\.?(\d{4})?/i.exec(t)?.slice(1, 4);
  const day = (p: (string | undefined)[] | undefined, anchor: string) =>
    p ? dayMonth(Number(p[0]), Number(p[1]), anchor, p[2] ? Number(p[2]) : undefined) : undefined;
  const validTo = day(to, today);
  let validFrom = day(from, validTo ?? today);
  if (validFrom && validTo && validFrom > validTo) validFrom = undefined;
  return { ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}) };
}

/** The leaflets on the list, in its order; undefined when the page isn't the list it was (no list, or blocks that
 * no longer read). */
export function parseListing(html: string, today: string): ListedLeaflet[] | undefined {
  const list = html.indexOf('class="newspapers-list"');
  if (list < 0) return undefined;
  const starts = [...html.matchAll(/<article\b[^>]*\bid="newspaper-(\d{1,12})"[^>]*>/g)].filter((m) => m.index! > list);
  const end = (from: number) => {
    const stops = ["</main>", 'id="adultModal"'].map((s) => html.indexOf(s, from)).filter((i) => i >= 0);
    return Math.min(html.length, ...stops);
  };
  if (starts.length === 0 && html.slice(list, end(list)).includes("<article")) return undefined;
  const out: ListedLeaflet[] = [];
  starts.forEach((m, i) => {
    const id = m[1]!;
    if (out.some((l) => l.id === id)) return;
    const block = html.slice(m.index!, Math.min(starts[i + 1]?.index ?? html.length, end(m.index!)));
    const content = /<div class="entry-content">([\s\S]*?)<\/div>/.exec(block)?.[1] ?? "";
    const text = decodeEntities(content.replace(/<button[\s\S]*?<\/button>/gi, " ").replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
    const alts = [...block.matchAll(/\balt="([^"]*)"/g)].map((a) => decodeEntities(a[1]!));
    // Desktop pages ("src", not the mobile set or the "thumb" originals); a shop site's copy has a plain `pages: [...]`.
    const set = /var\s+pagesDesktop\s*=\s*\[([\s\S]*?)\]\s*;/.exec(block)?.[1] ?? /\bpages\s*:\s*\[([\s\S]*?)\]/.exec(block)?.[1] ?? "";
    const images: string[] = [];
    for (const s of set.matchAll(/\bsrc\s*:\s*["']([^"']+)["']/g)) {
      const u = officialUrl(s[1], LECLERC_HOSTS, LECLERC_LISTING);
      if (u && u.pathname.startsWith("/wp-content/uploads/") && !images.includes(u.toString())) images.push(u.toString());
    }
    // Inline placeholder images (base64) are left out of the age-gate check: they are noise, not markup.
    const alcohol = AGE_GATE.test(block.replace(/data:[^"'\s)]*/g, "")) || [text, ...alts, ...images.map(fileWords)].some((s) => ALCOHOL.test(s));
    out.push({ id, ...datesFromText(text, today), alcohol, images });
  });
  return out;
}

/** This week's leaflets without alcohol, those already started first, cut to `maxPages` pages in all. `dropped`
 * counts the pages left out by the cap; `empty` the current leaflets whose pages couldn't be read. */
export function leclercLeaflets(listed: readonly ListedLeaflet[], today: string, maxPages = LECLERC_MAX_PAGES): { leaflets: LeafletRead[]; dropped: number; empty: number } {
  const current = listed.filter((l) => !l.alcohol && currentWeek(l.validFrom, l.validTo, today));
  const started = (l: ListedLeaflet) => (!l.validFrom || l.validFrom <= today ? 0 : 1);
  const ordered = current.map((l, i) => ({ l, i })).sort((a, b) => started(a.l) - started(b.l) || a.i - b.i).map((x) => x.l);
  const leaflets: LeafletRead[] = [];
  let room = maxPages;
  let dropped = 0;
  let empty = 0;
  for (const l of ordered) {
    if (l.images.length === 0) { empty++; continue; }
    const take = l.images.slice(0, Math.max(0, room));
    dropped += l.images.length - take.length;
    room -= take.length;
    if (take.length === 0) continue;
    const url = `${LECLERC_LISTING}#newspaper-${l.id}`;
    const title = l.validFrom && l.validTo ? `Gazetka E.Leclerc od ${dm(l.validFrom)} do ${dm(l.validTo)}.${l.validTo.slice(0, 4)}`
      : l.validTo ? `Gazetka E.Leclerc do ${dm(l.validTo)}.${l.validTo.slice(0, 4)}` : "Gazetka E.Leclerc";
    leaflets.push({
      leaflet: { title, url, ...(l.validFrom ? { validFrom: l.validFrom } : {}), ...(l.validTo ? { validTo: l.validTo } : {}) },
      products: [],
      pages: take.map((imageUrl, n) => ({ number: n + 1, imageUrl, url })),
      strategy: "all",
    });
  }
  return { leaflets, dropped, empty };
}

export const leclerc: ChainAdapter = {
  chain: "leclerc",
  hosts: LECLERC_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const r = await fetchOfficial(ctx, LECLERC_LISTING, LECLERC_HOSTS, "text/html");
    if (!r.ok) return r.read;
    const listed = parseListing(r.body.toString("utf8"), ctx.today);
    if (!listed) return { kind: "failed", reason: "unreadable_listing" };
    const { leaflets, dropped, empty } = leclercLeaflets(listed, ctx.today);
    if (leaflets.length === 0) return empty ? { kind: "failed", reason: "no_pages" } : { kind: "no_leaflet" };
    // Pages left out (the cap, a leaflet without readable pages) mean "nothing matched" can't be claimed.
    const incomplete = dropped ? "page_cap" : empty ? "some_leaflets_failed" : undefined;
    return { kind: "ok", leaflets, ...(incomplete ? { incomplete } : {}) };
  },
};
