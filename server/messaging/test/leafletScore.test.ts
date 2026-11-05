// The leaflet-reading scorer (ADR-661): a run's JSON against hand labels, with the service's own matcher.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { matchScore, MATCH_THRESHOLD, terms } from "../src/deals/match.js";

// The script is plain JavaScript beside the compiled tests (dist/test → ../../scripts).
const script = (await import(new URL("../../scripts/leaflet-score.mjs", import.meta.url).href)) as {
  grosze: (v: unknown) => number | undefined;
  score: (run: unknown, labels: unknown, match: (a: string, b: string) => boolean) => { counts: Record<string, number>; rates: Record<string, number | null> };
  renderScore: (result: unknown, run: unknown) => string;
};
const match = (a: string, b: string) => matchScore(terms(a), terms(b)) >= MATCH_THRESHOLD;
const zl = (minor: number) => ({ minor, currency: "PLN" });

describe("scoring a run against labels", () => {
  test("prices as printed in labels and as grosze in runs", () => {
    assert.equal(script.grosze("4,99"), 499);
    assert.equal(script.grosze("4.99 zł"), 499);
    assert.equal(script.grosze("5"), 500);
    assert.equal(script.grosze(zl(499)), 499);
    assert.equal(script.grosze(null), undefined);
    assert.equal(script.grosze("ok. 5"), undefined);
  });

  test("found, exact prices, conditions, products with no label, prices not printed, and whether check caught a wrong price", () => {
    const run = { chain: "biedronka", startedAt: "2026-10-29T08:00:00Z", pages: [
      { number: 4, status: "read", products: [
        { name: "Masło Extra 82%", price: zl(499), regularPrice: zl(649), lowest30d: null, conditionKinds: ["app"], check: false },
        { name: "Kawa mielona Jacobs 500 g", price: zl(2199), regularPrice: null, lowest30d: zl(2999), conditionKinds: [], check: true },
        { name: "Chleb żytni", price: zl(450), regularPrice: null, lowest30d: null, conditionKinds: [], check: false },
      ] },
      { number: 5, status: "refused", products: [] },
    ] };
    const labels = { chain: "biedronka", pages: [
      { number: 4, prices: ["4,99", "6,49", "21,99", "29,99"], offers: [
        { name: "Masło Extra 82% 200 g", price: "4,99", regularPrice: "6,49", conditions: ["app", "limit"] },
        { name: "Kawa mielona Jacobs Krönung 500 g", price: "19,99", lowest30d: "29,99", conditions: [] },
        { name: "Jogurt naturalny", price: "1,99", conditions: [] },
      ] },
      { number: 5, offers: [{ name: "Mleko", price: "3,29" }] },
    ] };
    const r = script.score(run, labels, match);
    assert.equal(r.counts.pagesScored, 1, "page 5 wasn't read, so it isn't scored");
    assert.equal(r.counts.labelledOffers, 3);
    assert.equal(r.counts.found, 2);
    assert.equal(r.counts.priceExact, 1);
    assert.equal(r.rates.priceExact, 0.5);
    assert.equal(r.rates.regularExact, 1);
    assert.equal(r.rates.lowest30dExact, 1);
    assert.equal(r.rates.conditionRecall, 0.5, "app found, limit missed");
    assert.equal(r.rates.conditionPrecision, 1);
    assert.equal(r.counts.unmatchedProducts, 1, "the bread has no label");
    assert.equal(r.counts.pricesNotPrinted, 1, "4,50 isn't printed on the page");
    assert.equal(r.rates.wrongPricesFlagged, 1, "the wrong coffee price was flagged check");
    assert.match(script.renderScore(r, run), /\| Price exact \| 50% \| 2 found \|/);
    assert.equal(r.rates.screenRecall, null, "a run without --screen has no screen recall");
  });

  test("screen recall: of the labelled pages with an offer that were screened, the share flagged", () => {
    const page = (number: number, screen?: string) => ({ number, status: "read", products: [], ...(screen ? { screen } : {}) });
    const run = { chain: "biedronka", pages: [page(1, "flagged"), page(2, "not_flagged"), page(3, "flagged"), page(4), page(5, "error")] };
    const labels = { pages: [1, 2, 3, 4, 5].map((number) => ({ number, offers: number === 3 ? [] : [{ name: "Masło", price: "4,99" }] })) };
    const r = script.score(run, labels, match);
    assert.equal(r.counts.screenedWithOffers, 2, "pages 1 and 2: page 3 has no offer, 4 wasn't screened, 5's screen failed");
    assert.equal(r.rates.screenRecall, 0.5);
    assert.match(script.renderScore(r, run), /\| Screen recall \(pages with an offer\) \| 50% \| 2 screened \|/);
  });
});
