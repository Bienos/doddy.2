import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { ShopifyUcpService, type ShopFetch } from "../src/shopify/ucp.js";
import { harness, type Harness } from "./helpers.js";

let h: Harness | undefined;
afterEach(async () => { if (h) { await h.close(); h = undefined; } });

test("Shopify search requires a Doddy session, doesn't log query and returns only provider results", async () => {
  const requests: string[] = [];
  const remote = (async (_input: unknown, init?: RequestInit) => {
    const request = JSON.parse(String(init?.body));
    requests.push(request.params.name);
    return new Response(JSON.stringify({
      jsonrpc: "2.0", id: 1,
      result: { isError: false, structuredContent: {
        ucp: { version: "2026-08-25" },
        products: [], messages: [],
      } },
    }));
  }) as ShopFetch;
  h = await harness({ shopify: new ShopifyUcpService(remote) });
  const denied = await h.call("POST", "/v1/shopify/search", { token: null, body: { query: "personal shopping request" } });
  assert.equal(denied.status, 401);
  assert.equal(requests.length, 0);
  const valid = await h.call("POST", "/v1/shopify/search", { body: { query: "personal shopping request" } });
  assert.equal(valid.status, 200, valid.text);
  assert.equal(valid.body.source, "shop_mcp");
  assert.deepEqual(valid.body.products, []);
  assert.deepEqual(requests, ["search_catalog"]);
  assert.doesNotMatch(h.logs.join("\n"), /personal shopping request/);
});

test("Shopify checkout rejects malformed or extra fields before contacting provider", async () => {
  const requests: string[] = [];
  const remote = (async (_input: unknown, init?: RequestInit) => {
    requests.push(String(init?.body));
    throw new Error("Should not call Shop MCP for invalid checkout");
  }) as ShopFetch;
  h = await harness({ shopify: new ShopifyUcpService(remote) });
  const invalid = await h.call("POST", "/v1/shopify/checkout", {
    body: { variantId: "gid://shopify/ProductVariant/1234", shop: "store.myshopify.com", quantity: 1, pay: true },
  });
  assert.equal(invalid.status, 400, invalid.text);
  assert.equal(requests.length, 0);
});

test("without a configured live Shopify service, the server never returns mock catalog products", async () => {
  h = await harness();
  const missing = await h.call("POST", "/v1/shopify/search", { body: { query: "shoe" } });
  assert.equal(missing.status, 404);
  assert.equal(missing.body.error.code, "not_found");
});
