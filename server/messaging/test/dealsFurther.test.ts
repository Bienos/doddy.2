// "Search further" under a leaflet answer (ADR-666): links for the person to open, built from the request alone,
// after the picks. Nothing here is fetched and nothing calls Anthropic.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { DEFAULT_SEARCH_SHOPS, furtherSearch, parseSearchShops, searchUrl, searchWords } from "../src/deals/further.js";
import { searchDeals, type DealsDeps } from "../src/deals/service.js";
import { DEFAULT_DEALS_SETTINGS, READ_CHAINS } from "../src/deals/types.js";
import { AffiliateLinks } from "../src/shopping/affiliate.js";
import { chainsWeb, FakeModel, read, ResponseSchema } from "./dealsFakes.js";

const [allegro, ceneo] = DEFAULT_SEARCH_SHOPS as [typeof DEFAULT_SEARCH_SHOPS[0], typeof DEFAULT_SEARCH_SHOPS[0]];

describe("search further", () => {
  test("the shops: Allegro then Ceneo by default, the setting's order otherwise, {} for none", () => {
    assert.deepEqual(parseSearchShops("").map((s) => s.name), ["Allegro", "Ceneo"]);
    assert.deepEqual(parseSearchShops("{}"), []);
    assert.deepEqual(parseSearchShops('{"Ceneo": "https://www.ceneo.pl/;szukaj-{q}", "Allegro": "https://allegro.pl/listing?string={q}"}').map((s) => s.name), ["Ceneo", "Allegro"]);
    assert.throws(() => parseSearchShops('{"A": "https://a.example/{q}/{q}"}'), /exactly one \{q\}/);
  });

  test("a shop's search gets the item's words without the rule words, percent-encoded and joined with +", () => {
    assert.equal(searchWords("masło tylko Łaciate"), "masło Łaciate");
    assert.equal(searchWords("mleko bez laktozy"), "mleko bez laktozy", "'bez laktozy' is what the item is");
    assert.equal(searchUrl(allegro, "kawa ziarnista 1 kg"), "https://allegro.pl/listing?string=kawa+ziarnista+1+kg");
    assert.equal(searchUrl(ceneo, "masło Łaciate"), "https://www.ceneo.pl/;szukaj-mas%C5%82o+%C5%81aciate");
    assert.equal(searchUrl(allegro, "M&M's  #1"), "https://allegro.pl/listing?string=M%26M's+%231", "nothing in the words can add a parameter");
    assert.equal(searchUrl(allegro, "   "), undefined);
  });

  test("leaflets of the chains Doddy doesn't read that weren't asked for, and the shops for every item", () => {
    const f = furtherSearch(["masło", "kawa ziarnista"], READ_CHAINS, { shops: DEFAULT_SEARCH_SHOPS })!;
    assert.deepEqual(f.leaflets.map((l) => l.chain), ["kaufland", "carrefour", "auchan", "netto"]);
    assert.equal(f.leaflets[0]!.url, "https://www.kaufland.pl/gazetka-promocyjna.html");
    assert.deepEqual(f.searches.map((s) => [s.item, s.links.map((l) => l.shop)]), [["masło", ["Allegro", "Ceneo"]], ["kawa ziarnista", ["Allegro", "Ceneo"]]]);
    assert.ok(f.searches.every((s) => s.links.every((l) => l.buyUrl === undefined)), "no partner link without a programme");
    const asked = furtherSearch(["masło"], ["biedronka", "kaufland", "netto"], { shops: [] })!;
    assert.deepEqual(asked.leaflets.map((l) => l.chain), ["carrefour", "auchan"], "a chain already in the answer's own rows isn't repeated");
    assert.deepEqual(asked.searches, []);
    assert.equal(furtherSearch(["masło"], ["kaufland", "carrefour", "auchan", "netto"], { shops: [] }), undefined, "nothing to suggest: no block");
  });

  test("a partner link only where a programme covers the shop's host, and it never adds, drops or moves a shop", () => {
    const affiliate = new AffiliateLinks([{ host: "allegro.pl", template: "https://network.example/click?id=7&to={url}" }]);
    const plain = furtherSearch(["kawa"], READ_CHAINS, { shops: DEFAULT_SEARCH_SHOPS })!;
    const partner = furtherSearch(["kawa"], READ_CHAINS, { shops: DEFAULT_SEARCH_SHOPS, affiliate })!;
    const [a, c] = partner.searches[0]!.links as [{ shop: string; url: string; buyUrl?: string }, { shop: string; url: string; buyUrl?: string }];
    assert.equal(a.buyUrl, `https://network.example/click?id=7&to=${encodeURIComponent("https://allegro.pl/listing?string=kawa")}`);
    assert.equal(c.buyUrl, undefined, "Ceneo has no programme here");
    assert.deepEqual(partner.searches[0]!.links.map(({ shop, url }) => ({ shop, url })), plain.searches[0]!.links, "same shops, same order, same plain addresses");
    assert.deepEqual(partner.leaflets, plain.leaflets);
  });

  test("in a search: the block comes last and changes nothing else; without its setting there is none", async () => {
    const model = () => new FakeModel().page("biedronka:2", { products: [read({ name: "Masło Extra 82%", size: "200 g", price: "4,99" })] });
    const run = (further?: DealsDeps["further"]) => searchDeals(
      { settings: { ...DEFAULT_DEALS_SETTINGS, maxPages: 5 }, fetcher: new PoliteFetcher({ fetch: chainsWeb().fetch }), model: model(),
        now: () => new Date("2026-10-24T06:10:00.000Z"), ...(further ? { further } : {}) },
      { items: ["masło"], chains: ["biedronka"], language: "pl" },
    );
    const without = await run();
    const affiliate = new AffiliateLinks([{ host: "allegro.pl", template: "https://network.example/click?id=7&to={url}" }]);
    const withIt = await run({ shops: DEFAULT_SEARCH_SHOPS, affiliate });
    assert.equal(without.response.further, undefined);
    const { further, ...rest } = withIt.response;
    assert.deepEqual(rest, without.response, "offers, chains and their order are the same with or without it");
    assert.deepEqual(further!.searches[0]!.links.map((l) => l.shop), ["Allegro", "Ceneo"]);
    const parsed = ResponseSchema.safeParse(withIt.response);
    assert.ok(parsed.success, JSON.stringify(parsed.error?.issues));
  });
});
