// The chain adapters against trimmed copies of what the chains served on 2026-10-24 (Aldi and Żabka on 2026-10-28;
// test/fixtures/deals). The fixtures' prices are the chains' published prices on those days.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { biedronka, datesFromTitle, findThisWeekOnListing, parseLeafletApi, parsePressPage } from "../src/deals/chains/biedronka.js";
import { currentWeek, dayMonth, officialUrl, warsawDay } from "../src/deals/chains/common.js";
import { dino, dinoLeaflets, nuxtLeaflets, unflatten } from "../src/deals/chains/dino.js";
import { lidl, parseFlyer, parseOverview } from "../src/deals/chains/lidl.js";
import { parsePromotions, rossmann, searchTerms } from "../src/deals/chains/rossmann.js";
import { aldi } from "../src/deals/chains/aldi.js";
import { parseListing, parseSpreads, zabka } from "../src/deals/chains/zabka.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext, ChainRead, LeafletRead } from "../src/deals/types.js";
import {
  ALDI_OFFERS, BIEDRONKA_API, BIEDRONKA_PRESS, chainsWeb, DINO_LISTING, FakeWeb, fixtureJson, fixtureText, LIDL_LISTING, rossmannSearch,
  ZABKA_LISTING, ZABKA_SPREADS,
} from "./dealsFakes.js";

const TODAY = "2026-10-24";
const ctx = (web: FakeWeb, queries: string[] = ["masło"]): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: web.fetch }), queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead[] => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? r.leaflets : [];
};

describe("dates and hosts", () => {
  test("Warsaw's day, a leaflet's day and month without a year, this week", () => {
    assert.equal(warsawDay(new Date("2026-10-24T22:30:00Z")), "2026-10-25", "00:30 in Warsaw");
    assert.equal(dayMonth(22, 10, TODAY), "2026-10-22");
    assert.equal(dayMonth(2, 1, "2026-12-30"), "2027-01-02", "January's leaflet seen in late December");
    assert.equal(dayMonth(31, 2, TODAY), undefined);
    assert.equal(currentWeek("2026-10-22", "2026-10-24", TODAY), true);
    assert.equal(currentWeek("2026-10-30", "2026-11-05", TODAY), true, "starts within the next six days");
    assert.equal(currentWeek("2026-11-01", undefined, TODAY), false);
    assert.equal(currentWeek(undefined, "2026-10-23", TODAY), false);
  });

  test("addresses found in a chain's data count only on its own hosts, over https", () => {
    assert.ok(officialUrl("https://images.biedronka.cloud/a.png", ["images.biedronka.cloud"]));
    assert.equal(officialUrl("http://images.biedronka.cloud/a.png", ["images.biedronka.cloud"]), undefined);
    assert.equal(officialUrl("https://evil.example/a.png", ["images.biedronka.cloud"]), undefined);
    assert.equal(officialUrl("https://user:pw@images.biedronka.cloud/a.png", ["images.biedronka.cloud"]), undefined);
  });
});

describe("Biedronka", () => {
  test("the press page names the leaflet; the API lists its single pages; dates come from the title", () => {
    assert.deepEqual(parsePressPage(fixtureText("biedronka_press.html")), {
      uuid: "a95fe048-0a65-4861-8fe4-8174a88a06b5", title: "Codziennie niskie ceny P - oferta od 22.10",
    });
    assert.deepEqual(datesFromTitle("Codziennie niskie ceny P - oferta od 22.10", TODAY), { validFrom: "2026-10-22" });
    assert.deepEqual(datesFromTitle("Tani weekend od 23.10 do 26.10", TODAY), { validFrom: "2026-10-23", validTo: "2026-10-26" });
    const pages = parseLeafletApi(fixtureJson("biedronka_leaflet.json"), BIEDRONKA_PRESS);
    assert.deepEqual(pages.map((p) => p.number), [1, 2, 3, 4, 5]);
    assert.ok(pages.every((p) => p.imageUrl.startsWith("https://images.biedronka.cloud/") && p.url === BIEDRONKA_PRESS));
    const tampered = { images_mobile: [{ page: 0, image: "https://evil.example/p.png" }, { page: 1, image: "http://images.biedronka.cloud/p.png" }] };
    assert.deepEqual(parseLeafletApi(tampered, BIEDRONKA_PRESS), [], "only the chain's image host, over https");
  });

  test("reads this week's leaflet through the redirects: page images to read, no product data", async () => {
    const web = chainsWeb();
    const [l] = ok(await biedronka.read(ctx(web)));
    assert.deepEqual(l!.leaflet, { title: "Codziennie niskie ceny P - oferta od 22.10", url: BIEDRONKA_PRESS, validFrom: "2026-10-22" });
    assert.equal(l!.strategy, "all");
    assert.equal(l!.products.length, 0);
    assert.equal(l!.pages.length, 5);
    assert.equal(web.hits(BIEDRONKA_API), 1);
  });

  test("falls back to the list's W_TYM_TYGODNIU slot; a 403 is blocked, a missing leaflet is no_leaflet", async () => {
    const slot = '<div class="adwrapper"\ndata-slot-id="2026_T43B_W_TYM_TYGODNIU"        >\n<a class="page-slot-columns" href="https://www.biedronka.pl/pl/press,id,1wmtizrux,title,codziennie-niskie-ceny-p-oferta-od-22-10" target="_self">';
    assert.equal(findThisWeekOnListing(slot), BIEDRONKA_PRESS);
    const moved = chainsWeb();
    moved.on("https://www.biedronka.pl/pl/w-tym-tygodniu", { status: 404 }).on("https://www.biedronka.pl/pl/gazetki", { headers: { "content-type": "text/html" }, body: slot });
    assert.equal(ok(await biedronka.read(ctx(moved))).length, 1);
    const blocked = chainsWeb().on("https://www.biedronka.pl/pl/w-tym-tygodniu", { status: 403 });
    assert.deepEqual(await biedronka.read(ctx(blocked)), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(blocked.hits("https://www.biedronka.pl/pl/gazetki"), 0, "a block isn't worked around through another page");
    const none = chainsWeb().on("https://www.biedronka.pl/pl/w-tym-tygodniu", { status: 404 }).on("https://www.biedronka.pl/pl/gazetki", { body: "<html></html>" });
    assert.deepEqual(await biedronka.read(ctx(none)), { kind: "no_leaflet" });
  });
});

describe("Lidl", () => {
  test("the list's leaflets with their sections; alcohol catalogues are left out by the adapter", async () => {
    const flyers = parseOverview(fixtureText("lidl_overview.html"));
    assert.deepEqual(flyers.map((f) => [f.section, f.slug, f.name, f.title]), [
      ["Aktualne gazetki", "gazetka-22-10-czw-kw43", "Gazetka", "22.10"],
      ["Aktualne gazetki", "gazetka-19-10-katalog-kw43", "Katalog", "19.10"],
      ["Aktualne gazetki", "gazetka-26-10-katalog-kw44", "Katalog", "26.10"],
      ["Aktualne gazetki", "rewolucja-cenowa-oszczedzaj-kazdego-dnia-16092026", "Rewolucja cenowa!", "Każdego dnia tanio!"],
      ["Katalogi alkoholowe", "katalog-alkoholi-mocnych-katalog-od-28-09", "Katalog alkoholi mocnych", "28.09"],
      ["Katalogi alkoholowe", "karta-win-katalog-od-28-09", "Karta Win", "28.09"],
    ]);
    const web = chainsWeb();
    const r = await lidl.read(ctx(web));
    assert.equal(web.hits("https://endpoints.leaflets.schwarz/v4/flyer?flyer_identifier=katalog-alkoholi"), 0);
    assert.equal(web.hits("https://endpoints.leaflets.schwarz/v4/flyer?flyer_identifier=karta-win"), 0);
    assert.equal(r.kind === "ok" && r.incomplete, "some_leaflets_failed", "the other three aren't served by the fake: the read says so");
    assert.equal(ok(r).length, 1);
  });

  test("a flyer: dates, pages with Lidl's own text and the 2400 px image, linked products with the chain's price", () => {
    const l = parseFlyer(fixtureJson("lidl_flyer.json"), "gazetka-22-10-czw-kw43", TODAY);
    assert.ok(l && l !== "not_current");
    assert.deepEqual(l.leaflet, {
      title: "Gazetka 22.10", url: "https://www.lidl.pl/l/pl/gazetki/gazetka-22-10-czw-kw43/ar/0", validFrom: "2026-10-22", validTo: "2026-10-24",
    });
    assert.equal(l.strategy, "text");
    assert.deepEqual(l.pages.map((p) => p.number), [1, 4, 6, 30, 42]);
    const p6 = l.pages.find((p) => p.number === 6)!;
    assert.match(p6.text!, /Pilos Masło Ekstra 83%/);
    assert.match(p6.imageUrl, /^https:\/\/imgproxy\.leaflets\.schwarz\/.*rs:fit:2400:2400/);
    assert.equal(p6.url, "https://www.lidl.pl/l/pl/gazetki/gazetka-22-10-czw-kw43/view/flyer/page/6");
    assert.deepEqual(l.products.map((p) => [p.name, p.price.minor, p.page]), [
      ["ESMARA® Kurtka pikowana damska", 7999, 42],
      ["PARKSIDE® Reflektor roboczy, 2000 lm", 4999, undefined],
    ]);
    assert.equal(parseFlyer(fixtureJson("lidl_flyer.json"), "gazetka-22-10-czw-kw43", "2026-11-10"), "not_current");
    assert.equal(parseFlyer({ success: false }, "x", TODAY), undefined);
  });

  test("a blocked list is blocked", async () => {
    const web = chainsWeb().on(LIDL_LISTING, { status: 429 });
    assert.deepEqual(await lidl.read(ctx(web)), { kind: "blocked", reason: "blocked:http_429" });
  });
});

describe("Dino", () => {
  test("devalue's flat payload: wrappers, shared entries, negative indices, Set and Date", () => {
    const flat = [{ a: 1, b: 3, c: 5, d: -1, e: 6, f: 8 }, ["Reactive", 2], { x: 4 }, ["Ref", 4], "shared", ["Set", 4, 7], ["Date", "2026-10-24T00:00:00.000Z"], 9, ["EmptyRef", 9], '"false"'];
    assert.deepEqual(unflatten(flat), { a: { x: "shared" }, b: "shared", c: ["shared", 9], d: undefined, e: "2026-10-24T00:00:00.000Z", f: "false" });
    assert.equal(unflatten("nope"), undefined);
    assert.equal(unflatten([["Unknown", 1], 2]), undefined);
  });

  test("this week's leaflets from the page's Nuxt payload; alcohol leaflets skipped; hotspots are Dino's data", () => {
    const raw = nuxtLeaflets(fixtureText("dino_gazetki.html"));
    assert.equal(raw?.length, 2);
    const leaflets = dinoLeaflets(raw!, TODAY);
    assert.equal(leaflets.length, 1, "Oferta alkoholowa is left out (its wine hotspot wasn't even flagged isAlcohol)");
    const l = leaflets[0]!;
    assert.deepEqual(l.leaflet, { title: "Gazetka 43 / 2026", url: DINO_LISTING, validFrom: "2026-10-21", validTo: "2026-10-27" });
    assert.equal(l.strategy, "confirm");
    assert.deepEqual(l.products.map((p) => [p.name, p.price.minor, p.ean, p.page, p.confirmOnPage]), [
      ["Sok march jabł mango odporność Vitaminka Hortex 1l", 379, "5900500048715", 4, true],
      ["Sok march jabł malin witalność Vitaminka Hortex 1l", 379, "5900500048692", 4, true],
      ["Kawa mielona MK Cafe Premium 2x500g", 4995, "5900788346374", 13, true],
      ["Kawa mielona Reich Rosten Swisso 250g", 1299, "4260623230963", 13, true],
      ["Masło ekstra 82% Łowickie 250g", 449, "5900120025967", 51, true],
    ]);
    assert.deepEqual(l.pages.map((p) => p.number), [4, 13, 51]);
    assert.ok(l.pages.every((p) => p.imageUrl.startsWith("https://api.marketdino.pl/media/pdf/promo_news_pages/")));
    assert.equal(dinoLeaflets(raw!, "2026-11-20").length, 0);
  });

  test("the adapter: one page request; no payload is failed; a robots.txt disallow is blocked and nothing is fetched", async () => {
    const web = chainsWeb();
    assert.equal(ok(await dino.read(ctx(web))).length, 1);
    assert.equal(web.hits(DINO_LISTING), 1);
    assert.deepEqual(await dino.read(ctx(chainsWeb().on(DINO_LISTING, { body: "<html></html>" }))), { kind: "failed", reason: "no_payload" });
    const shut = chainsWeb().robots("https://marketdino.pl", "User-agent: *\nDisallow: /gazetki/\n");
    assert.deepEqual(await dino.read(ctx(shut)), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(shut.hits(DINO_LISTING), 0);
  });
});

describe("Rossmann", () => {
  test("promoted products from /promocje: name with size, price, regular and 30-day price, EAN, dates, product page", () => {
    const products = parsePromotions(fixtureText("rossmann_promocje_pieluchy.html"), TODAY)!;
    const pampers = products.find((p) => p.name.startsWith("Pampers"))!;
    assert.deepEqual(pampers, {
      name: "Pampers Premium Care pieluchy, 9-14 kg, rozmiar 4, 52 szt.",
      price: { minor: 6499, currency: "PLN" },
      url: "https://www.rossmann.pl/Produkt/Pieluchy-jednorazowe/Pampers-Premium-Care-pieluchy-9-14-kg-rozmiar-4-52-szt,154963,14008",
      conditions: [], validFrom: "2026-10-15", validTo: "2026-10-28", sizeText: "52 szt.", printedUnitPrice: "1 szt. = 1,25 zł",
      regularPrice: { minor: 7599, currency: "PLN" }, lowest30d: { minor: 7599, currency: "PLN" }, ean: "4015400278818",
    });
    assert.equal(products.length, 4);
    assert.equal(parsePromotions(fixtureText("rossmann_promocje_pieluchy.html"), "2026-11-20")!.length, 0, "ended promotions are left out");
    assert.equal(parsePromotions("<html></html>", TODAY), undefined);
  });

  test("what is searched: the item, then its first word if the item finds nothing", () => {
    assert.deepEqual(searchTerms("pieluchy rozmiar 4"), ["pieluchy rozmiar 4", "pieluchy"]);
    assert.deepEqual(searchTerms("masło"), ["masło"]);
  });

  test("the adapter never touches the robots-disallowed gazetka.rossmann.pl, and stops at the first block", async () => {
    const web = chainsWeb();
    const [l] = ok(await rossmann.read(ctx(web, ["pieluchy rozmiar 4", "masło"])));
    assert.equal(l!.products.length, 4);
    assert.deepEqual(l!.leaflet, { title: "Promocje Rossmann", url: "https://www.rossmann.pl/promocje" });
    assert.ok(!web.hosts().has("gazetka.rossmann.pl"));
    assert.equal(web.hits(rossmannSearch("masło")), 1, "one search for a one-word item");

    const blocked = chainsWeb().onPrefix("https://www.rossmann.pl/promocje?Search=", { status: 429 });
    const r = await rossmann.read(ctx(blocked, ["a1", "b2", "c3", "d4", "e5"]));
    assert.equal(r.kind, "blocked");
    assert.ok(blocked.hits("https://www.rossmann.pl/promocje?Search=") <= 2, "at most the requests already in flight");
  });
});

describe("Aldi", () => {
  const at = (web: FakeWeb) => ({ ...ctx(web), today: "2026-10-28" });
  const products = async (web = chainsWeb()) => ok(await aldi.read(at(web)))[0]!;

  test("this week's offers from the page's own data, each mechanic as the shopper pays it", async () => {
    const web = chainsWeb();
    const l = await products(web);
    assert.deepEqual(l.leaflet, { title: "Oferty ALDI", url: ALDI_OFFERS, validFrom: "2026-10-26", validTo: "2026-10-31" });
    assert.equal(l.strategy, "none");
    assert.deepEqual(l.pages, []);
    const by = (name: string) => l.products.find((p) => p.name === name);
    assert.deepEqual(by("Filety z makreli w oleju"), {
      name: "Filety z makreli w oleju", price: { minor: 559, currency: "PLN" }, url: ALDI_OFFERS,
      conditions: [{ kind: "min_quantity", quantity: 2 }], sizeText: "Puszka 170 g", printedUnitPrice: "32,88 zł/kg",
      regularPrice: { minor: 699, currency: "PLN" }, lowest30d: { minor: 699, currency: "PLN" }, validFrom: "2026-10-26", validTo: "2026-10-31",
    }, "'-20% przy zakupie 2 szt.': the price of one when buying two, the regular price of one");
    const instant = by("Kawa rozpuszczalna Classic")!;
    assert.deepEqual(instant.price, { minor: 3699, currency: "PLN" }, "'co druga -91%': the price of one jar, not the 2,99 zł of the second");
    assert.deepEqual(instant.conditions, [{ kind: "second_for", price: { minor: 299, currency: "PLN" } }],
      "the second jar's price as a condition; the service works out (36,99 + 2,99) / 2 per jar when buying two");
    assert.equal(instant.printedUnitPrice, undefined, "Aldi's unit price for it is the second jar's");
    assert.deepEqual(by("Jaja z wolnego wybiegu L")!.conditions, [{ kind: "second_for", price: { minor: 699, currency: "PLN" } }]);
    assert.deepEqual(by("Papier toaletowy 3-warstwowy")!.conditions, [{ kind: "multi_buy", text: "1+1" }]);
    assert.equal(by("Papier toaletowy 3-warstwowy")!.regularPrice, undefined, "1+1: the price shown is the regular one");
    assert.deepEqual(by("Banany"), {
      name: "Banany", price: { minor: 349, currency: "PLN" }, url: ALDI_OFFERS, conditions: [], sizeText: "1 kg",
      regularPrice: { minor: 699, currency: "PLN" }, validFrom: "2026-10-26", validTo: "2026-10-31",
    }, "'Cena za kg', and the price before the first cut (perishables) as the regular price");
    assert.equal(by("Gęś owsiana")!.sizeText, "100 g", "'Cena za 100 g'");
    assert.deepEqual(by("Rogal z białym makiem")!.conditions, [{ kind: "min_quantity", quantity: 2 }]);
    assert.equal(by("Rogal z białym makiem")!.printedUnitPrice, undefined, "no pack size: Aldi's unit price can't be checked, so it isn't kept");
    assert.equal(by("Miód wielokwiatowy nektarowy"), undefined, "'co druga' without the price of the first: left out, not guessed");
    assert.equal(l.products.length, 8);
    assert.deepEqual([...web.hosts()], ["www.aldi.pl"]);
    assert.equal(web.hits("https://www.aldi.pl/"), 2, "robots.txt and the one page");
  });

  test("alcohol is left out; a page without the payload is failed; a block is blocked", async () => {
    const html = fixtureText("aldi_oferty.html").replace("Filety z makreli w oleju", "Piwo jasne pełne");
    const beer = chainsWeb().on(ALDI_OFFERS, { headers: { "content-type": "text/html" }, body: html });
    assert.ok(!(await products(beer)).products.some((p) => /piwo/i.test(p.name)));
    const empty = chainsWeb().on(ALDI_OFFERS, { headers: { "content-type": "text/html" }, body: "<html></html>" });
    assert.deepEqual(await aldi.read(at(empty)), { kind: "failed", reason: "no_payload" });
    const blocked = chainsWeb().on(ALDI_OFFERS, { status: 403 });
    assert.deepEqual(await aldi.read(at(blocked)), { kind: "blocked", reason: "blocked:http_403" });
  });
});

describe("Żabka", () => {
  const at = (web: FakeWeb, queries = ["jogurt pitny"]) => ({ ...ctx(web, queries), today: "2026-10-28" });

  test("the list's leaflets with their dates; pages with Żabka's own text, beer pages left out", () => {
    assert.deepEqual(parseListing(fixtureText("zabka_gazetka.html")), [
      { slug: "gazetka-promocyjna-45-46-2026", validFrom: "2026-11-04", validTo: "2026-11-17" },
      { slug: "gazetka-promocyjna-43-44-2026", validFrom: "2026-10-21", validTo: "2026-11-03" },
    ]);
    const pages = parseSpreads(fixtureJson("zabka_spreads.json"), "gazetka-promocyjna-43-44-2026");
    assert.deepEqual(pages.map((p) => p.number), [3, 44, 48, 69], "page 18 carries the beer warning");
    assert.equal(pages[2]!.url, "https://gazetka.zabka.pl/gazetka-promocyjna-43-44-2026/page/48");
    assert.ok(pages[2]!.imageUrl.startsWith("https://view.publitas.com/resize/") && pages[2]!.imageUrl.includes("/fit-in/1565x2555/"));
    assert.ok(/Jogurt pitny Skyr/.test(pages[2]!.text ?? ""));
  });

  test("the adapter reads only this week's leaflet; its pages are read from the image, chosen by their text", async () => {
    const web = chainsWeb();
    const [l, ...rest] = ok(await zabka.read(at(web)));
    assert.equal(rest.length, 0, "45-46 starts on 4 Nov, after this week");
    assert.deepEqual(l!.leaflet, {
      title: "Gazetka promocyjna Żabka", url: "https://gazetka.zabka.pl/gazetka-promocyjna-43-44-2026/", validFrom: "2026-10-21", validTo: "2026-11-03",
    });
    assert.equal(l!.strategy, "text");
    assert.deepEqual(l!.products, []);
    assert.equal(web.hits(ZABKA_SPREADS), 1);
    assert.equal(web.hits("https://gazetka.zabka.pl/gazetka-promocyjna-45-46-2026/"), 0);
  });

  test("a blocked list is blocked; a list with no current leaflet is no_leaflet", async () => {
    assert.deepEqual(await zabka.read(at(chainsWeb().on(ZABKA_LISTING, { status: 403 }))), { kind: "blocked", reason: "blocked:http_403" });
    const old = fixtureText("zabka_gazetka.html").replace(/2026-11-03/g, "2026-10-25").replace(/2026-11-04/g, "2026-12-04");
    assert.deepEqual(await zabka.read(at(chainsWeb().on(ZABKA_LISTING, { headers: { "content-type": "text/html" }, body: old }))), { kind: "no_leaflet" });
  });
});
