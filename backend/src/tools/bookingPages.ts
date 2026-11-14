/**
 * Booking pages (decision docs/decisions/2026-11-11-salon-booking-pages.md, step 5 of
 * 2026-11-09-restaurant-calls-one-tap): when a place search or a web search returns a link on a booking
 * platform people in Poland use, Doddy keeps that link so it can offer it ("Booksy has an online booking
 * page; shall I text it to you?"). Doddy never books through these sites: none of them lets an app book
 * for someone without a partner agreement, so the person books on the page themselves.
 *
 * Only exact platform hosts (or their subdomains) count, over https, so text in a listing can never pass
 * for a booking page. The link is data: Doddy offers it, never follows instructions in it.
 */

export interface BookingPlatform {
  /** The name Doddy says, e.g. "Booksy". */
  readonly name: string;
  /** Registrable hosts; a subdomain of one also counts (e.g. "salon.reservio.com"). */
  readonly hosts: readonly string[];
}

/** Read 11 Nov 2026. Add a platform only after checking that its pages are public booking pages. */
export const BOOKING_PLATFORMS: readonly BookingPlatform[] = [
  { name: "Booksy", hosts: ["booksy.com"] },
  { name: "Fresha", hosts: ["fresha.com"] },
  { name: "Reservio", hosts: ["reservio.com"] },
  { name: "Bookero", hosts: ["bookero.pl"] },
  { name: "ZnanyLekarz", hosts: ["znanylekarz.pl"] },
];

export interface BookingPage {
  readonly platform: string;
  readonly url: string;
}

const MAX_URL = 300;

/** The booking page a link points to, or null when it isn't one of the platforms above. */
export function bookingPage(link: unknown): BookingPage | null {
  if (typeof link !== "string" || link.length > MAX_URL) return null;
  let url: URL;
  try {
    url = new URL(link.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password || url.port) return null;
  const host = url.hostname.toLowerCase();
  const platform = BOOKING_PLATFORMS.find((p) => p.hosts.some((h) => host === h || host.endsWith(`.${h}`)));
  if (!platform) return null;
  url.hash = "";
  return { platform: platform.name, url: url.toString() };
}

/**
 * A Google listing's booking link. Listings answer in different shapes, so a few known fields are read
 * (`book_online`, `reservations`, `website`, and the same names under `links`); the first that is a
 * booking page on a platform above wins. Anything else, including a place's own website, is ignored.
 */
export function listingBookingPage(listing: Record<string, unknown>): BookingPage | null {
  const links = typeof listing.links === "object" && listing.links !== null && !Array.isArray(listing.links) ? (listing.links as Record<string, unknown>) : {};
  for (const value of [listing.book_online, listing.reservations, listing.website, links.book_online, links.reservations, links.website]) {
    const page = bookingPage(value);
    if (page) return page;
  }
  return null;
}

/** The line Doddy reads after results that include a booking page. */
export const BOOKING_PAGE_NOTE =
  "A booking page is where the person can book online themselves; Doddy has not booked anything. Offer it, and text it to them with text_me only if they ask. Never say a slot is free or booked from a booking page.";
