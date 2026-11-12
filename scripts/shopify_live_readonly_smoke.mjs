// Live, read-only verification of Shopify's official Shop MCP API.
// This script MUST NOT create carts, checkouts, payments, accounts or orders.
// CI is opt-in in .github/workflows/shopify-ucp-readonly.yml; no buyer data, credentials,
// private links or user-specific queries are sent to Shopify.
import assert from "node:assert/strict";
import { ShopifyUcpService } from "../backend/dist/src/shopify/ucp.js";

const service = new ShopifyUcpService();
const started = Date.now();
const result = await service.search({ query: "rain jacket" });

assert.equal(result.source, "shop_mcp", "Not a real Shop MCP response");
assert.equal(result.market, "PL", "Unexpected market");
assert.ok(Array.isArray(result.products), "Missing provider products");
assert.ok(Array.isArray(result.messages), "Missing provider disclosures");

const variants = result.products.flatMap((p) => p.variants);
for (const v of variants) {
  assert.ok(v.variantId.startsWith("gid://shopify/ProductVariant/"), "Invalid merchant variant");
  assert.ok(/^[A-Z]{3}$/.test(v.currency), "Unrecognized currency");
  assert.ok(Number.isSafeInteger(v.priceMinor) && v.priceMinor >= 0, "Invalid real price");
  assert.ok(/^[a-z0-9.-]+\.[a-z]{2,}$/.test(v.shop), "Missing merchant shop");
  assert.ok(v.available === true, "Unexpected sold-out offer");
}

// A 200 JSON response with zero usable products may mean the catalog has no
// Polish shipping offers, or the parser is incompatible. Treat that as needing
// explicit human review, not a successful integration.
assert.ok(variants.length > 0, "Shop MCP returned no usable Polish-market Shopify offers");

console.log(JSON.stringify({
  verification: "live_shop_mcp_catalog_read_only",
  source: result.source,
  market: result.market,
  usableOfferCount: variants.length,
  warningCount: result.messages.length,
  elapsedMs: Date.now() - started,
  noWrites: true,
  noPaymentOrOrder: true,
}));
