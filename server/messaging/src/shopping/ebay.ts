// Read-only eBay Browse API source for second-hand shopping errands.
// No credential is sent to the iPhone, no automatic purchase, no scraping and no affiliate claim.
// eBay prices are leads only: the shopping runner still verifies a shop page before displaying a price.
import type { OfferSearch, OfferSource, RawOffer } from "./offers.js";

interface Token { value: string; expiresAt: number }
const SCOPE = "https://api.ebay.com/oauth/api_scope";
const EBAY_HOST = /(^|\.)ebay\.(pl|com|co\.uk|de|fr|it|es|nl|at|be|ch|ie|com\.au|ca)$/iu;

function itemLink(input: unknown): string | undefined {
  if (typeof input !== "string") return;
  try {
    const u = new URL(input);
    return u.protocol === "https:" && EBAY_HOST.test(u.hostname) ? u.toString() : undefined;
  } catch { return; }
}

function itemPrice(input: unknown): string | undefined {
  if (!input || typeof input !== "object") return;
  const price = input as { value?: unknown; currency?: unknown };
  if (typeof price.value !== "string" || !/^\d{1,9}(\.\d{1,2})?$/u.test(price.value)) return;
  if (price.currency !== "PLN" && price.currency !== "EUR" && price.currency !== "USD") return;
  return price.currency + " " + price.value;
}

export class EbayUsedOfferSource implements OfferSource {
  readonly name = "ebay-used";
  private token?: Token;

  constructor(
    private readonly clientId: string | undefined,
    private readonly clientSecret: string | undefined,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly now: () => number = Date.now,
  ) {}

  private async accessToken(signal?: AbortSignal): Promise<string> {
    if (this.token && this.token.expiresAt > this.now() + 60_000) return this.token.value;
    const response = await this.fetchImpl("https://api.ebay.com/identity/v1/oauth2/token", {
      method: "POST",
      headers: {
        Authorization: "Basic " + Buffer.from(this.clientId + ":" + this.clientSecret).toString("base64"),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ grant_type: "client_credentials", scope: SCOPE }),
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(10_000)]) : AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error("ebay token rejected");
    const body: unknown = await response.json();
    const token = body as { access_token?: unknown; expires_in?: unknown };
    if (typeof token?.access_token !== "string" || token.access_token.length < 8 ||
        typeof token.expires_in !== "number" || token.expires_in <= 60) throw new Error("invalid ebay token");
    this.token = { value: token.access_token, expiresAt: this.now() + token.expires_in * 1000 };
    return this.token.value;
  }

  async search(query: string, signal?: AbortSignal): Promise<OfferSearch> {
    if (!this.clientId || !this.clientSecret) return { kind: "not_set_up", reason: "eBay is not connected" };
    const q = query.trim().slice(0, 120);
    if (!q) return { kind: "ok", offers: [] };
    try {
      const token = await this.accessToken(signal);
      const url = new URL("https://api.ebay.com/buy/browse/v1/item_summary/search");
      url.searchParams.set("q", q);
      url.searchParams.set("limit", "10");
      // eBay Buy API requires same-market delivery filtering for shopper results.
      url.searchParams.set("filter", "conditions:{USED},deliveryCountry:PL");
      const response = await this.fetchImpl(url, {
        headers: {
          Authorization: "Bearer " + token,
          "X-EBAY-C-MARKETPLACE-ID": "EBAY_PL",
          "Accept-Language": "pl-PL",
        },
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(10_000)]) : AbortSignal.timeout(10_000),
      });
      if (!response.ok) return { kind: "failed", reason: "eBay search unavailable" };
      const body: unknown = await response.json();
      const rows = (body as { itemSummaries?: unknown })?.itemSummaries;
      if (!Array.isArray(rows)) return { kind: "ok", offers: [] };
      const offers: RawOffer[] = [];
      for (const row of rows.slice(0, 10)) {
        if (!row || typeof row !== "object") continue;
        const item = row as { title?: unknown; itemWebUrl?: unknown; price?: unknown };
        const link = itemLink(item.itemWebUrl);
        const priceText = itemPrice(item.price);
        if (!link || !priceText || typeof item.title !== "string" || !item.title.trim()) continue;
        offers.push({ title: item.title.slice(0, 160), shop: "eBay", priceText, link });
      }
      return { kind: "ok", offers };
    } catch {
      return { kind: "failed", reason: "eBay search unavailable" };
    }
  }
}

/** Keep the existing Google Shopping behavior. Only search eBay when the query requests used goods. */
export class UsedGoodsOfferRouter implements OfferSource {
  readonly name = "shopping-and-used";
  constructor(private readonly primary: OfferSource, private readonly secondHand: OfferSource) {}

  async search(query: string, signal?: AbortSignal): Promise<OfferSearch> {
    const used = /\b(?:używan\w*|uzywan\w*|używk\w*|z\s+drugiej\s+ręki|second[\s-]?hand|pre[\s-]?owned|used|vinted|ebay)\b/iu.test(query);
    if (!used) return this.primary.search(query, signal);
    const [first, second] = await Promise.all([
      this.primary.search(query, signal), this.secondHand.search(query, signal),
    ]);
    if (first.kind === "ok" && second.kind === "ok") {
      return { kind: "ok", offers: [...first.offers, ...second.offers].slice(0, 25) };
    }
    if (first.kind === "ok") return first;
    if (second.kind === "ok") return second;
    return first.kind === "failed" ? first : second;
  }
}
