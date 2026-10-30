// ADR-668: a partner link on an offer's own page, only where a programme covers its host, added after the picks.
// The answer is the same with or without it, offer for offer, in the same order. Nothing reaches a shop or Anthropic.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { searchDeals } from "../src/deals/service.js";
import { DEFAULT_DEALS_SETTINGS, type ChainAdapter, type DataProduct, type DealsResponse, type ReadChain } from "../src/deals/types.js";
import { AffiliateLinks } from "../src/shopping/affiliate.js";
import { FakeWeb, ResponseSchema } from "./dealsFakes.js";

const product = (name: string, zl: number, url: string): DataProduct => ({ name, price: { minor: zl * 100, currency: "PLN" }, conditions: [], url });
const adapter = (chain: ReadChain, products: DataProduct[]): ChainAdapter => ({
  chain, hosts: [],
  read: async () => ({ kind: "ok", leaflets: [{ leaflet: { title: chain, url: products[0]!.url }, products, pages: [], strategy: "none" }] }),
});
const adapters = {
  ccc: adapter("ccc", [product("adidas BREAKNET, sneakersy damskie", 199, "https://ccc.eu/pl/pl/p/adidas-breaknet-1"), product("JENNY, sneakersy damskie", 47, "https://ccc.eu/pl/pl/p/jenny-2")]),
  aldi: adapter("aldi", [product("Sneakersy damskie", 59, "https://www.aldi.pl/oferty.html")]),
} as Partial<Record<ReadChain, ChainAdapter>>;

async function run(affiliate?: AffiliateLinks): Promise<DealsResponse> {
  const { response } = await searchDeals(
    { settings: DEFAULT_DEALS_SETTINGS, fetcher: new PoliteFetcher({ fetch: new FakeWeb().fetch }), adapters, now: () => new Date("2026-10-30T08:00:00Z"), ...(affiliate ? { affiliate } : {}) },
    { items: ["sneakersy damskie"], chains: ["aldi", "ccc"], language: "pl" },
  );
  return response;
}

describe("partner links on offers", () => {
  test("only the covered shop's offers get one; everything else is the same, in the same order", async () => {
    const plain = await run();
    const partner = await run(new AffiliateLinks([{ host: "ccc.eu", template: "https://network.example/click?id=7&to={url}" }]));
    const offers = partner.items[0]!.offers;
    assert.ok(offers.length >= 2);
    for (const o of offers) {
      if (o.chain === "ccc") assert.equal(o.buyUrl, `https://network.example/click?id=7&to=${encodeURIComponent(o.source.url)}`);
      else assert.equal(o.buyUrl, undefined, "no programme for aldi.pl: no partner link");
    }
    const strip = (r: DealsResponse) => ({ ...r, items: r.items.map((i) => ({ ...i, offers: i.offers.map(({ buyUrl: _b, ...o }) => o) })) });
    assert.deepEqual(strip(partner), plain, "the same offers, prices and order with or without partner links");
    assert.ok(plain.items[0]!.offers.every((o) => o.buyUrl === undefined));
    const parsed = ResponseSchema.safeParse(partner);
    assert.ok(parsed.success, JSON.stringify(parsed.error?.issues));
  });
});
