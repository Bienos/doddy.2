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

// Production checkout revalidates the exact variant using lookup_catalog. Exercise
// that same genuinely READ-ONLY Shop MCP tool without creating a cart or checkout.
// A search-only pass must not conceal a broken lookup → checkout handoff.
const selected = variants[0];
const lookupStart = Date.now();
const lookupReply = await fetch("https://mcp.shop.com/", {
  method: "POST",
  redirect: "error",
  signal: AbortSignal.timeout(7_000),
  headers: {
    "content-type": "application/json",
    "accept": "application/json, text/event-stream",
    "MCP-Protocol-Version": "2026-07-28",
    "Mcp-Method": "tools/call",
    "Mcp-Name": "lookup_catalog",
  },
  body: JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: "lookup_catalog",
      arguments: {
        catalog: {
          ids: [selected.variantId],
          context: { address_country: "PL", currency: "PLN" },
          filters: { ships_to: { country: "PL" }, available: true },
        },
      },
      _meta: {
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientInfo": { name: "DODDY", version: "0.1.0" },
        "io.modelcontextprotocol/clientCapabilities": {},
      },
    },
  }),
});
assert.ok(lookupReply.ok, `Shop MCP lookup HTTP ${lookupReply.status}`);
const lookupJson = await lookupReply.json();
assert.ok(!lookupJson.error, "Shop MCP lookup JSON-RPC error");
assert.equal(lookupJson.result?.isError, false, "Shop MCP lookup returned an error");
const lookupDocument = lookupJson.result?.structuredContent;
assert.notEqual(lookupDocument?.ucp?.status, "error", "Shop MCP lookup rejected this variant");
assert.ok(Array.isArray(lookupDocument?.products), "Shop MCP lookup has no products");
const lookupVariants = lookupDocument.products.flatMap((p) => p.variants ?? []);
assert.ok(
  lookupVariants.some((v) => v.id === selected.variantId
    && v.seller?.domain === selected.shop && v.availability?.available === true),
  "Shop MCP could not reverify the exact selected variant and merchant",
);

console.log(JSON.stringify({
  verification: "live_shop_mcp_catalog_read_only",
  source: result.source,
  market: result.market,
  usableOfferCount: variants.length,
  exactVariantLookupVerified: true,
  lookupMs: Date.now() - lookupStart,
  warningCount: result.messages.length,
  elapsedMs: Date.now() - started,
  noWrites: true,
  noPaymentOrOrder: true,
}));
