import { randomUUID } from "node:crypto";
import { z } from "zod";
import { AppError } from "../errors.js";

/**
 * Live Shopify shopping through Shop MCP (UCP). One fixed official server; no user-selected
 * HTTP endpoints and NO demo fallback. Anonymous catalog, cart and checkout tools are available.
 * No complete_checkout, payment instruments, card data, order placement or Shop OAuth here.
 *
 * Primary sources checked 2026-11-11:
 *   https://shop.dev/docs/quickstart
 *   https://shop.dev/docs/tools
 *   https://shop.dev/docs/checkout
 * REST Global Catalog was retired 2026-11-02; never use it.
 */
export const SHOP_MCP = "https://mcp.shop.com/";
export const SHOP_MCP_VERSION = "2026-07-28";
export const SHOP_COUNTRY = "PL";
export const SHOP_CURRENCY = "PLN";

const Search = z.object({
  query: z.string().trim().min(2).max(160),
}).strict();

const Prepare = z.object({
  variantId: z.string().min(15).max(500).regex(/^gid:\/\/shopify\/ProductVariant\/[A-Za-z0-9?=&_:.%-]+$/),
  /** The merchant domain returned by Shop MCP, never an arbitrary URL to fetch. */
  shop: z.string().min(4).max(180).regex(/^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$/),
  quantity: z.number().int().min(1).max(10),
}).strict();

interface ShopVariant {
  variantId: string;
  title: string;
  merchant: string;
  shop: string;
  priceMinor: number;
  currency: string;
  available: boolean;
  productURL: string | null;
}
interface ShopProduct {
  productId: string;
  title: string;
  variants: ShopVariant[];
}
interface MerchantCheckout {
  checkoutURL: string;
  shop: string;
  seller: string;
  currency: string | null;
  totalMinor: number | null;
  /** Warnings and legally significant disclosures returned by the merchant. */
  messages: string[];
  /** Never claim an order exists or that a payment happened. */
  status: "awaiting_buyer";
}
type JsonObj = Record<string, unknown>;
export type ShopFetch = typeof fetch;

function obj(value: unknown): JsonObj | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as JsonObj : null;
}
function asString(value: unknown, cap = 300): string | null {
  return typeof value === "string" && value.length > 0 && value.length <= cap ? value : null;
}
function positiveMinor(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : null;
}
function safeHttps(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2048) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.port || url.username || url.password || url.hash) return null;
    const host = url.hostname.toLowerCase();
    if (!host.includes(".") || host === "localhost" || host.endsWith(".localhost")
        || host.endsWith(".local") || host.endsWith(".internal") || /^[\d.]+$/.test(host)
        || host.includes(":")) return null;
    return url.toString();
  } catch { return null; }
}
function textList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 10).flatMap(v => {
    const m = obj(v);
    const text = m && asString(m.content, 350);
    return text ? [text] : [];
  });
}
function parseVariant(value: unknown): ShopVariant | null {
  const v = obj(value);
  if (!v) return null;
  const seller = obj(v.seller);
  const price = obj(v.price);
  if (!seller || !price) return null;
  const variantId = asString(v.id, 500);
  const shop = asString(seller.domain, 180);
  const merchant = asString(seller.name, 160);
  const amount = positiveMinor(price.amount);
  const currency = asString(price.currency, 3);
  if (!variantId?.startsWith("gid://shopify/ProductVariant/") || !shop || !merchant
      || !shop.match(/^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$/)
      || amount === null || !currency?.match(/^[A-Z]{3}$/)) return null;
  // Do not represent externally indexed listings as native Shopify checkout candidates.
  if (v.source === "external" || v.id?.toString().startsWith("gid://catalog/")) return null;
  const availability = obj(v.availability);
  return {
    variantId, title: asString(v.title, 160) ?? "",
    merchant, shop, priceMinor: amount, currency,
    available: availability?.available === true,
    productURL: safeHttps(v.url),
  };
}
function parseProduct(value: unknown): ShopProduct | null {
  const p = obj(value);
  const productId = p && asString(p.id, 500);
  const title = p && asString(p.title, 250);
  if (!productId || !title || !productId.startsWith("gid://shopify/p/")) return null;
  const variants = Array.isArray(p?.variants) ? p.variants.map(parseVariant).filter((v): v is ShopVariant => !!v).slice(0, 8) : [];
  if (!variants.length) return null;
  return { productId, title, variants };
}
function readCheckoutResult(value: unknown, shop: string, merchant: string): MerchantCheckout {
  const root = obj(value);
  const d = obj(root?.checkout) ?? root;
  if (!d) throw new AppError("malformed_provider_result");
  const url = safeHttps(d.continue_url);
  if (!url) throw new AppError("malformed_provider_result");
  const host = new URL(url).hostname.toLowerCase();
  // The checkout's bearer URL must belong to the merchant (or Shopify's own Shop service).
  if (host !== shop && host !== "shop.app" && !host.endsWith(".shop.app")
      && host !== "checkout.shopify.com" && !host.endsWith(".myshopify.com")) {
    throw new AppError("malformed_provider_result");
  }
  const totals = Array.isArray(d.totals) ? d.totals : [];
  const sum = totals.map(obj).find(t => t?.type === "total");
  const totalMinor = positiveMinor(sum?.amount);
  return {
    checkoutURL: url, shop, seller: merchant,
    currency: asString(d.currency, 3), totalMinor,
    messages: textList(d.messages),
    status: "awaiting_buyer",
  };
}

export class ShopifyUcpService {
  private readonly send: ShopFetch;
  constructor(fetcher: ShopFetch = fetch) { this.send = fetcher; }

  private async call(name: "search_catalog" | "get_product" | "create_cart" | "create_checkout", args: JsonObj): Promise<JsonObj> {
    let response: Response;
    try {
      response = await this.send(SHOP_MCP, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "accept": "application/json, text/event-stream",
          "MCP-Protocol-Version": SHOP_MCP_VERSION,
          "Mcp-Method": "tools/call",
          "Mcp-Name": name,
        },
        redirect: "error",
        signal: AbortSignal.timeout(7_000),
        body: JSON.stringify({
          jsonrpc: "2.0", id: 1, method: "tools/call",
          params: {
            name, arguments: args,
            _meta: {
              "io.modelcontextprotocol/protocolVersion": SHOP_MCP_VERSION,
              "io.modelcontextprotocol/clientInfo": { name: "DODDY", version: "0.1.0" },
              "io.modelcontextprotocol/clientCapabilities": {},
            },
          },
        }),
      });
    } catch {
      throw new AppError("provider_timeout");
    }
    if (response.status === 429) throw new AppError("rate_limited");
    if (!response.ok) throw new AppError("provider_unavailable");
    let json: JsonObj | null;
    try {
      const data = await response.text();
      if (Buffer.byteLength(data, "utf8") > 512 * 1024) throw new Error("large response");
      json = obj(JSON.parse(data));
    } catch { throw new AppError("malformed_provider_result"); }
    const result = obj(json?.result);
    if (json?.error || !result || result.isError === true) throw new AppError("provider_unavailable");
    const doc = obj(result.structuredContent);
    if (!doc || obj(doc.ucp)?.status === "error") throw new AppError("malformed_provider_result");
    return doc;
  }

  /** Genuine merchant offers; never generated by an LLM or local fixtures. */
  async search(body: unknown): Promise<{ products: ShopProduct[]; messages: string[]; source: "shop_mcp"; market: "PL" }> {
    const parsed = Search.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");
    const doc = await this.call("search_catalog", {
      catalog: {
        query: parsed.data.query,
        context: { address_country: SHOP_COUNTRY, currency: SHOP_CURRENCY, language: "pl" },
        filters: { available: true, ships_to: { country: SHOP_COUNTRY } },
        pagination: { limit: 10 },
      },
    });
    if (!Array.isArray(doc.products)) throw new AppError("malformed_provider_result");
    return {
      products: doc.products.slice(0, 10).map(parseProduct).filter((p): p is ShopProduct => !!p),
      messages: textList(doc.messages),
      source: "shop_mcp", market: "PL",
    };
  }

  /** Creates a real merchant cart AND checkout, but does not pay or place an order. */
  async prepareCheckout(body: unknown): Promise<MerchantCheckout> {
    const parsed = Prepare.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");
    const { variantId, shop, quantity } = parsed.data;

    // Read the selected offer again, rather than trusting the client-supplied shop/price.
    const found = await this.call("get_product", {
      catalog: { id: variantId, context: { address_country: SHOP_COUNTRY, currency: SHOP_CURRENCY },
        filters: { ships_to: { country: SHOP_COUNTRY }, available: true } },
    });
    const rootProduct = obj(found.product);
    const product = rootProduct ? parseProduct(rootProduct) : null;
    const alternatives = Array.isArray(found.products) ? found.products.map(parseProduct).filter((p): p is ShopProduct => !!p) : [];
    const offer = [ ...(product ? [product] : []), ...alternatives]
      .flatMap(p => p.variants).find(v => v.variantId === variantId && v.shop === shop && v.available);
    if (!offer) throw new AppError("refused", { message: "This product or merchant is no longer available. Search again." });

    // Shop MCP is the only egress endpoint, independent of the merchant domain.
    // A new UUID per operation avoids duplicate cart/checkout writes on retried requests.
    // Never auto-retry after a timeout: a cart or checkout may have been created.
    const cart = await this.call("create_cart", {
      shop, cart: {
        line_items: [{ quantity, item: { id: variantId } }],
        context: { address_country: SHOP_COUNTRY },
      },
      meta: { "idempotency-key": randomUUID() },
    });
    const cartDoc = obj(cart.cart) ?? cart;
    const cartId = asString(cartDoc.id, 500);
    if (!cartId || !cartId.startsWith("gid://shopify/Cart/")) {
      throw new AppError("malformed_provider_result");
    }

    const checkout = await this.call("create_checkout", {
      shop,
      checkout: { cart_id: cartId, line_items: [] },
      meta: { "idempotency-key": randomUUID() },
    });
    const result = readCheckoutResult(checkout, shop, offer.merchant);
    if (result.currency && result.currency !== offer.currency) {
      // Merchant chooses final currency. The result must be shown as quoted, not the search price.
      return result;
    }
    return result;
  }
}
