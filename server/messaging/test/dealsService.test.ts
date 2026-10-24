// The leaflet search end to end without a database: the four chains as they answered on 2026-10-24 (fixtures),
// a fake web and a fake model in place of Claude Haiku. Checks the contract's shape, that every price comes from
// a chain's own data or a page read, the code's checks, and that one chain's failure leaves the others alone.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { dinoLeaflets, nuxtLeaflets } from "../src/deals/chains/dino.js";
import { parseFlyer } from "../src/deals/chains/lidl.js";
import { parsePromotions } from "../src/deals/chains/rossmann.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { parsePrice } from "../src/deals/vision.js";
import { searchDeals, type DealsDeps } from "../src/deals/service.js";
import { DEFAULT_DEALS_SETTINGS, type Chain, type DealsResponse, type Offer } from "../src/deals/types.js";
import {
  BIEDRONKA_PRESS, chainsWeb, contractFixture, DINO_LISTING, FakeModel, FakeWeb, fixtureJson, fixtureText, LIDL_LISTING, read, ResponseSchema,
} from "./dealsFakes.js";

const NOW = new Date("2026-10-24T06:10:00.000Z");
const ITEMS = ["masło", "pieluchy rozmiar 4", "kawa mielona"];
const CHAINS: Chain[] = ["biedronka", "lidl", "dino", "rossmann", "kaufland"];

/** What the fake reader "reads" on each page (test data, not the chains' real prices). */
function reader(): FakeModel {
  return new FakeModel()
    .page("biedronka:2", { products: [read({
      name: "Masło Extra 82%", size: "200 g", price: "4,99", regularPrice: "6,49",
      conditions: [{ kind: "app", quantity: null, text: null }, { kind: "limit", quantity: 4, text: null }],
    })] })
    // An unreadable price: the code must drop the product, never guess one.
    .page("biedronka:3", { products: [read({ name: "Masło Polskie 200 g", price: "ok. 3 zł" })] })
    .page("lidl:6", { products: [read({ name: "Pilos Masło Ekstra 83%", size: "200 g", price: "2,49", regularPrice: "4,99", conditions: [{ kind: "app", quantity: null, text: null }] })] })
    .page("lidl:30", { products: [read({ name: "Kawa mielona Lavazza Crema e Gusto", size: "250 g", price: "15,99" })] })
    .page("dino:51", { products: [read({ name: "Masło ekstra Łowickie 82%", size: "250 g", price: "4,49", lowest30d: "4,99" })] })
    .page("dino:13", { products: [read({
      name: "Kawa mielona Swisso Reich Rösten", size: "250 g", price: "12,99", conditions: [{ kind: "min_quantity", quantity: 2, text: null }],
    })] });
}

async function search(opts: { web?: FakeWeb; model?: FakeModel | null; deps?: Partial<DealsDeps>; items?: string[]; chains?: Chain[]; language?: string } = {}) {
  const web = opts.web ?? chainsWeb();
  const model = opts.model === null ? undefined : opts.model ?? reader();
  const logs: { msg: string; extra?: object }[] = [];
  const deps: DealsDeps = {
    settings: DEFAULT_DEALS_SETTINGS, fetcher: new PoliteFetcher({ fetch: web.fetch }), model, now: () => NOW,
    log: (msg, extra) => logs.push({ msg, extra }), ...opts.deps,
  };
  const r = await searchDeals(deps, { items: opts.items ?? ITEMS, chains: opts.chains ?? CHAINS, language: opts.language ?? "pl" });
  return { ...r, web, model, logs };
}
const row = (res: DealsResponse, chain: Chain) => res.chains.find((c) => c.chain === chain)!;
const offers = (res: DealsResponse, query: string) => res.items.find((i) => i.query === query)!.offers;
const brief = (o: Offer) => [o.chain, o.product, o.price.minor];

describe("the leaflet search", () => {
  test("the contract's shape (the fixture itself passes the same strict schema)", async () => {
    assert.ok(ResponseSchema.safeParse(contractFixture().response).success, "the schema describes the contract fixture");
    const { response } = await search();
    const parsed = ResponseSchema.safeParse(response);
    assert.ok(parsed.success, JSON.stringify(parsed.error?.issues));
    assert.equal(response.checkedAt, "2026-10-24T06:10:00.000Z");
    assert.deepEqual(response.items.map((i) => i.query), ITEMS);
    assert.deepEqual(Object.keys(response), Object.keys(contractFixture().response as object));
  });

  test("four chains read, Kaufland a link; offers per item cheapest first, with what each chain gave", async () => {
    const { response, stats, model } = await search();
    assert.deepEqual(response.chains, [
      { chain: "biedronka", status: "checked", leaflet: { title: "Codziennie niskie ceny P - oferta od 22.10", url: BIEDRONKA_PRESS, validFrom: "2026-10-22" } },
      { chain: "lidl", status: "checked", leaflet: { title: "Gazetka 22.10", url: "https://www.lidl.pl/l/pl/gazetki/gazetka-22-10-czw-kw43/ar/0", validFrom: "2026-10-22", validTo: "2026-10-24" } },
      { chain: "dino", status: "checked", leaflet: { title: "Gazetka 43 / 2026", url: DINO_LISTING, validFrom: "2026-10-21", validTo: "2026-10-27" } },
      { chain: "rossmann", status: "checked", leaflet: { title: "Promocje Rossmann", url: "https://www.rossmann.pl/promocje" } },
      { chain: "kaufland", status: "link_only", leafletUrl: "https://www.kaufland.pl/gazetka-promocyjna.html" },
    ]);

    assert.deepEqual(offers(response, "masło").map(brief), [
      ["lidl", "Pilos Masło Ekstra 83%", 249], ["dino", "Masło ekstra 82% Łowickie 250g", 449], ["biedronka", "Masło Extra 82%", 499],
    ]);
    const [lidlButter, dinoButter, biedronkaButter] = offers(response, "masło");
    assert.deepEqual(biedronkaButter, {
      chain: "biedronka", product: "Masło Extra 82%", price: { minor: 499, currency: "PLN" }, size: { value: 200, unit: "g" },
      unitPrice: { minor: 2495, per: "kg" }, regularPrice: { minor: 649, currency: "PLN" },
      conditions: ["z aplikacją Moja Biedronka", "max 4 szt."], validFrom: "2026-10-22",
      source: { url: BIEDRONKA_PRESS, page: 2 }, readBy: "page_image", check: false,
    });
    assert.deepEqual(lidlButter!.conditions, ["z Lidl Plus"]);
    assert.deepEqual(lidlButter!.source, { url: "https://www.lidl.pl/l/pl/gazetki/gazetka-22-10-czw-kw43/view/flyer/page/6", page: 6 });
    assert.deepEqual(lidlButter!.unitPrice, { minor: 1245, per: "kg" });
    assert.deepEqual(dinoButter, {
      chain: "dino", product: "Masło ekstra 82% Łowickie 250g", price: { minor: 449, currency: "PLN" }, size: { value: 250, unit: "g" },
      unitPrice: { minor: 1796, per: "kg" }, lowest30d: { minor: 499, currency: "PLN" }, conditions: [],
      validFrom: "2026-10-21", validTo: "2026-10-27", source: { url: DINO_LISTING, page: 51 }, readBy: "leaflet_data",
      ean: "5900120025967", check: false,
    }, "Dino's own name, price and EAN; the page read confirmed it and added the 30-day price");

    assert.deepEqual(offers(response, "pieluchy rozmiar 4").map((o) => [...brief(o), o.unitPrice?.minor, o.check]), [
      ["rossmann", "Babydream EKO pieluchy, 4 Maxi, 8-14 kg, 30 szt.", 2399, 80, false],
      ["rossmann", "Pampers Premium Care pieluchy, 9-14 kg, rozmiar 4, 52 szt.", 6499, 125, false],
    ], "size 5 and size S nappies are left out; the unit price agrees with Rossmann's own");

    const coffee = offers(response, "kawa mielona");
    assert.deepEqual(coffee.map((o) => [...brief(o), o.check]), [
      ["dino", "Kawa mielona Reich Rosten Swisso 250g", 1299, false],
      ["lidl", "Kawa mielona Lavazza Crema e Gusto", 1599, false],
      ["dino", "Kawa mielona MK Cafe Premium 2x500g", 4995, true],
    ]);
    assert.deepEqual(coffee[0]!.conditions, ["przy zakupie 2 szt."], "the condition Dino's data doesn't carry, read from the page");
    assert.deepEqual(coffee[2]!.size, { value: 1000, unit: "g" });

    // What was read: every Biedronka page (5, under the 40-page cap), Lidl's pages whose own text names an item
    // (1, 6, 30), Dino's pages holding a matched product (13, 51).
    assert.deepEqual(model!.reads.map((r) => r.marker).sort(), ["biedronka:1", "biedronka:2", "biedronka:3", "biedronka:4", "biedronka:5", "dino:13", "dino:51", "lidl:1", "lidl:30", "lidl:6"]);
    assert.equal(stats.pagesRead, 10);
    assert.equal(stats.inputTokens, 10 * 2000 + 300);
    assert.equal(stats.picked, "model");
    assert.deepEqual(stats.statuses, { checked: 4, link_only: 1 });
  });

  test("every price comes from a chain's own data or from a page the reader read, never from anywhere else", async () => {
    const model = reader();
    // The pick may only name ids; whatever else it says can't become a price.
    model.pickImpl = (req) => ({ kind: "ok", usage: { inputTokens: 1, outputTokens: 1 }, output: { matches: req.candidates.map((l, i) => ({ item: i, ids: [...l.map((c) => c.id), "c999", "9,99 zł"] })) } });
    const { response } = await search({ model });
    const data = new Set<string>();
    // Regular and 30-day prices too: each must be the chain's own figure or one the reader read.
    const extras = new Set<number>();
    const lidlFlyer = parseFlyer(fixtureJson("lidl_flyer.json"), "gazetka-22-10-czw-kw43", "2026-10-24");
    for (const p of [
      ...dinoLeaflets(nuxtLeaflets(fixtureText("dino_gazetki.html"))!, "2026-10-24").flatMap((l) => l.products),
      ...parsePromotions(fixtureText("rossmann_promocje_pieluchy.html"), "2026-10-24")!,
      ...(lidlFlyer && lidlFlyer !== "not_current" ? lidlFlyer.products : []),
    ]) {
      data.add(`${p.name}|${p.price.minor}`);
      for (const m of [p.regularPrice, p.lowest30d]) if (m) extras.add(m.minor);
    }
    for (const step of model.pages.values()) {
      if (typeof step !== "object") continue;
      for (const p of step.products) for (const s of [p.regularPrice, p.lowest30d]) { const m = parsePrice(s); if (m) extras.add(m.minor); }
    }
    let checked = 0;
    for (const item of response.items) {
      for (const o of item.offers) {
        checked++;
        if (o.readBy === "leaflet_data") {
          assert.ok(data.has(`${o.product}|${o.price.minor}`), `data price ${o.product} ${o.price.minor}`);
        } else {
          const step = model.pages.get(`${o.chain}:${o.source.page}`);
          assert.ok(step && typeof step === "object", `a page read for ${o.product}`);
          const readHere = step.products.filter((p) => p.name === o.product).map((p) => parsePrice(p.price)?.minor);
          assert.deepEqual(readHere, [o.price.minor], `${o.product} as read on ${o.chain} page ${o.source.page}`);
        }
        for (const extra of [o.regularPrice, o.lowest30d]) if (extra) assert.ok(extras.has(extra.minor), `${o.product}: ${extra.minor}`);
      }
    }
    assert.ok(checked >= 8);
    assert.ok(!JSON.stringify(response).includes("Masło Polskie"), "a product whose price couldn't be read never appears");
    assert.ok(!JSON.stringify(response).includes("999"), "an unknown id from the pick changes nothing");
  });

  test("the model's pick narrows the code's candidates; if it fails, the code's choice stands", async () => {
    const model = reader();
    model.pickImpl = (req) => ({
      kind: "ok", usage: { inputTokens: 1, outputTokens: 1 },
      output: { matches: req.candidates.map((l, i) => ({ item: i, ids: l.filter((c) => i !== 0 || c.chain === "Biedronka").map((c) => c.id) })) },
    });
    const narrowed = await search({ model });
    assert.deepEqual(offers(narrowed.response, "masło").map((o) => o.chain), ["biedronka"]);
    assert.ok(model.picks[0]!.candidates.flat().every((c) => !("price" in c)), "the pick sees names and sizes, not prices");
    const failing = reader();
    failing.pickImpl = () => { throw new Error("api down"); };
    const fallback = await search({ model: failing });
    assert.equal(offers(fallback.response, "masło").length, 3);
    assert.equal(fallback.stats.picked, "code");
  });

  test("without a reader: data chains still answer (Dino's offers flagged as unconfirmed), image chains say failed", async () => {
    const { response, stats } = await search({ model: null });
    assert.equal(row(response, "biedronka").status, "failed");
    assert.equal(row(response, "lidl").status, "failed");
    assert.equal(row(response, "dino").status, "checked");
    assert.equal(row(response, "rossmann").status, "checked");
    const dino = response.items.flatMap((i) => i.offers).filter((o) => o.chain === "dino");
    assert.ok(dino.length >= 3 && dino.every((o) => o.check && o.readBy === "leaflet_data"), "conditions not confirmed on the page");
    assert.equal(stats.pagesRead, 0);
  });

  test("pages over DEALS_MAX_PAGES are not read, and then 'nothing matched' is not claimed", async () => {
    const { response, model } = await search({ deps: { settings: { ...DEFAULT_DEALS_SETTINGS, maxPages: 1 } }, items: ["masło"], chains: ["biedronka"] });
    assert.deepEqual(model!.reads.map((r) => r.marker), ["biedronka:1"]);
    assert.deepEqual(response.chains, [{ chain: "biedronka", status: "failed" }]);
  });

  test("a chain read fully with nothing that fits is no_match", async () => {
    const { response } = await search({ items: ["szampon"], chains: ["biedronka", "dino"] });
    assert.deepEqual(response.chains, [{ chain: "biedronka", status: "no_match" }, { chain: "dino", status: "no_match" }]);
    assert.deepEqual(response.items, [{ query: "szampon", offers: [] }]);
  });

  test("one chain failing leaves the others alone; a block is reported, never worked around", async () => {
    const web = chainsWeb().on(LIDL_LISTING, { status: 500 }).on("https://www.biedronka.pl/pl/w-tym-tygodniu", { status: 403 });
    const { response } = await search({
      web, deps: { adapters: { rossmann: { chain: "rossmann", hosts: [], read: async () => { throw new Error("boom"); } } } },
    });
    assert.deepEqual(response.chains.map((c) => [c.chain, c.status]), [
      ["biedronka", "blocked"], ["lidl", "failed"], ["dino", "checked"], ["rossmann", "failed"], ["kaufland", "link_only"],
    ]);
    assert.equal(web.hits("https://www.biedronka.pl/pl/w-tym-tygodniu"), 1);
    assert.equal(web.hits("https://www.biedronka.pl/pl/gazetki"), 0);
    assert.ok(offers(response, "masło").some((o) => o.chain === "dino"));
  });

  test("an image host whose robots.txt says ai-input=no: its pages never reach the reader", async () => {
    const web = chainsWeb().robots("https://images.biedronka.cloud", "User-agent: *\nContent-Signal: ai-input=no\n");
    const { response, model } = await search({ web, items: ["masło"], chains: ["biedronka"] });
    assert.equal(model!.reads.length, 0);
    assert.equal(web.hits("https://images.biedronka.cloud/api/"), 0);
    assert.deepEqual(response.chains, [{ chain: "biedronka", status: "failed" }]);
  });

  test("the time budget: pages aren't started when too little time is left; data chains still answer", async () => {
    const { response, model } = await search({ deps: { budgetMs: 3200 } });
    assert.equal(model!.reads.length, 0);
    assert.equal(row(response, "biedronka").status, "failed");
    assert.equal(row(response, "rossmann").status, "checked");
  });

  test("conditions in English for language en; logs carry codes and counts, never the items", async () => {
    const { response, logs } = await search({ language: "en" });
    assert.deepEqual(offers(response, "masło").find((o) => o.chain === "biedronka")!.conditions, ["with the Moja Biedronka app", "max 4 per customer"]);
    const text = JSON.stringify(logs);
    for (const word of ["masło", "maslo", "pieluchy", "kawa", "Masło"]) assert.ok(!text.includes(word), word);
    assert.ok(logs.some((l) => l.msg === "deals chain read"));
  });

  test("a reader that refuses or fails for a page leaves that page unread, not a guess", async () => {
    const model = reader().page("biedronka:2", "refuse").page("biedronka:4", "throw");
    const { response } = await search({ model, items: ["masło"], chains: ["biedronka"] });
    assert.deepEqual(response.chains, [{ chain: "biedronka", status: "failed" }]);
    assert.deepEqual(response.items[0]!.offers, []);
  });

  test("the code's checks: a regular price not above the price, a 30-day price below it, a dated read outside the leaflet", async () => {
    const model = new FakeModel().page("biedronka:2", { products: [
      read({ name: "Masło A", size: "200 g", price: "4,99", regularPrice: "4,99" }),
      read({ name: "Masło B", size: "200 g", price: "5,99", lowest30d: "5,49" }),
      read({ name: "Masło C", size: "200 g", price: "6,99", validFrom: "15.10", validTo: "18.10" }),
      read({ name: "Masło D", size: "200 g", price: "7,99", unitPrice: "19,99 zł/kg" }),
      read({ name: "Masło E", size: "200 g", price: "8,99", confidence: "low" }),
      read({ name: "Masło F", size: "200 g", price: "9,99", unitPrice: "49,95 zł/kg", validFrom: "23.10", validTo: "25.10" }),
    ] });
    const { response } = await search({ model, items: ["masło"], chains: ["biedronka"] });
    const got = Object.fromEntries(response.items[0]!.offers.map((o) => [o.product, [o.check, o.validFrom, o.validTo]]));
    assert.deepEqual(got, {
      "Masło A": [true, "2026-10-22", undefined],
      "Masło B": [true, "2026-10-22", undefined],
      "Masło C": [true, "2026-10-22", undefined],
      "Masło D": [true, "2026-10-22", undefined],
      "Masło E": [true, "2026-10-22", undefined],
      "Masło F": [false, "2026-10-23", "2026-10-25"],
    });
  });
});
