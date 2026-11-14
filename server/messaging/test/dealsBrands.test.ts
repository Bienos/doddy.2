// Brands and models (13 Nov 2026; decision docs/decisions/2026-11-13-leaflet-results-and-deal-watches.md): "słuchawki
// Apple" found nothing because a leaflet prints "Apple AirPods 4" without "słuchawki". A query naming a brand matches a
// product that names it and is the same thing; a query naming the thing matches a product named only by its brand or
// model; the same thing of another brand is only ever "similar", never the item. Pure code, no model.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { brandsOf, MARKS, marksIn, markThing, queryMarks, thingOf } from "../src/deals/brands.js";
import { CATEGORIES } from "../src/deals/categories.js";
import { normalize } from "../src/deals/match.js";
import { itemOffers, searchDeals, type ChainMaterial } from "../src/deals/service.js";
import { itemKinds } from "../src/deals/specialty.js";
import { DEFAULT_DEALS_SETTINGS, type LeafletRead, type Offer, type ReadChain } from "../src/deals/types.js";
import type { ReadProduct } from "../src/deals/vision.js";
import type { CatalogStore, ChainSnapshot } from "../src/deals/catalog.js";

const NOW = new Date("2026-11-13T09:00:00.000Z");
const TODAY = "2026-11-13";
const ids = (text: string) => marksIn(text).map((m) => m.id).sort();

describe("the list of brands and models", () => {
  test("every mark has a unique id, names that survive normalising, and things that are categories", () => {
    assert.equal(new Set(MARKS.map((m) => m.id)).size, MARKS.length);
    const cats = new Set(CATEGORIES.map((c) => c.id));
    const marks = new Set(MARKS.map((m) => m.id));
    for (const m of MARKS) {
      assert.ok(m.names.length > 0, m.id);
      for (const n of m.names) assert.ok(normalize(n).length > 0, `${m.id}: ${n}`);
      for (const t of m.things) assert.ok(cats.has(t), `${m.id}: ${t} is not a category`);
      assert.ok(marks.has(m.brand), `${m.id}: its brand ${m.brand} is a mark`);
    }
    assert.ok(MARKS.length >= 150, "a sensible list for the Polish market");
    for (const brand of ["airpods", "kinder", "pampers", "lego", "philips", "bosch", "playstation", "iphone", "nutella", "coca_cola", "tymbark",
      "zywiec", "milka", "lavazza", "fairy", "persil", "ariel", "jacobs", "prince_polo", "pepsi"]) {
      assert.ok(marks.has(brand), brand);
    }
  });

  test("names are found the way the matcher finds words: endings yes, shorter words and shared starts no", () => {
    assert.deepEqual(ids("Apple AirPods 4"), ["airpods", "apple"]);
    assert.deepEqual(ids("Pampersy Active Baby 4"), ["pampers"]);
    assert.deepEqual(ids("Czekolada Milki"), ["milka"]);
    assert.deepEqual(ids("Kawa Lavazzy"), ["lavazza"]);
    assert.deepEqual(ids("piwo z Żywca"), ["zywiec"], "an inflection whose stem moves is a name of its own");
    assert.deepEqual(ids("Alpro Oat Milk"), [], "'milk' is shorter than Milka: not Milka");
    assert.deepEqual(ids("Legowisko dla psa"), [], "not Lego");
    assert.deepEqual(ids("Pad DualSense do PS5"), ["playstation"]);
    assert.deepEqual(ids("Chipsy Lay's Max"), ["lays"]);
    assert.deepEqual(ids("COCA-COLA Zero 1,5 l"), ["coca_cola"]);
  });

  test("a longer name wins its place: Galaxy Buds are not also Galaxy, Żywiec Zdrój is water, not beer; a model names its maker", () => {
    assert.deepEqual(ids("Samsung Galaxy Buds 3"), ["galaxy_buds", "samsung"]);
    assert.deepEqual(ids("Woda Żywiec Zdrój niegazowana"), ["zywiec_zdroj"]);
    assert.deepEqual(ids("Kinder Bueno 43 g"), ["kinder", "kinder_bueno"]);
    assert.deepEqual([...brandsOf(marksIn("AirPods Pro 2"))], ["apple"]);
  });

  test("what a product is: its own clear words first, then the one thing its brand or model is", () => {
    assert.equal(thingOf("Apple AirPods 4").thing?.id, "headphones");
    assert.equal(thingOf("Apple AirPods 4").from, "mark");
    assert.equal(thingOf("Ciastka Milka Choco").thing?.id, "biscuits", "the leaflet's word beats the brand's usual thing");
    assert.equal(thingOf("Finish Quantum tabletki 40 szt.").thing?.id, "dishwasher", "'tabletki' alone is only a guess at 'tablet'");
    assert.equal(thingOf("Apple 20W ładowarka").thing, undefined, "Apple makes many things");
    assert.equal(markThing(marksIn("Kinder")), undefined);
    assert.equal(queryMarks("AirPods").thing?.id, "headphones");
    assert.deepEqual([...queryMarks("słuchawki Apple").brands], ["apple"]);
  });

  test("a pet-food brand alone asks the pet shops, as 'karma dla kota' does", () => {
    assert.ok(itemKinds(["Whiskas"]).has("pets"));
    assert.ok(!itemKinds(["Milka"]).has("pets"));
  });
});

// ---------- in a search ----------

/** One leaflet page whose reader read these products (test data, not real prices). */
function material(products: [string, number][]): ChainMaterial {
  const leaflet: LeafletRead = {
    leaflet: { title: "Gazetka", url: "https://shop.example/gazetka", validFrom: "2026-11-10", validTo: "2026-11-16" },
    products: [], pages: [{ number: 1, imageUrl: "https://img.example/1.png", url: "https://shop.example/gazetka#1" }], strategy: "all",
  };
  const reads: ReadProduct[] = products.map(([name, minor]) => ({ name, price: { minor, currency: "PLN" }, conditions: [], lowConfidence: false }));
  return { leaflets: [leaflet], reads: new Map([["0:1", reads]]), promos: new Map(), complete: true, reasons: new Set(), readAt: NOW.toISOString() };
}

const LEAFLET: [string, number][] = [
  ["Słuchawki bezprzewodowe Apple AirPods Pro 2", 99900],
  ["Apple AirPods 4", 59900],
  ["Słuchawki JBL Tune 520BT", 14999],
  ["Apple iPhone 16 128 GB", 399900],
  ["Pampers Active Baby 4, 76 szt.", 6999],
  ["Pieluchy Dada Extra Soft 4", 3999],
  ["Kawa mielona Jacobs Krönung 500 g", 2499],
  ["Lavazza Qualità Rossa 250 g", 1999],
  ["Kinder Bueno 43 g", 299],
  ["Milka Alpine Milk 100 g", 549],
  ["Baton Prince Polo 35 g", 199],
  ["Klocki Cobi Czołg", 12999],
  ["LEGO City 60414 Remiza", 34999],
];

const names = (offers: Offer[]) => offers.map((o) => [o.product, o.match]);

describe("brand and model matches in a leaflet", () => {
  const find = (item: string) => names(itemOffers(item, "biedronka", material(LEAFLET), TODAY, "pl"));

  test("'słuchawki Apple' finds Apple's headphones that don't say 'słuchawki', and never an iPhone", () => {
    assert.deepEqual(find("słuchawki Apple"), [["Słuchawki bezprzewodowe Apple AirPods Pro 2", "exact"], ["Apple AirPods 4", "brand"]]);
  });

  test("'AirPods' finds AirPods only; JBL's headphones are not AirPods", () => {
    assert.deepEqual(find("AirPods"), [["Słuchawki bezprzewodowe Apple AirPods Pro 2", "exact"], ["Apple AirPods 4", "exact"]]);
  });

  test("the reverse: 'słuchawki' finds headphones of any brand, also those named only by their model", () => {
    assert.deepEqual(find("słuchawki"), [
      ["Słuchawki bezprzewodowe Apple AirPods Pro 2", "exact"], ["Apple AirPods 4", "brand"], ["Słuchawki JBL Tune 520BT", "exact"],
    ]);
    assert.deepEqual(find("pieluchy"), [["Pampers Active Baby 4, 76 szt.", "brand"], ["Pieluchy Dada Extra Soft 4", "exact"]]);
    assert.deepEqual(find("kawa"), [["Kawa mielona Jacobs Krönung 500 g", "exact"], ["Lavazza Qualità Rossa 250 g", "brand"]]);
    assert.deepEqual(find("czekolada"), [["Milka Alpine Milk 100 g", "brand"]]);
    assert.deepEqual(find("klocki"), [["Klocki Cobi Czołg", "exact"], ["LEGO City 60414 Remiza", "brand"]]);
  });

  test("Polish endings on a brand: 'pampersy' are Pampers", () => {
    assert.deepEqual(find("pampersy"), [["Pampers Active Baby 4, 76 szt.", "exact"]]);
  });

  test("an item that names a brand never gets another brand as the item, even when its other words match", () => {
    assert.deepEqual(find("kawa mielona Lavazza"), [["Lavazza Qualità Rossa 250 g", "brand"]], "Jacobs isn't Lavazza");
    assert.deepEqual(find("klocki Lego"), [["LEGO City 60414 Remiza", "brand"]], "Cobi isn't Lego");
    assert.deepEqual(find("Kinder"), [["Kinder Bueno 43 g", "exact"]], "a brand of many things alone: its products only, nothing similar");
  });
});

describe("brand matches through the whole search", () => {
  class OneSnapshot implements CatalogStore {
    constructor(private readonly s: ChainSnapshot) {}
    async snapshots(chains: readonly ReadChain[]) { return new Map(chains.includes(this.s.chain) ? [[this.s.chain, this.s]] : []); }
  }
  const snapshot: ChainSnapshot = {
    chain: "biedronka", scannedAt: NOW.toISOString(), complete: true, reasons: [],
    leaflets: [material(LEAFLET).leaflets[0]!],
    reads: { "0:1": { products: [...material(LEAFLET).reads.get("0:1")!], promotions: [], readAt: "2026-11-13T05:45:00.000Z" } },
  };
  const search = (items: string[]) => searchDeals(
    { settings: DEFAULT_DEALS_SETTINGS, now: () => NOW, catalog: new OneSnapshot(snapshot) }, { items, chains: ["biedronka"], language: "pl" });

  test("the item's own and brand matches are its offers; the same thing of another brand is similar, labelled, never the item", async () => {
    const { response } = await search(["AirPods", "kawa mielona Lavazza"]);
    const [airpods, lavazza] = response.items;
    assert.deepEqual(airpods!.offers.map((o) => [o.product, o.match]), [["Apple AirPods 4", "exact"], ["Słuchawki bezprzewodowe Apple AirPods Pro 2", "exact"]]);
    assert.deepEqual(airpods!.similar?.map((o) => [o.product, o.match]), [["Słuchawki JBL Tune 520BT", "similar"]]);
    assert.deepEqual(lavazza!.offers.map((o) => [o.product, o.match]), [["Lavazza Qualità Rossa 250 g", "brand"]]);
    assert.deepEqual(lavazza!.similar?.map((o) => [o.product, o.match]), [["Kawa mielona Jacobs Krönung 500 g", "similar"]]);
    assert.equal(JSON.stringify(response).includes("iPhone"), false);
  });

  test("each offer says when its page was read, the leaflet's dates, and that the chain was read whole", async () => {
    const { response } = await search(["słuchawki"]);
    for (const o of response.items[0]!.offers) {
      assert.deepEqual(o.leafletRead, { readAt: "2026-11-13T05:45:00.000Z", validFrom: "2026-11-10", validTo: "2026-11-16", complete: true });
    }
    assert.deepEqual(response.chains[0], { chain: "biedronka", status: "checked", leaflet: snapshot.leaflets[0]!.leaflet, readAt: NOW.toISOString(), complete: true });
  });
});
