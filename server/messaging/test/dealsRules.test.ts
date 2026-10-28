// ADR-664: the person's own rules in an item. "masło tylko Łaciate" keeps only products naming Łaciate; "mleko bez
// laktozy" only products saying "bez laktozy". The rest of the words match as before. Nothing here calls Anthropic.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { itemRules, meetsRules } from "../src/deals/match.js";
import { searchDeals } from "../src/deals/service.js";
import { DEFAULT_DEALS_SETTINGS } from "../src/deals/types.js";
import { chainsWeb, FakeModel, read } from "./dealsFakes.js";

describe("rules in the item's words", () => {
  test("'tylko' and 'bez', in Polish and English; the rest are the item", () => {
    const r = itemRules("masło tylko Łaciate");
    assert.equal(r.words, "masło");
    assert.equal(r.search, "masło Łaciate");
    assert.ok(meetsRules(r, "Masło Łaciate 82% 200 g"));
    assert.ok(!meetsRules(r, "Masło Extra 82% 200 g"));
    const lactose = itemRules("mleko bez laktozy");
    assert.equal(lactose.words, "mleko bez laktozy", "'bez laktozy' is part of what the item is");
    assert.ok(meetsRules(lactose, "Mleko UHT bez laktozy 3,2% 1 l"));
    assert.ok(!meetsRules(lactose, "Mleko UHT 3,2% 1 l laktoza"), "the word alone isn't the phrase");
    const pampers = itemRules("pieluchy tylko Pampers rozmiar 4");
    assert.equal(pampers.words, "pieluchy rozmiar 4", "the word after 'tylko' is the rule; the words after it are the item again");
    assert.equal(pampers.search, "pieluchy rozmiar 4 Pampers");
    assert.ok(meetsRules(pampers, "Pieluchy Pampers Premium Care 4"));
    assert.ok(!meetsRules(pampers, "Pieluchy Dada 4"));
    assert.ok(meetsRules(itemRules("nappies only Pampers"), "Pampers Baby-Dry 4"));
    assert.deepEqual(itemRules("kawa mielona").required, []);
    assert.ok(meetsRules(itemRules("kawa mielona"), "anything"));
    assert.equal(itemRules("tylko").words, "tylko", "a rule word with nothing after it is just a word");
  });

  test("in a search: only the brand asked for, the similar list follows the rule too", async () => {
    const model = new FakeModel().page("biedronka:2", { products: [
      read({ name: "Masło Łaciate 82%", size: "200 g", price: "6,49" }),
      read({ name: "Masło Extra 82%", size: "200 g", price: "4,99" }),
      read({ name: "Masło roślinne Delma", size: "250 g", price: "5,49" }),
    ] });
    const web = chainsWeb();
    const { response } = await searchDeals(
      { settings: { ...DEFAULT_DEALS_SETTINGS, maxPages: 5 }, fetcher: new PoliteFetcher({ fetch: web.fetch }), model, now: () => new Date("2026-10-24T06:10:00.000Z") },
      { items: ["masło tylko Łaciate"], chains: ["biedronka"], language: "pl" },
    );
    assert.equal(response.items[0]!.query, "masło tylko Łaciate", "the item is answered in the person's words");
    assert.deepEqual(response.items[0]!.offers.map((o) => o.product), ["Masło Łaciate 82%"]);
    assert.equal(response.items[0]!.similar, undefined, "Delma isn't Łaciate");
    assert.deepEqual(model.reads[0]!.queries, ["masło tylko Łaciate"], "the reader gets the whole item, rule included");
  });
});
