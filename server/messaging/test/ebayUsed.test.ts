import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { EbayUsedOfferSource, UsedGoodsOfferRouter } from "../src/shopping/ebay.js";
import type { OfferSource } from "../src/shopping/offers.js";

const token = { access_token: "test-token-123456789", expires_in: 7200 };
const results = { itemSummaries: [
  { title: "Used headphones", price: { value: "199.99", currency: "PLN" }, itemWebUrl: "https://www.ebay.pl/itm/123" },
  { title: "Fake redirect", price: { value: "10", currency: "PLN" }, itemWebUrl: "https://ebay.pl.evil.test/itm/1" },
  { title: "Malformed price", price: { value: "-12", currency: "PLN" }, itemWebUrl: "https://www.ebay.pl/itm/2" },
] };

describe("read-only eBay used-goods offers", () => {
  test("no credentials: no network request and no guessed products", async () => {
    const fetchImpl = (async () => { throw new Error("must not fetch"); }) as typeof fetch;
    const out = await new EbayUsedOfferSource(undefined, undefined, fetchImpl).search("used headphones");
    assert.equal(out.kind, "not_set_up");
  });

  test("OAuth application token, Browse API filtering, safe results, and token caching", async () => {
    const calls: Array<{url: string; init?: RequestInit}> = [];
    const fetchImpl = (async (url: string | URL | Request, init?: RequestInit) => {
      calls.push({ url: String(url), init });
      return new Response(JSON.stringify(calls.length === 1 ? token : results), { status: 200 });
    }) as typeof fetch;
    const source = new EbayUsedOfferSource("app-id", "app-secret", fetchImpl, () => 1_000);
    const first = await source.search("używane słuchawki");
    assert.deepEqual(first, {kind: "ok", offers: [
      { title: "Used headphones", shop: "eBay", priceText: "PLN 199.99", link: "https://www.ebay.pl/itm/123" },
    ]});
    assert.equal(calls[0]?.url, "https://api.ebay.com/identity/v1/oauth2/token");
    assert.equal(calls[0]?.init?.method, "POST");
    const query = new URL(calls[1]!.url);
    assert.equal(query.host, "api.ebay.com");
    assert.equal(query.searchParams.get("filter"), "conditions:{USED}");
    assert.equal(query.searchParams.get("q"), "używane słuchawki");
    assert.equal((calls[1]!.init?.headers as Record<string, string>)["X-EBAY-C-MARKETPLACE-ID"], "EBAY_PL");
    await source.search("używane słuchawki");
    assert.equal(calls.length, 3, "second query must reuse token; no extra auth call");
  });

  test("provider rejection is not treated as empty successful search", async () => {
    const fetchImpl = (async () => new Response("not authorized", {status: 401})) as typeof fetch;
    const result = await new EbayUsedOfferSource("app-id", "app-secret", fetchImpl).search("used coat");
    assert.deepEqual(result, {kind: "failed", reason: "eBay search unavailable"});
  });
});

describe("used-goods router", () => {
  const source = (name: string, offered: string): OfferSource => ({
    name,
    async search() { return { kind: "ok", offers: [{title: offered, shop: name, priceText: "100 zł", link: "https://example.com"}]}; },
  });
  test("ordinary queries keep existing source, used queries include eBay", async () => {
    let ebayCalls = 0;
    const ebay: OfferSource = {name: "ebay", async search() {
      ebayCalls++;
      return {kind:"ok", offers: [{title:"Used item", shop:"eBay", priceText:"80 zł", link:"https://www.ebay.pl/itm/1"}]};
    }};
    const router = new UsedGoodsOfferRouter(source("google", "New item"), ebay);
    const ordinary = await router.search("słuchawki");
    assert.equal(ordinary.kind, "ok");
    assert.equal(ebayCalls, 0);
    const used = await router.search("używane słuchawki");
    assert.equal(used.kind, "ok");
    if (used.kind === "ok") assert.equal(used.offers.length, 2);
    assert.equal(ebayCalls, 1);
  });
});
