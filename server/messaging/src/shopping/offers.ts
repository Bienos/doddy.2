// Offers for a shopping errand (docs/implementation/SHOPPING.md 1, 1.1). Two ways in, both run by the
// code: an offer source (Google Shopping through Serper) and a shop page the code read itself. Every
// offer gets an id in the registry; the model only ever refers to offers by that id, so no price,
// shop, link or time in a result comes from the model.
import { shorten } from "../news/writer.js";
import { SHOPPING_LIMITS, LIMITS } from "../errands/schema.js";
import { parseMoney, type Money } from "./money.js";
import type { PageOffer } from "./pagecheck.js";

/** One offer as a source returned it, before the registry checks it. */
export interface RawOffer {
  title?: string;
  shop?: string;
  priceText?: string;
  link?: string;
  delivery?: string;
}

export type OfferSearch =
  | { kind: "ok"; offers: RawOffer[] }
  | { kind: "not_set_up" | "failed"; reason: string };

export interface OfferSource {
  readonly name: string;
  search(query: string, signal?: AbortSignal): Promise<OfferSearch>;
}

/** Google Shopping for Poland through Serper (google.serper.dev). One call per query. */
export class SerperOfferSource implements OfferSource {
  readonly name = "serper";
  constructor(
    private readonly apiKey: string | undefined,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly endpoint = "https://google.serper.dev/shopping",
  ) {}

  async search(query: string, signal?: AbortSignal): Promise<OfferSearch> {
    if (!this.apiKey) return { kind: "not_set_up", reason: "no offer source is set up on this server" };
    let res: Response;
    try {
      res = await this.fetchImpl(this.endpoint, {
        method: "POST",
        headers: { "X-API-KEY": this.apiKey, "content-type": "application/json" },
        body: JSON.stringify({ q: query, gl: "pl", hl: "pl", num: 20 }),
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(15_000)]) : AbortSignal.timeout(15_000),
      });
    } catch {
      return { kind: "failed", reason: "the offer source didn't answer" };
    }
    if (!res.ok) return { kind: "failed", reason: `the offer source answered ${res.status}` };
    let body: unknown;
    try { body = await res.json(); } catch { return { kind: "failed", reason: "the offer source's answer wasn't readable" }; }
    const list = (body as { shopping?: unknown })?.shopping;
    if (!Array.isArray(list)) return { kind: "ok", offers: [] };
    const s = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : undefined);
    return {
      kind: "ok",
      offers: list.slice(0, 20).map((r: Record<string, unknown>) => ({
        title: s(r.title), shop: s(r.source) ?? s(r.seller), priceText: s(r.price),
        link: s(r.link) ?? s(r.productLink), delivery: s(r.delivery),
      })),
    };
  }
}

export interface RegisteredOffer {
  id: string;
  title: string;
  shop: string;
  price: Money;
  delivery?: string;
  url: string;
  site?: string;
  evidence: "shop_page" | "listing";
  seenAt: string;
  gtin?: string;
}

/** The host without "www.", as the site label. */
export function siteLabel(url: string): string | undefined {
  try {
    const h = new URL(url).hostname.replace(/^www\./u, "");
    return h ? shorten(h, LIMITS.site) : undefined;
  } catch { return undefined; }
}

const httpsOrHttp = (u: string | undefined) => !!u && /^https?:\/\/\S+$/u.test(u) && u.length <= LIMITS.url;
const sameUrl = (a: string, b: string) => a.replace(/[#?].*$/u, "").replace(/\/$/u, "") === b.replace(/[#?].*$/u, "").replace(/\/$/u, "");

/** Every offer this run registered. Ids are o1, o2, … in order; at most `max`. */
export class OfferRegistry {
  private readonly offers: RegisteredOffer[] = [];
  private readonly shops = new Set<string>();
  /** Listings the source returned, counted whether or not they were registered (stats). */
  seen = 0;
  constructor(private readonly max = 60) {}

  get size() { return this.offers.length; }
  get shopCount() { return this.shops.size; }
  get(id: string) { return this.offers.find((o) => o.id === id); }
  list(): readonly RegisteredOffer[] { return this.offers; }

  private push(o: Omit<RegisteredOffer, "id">): RegisteredOffer | undefined {
    if (this.offers.length >= this.max) return undefined;
    const offer = { id: `o${this.offers.length + 1}`, ...o };
    this.offers.push(offer);
    this.shops.add(o.shop.toLocaleLowerCase("pl"));
    return offer;
  }

  /** A Google Shopping listing: kept only with a title, a shop, one readable price in a currency and a link. */
  addListing(raw: RawOffer, seenAt: Date): RegisteredOffer | undefined {
    this.seen++;
    const price = raw.priceText ? parseMoney(raw.priceText, "PLN") : undefined;
    if (!raw.title || !raw.shop || !price || !httpsOrHttp(raw.link)) return undefined;
    const link = raw.link as string;
    const dup = this.offers.find((o) => sameUrl(o.url, link) && o.shop === raw.shop && o.price.minor === price.minor);
    if (dup) return dup;
    return this.push({
      title: shorten(raw.title, SHOPPING_LIMITS.offerTitle), shop: shorten(raw.shop, SHOPPING_LIMITS.shop), price,
      delivery: raw.delivery ? shorten(raw.delivery, SHOPPING_LIMITS.delivery) : undefined,
      url: link, site: siteLabel(link), evidence: "listing", seenAt: seenAt.toISOString(),
    });
  }

  /**
   * A price the code read on the shop's own page. An earlier listing for the same address is upgraded
   * in place (same id) to `shop_page` with the page's price; otherwise a new offer is registered.
   */
  addShopPage(page: PageOffer, requestedUrl: string, seenAt: Date, titleHint?: string): RegisteredOffer | undefined {
    const url = httpsOrHttp(page.finalUrl) ? page.finalUrl : requestedUrl;
    const site = siteLabel(url);
    const shop = shorten(page.seller ?? site ?? "sklep", SHOPPING_LIMITS.shop);
    const title = shorten(page.name ?? titleHint ?? site ?? url, SHOPPING_LIMITS.offerTitle);
    const existing = this.offers.find((o) => sameUrl(o.url, url) || sameUrl(o.url, requestedUrl));
    if (existing) {
      existing.price = page.price;
      existing.evidence = "shop_page";
      existing.seenAt = seenAt.toISOString();
      existing.url = url;
      existing.site = site;
      if (page.gtin) existing.gtin = page.gtin;
      return existing;
    }
    return this.push({ title, shop, price: page.price, url, site, evidence: "shop_page", seenAt: seenAt.toISOString(), gtin: page.gtin });
  }
}
