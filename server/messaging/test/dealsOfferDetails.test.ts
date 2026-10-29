// ADR-661: what an offer carries beyond its price — the price per piece under a multi-buy mechanic, the real
// reduction against the leaflet's own 30-day lowest price, the flags the app's checklist reads, the limit —
// and promotions printed without a price. All of it is the code's arithmetic and words, never the model's.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { buildOffer, effectivePrice, flagsOf, mechanicText, rankValue, searchDeals, selectOffers } from "../src/deals/service.js";
import { readMechanic, readPromotions, readProducts } from "../src/deals/vision.js";
import { DEFAULT_DEALS_SETTINGS, type Condition, type Money, type ReadChain } from "../src/deals/types.js";
import { BIEDRONKA_PRESS, chainsWeb, cond, fakePng, FakeModel, fixtureJson, promo, read } from "./dealsFakes.js";

const zl = (minor: number): Money => ({ minor, currency: "PLN" });
const offer = (o: { name?: string; price: number; size?: string; conditions?: Condition[]; lowest30d?: number; regular?: number; chain?: ReadChain }) =>
  buildOffer({
    chain: o.chain ?? "lidl", name: o.name ?? "Masło 200 g", price: zl(o.price), sizeText: o.size, conditions: o.conditions ?? [],
    ...(o.lowest30d ? { lowest30d: zl(o.lowest30d) } : {}), ...(o.regular ? { regularPrice: zl(o.regular) } : {}),
    source: { url: "https://www.lidl.pl/" }, readBy: "page_image", doubts: [],
  }, "pl").offer;

describe("the price per piece under a mechanic", () => {
  test("1+1, 2+1, the second for X, every n-th k% off, a minimum quantity; rounded up to the grosz", () => {
    assert.deepEqual(effectivePrice(zl(999), [{ kind: "multi_buy", text: "1+1" }]), { price: zl(500), quantity: 2 }, "9,99 / 2 = 4,995 → 5,00");
    assert.deepEqual(effectivePrice(zl(600), [{ kind: "multi_buy", text: "2+1" }]), { price: zl(400), quantity: 3 });
    assert.deepEqual(effectivePrice(zl(3699), [{ kind: "second_for", price: zl(299) }]), { price: zl(1999), quantity: 2 }, "Aldi's 'co druga -91%'");
    assert.deepEqual(effectivePrice(zl(1000), [{ kind: "nth_discount", quantity: 2, percent: 50 }]), { price: zl(750), quantity: 2 });
    assert.deepEqual(effectivePrice(zl(1000), [{ kind: "nth_discount", quantity: 3, percent: 100 }]), { price: zl(667), quantity: 3 }, "6,666… → 6,67");
    assert.deepEqual(effectivePrice(zl(559), [{ kind: "min_quantity", quantity: 2 }]), { price: zl(559), quantity: 2 }, "the leaflet's price already is the price at 2");
    assert.equal(effectivePrice(zl(559), []), undefined);
    assert.equal(effectivePrice(zl(559), [{ kind: "second_for", price: zl(600) }]), undefined, "a 'second for' above the price isn't a deal");
    assert.equal(effectivePrice(zl(559), [{ kind: "multi_buy", text: "dwa za trzy" }]), undefined);
  });

  test("the offer carries it with its own unit price, the flags and the limit", () => {
    const o = offer({ name: "Kawa mielona 500 g", price: 2599, conditions: [{ kind: "multi_buy", text: "2+1" }, { kind: "app" }, { kind: "limit", quantity: 6 }, { kind: "deposit" }] });
    assert.deepEqual(o.effective, { price: zl(1733), quantity: 3, unitPrice: { minor: 3466, per: "kg" } });
    assert.deepEqual(o.flags, ["app", "deposit"]);
    assert.equal(o.limit, 6);
    assert.deepEqual(o.conditions, ["2+1", "z Lidl Plus", "max 6 szt.", "plus kaucja za opakowanie"]);
    assert.deepEqual(flagsOf([{ kind: "selected_stores" }, { kind: "stock" }, { kind: "card" }]), ["card", "stock", "selected_stores"]);
  });
});

describe("a real reduction, against the leaflet's own 30-day lowest price (Omnibus)", () => {
  test("below the 30-day low: the cut in percent; at or above it: not a cut; never from a 'regular' price", () => {
    assert.deepEqual(offer({ price: 449, lowest30d: 499 }).cut, { percent: 10 });
    const same = offer({ price: 499, lowest30d: 499 });
    assert.equal(same.cut, undefined);
    assert.deepEqual(same.flags, ["not_a_cut"], "a promo at the 30-day low isn't a reduction");
    const above = offer({ price: 549, lowest30d: 499 });
    assert.deepEqual(above.flags, ["not_a_cut"]);
    assert.equal(above.check, true, "a 30-day price below the promo is also a doubt about the read");
    assert.equal(offer({ price: 449, regular: 699 }).cut, undefined, "a crossed-out regular price is not the reference");
    assert.equal(offer({ price: 449, lowest30d: 499, conditions: [{ kind: "multi_buy", text: "2+1" }] }).cut, undefined, "multi-buy offers aren't price cuts");
    const secondFor = offer({ price: 3699, lowest30d: 3299, conditions: [{ kind: "second_for", price: zl(299) }] });
    assert.equal(secondFor.check, false, "under 'the second for X' the price is the price of one alone, which may be above the 30-day low");
    assert.equal(offer({ price: 3699, lowest30d: 3299, conditions: [{ kind: "multi_buy", text: "1+1" }] }).check, true);
  });
});

describe("ranking: the price per kg under the mechanic, with a small penalty for what the price asks", () => {
  test("a near tie goes to the price anyone can get; a clearly better deal still wins", () => {
    const plain = offer({ name: "Masło 200 g", price: 500, chain: "dino" }); // 25,00 zł/kg
    const app = offer({ name: "Masło 200 g", price: 490, conditions: [{ kind: "app" }], chain: "lidl" }); // 24,50, +5% → 25,73
    const twoPlusOne = offer({ name: "Masło 200 g", price: 600, conditions: [{ kind: "multi_buy", text: "2+1" }], chain: "biedronka" }); // 20,00/kg at 3, +5% → 21,00
    assert.equal(rankValue(plain, "kg"), 2500);
    assert.equal(rankValue(app, "kg"), 2450 * 1.05);
    assert.equal(rankValue(twoPlusOne, "kg"), 2000 * 1.05);
    const cand = (o: ReturnType<typeof offer>, i: number) => ({ id: `x${i}`, chain: o.chain, offer: o, doubts: [], scores: [1] });
    assert.deepEqual(selectOffers([app, plain, twoPlusOne].map(cand)).map((o) => o.chain), ["biedronka", "dino", "lidl"]);
  });
});

describe("the reader's new conditions and promotions without a price", () => {
  test("conditions: the second for X, every n-th k% off, deposit, while stocks last, selected stores", () => {
    const [p] = readProducts({ promotions: [], products: [read({ name: "Kawa Lavazza 250 g", price: "15,99", conditions: [
      cond({ kind: "second_for", price: "5,00" }), cond({ kind: "nth_discount", quantity: 2, percent: 50 }), cond({ kind: "deposit" }),
      cond({ kind: "stock" }), cond({ kind: "selected_stores" }), cond({ kind: "second_for", price: "ok. 5" }), cond({ kind: "nth_discount", quantity: 1, percent: 50 }),
    ] })] });
    assert.deepEqual(p!.conditions, [
      { kind: "second_for", price: zl(500) }, { kind: "nth_discount", quantity: 2, percent: 50 }, { kind: "deposit" }, { kind: "stock" }, { kind: "selected_stores" },
    ], "an unreadable 'second for' price and an 'every 1st' are dropped");
  });

  test("a mechanic must hold whole numbers in range and a readable price; a range that names money is dropped", () => {
    const m = (x: Partial<Parameters<typeof readMechanic>[0]> & Pick<Parameters<typeof readMechanic>[0], "kind">) =>
      readMechanic({ buy: null, free: null, n: null, percent: null, price: null, ...x });
    assert.deepEqual(m({ kind: "multi_buy", buy: 1, free: 1 }), { kind: "multi_buy", buy: 1, free: 1 });
    assert.equal(m({ kind: "multi_buy", buy: 0, free: 1 }), undefined);
    assert.deepEqual(m({ kind: "second_for", price: "5" }), { kind: "second_for", price: zl(500) });
    assert.equal(m({ kind: "percent_off", percent: 95 }), undefined);
    const promos = readPromotions({ products: [], promotions: [
      promo({ range: "Persil, wszystkie proszki i kapsułki", mechanic: { kind: "multi_buy", buy: 1, free: 1, n: null, percent: null, price: null }, conditions: [cond({ kind: "app" })] }),
      promo({ range: "Kawa Jacobs od 19,99 zł", mechanic: { kind: "percent_off", buy: null, free: null, n: null, percent: 30, price: null } }),
    ] });
    assert.equal(promos.length, 1);
    assert.equal(mechanicText(promos[0]!.mechanic, "pl"), "1+1");
    assert.equal(mechanicText({ kind: "second_for", price: zl(500) }, "pl"), "druga sztuka za 5,00 zł");
    assert.equal(mechanicText({ kind: "nth_discount", n: 2, percent: 50 }, "pl"), "co druga sztuka −50%");
    assert.equal(mechanicText({ kind: "nth_discount", n: 3, percent: 100 }, "en"), "every third one −100%");
  });

  test("a promotion that fits an item comes back with the item, as a mechanic and never a price; the chain counts as checked", async () => {
    const model = new FakeModel().page("biedronka:3", { products: [], promotions: [
      promo({ range: "Persil, wszystkie proszki i kapsułki do prania", mechanic: { kind: "multi_buy", buy: 1, free: 1, n: null, percent: null, price: null },
        conditions: [cond({ kind: "app" }), cond({ kind: "limit", quantity: 2 })], validTo: "26.10" }),
      promo({ range: "Wszystkie sery żółte", mechanic: { kind: "percent_off", buy: null, free: null, n: null, percent: 30, price: null } }),
    ] });
    const { response } = await searchDeals(
      { settings: DEFAULT_DEALS_SETTINGS, fetcher: new PoliteFetcher({ fetch: chainsWeb().fetch }), model, now: () => new Date("2026-10-24T06:10:00.000Z") },
      { items: ["proszek do prania"], chains: ["biedronka"], language: "pl" },
    );
    assert.deepEqual(response.chains[0]!.status, "checked");
    assert.deepEqual(response.items[0]!.offers, []);
    assert.deepEqual(response.items[0]!.promotions, [{
      chain: "biedronka", text: "Persil, wszystkie proszki i kapsułki do prania", mechanic: "1+1",
      conditions: ["z aplikacją Moja Biedronka", "max 2 szt."], flags: ["app"], validFrom: "2026-10-22", validTo: "2026-10-26",
      source: { url: BIEDRONKA_PRESS, page: 3 },
    }]);
    assert.ok(!JSON.stringify(response.items[0]!.promotions).match(/\d+,\d{2}/), "no price anywhere in a promotion");
  });
});

describe("page images over the size cap", () => {
  test("are asked for once more a moment later (a cold cache sends the full PNG first); still too big counts as unread", async () => {
    const web = chainsWeb();
    const first = fixtureJson<{ images_mobile: { page: number; image: string }[] }>("biedronka_leaflet.json").images_mobile[0]!.image;
    let calls = 0;
    web.on(first, () => (++calls === 1
      ? { headers: { "content-type": "image/png" }, body: Buffer.alloc(3 * 1024 * 1024 + 10) }
      : { headers: { "content-type": "image/png" }, body: fakePng(1146, 1800, "biedronka:1") }));
    const model = new FakeModel();
    const { response } = await searchDeals(
      { settings: { ...DEFAULT_DEALS_SETTINGS, maxPages: 1 }, fetcher: new PoliteFetcher({ fetch: web.fetch }), model, now: () => new Date("2026-10-24T06:10:00.000Z") },
      { items: ["masło"], chains: ["biedronka"], language: "pl" },
    );
    assert.equal(calls, 2);
    assert.deepEqual(model.reads.map((r) => r.marker), ["biedronka:1"]);
    assert.deepEqual(response.chains, [{ chain: "biedronka", status: "failed", pages: { read: 1, of: 5 } }]);
  });
});
