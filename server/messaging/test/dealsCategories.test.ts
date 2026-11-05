// ADR-662: categories tell the code what kind of thing a query and a product are. Another family is no match
// ("masło shea" for "masło"); another kind in the same family is a similar product, kept apart and never counted
// as the item ("masło roślinne" for "masło", "kawa rozpuszczalna" for "kawa mielona"). Nothing here calls Anthropic.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { CATEGORIES, categoryOf, relation } from "../src/deals/categories.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { searchDeals } from "../src/deals/service.js";
import { DEFAULT_DEALS_SETTINGS, type ReadChain } from "../src/deals/types.js";
import { chainsWeb, FakeModel, read } from "./dealsFakes.js";

const NOW = () => new Date("2026-10-24T06:10:00.000Z");
const cat = (text: string) => categoryOf(text)?.id;

describe("what kind of thing a name is", () => {
  test("queries and leaflet names, inflected and with brands", () => {
    const cases: [string, string | undefined][] = [
      ["masło", "butter"], ["Masło Extra 82% 200 g", "butter"], ["Pilos Masło Ekstra 83%", "butter"],
      ["Masło shea do ciała", "body_lotion"], ["Masło orzechowe", "spread_sweet"], ["Masło roślinne Delma", "margarine"],
      ["mleko", "milk"], ["Mleko modyfikowane Bebilon 2", "baby_milk"], ["Mleko kokosowe", "coconut_milk"], ["Mleko owsiane Alpro", "plant_drink"],
      ["kawa mielona", "coffee_ground"], ["Kawa Jacobs Krönung 500 g", "coffee"], ["Kawa mrożona", "iced_tea"],
      ["Persil proszek do prania", "laundry_powder"], ["proszku do prania", "laundry"], ["Chusteczki nawilżane Pampers", "tissues"],
      ["Woda toaletowa", "perfume"], ["Serek wiejski", "cheese_white"], ["Kasza gryczana", "groats"], ["Szampan Dorato", "wine"],
      ["Szampon Head & Shoulders", "shampoo"], ["Jaja z wolnego wybiegu L", "eggs"], ["pieluchy rozmiar 4", "nappies"], ["szafran", undefined],
      ["Woda micelarna Garnier", "face"], ["Olej silnikowy 5W30", "car"], ["Karma dla kota z kurczakiem", "cat_food"],
    ];
    for (const [text, id] of cases) assert.equal(cat(text), id, text);
  });

  test("every word in the list names its own category, and ids are unique", () => {
    assert.equal(new Set(CATEGORIES.map((c) => c.id)).size, CATEGORIES.length);
    assert.ok(CATEGORIES.length >= 150);
    for (const c of CATEGORIES) for (const w of c.words) assert.equal(cat(w), c.id, `${c.id}: ${w}`);
  });

  test("the same, similar, another kind, or not known", () => {
    const of = (t: string) => categoryOf(t);
    assert.equal(relation(of("masło"), of("Masło Extra 82%")), "same");
    assert.equal(relation(of("masło"), of("Masło roślinne")), "similar");
    assert.equal(relation(of("masło"), of("Masło shea do ciała")), "other");
    assert.equal(relation(of("kawa"), of("Kawa ziarnista 1 kg")), "same", "the family's general word takes every kind");
    assert.equal(relation(of("kawa mielona"), of("Kawa Jacobs 500 g")), "same", "a product that doesn't say its kind could be it");
    assert.equal(relation(of("kawa mielona"), of("Kawa ziarnista 1 kg")), "similar");
    assert.equal(relation(of("mleko"), of("Mleko modyfikowane")), "other");
    assert.equal(relation(of("szafran"), of("Masło")), "unknown");
  });
});

describe("in a search", () => {
  async function search(items: string[], chains: ReadChain[], model?: FakeModel) {
    const web = chainsWeb();
    return (await searchDeals(
      { settings: { ...DEFAULT_DEALS_SETTINGS, maxPages: 5 }, fetcher: new PoliteFetcher({ fetch: web.fetch }), model, now: NOW },
      { items, chains, language: "pl" },
    )).response;
  }

  test("a page with butter, plant butter and shea butter: the first an offer, the second similar, the third nowhere", async () => {
    const model = new FakeModel().page("biedronka:2", { products: [
      read({ name: "Masło Extra 82%", size: "200 g", price: "4,99" }),
      read({ name: "Masło roślinne Delma", size: "250 g", price: "5,49" }),
      read({ name: "Masło shea do ciała", size: "100 ml", price: "9,99" }),
    ] });
    const r = await search(["masło"], ["biedronka"], model);
    assert.deepEqual(r.items[0]!.offers.map((o) => o.product), ["Masło Extra 82%"]);
    assert.deepEqual(r.items[0]!.similar?.map((o) => o.product), ["Masło roślinne Delma"]);
    assert.ok(!JSON.stringify(r).includes("shea"));
    assert.deepEqual(model.picks[0]!.candidates[0]!.map((c) => c.name), ["Masło Extra 82%"], "only the item's own candidates go to the pick");
  });

  test("Aldi's data: instant coffee is similar to ground coffee, and the same as coffee", async () => {
    const ground = await search(["kawa mielona"], ["aldi"]);
    assert.deepEqual(ground.items[0]!.offers.map((o) => o.product), ["Kawa mielona Premium"]);
    assert.deepEqual(ground.items[0]!.similar?.map((o) => o.product), ["Kawa rozpuszczalna Classic"], "its words don't match; its family does");
    const any = await search(["kawa"], ["aldi"]);
    assert.deepEqual(any.items[0]!.offers.map((o) => o.product).sort(), ["Kawa mielona Premium", "Kawa rozpuszczalna Classic"]);
    assert.equal(any.items[0]!.similar, undefined);
    const tea = await search(["herbata zielona"], ["aldi"]);
    assert.deepEqual(tea.items[0]!.offers, []);
    assert.equal(tea.items[0]!.similar, undefined, "coffee is another family: nothing similar");
    assert.equal(tea.chains[0]!.status, "no_match");
  });
});
