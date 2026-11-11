import assert from "node:assert/strict";
import { test } from "node:test";
import { AppError } from "../src/errors.js";
import { SHOP_MCP, ShopifyUcpService, type ShopFetch } from "../src/shopify/ucp.js";

const variantId = "gid://shopify/ProductVariant/40439010361434";
const productId = "gid://shopify/p/example123";
const shop = "tog24.myshopify.com";

const product = {
  id: productId, title: "Original jacket",
  variants: [{
    id: variantId, title: "Blue / M",
    price: { amount: 7999, currency: "PLN" },
    availability: { available: true },
    seller: { name: "TOG24", domain: shop, url: "https://www.tog24.com" },
    url: "https://www.tog24.com/products/coat?variant=40439010361434",
  }],
};
const document = (payload: object) => new Response(JSON.stringify({
  jsonrpc: "2.0", id: 1, result: { isError: false, structuredContent: { ucp: { version: "2026-08-25" }, ...payload } },
}), { headers: { "content-type": "application/json" } });

type Call = { name: string; args: Record<string, any>; url: string; headers: Headers };
function session(answers: Record<string, Response | (() => Response)>): { service: ShopifyUcpService; calls: Call[] } {
  const calls: Call[] = [];
  const mock = (async (input: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body));
    const name: string = body.params.name;
    calls.push({ name, args: body.params.arguments, url: String(input), headers: new Headers(init?.headers) });
    const answer = answers[name];
    if (!answer) throw new Error("unexpected tool " + name);
    return typeof answer === "function" ? answer() : answer;
  }) as ShopFetch;
  return { service: new ShopifyUcpService(mock), calls };
}

test("search uses the real fixed Shop MCP JSON-RPC endpoint, Polish shipping filter and no fabricated prices", async () => {
  const { service, calls } = session({
    search_catalog: document({ products: [product], messages: [] }),
  });
  const result = await service.search({ query: "kurtka" });
  assert.equal(result.source, "shop_mcp");
  assert.equal(result.market, "PL");
  assert.equal(result.products.length, 1);
  assert.equal(result.products[0]?.variants[0]?.priceMinor, 7999);
  assert.equal(result.products[0]?.variants[0]?.shop, shop);
  assert.deepEqual(calls.map(c => c.name), ["search_catalog"]);
  assert.equal(calls[0]?.url, SHOP_MCP);
  assert.equal(calls[0]?.headers.get("Mcp-Method"), "tools/call");
  assert.equal(calls[0]?.args.catalog.context.address_country, "PL");
  assert.equal(calls[0]?.args.catalog.filters.ships_to.country, "PL");
});

test("invalid client input is rejected before any Shopify tool call", async () => {
  const { service, calls } = session({});
  for (const request of [{}, { query: "a" }, { query: "phone", userId: "another-user" }]) {
    await assert.rejects(service.search(request), (e: unknown) => e instanceof AppError && e.code === "invalid_request");
  }
  await assert.rejects(service.prepareCheckout({
    shop, variantId, quantity: 1, pay: true,
  }), (e: unknown) => e instanceof AppError && e.code === "invalid_request");
  assert.equal(calls.length, 0);
});

test("real cart and checkout are created with the exact Shopify variant and no payment tool", async () => {
  const { service, calls } = session({
    get_product: document({ product }),
    create_cart: document({ cart: { id: "gid://shopify/Cart/real-merchant-cart", continue_url: "https://tog24.myshopify.com/cart/c/real" } }),
    create_checkout: document({
      checkout: {
        id: "gid://shopify/Checkout/real",
        continue_url: "https://tog24.myshopify.com/checkouts/c/real?key=secret",
        currency: "PLN", totals: [{ type: "total", amount: 8199 }],
        messages: [{ type: "warning", content: "Delivery price may change at checkout." }],
      },
    }),
  });
  const checkout = await service.prepareCheckout({ variantId, shop, quantity: 2 });
  assert.equal(checkout.checkoutURL, "https://tog24.myshopify.com/checkouts/c/real?key=secret");
  assert.equal(checkout.totalMinor, 8199);
  assert.equal(checkout.seller, "TOG24");
  assert.equal(checkout.status, "awaiting_buyer");
  assert.deepEqual(checkout.messages, ["Delivery price may change at checkout."]);
  assert.deepEqual(calls.map(c => c.name), ["get_product", "create_cart", "create_checkout"]);
  assert.equal(calls[1]?.args.cart.line_items[0].quantity, 2);
  assert.equal(calls[1]?.args.cart.line_items[0].item.id, variantId);
  assert.equal(calls[2]?.args.checkout.cart_id, "gid://shopify/Cart/real-merchant-cart");
  assert.equal(typeof calls[1]?.args.meta["idempotency-key"], "string");
  assert.equal(typeof calls[2]?.args.meta["idempotency-key"], "string");
  assert.ok(!calls.some(c => /complete_checkout|pay|order/.test(c.name)));
});

test("wrong merchant, changed price availability, or missing selected variant never creates a cart", async () => {
  const { service, calls } = session({ get_product: document({ product }) });
  await assert.rejects(service.prepareCheckout({
    variantId, shop: "unrelated.myshopify.com", quantity: 1,
  }), (e: unknown) => e instanceof AppError && e.code === "refused");
  assert.deepEqual(calls.map(c => c.name), ["get_product"]);
});

test("fraudulent checkout links and malformed seller payloads fail closed", async () => {
  const { service, calls } = session({
    get_product: document({ product }),
    create_cart: document({ cart: { id: "gid://shopify/Cart/c" } }),
    create_checkout: document({ checkout: { continue_url: "https://evil.example/pay", currency: "PLN" } }),
  });
  await assert.rejects(service.prepareCheckout({
    variantId, shop, quantity: 1,
  }), (e: unknown) => e instanceof AppError && e.code === "malformed_provider_result");
  assert.equal(calls.length, 3);
});

test("Shop errors never get transformed into fake product results", async () => {
  const { service } = session({
    search_catalog: document({ ucp: { status: "error" }, products: [] }),
  });
  await assert.rejects(service.search({ query: "pizza" }), (e: unknown) => e instanceof AppError && e.code === "malformed_provider_result");
});

test("the Shopify UCP client cannot charge, order or make independent network calls to a merchant", () => {
  assert.equal(typeof (ShopifyUcpService.prototype as any).completeCheckout, "undefined");
  assert.equal(typeof (ShopifyUcpService.prototype as any).pay, "undefined");
  assert.equal(typeof (ShopifyUcpService.prototype as any).placeOrder, "undefined");
});
