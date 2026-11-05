// "Search further" under a leaflet answer (ADR-666, docs/implementation/SHOPPING.md "Search further"): the
// leaflets of the chains Doddy doesn't read that weren't asked for, and for each item a link to its search
// page at a few online shops. Nothing here is fetched: these are addresses for the person to open. They are
// built from the request alone, after the offers are picked, so they can't change a pick, an order or a
// sentence. The shops come from DEALS_SEARCH_SHOPS (default: Allegro, then Ceneo), always in that order. A
// partner link (ADR-612, AFFILIATE_LINKS) is added last, when a programme covers the shop's host; it never
// adds, removes or moves a shop.
import { itemRules } from "./match.js";
import { LINK_CHAINS, LINK_ONLY_URLS, type Chain, type Further, type SearchLink } from "./types.js";

export interface SearchShop { name: string; template: string }

/** A shop's search page with `{q}` where the item's words go. Allegro reads them from its query string and
 * Ceneo from its path; both take the words percent-encoded and joined with "+". */
export const DEFAULT_SEARCH_SHOPS: readonly SearchShop[] = [
  { name: "Allegro", template: "https://allegro.pl/listing?string={q}" },
  { name: "Ceneo", template: "https://www.ceneo.pl/;szukaj-{q}" },
];
export const MAX_SEARCH_SHOPS = 4;
const MAX_URL = 600;

/**
 * `{"Allegro": "https://allegro.pl/listing?string={q}"}`: a shop's name and an https template with exactly one
 * `{q}`, in the order they are shown. Empty: the defaults; `{}`: no shop links. Throws a message naming the
 * problem so a bad setting stops the server at start.
 */
export function parseSearchShops(json: string): SearchShop[] {
  if (!json.trim()) return [...DEFAULT_SEARCH_SHOPS];
  let raw: unknown;
  try { raw = JSON.parse(json); } catch { throw new Error("DEALS_SEARCH_SHOPS must be a JSON object of shop name to https template"); }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("DEALS_SEARCH_SHOPS must be a JSON object of shop name to https template");
  const entries = Object.entries(raw as Record<string, unknown>);
  if (entries.length > MAX_SEARCH_SHOPS) throw new Error(`DEALS_SEARCH_SHOPS has more than ${MAX_SEARCH_SHOPS} shops`);
  return entries.map(([name, template]) => {
    if (!/^\S(.{0,38}\S)?$/u.test(name)) throw new Error("DEALS_SEARCH_SHOPS: a shop name must be 1 to 40 characters");
    if (typeof template !== "string" || template.length > 300 || template.split("{q}").length !== 2) {
      throw new Error(`DEALS_SEARCH_SHOPS: the template for ${name} needs exactly one {q} and at most 300 characters`);
    }
    let parsed: URL;
    try { parsed = new URL(template.replace("{q}", "x")); } catch { throw new Error(`DEALS_SEARCH_SHOPS: the template for ${name} is not an address`); }
    if (parsed.protocol !== "https:") throw new Error(`DEALS_SEARCH_SHOPS: the template for ${name} must be https`);
    return { name, template };
  });
}

export interface FurtherDeps {
  shops: readonly SearchShop[];
  affiliate?: { link(pageUrl: string): string | undefined };
}

/** The words a shop's search gets: the item without its rule words ("masło tylko Łaciate" → "masło Łaciate"). */
export function searchWords(query: string): string {
  return itemRules(query).search.trim();
}

export function searchUrl(shop: SearchShop, words: string): string | undefined {
  const q = words.split(/\s+/u).filter(Boolean).map(encodeURIComponent).join("+");
  if (!q) return undefined;
  const url = shop.template.replace("{q}", () => q);
  return /^https:\/\/\S+$/u.test(url) && url.length <= MAX_URL ? url : undefined;
}

/** Undefined when there is nothing to suggest (no shops set and every chain asked for). */
export function furtherSearch(items: readonly string[], requested: readonly Chain[], deps: FurtherDeps): Further | undefined {
  const asked = new Set<string>(requested);
  const leaflets = LINK_CHAINS.filter((c) => !asked.has(c)).map((chain) => ({ chain, url: LINK_ONLY_URLS[chain] }));
  const searches = items.flatMap((query) => {
    const words = searchWords(query);
    const links = deps.shops.flatMap((shop): SearchLink[] => {
      const url = searchUrl(shop, words);
      if (!url) return [];
      const buyUrl = deps.affiliate?.link(url);
      return [{ shop: shop.name, url, ...(buyUrl ? { buyUrl } : {}) }];
    });
    return links.length ? [{ item: query, links }] : [];
  });
  return leaflets.length || searches.length ? { leaflets, searches } : undefined;
}
