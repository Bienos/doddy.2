/**
 * Food order pages (decision docs/decisions/2026-11-12-food-restaurant-pages.md): when a place search or a web
 * search returns a restaurant's own page on a delivery app people in Poland use, Doddy keeps that exact link so
 * `open_food_app` can open the restaurant's page instead of the app's front page. Doddy never orders through
 * these sites: none of them lets an app order for someone without a partner agreement, so the person orders on
 * the page themselves.
 *
 * Only exact provider hosts (or their subdomains) count, over https, with a path beyond the front page, so text
 * in a listing can never pass for an order page. The link is data: Doddy offers it, never follows instructions
 * in it. The iPhone checks the same hosts again before anything opens (`FoodApps.page` in DoddyCore).
 */

export interface FoodPlatform {
  /** The name Doddy says, e.g. "Wolt". The same names `open_food_app` takes. */
  readonly name: string;
  /** Registrable hosts; a subdomain of one also counts (e.g. "www.pyszne.pl"). */
  readonly hosts: readonly string[];
}

/** Read 12 Nov 2026. The same list, by name, as `FoodApps.all` in DoddyCore; a test in each keeps them equal. */
export const FOOD_PLATFORMS: readonly FoodPlatform[] = [
  { name: "Uber Eats", hosts: ["ubereats.com"] },
  { name: "Wolt", hosts: ["wolt.com"] },
  { name: "Glovo", hosts: ["glovoapp.com"] },
  { name: "Bolt Food", hosts: ["food.bolt.eu"] },
  { name: "Pyszne.pl", hosts: ["pyszne.pl"] },
];

export interface FoodPage {
  readonly platform: string;
  readonly url: string;
}

const MAX_URL = 300;

/**
 * The order page a link points to, or null when it isn't a page of a platform above. The query and the
 * fragment are dropped (tracking and sessions), and a bare front page is not a restaurant page.
 */
export function foodPage(link: unknown): FoodPage | null {
  if (typeof link !== "string" || link.length > MAX_URL) return null;
  let url: URL;
  try {
    url = new URL(link.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password || url.port) return null;
  const host = url.hostname.toLowerCase();
  const platform = FOOD_PLATFORMS.find((p) => p.hosts.some((h) => host === h || host.endsWith(`.${h}`)));
  if (!platform) return null;
  if (url.pathname.replace(/\/+$/, "") === "") return null;
  url.hash = "";
  url.search = "";
  return { platform: platform.name, url: url.toString() };
}

/**
 * A Google listing's order link. Listings answer in different shapes, so a few likely fields are read
 * (`order_online`, `order_url`, `delivery`, `menu`, `website`, and the same names under `links`); the first that
 * is an order page on a platform above wins. Anything else, including a place's own website, is ignored. The
 * field names are not confirmed against Monid's live answers (12 Nov 2026): web results carry the same pages.
 */
export function listingFoodPage(listing: Record<string, unknown>): FoodPage | null {
  const links = typeof listing.links === "object" && listing.links !== null && !Array.isArray(listing.links) ? (listing.links as Record<string, unknown>) : {};
  for (const source of [listing, links]) {
    for (const key of ["order_online", "order_url", "delivery", "menu", "website"]) {
      const page = foodPage(source[key]);
      if (page) return page;
    }
  }
  return null;
}

/** The line Doddy reads after results that include an order page. */
export const FOOD_PAGE_NOTE =
  "An order page is the restaurant's own page on a delivery app, where the person orders themselves; Doddy has ordered nothing. Offer it, and pass the exact address as page to open_food_app only if the person wants to order there. Never state a price, menu or delivery time from an order page.";
