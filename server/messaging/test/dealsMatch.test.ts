// Matching items to leaflet products, pack sizes and unit prices (all code, no model), and the model's pick
// (ids only) with a fake model.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  headMention, matchScore, MATCH_THRESHOLD, normalize, parsePrintedUnitPrice, parseSize, pickWithModel, stem, terms, unitPrice, unitPricesAgree,
} from "../src/deals/match.js";
import { FakeModel } from "./dealsFakes.js";

const score = (q: string, name: string) => matchScore(terms(q), terms(name));
const zl = (minor: number) => ({ minor, currency: "PLN" as const });

describe("Polish-aware matching", () => {
  test("normalising: lowercase, ł and other Polish letters folded, digits split from units", () => {
    assert.equal(normalize("Masło EXTRA 82% 200g"), "maslo extra 82 200 g");
    assert.equal(normalize("ŁOWICKIE Żółty ser"), "lowickie zolty ser");
    assert.equal(normalize("Kawa mielona 2x500g"), "kawa mielona 2 x 500 g");
    assert.equal(stem("kawy"), "kaw");
    assert.equal(stem(normalize("masła")), "masl");
    assert.equal(stem("ser"), "ser");
  });

  test("the same thing in other forms matches; different things sharing a word don't", () => {
    const yes: [string, string][] = [
      ["masło", "Masło ekstra 82% Łowickie 250g"],
      ["maslo", "Masło Extra 82% 200 g"],
      ["masło", "Pilos Masło Ekstra 83%"],
      ["kawa mielona", "Kawa mielona Jacobs Kronung 550g"],
      ["kawa", "Wszystkie kawy Lavazza"],
      ["jajka", "Jaja z wolnego wybiegu 10 szt."],
      ["pieluchy rozmiar 4", "Pampers Premium Care pieluchy, 9-14 kg, rozmiar 4, 52 szt."],
      ["pieluchy rozmiar 4", "Babydream EKO pieluchy, 4 Maxi, 8-14 kg, 30 szt."],
      ["sok jabłkowy", "Sok jabłkowy Tymbark 1l"],
    ];
    for (const [q, name] of yes) assert.ok(score(q, name) >= MATCH_THRESHOLD, `${q} ~ ${name}: ${score(q, name)}`);
    const no: [string, string][] = [
      ["kawa mielona", "Kawa ziarnista Jacobs Crema 1,1kg"],
      ["kawa mielona", "Mięso mielone wieprzowe 500 g"],
      ["kawa", "Kawior z łososia"],
      ["masło", "Maślanka naturalna 1 l"],
      ["pieluchy rozmiar 4", "Babydream Premium pieluchy, 5 Junior, 10-16 kg, 68 szt."],
      ["pieluchy rozmiar 4", "Pampers Premium Care pieluchy, 3, 6-10 kg, 60 szt."],
      ["4", "Masło 4 kostki"],
    ];
    for (const [q, name] of no) assert.ok(score(q, name) < MATCH_THRESHOLD, `${q} !~ ${name}: ${score(q, name)}`);
    assert.equal(score("kawa mielona", "Kawa mielona Jacobs"), score("kawa mielona", "Kawa mielona Jacobs Kronung Crema 550 g"),
      "only the item's words count: a longer product name isn't penalised");
  });

  test("a page is worth reading when its text names the item's first word", () => {
    assert.ok(headMention(terms("kawa mielona"), terms("Miksuj Dowolnie Wszystkie Kawy Lavazza Limit")) > 0);
    assert.equal(headMention(terms("kawa mielona"), terms("Pilos Ser Gouda Kawałku Xxl")), 0);
  });
});

describe("sizes and unit prices", () => {
  test("pack sizes as leaflets and shops write them", () => {
    const cases: [string, ReturnType<typeof parseSize>][] = [
      ["200 g", { value: 200, unit: "g" }],
      ["Masło Extra 82% 200 g", { value: 200, unit: "g" }],
      ["2,25 l", { value: 2.25, unit: "l" }],
      ["Napój gaz. Pepsi Cola zero 2,25l", { value: 2.25, unit: "l" }],
      ["50 szt.", { value: 50, unit: "szt" }],
      ["Pieluchy rozmiar 4, 50 szt.", { value: 50, unit: "szt" }],
      ["4 x 100 g", { value: 400, unit: "g" }],
      ["Kawa mielona MK Cafe Premium 2x500g", { value: 1000, unit: "g" }],
      ["Kawa zbożowa Anatol 20x4,2g", { value: 84, unit: "g" }],
      ["Kawa ziarnista Jacobs Crema 1,1kg", { value: 1.1, unit: "kg" }],
      ["Wino 0,75l 10%", { value: 0.75, unit: "l" }],
      ["Sok jabłkowy Tymbark 1l", { value: 1, unit: "l" }],
      ["10 dag", { value: 100, unit: "g" }],
      ["500 ml", { value: 500, unit: "ml" }],
      ["pieluchy, 9-14 kg, rozmiar 4", undefined],
      ["Masło 82%", undefined],
      [undefined as unknown as string, undefined],
    ];
    for (const [text, want] of cases) assert.deepEqual(parseSize(text), want, text);
  });

  test("unit prices are the code's arithmetic (the contract fixture's figures come out the same)", () => {
    assert.deepEqual(unitPrice(zl(499), { value: 200, unit: "g" }), { minor: 2495, per: "kg" });
    assert.deepEqual(unitPrice(zl(549), { value: 200, unit: "g" }), { minor: 2745, per: "kg" });
    assert.deepEqual(unitPrice(zl(4499), { value: 50, unit: "szt" }), { minor: 90, per: "szt" });
    assert.deepEqual(unitPrice(zl(1999), { value: 500, unit: "g" }), { minor: 3998, per: "kg" });
    assert.deepEqual(unitPrice(zl(349), { value: 2, unit: "l" }), { minor: 175, per: "l" });
    assert.deepEqual(unitPrice(zl(7899), { value: 100, unit: "ml" }), { minor: 78990, per: "l" });
    assert.equal(unitPrice(zl(499), undefined), undefined);
  });

  test("printed unit prices are read only to cross-check", () => {
    assert.deepEqual(parsePrintedUnitPrice("1,75 zł/l"), { minor: 175, per: "l" });
    assert.deepEqual(parsePrintedUnitPrice("24,95 zł/kg"), { minor: 2495, per: "kg" });
    assert.deepEqual(parsePrintedUnitPrice("100 ml = 78,99 zł"), { minor: 78990, per: "l" });
    assert.deepEqual(parsePrintedUnitPrice("1 szt. = 1,25 zł"), { minor: 125, per: "szt" });
    assert.deepEqual(parsePrintedUnitPrice("100 g = 153,50 zł"), { minor: 153500, per: "kg" });
    assert.deepEqual(parsePrintedUnitPrice("1,23 zł/100 g"), { minor: 1230, per: "kg" });
    assert.equal(parsePrintedUnitPrice("tanio!"), undefined);
    assert.equal(unitPricesAgree({ minor: 125, per: "szt" }, { minor: 125, per: "szt" }), true);
    assert.equal(unitPricesAgree({ minor: 56, per: "szt" }, { minor: 56, per: "szt" }), true);
    assert.equal(unitPricesAgree({ minor: 2495, per: "kg" }, { minor: 2600, per: "kg" }), false);
    assert.equal(unitPricesAgree({ minor: 2495, per: "kg" }, { minor: 2495, per: "l" }), false);
  });
});

describe("the model's pick (ids only)", () => {
  const cands = [
    [{ id: "c1", chain: "Biedronka", name: "Masło Extra 82% 200 g" }, { id: "c2", chain: "Lidl", name: "Masło orzechowe 350 g" }],
    [{ id: "c3", chain: "Dino", name: "Kawa mielona 500 g" }],
    [{ id: "c4", chain: "Rossmann", name: "Pampers 4" }],
  ];
  test("keeps only ids offered for that item; an item it didn't answer stays undefined", async () => {
    const model = new FakeModel();
    model.pickImpl = () => ({
      kind: "ok", usage: { inputTokens: 10, outputTokens: 5 },
      output: { matches: [{ item: 0, ids: ["c1", "c3", "c99"] }, { item: 1, ids: [] }, { item: 7, ids: ["c4"] }, { item: 0, ids: ["c2"] }] },
    });
    const r = await pickWithModel(model, ["masło", "kawa mielona", "pieluchy"], cands, new AbortController().signal);
    assert.equal(r.outcome, "ok");
    assert.deepEqual([...r.picks[0]!], ["c1"], "c3 belongs to another item, c99 doesn't exist, the second entry for item 0 is ignored");
    assert.deepEqual([...r.picks[1]!], []);
    assert.equal(r.picks[2], undefined);
    assert.deepEqual(model.picks[0]!.queries, ["masło", "kawa mielona", "pieluchy"]);
  });

  test("a refusal leaves every item to the code", async () => {
    const model = new FakeModel();
    model.pickImpl = () => ({ kind: "refused", usage: { inputTokens: 10, outputTokens: 0 } });
    const r = await pickWithModel(model, ["a", "b", "c"], cands, new AbortController().signal);
    assert.equal(r.outcome, "refused");
    assert.deepEqual(r.picks, [undefined, undefined, undefined]);
  });
});
