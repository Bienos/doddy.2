// zooplus's promotions pages, against SYNTHETIC pages built here in the shape www.zooplus.pl served on 2026-10-30 (a
// Next.js page whose flight data, self.__next_f.push([1, "…"]), holds the header's category tree and
// initialStoreState.products). Names, brands, codes and prices are made up; no copy of the shop's page is kept.
// Nothing reaches the network.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  animalPages, bundleCondition, extraDiscountCondition, flightRows, ONLINE_ONLY, parseZooplusPage, sizeAndUnit, sizesIn, ZOOPLUS_MAX_PAGES,
  ZOOPLUS_PAGES, zooplus,
} from "../src/deals/chains/zooplus.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { buildOffer } from "../src/deals/service.js";
import type { ChainContext, ChainRead, DataProduct, LeafletRead } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const DOG = "https://www.zooplus.pl/shop/psy/oferty_specjalne_psy";
const CAT = "https://www.zooplus.pl/shop/koty/oferty_specjalne_koty";
const SMALL = "https://www.zooplus.pl/shop/gryzonie/oferty_specjalne_gryzonie";
const BIRDS = "https://www.zooplus.pl/shop/ptaki/oferty_specjalne_ptaki";
// The rules that matter here, as the shop's robots.txt wrote them on 2026-10-30 (DoddyBot falls under `*`).
const ROBOTS = "User-agent: ClaudeBot\nDisallow: /specials/\nAllow: /\n\nUser-agent: ia_archiver\nDisallow: /\n\n"
  + "User-agent: *\nDisallow: /askdetail?\nDisallow: /miva/\nDisallow: /recommendation/\nDisallow: /ov?\nDisallow: /specials/\n";

// ---------- a synthetic page in the shop's shape ----------

/** The header's category tree: path and the shop's own title. */
const CATEGORIES: [string, string][] = [
  ["/shop/psy", "Psy"], ["/shop/psy/karma_dla_psa_sucha", "Karma sucha dla psa"], ["/shop/psy/karma_dla_psa_sucha/psotka", "Psotka"],
  ["/shop/psy/gryzaki_dla_psa", "Przysmaki dla psa"], ["/shop/psy/smycz_obroza_dla_psa", "Spacer: smycze, szelki i obroże"],
  ["/shop/koty", "Koty"], ["/shop/koty/karma_dla_kota_mokra", "Karma mokra dla kota"], ["/shop/koty/pielegnacja_kota", "Pielęgnacja kota"],
  ["/shop/gryzonie", "Małe zwierzęta"], ["/shop/ptaki", "Ptaki"],
];

interface TileInput {
  title: string; variant: string; path: string; id: string; price: string; brands?: string[];
  type?: "REGULAR" | "SET" | "OFFER"; before?: string; prefix?: string; tooltip?: string; percent?: string;
  unitPrice?: string; unit?: string | null; extra?: string; stock?: boolean; available?: boolean; sponsored?: boolean;
  petTypes?: string[]; variantUrl?: string;
}
const BUNDLE_TIP = "Całkowita cena tych samych produktów, gdyby zostały zakupione osobno";
const LOWEST_TIP = "Najniższa cena w ciągu 30 dni przed obniżką";

function tile(t: TileInput): Record<string, unknown> {
  const money = (s: string) => ({ prefix: "", value: s });
  return {
    path: t.path, variantUrl: t.variantUrl ?? `${t.path}?activeVariant=${t.id}`, reviewUrl: `${t.path}?activeVariant=${t.id}#reviews`,
    shopIdentifier: t.path.split("/").pop(), title: t.title, summary: "<strong>Opis</strong> produktu", picture200: "https://media.example/p.jpg",
    newProduct: false, isLimitedDeal: false, isSponsored: t.sponsored ?? false, numberOfVariants: 2, promotionText: null,
    displayedPrice: t.price, productVariantDiscountText: t.extra ? `${t.extra} Extra Rabat` : null, petTypes: t.petTypes ?? ["DOGS"],
    labels: { whileStocksLast: "Tylko do wyczerpania zapasów", moreVariants: "{0} opcji" },
    variant: {
      description: t.variant, brands: t.brands ?? [], available: t.available ?? true, whileStockLasts: t.stock ?? false, id: 1,
      activeVariantId: t.id, priceType: t.type ?? "REGULAR", tooltipText: t.tooltip ?? null, percentageDiscountLabel: t.percent ?? null,
      articleDiscount: { discountLabel: t.extra ?? null, isEnabled: true, labels: { articleDiscountInactive: "{0} Extra Rabat - Aktywuj" } },
      abdPrice: t.extra ? { price: { beforePrice: t.price, price: money("1,00 zł") } } : null,
      price: {
        beforePricePrefix: t.prefix ?? null, beforePrice: t.before ?? null, refPriceAriaLabel: "Więcej informacji", price: money(t.price),
        unit: t.unit === undefined ? "kg" : t.unit, unitPrice: t.unitPrice ?? null,
      },
      autoshipment: { autoshipmentPriceLabel: "1,00 zł" },
    },
  };
}

/** A promotions page: the header's categories and the listing's tiles in the flight data, split over two pushes. */
function page(tiles: unknown[], count: number | null = 1, categories: [string, string][] = CATEGORIES): string {
  const nav = ["$", "$L34", null, { content: { siteId: 8, navigation: categories.map(([path, title]) => ({
    animalType: "DOGS", children: [], path, pictureFile: "x.jpg", specials: [], title, type: "ANIMAL",
  })) } }];
  const store = ["$", "$L38", null, { initialStoreState: {
    uri: { pathname: "/shop/psy/oferty_specjalne_psy" }, pageType: "level3", pagination: count === null ? null : { current: 1, count },
    products: tiles, site: { id: 8, currency: "EUR", alternativeCurrency: "PLN" },
  } }];
  const rows = `0:{"P":null,"b":"build"}\n22:I[24002,["747","static/chunks/a.js"],"default"]\n23:${JSON.stringify(nav)}\n`
    + `24:T2a,line one of a text row\n{"not": json\n31:${JSON.stringify(store)}\n39:["$","$L3b",null,{"level3Data":{"pageType":"level3"}}]\n`;
  const half = Math.floor(rows.length / 2);
  // Next escapes "<" inside the pushed strings.
  const push = (s: string) => `<script>self.__next_f.push(${JSON.stringify([1, s]).replace(/</g, "\\u003c")})</script>`;
  return `<!DOCTYPE html><html lang="pl"><head><title>Karmy i akcesoria w wyjątkowych cenach</title></head><body>`
    + `<div class="z-product-price"><span>wcześniej</span><del>139,96 zł</del><span class="z-product-price__amount">116,56 zł</span></div>`
    + `<script>(self.__next_f=self.__next_f||[]).push([0])</script>${push(rows.slice(0, half))}${push(rows.slice(half))}`
    + `<script type="application/ld+json">{"@context":"https://schema.org","@graph":[]}</script></body></html>`;
}

const PLAIN = tile({ title: "Psotka, skóra łososia", variant: "50 g", path: "/shop/psy/gryzaki_dla_psa/psotka/1000001", id: "1000001.0", price: "13,96 zł", unitPrice: "279,20 zł", brands: ["PSOTKA"] });
const OFFER = tile({
  title: "10 + 2 kg gratis! Psotka Vet, karma sucha dla psa, 12 kg", variant: "Dermatosis", path: "/shop/psy/karma_dla_psa_sucha/psotka/1000002",
  id: "1000002.8", price: "116,56 zł", type: "OFFER", prefix: "wcześniej", before: "139,96 zł", tooltip: LOWEST_TIP, percent: "-16.72%", unitPrice: "9,72 zł",
});
const SET = tile({
  title: "12,5 kg + 2,5 kg gratis! Psotka, karma sucha dla psa, 15 kg", variant: "Adult, jagnięcina i ryż", path: "/shop/psy/karma_dla_psa_sucha/psotka/1000003",
  id: "1000003.2", price: "153,96 zł", type: "SET", prefix: "pojedynczo", before: "184,76 zł", tooltip: BUNDLE_TIP, percent: "-16.67%", unitPrice: "10,28 zł",
});
const EXTRA = tile({
  title: "Obroża Kłapouch London, pomarańczowa", variant: "Vario Plus, L, obwód szyi: 34-56 cm, szer. 20 mm", path: "/shop/psy/smycz_obroza_dla_psa/klapouch/1000004",
  id: "1000004.2", price: "13,96 zł", unit: "szt.", extra: "-20%", stock: true,
});
const WIPES = tile({
  title: "Mruczek chusteczki dla zwierząt", variant: "2 x 20 szt.", path: "/shop/koty/pielegnacja_kota/siersc/reczniki/2000001", id: "2000001.1",
  price: "28,96 zł", type: "SET", prefix: "pojedynczo", before: "31,92 zł", tooltip: BUNDLE_TIP, percent: "-9.27%", unit: null, petTypes: ["CATS", "DOGS", "RODENTS"],
});
const FREE = tile({ title: "Gratis dla Ciebie! Psotka Chunks, 60 g", variant: "Indyk", path: "/shop/psy/gryzaki_dla_psa/psotka/1000005", id: "1000005.0", price: "0,00 zł", unitPrice: "0,00 zł" });
const DOG_TILES = [PLAIN, OFFER, SET, EXTRA, WIPES, FREE];
const CAT_TILES = [
  WIPES,
  tile({
    title: "3 + 1 gratis! 4x Mruczek, karma mokra dla kota, różne rodzaje", variant: "4 x (24 x 85 g) w galarecie, mięsne smaki, (72 + 24 gratis!)",
    path: "/shop/koty/karma_dla_kota_mokra/mruczek/2000002", id: "2000002.6", price: "104,96 zł", type: "SET", prefix: "pojedynczo", before: "139,84 zł",
    tooltip: BUNDLE_TIP, percent: "-24.94%", unitPrice: "12,88 zł", petTypes: ["CATS"],
  }),
  tile({
    title: "Mruczek Gold: 96 x 85 g Megapakiet + Zupki, 48 x 45 g gratis!", variant: "Delikatny mus", path: "/shop/koty/karma_dla_kota_mokra/mruczek/2000003",
    id: "2000003.4", price: "166,96 zł", type: "SET", prefix: "pojedynczo", before: "270,64 zł", tooltip: BUNDLE_TIP, percent: "-38.31%", unitPrice: "16,16 zł", petTypes: ["CATS"],
  }),
];
const SMALL_TILES = [tile({ title: "Pojnik dla królików 2,0 l", variant: "2,0 l", path: "/shop/gryzonie/wyposazenie_klatki/3000001", id: "3000001.0", price: "46,96 zł", unit: null, brands: ["Chrupek"], petTypes: ["RODENTS"] })];
const BIRD_TILES = [tile({ title: "Ćwirek zabawka dla ptaków", variant: "1 szt.", path: "/shop/ptaki/akcesoria_do_klatek/4000001", id: "4000001.0", price: "28,96 zł", unit: "szt.", petTypes: ["BIRDS"] })];

function shopWeb(pages: Partial<Record<string, string>> = {
  [DOG]: page(DOG_TILES, 12), [CAT]: page(CAT_TILES, 10), [SMALL]: page(SMALL_TILES, null), [BIRDS]: page(BIRD_TILES, null),
}): FakeWeb {
  const web = new FakeWeb().robots("https://www.zooplus.pl", ROBOTS);
  for (const [url, body] of Object.entries(pages)) if (body !== undefined) web.on(url, { headers: { "content-type": "text/html; charset=utf-8" }, body });
  return web;
}
const ctx = (web: FakeWeb, queries: string[]): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: web.fetch }), queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead & { incomplete?: string } => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? { ...r.leaflets[0]!, ...(r.incomplete ? { incomplete: r.incomplete } : {}) } : (undefined as never);
};
const byName = (products: DataProduct[], part: string) => products.find((p) => p.name.includes(part))!;

// ---------- the parser ----------

describe("zooplus: a promotions page's own data", () => {
  test("the flight data is read across pushes; text rows and other rows are skipped", () => {
    const rows = flightRows(page(DOG_TILES, 12));
    assert.equal(rows.length, 4, "the header, the store, level3Data and the first row; not the import or the text row");
    assert.deepEqual(flightRows("<html><body>no data</body></html>"), []);
  });

  test("a plain tile: name with the variant, price, size, the shop's unit price, the variant's page, online only", () => {
    const listing = parseZooplusPage(page(DOG_TILES, 12), "psy")!;
    assert.equal(listing.totalPages, 12);
    assert.equal(listing.products.length, 5, "the free gift (0,00 zł) isn't an offer");
    assert.deepEqual(listing.products[0], {
      name: "Psotka, skóra łososia, 50 g", price: { minor: 1396, currency: "PLN" },
      url: "https://www.zooplus.pl/shop/psy/gryzaki_dla_psa/psotka/1000001?activeVariant=1000001.0",
      conditions: [{ kind: "other", text: ONLINE_ONLY }], sizeText: "50 g", printedUnitPrice: "279,20 zł/kg",
      matchText: "Psy Przysmaki dla psa gryzaki dla psa dla psa",
    });
  });

  test("\"wcześniej\" with the 30-day note is the lowest price of the last 30 days, never a regular price", () => {
    const p = byName(parseZooplusPage(page(DOG_TILES))!.products, "Dermatosis");
    assert.deepEqual(p.lowest30d, { minor: 13996, currency: "PLN" });
    assert.equal(p.regularPrice, undefined);
    assert.equal(p.sizeText, "12 kg", "the pack, not the free part: its unit price agrees with the shop's");
    assert.deepEqual(p.conditions, [{ kind: "other", text: ONLINE_ONLY }]);
    assert.ok(!("validFrom" in p) && !("validTo" in p), "the page shows no dates, so none are given");
  });

  test("a bundle: the price is the bundle's; the saving against buying separately is a condition, never a regular price or a multi-buy", () => {
    const p = byName(parseZooplusPage(page(DOG_TILES))!.products, "jagnięcina i ryż");
    assert.equal(p.name, "12,5 kg + 2,5 kg gratis! Psotka, karma sucha dla psa, 15 kg, Adult, jagnięcina i ryż");
    assert.deepEqual(p.price, { minor: 15396, currency: "PLN" });
    assert.equal(p.regularPrice, undefined, "\"pojedynczo\" isn't struck and isn't this product's regular price");
    assert.equal(p.lowest30d, undefined);
    assert.deepEqual(p.conditions, [{ kind: "other", text: ONLINE_ONLY }, { kind: "other", text: "pakiet o 16% taniej niż osobno" }]);
    assert.ok(!p.conditions.some((c) => c.kind === "multi_buy"), "the price already covers every piece in the bundle");
    assert.equal(p.sizeText, "15 kg");
    const { offer } = buildOffer({ chain: "zooplus", name: p.name, price: p.price, sizeText: p.sizeText, printedUnitPrice: p.printedUnitPrice, conditions: p.conditions, source: { url: p.url }, readBy: "leaflet_data", doubts: [] }, "pl");
    assert.equal(offer.effective, undefined, "no per-piece price is worked out for a bundle");
    assert.equal(offer.check, false);
    assert.deepEqual(offer.conditions, [ONLINE_ONLY, "pakiet o 16% taniej niż osobno"]);
  });

  test("the bundle's saving is rounded down, with no amount of money; under 1% it says only that it is cheaper", () => {
    assert.deepEqual(bundleCondition("-16.67%"), { kind: "other", text: "pakiet o 16% taniej niż osobno" });
    assert.deepEqual(bundleCondition("-0.74%"), { kind: "other", text: "pakiet taniej niż osobno" });
    assert.deepEqual(bundleCondition(null), { kind: "other", text: "pakiet taniej niż osobno" });
    const cheaperAlone = parseZooplusPage(page([tile({ title: "A", variant: "1 kg", path: "/shop/psy/x/1", id: "1.0", price: "10,00 zł", type: "SET", prefix: "pojedynczo", before: "9,00 zł", tooltip: BUNDLE_TIP })]))!.products[0]!;
    assert.deepEqual(cheaperAlone.conditions, [{ kind: "other", text: ONLINE_ONLY }], "not cheaper than separately: nothing said");
  });

  test("an Extra Rabat to activate and \"while stocks last\" are conditions; the price is the one shown before activation", () => {
    const p = byName(parseZooplusPage(page(DOG_TILES))!.products, "Obroża");
    assert.deepEqual(p.price, { minor: 1396, currency: "PLN" });
    assert.deepEqual(p.conditions, [
      { kind: "other", text: ONLINE_ONLY }, { kind: "other", text: "dodatkowe −20% (Extra Rabat) po aktywacji w sklepie" }, { kind: "stock" },
    ]);
    assert.equal(p.sizeText, undefined, "\"20 mm\" and \"34-56 cm\" aren't pack sizes");
    assert.equal(p.name, "Obroża Kłapouch London, pomarańczowa, Vario Plus, L, obwód szyi: 34-56 cm, szer. 20 mm");
    assert.equal(extraDiscountCondition(null), undefined);
    assert.deepEqual(extraDiscountCondition("-5%"), { kind: "other", text: "dodatkowe −5% (Extra Rabat) po aktywacji w sklepie" });
  });

  test("a struck price under a label the code doesn't know is a regular price, and only when above the price", () => {
    const struck = (before: string) => parseZooplusPage(page([tile({ title: "Psotka Gryzak", variant: "1 szt.", path: "/shop/psy/x/9", id: "9.0", price: "10,00 zł", type: "OFFER", prefix: "", before })]))!.products[0]!;
    assert.deepEqual(struck("12,00 zł").regularPrice, { minor: 1200, currency: "PLN" });
    assert.equal(struck("12,00 zł").lowest30d, undefined);
    assert.equal(struck("9,00 zł").regularPrice, undefined);
  });

  test("the brand goes in front only when the name doesn't say it", () => {
    const products = parseZooplusPage(page([...DOG_TILES, ...SMALL_TILES]))!.products;
    assert.equal(byName(products, "skóra").name, "Psotka, skóra łososia, 50 g", "PSOTKA is already there");
    assert.equal(byName(products, "Pojnik").name, "Chrupek Pojnik dla królików 2,0 l", "and the variant \"2,0 l\" isn't said twice");
  });

  test("sizes as the shop writes them: nested multipacks, a free pack added, the unit the shop prices by", () => {
    assert.deepEqual(sizesIn("3 + 1 gratis! 4x Felix, 4 x (24 x 85 g) w galarecie, (72 + 24 gratis!)"), ["96 x 85 g"]);
    assert.deepEqual(sizesIn("Frolic z drobiem, 7,8 kg (3 x 2,6 kg)"), ["7,8 kg", "3 x 2,6 kg"]);
    const cats = parseZooplusPage(page(CAT_TILES))!.products;
    const four = byName(cats, "4x Mruczek");
    assert.equal(four.sizeText, "96 x 85 g");
    assert.equal(four.printedUnitPrice, "12,88 zł/kg");
    const gold = byName(cats, "Megapakiet");
    assert.equal(gold.sizeText, "10,32 kg", "96 x 85 g and the 48 x 45 g free: the shop's 16,16 zł/kg is for both");
    const price = { minor: 4996, currency: "PLN" as const };
    assert.deepEqual(sizeAndUnit("Kalendarz adwentowy, 1 szt. (67 g)", price, undefined, "szt."), { sizeText: "1 szt." }, "sold per piece");
    assert.deepEqual(sizeAndUnit("Smycz, szer. 20 mm", price, undefined, "szt."), {});
  });

  test("a unit price that agrees with no size keeps the shop's figure, so the offer is marked for checking", () => {
    const size = sizeAndUnit("Psotka przysmak z króliczej skóry, 85 g", { minor: 996, currency: "PLN" }, "11,72 zł", "kg");
    assert.deepEqual(size, { sizeText: "85 g", printedUnitPrice: "11,72 zł/kg" });
    const { offer } = buildOffer({ chain: "zooplus", name: "Psotka przysmak z króliczej skóry, 85 g", price: { minor: 996, currency: "PLN" }, ...size, conditions: [], source: { url: "https://www.zooplus.pl/shop/psy/x/1" }, readBy: "leaflet_data", doubts: [] }, "pl");
    assert.equal(offer.check, true);
  });

  test("a long name is cut between words, after its size was read", () => {
    const long = tile({
      title: "Megapakiet Mruczek Fantastic, karma mokra dla kota, różne rodzaje i smaki w galarecie oraz w sosie",
      variant: "Kurczak, wołowina, tuńczyk, łosoś, dorsz, kaczka, jagnięcina w galarecie, tak dobre jak wygląda, 88 x 85 g",
      path: "/shop/koty/karma_dla_kota_mokra/mruczek/2000009", id: "2000009.0", price: "89,96 zł", unitPrice: "12,04 zł", petTypes: ["CATS"],
    });
    const p = parseZooplusPage(page([long]))!.products[0]!;
    assert.ok(p.name.length <= 160 && !p.name.endsWith(" "), p.name);
    assert.ok(p.name.endsWith("łosoś, dorsz, kaczka"), `${p.name}: no half word, no trailing comma`);
    assert.equal(p.sizeText, "88 x 85 g");
  });

  test("tiles that aren't an available product on the shop's host with a price in złoty are skipped; a variant is kept once", () => {
    const base = { title: "Psotka", variant: "1 kg", path: "/shop/psy/karma_dla_psa_sucha/psotka/5", price: "10,00 zł" };
    const products = parseZooplusPage(page([
      tile({ ...base, id: "5.1", variantUrl: "https://evil.example/shop/psy/karma_dla_psa_sucha/psotka/5?activeVariant=5.1", path: "https://evil.example/shop/psy/x/5" }),
      tile({ ...base, id: "5.2", sponsored: true }),
      tile({ ...base, id: "5.3", available: false }),
      tile({ ...base, id: "5.4", price: "10,00 €" }),
      tile({ ...base, id: "5.5", variantUrl: "/specials/psy", path: "/specials/psy" }),
      tile({ ...base, id: "5.6", variantUrl: "/shop/psy/karma_dla_psa_sucha/psotka/5?activeVariant=5.6&utm=x#top" }),
      tile({ ...base, id: "5.6" }),
      tile({ ...base, id: "javascript:1" }),
    ]))!.products;
    assert.deepEqual(products.map((p) => p.url), [
      "https://www.zooplus.pl/shop/psy/karma_dla_psa_sucha/psotka/5?activeVariant=5.6",
      "https://www.zooplus.pl/shop/psy/karma_dla_psa_sucha/psotka/5",
    ]);
    assert.equal(parseZooplusPage("<html><body>Nie znaleziono strony</body></html>"), undefined);
    assert.equal(parseZooplusPage(`<script>self.__next_f.push([1,"0:{\\"P\\":null}\\n"])</script>`), undefined, "flight data without a listing");
    assert.equal(parseZooplusPage(page([], null))!.totalPages, 1);
  });
});

describe("zooplus: the kind of product the name leaves out (ADR-667)", () => {
  test("the shop's category titles, the category's address and the animals go to the matcher, never into the name", () => {
    const products = parseZooplusPage(page(DOG_TILES), "psy")!.products;
    assert.equal(byName(products, "Dermatosis").matchText, "Psy Karma sucha dla psa Psotka karma dla psa sucha dla psa");
    assert.equal(byName(products, "chusteczki").matchText, "Koty Pielęgnacja kota pielegnacja kota dla kota dla psa dla gryzoni", "the shop's own animals");
    assert.ok(!byName(products, "skóra").name.includes("Przysmaki"));
    const noAnimals = tile({ title: "Psotka Gryzak", variant: "1 szt.", path: "/shop/psy/gryzaki_dla_psa/psotka/7", id: "7.0", price: "5,00 zł", petTypes: [] });
    assert.equal(parseZooplusPage(page([noAnimals], 1, []), "psy")!.products[0]!.matchText, "gryzaki dla psa dla psa", "no categories in the page: the address and the page's animal");
  });
});

// ---------- which pages ----------

describe("zooplus: the animal pages an item picks", () => {
  test("the animal the item names; dog and cat when it names none; birds have a page here", () => {
    assert.deepEqual(animalPages(["karma dla psa"]), [DOG]);
    assert.deepEqual(animalPages(["karma dla kota"]), [CAT]);
    assert.deepEqual(animalPages(["żwirek dla kociąt"]), [CAT]);
    assert.deepEqual(animalPages(["siano dla królika"]), [SMALL]);
    assert.deepEqual(animalPages(["ziarno dla papugi"]), [BIRDS]);
    assert.deepEqual(animalPages(["karma dla ptaków"]), [BIRDS]);
    assert.deepEqual(animalPages(["smycz"]), [DOG, CAT]);
    assert.deepEqual(animalPages(["karma z rybą"]), [DOG, CAT], "'z rybą' is what's in it");
    assert.deepEqual(animalPages(["kotlet"]), [DOG, CAT], "no cat in 'kotlet'");
    assert.equal(ZOOPLUS_PAGES.length, 4);
  });

  test("fish, terrarium animals and horses have no promotions page: they read none", () => {
    assert.deepEqual(animalPages(["pokarm dla rybek"]), []);
    assert.deepEqual(animalPages(["akwarium 60 l"]), []);
    assert.deepEqual(animalPages(["karma dla żółwia"]), []);
    assert.deepEqual(animalPages(["smakołyki dla konia"]), []);
    assert.deepEqual(animalPages(["pokarm dla rybek", "karma dla kota"]), [CAT]);
  });
});

// ---------- the adapter ----------

describe("zooplus: reading the shop", () => {
  test("one page for a dog item: robots.txt and that page only, as DoddyBot; a listing with more pages says so", async () => {
    const web = shopWeb();
    const l = ok(await zooplus.read(ctx(web, ["karma dla psa"])));
    assert.deepEqual(l.leaflet, { title: "Promocje zooplus", url: DOG });
    assert.equal(l.strategy, "none");
    assert.deepEqual(l.pages, []);
    assert.equal(l.products.length, 5);
    assert.ok(l.products.every((p) => p.conditions[0]?.text === ONLINE_ONLY));
    assert.equal(l.incomplete, "first_page_only", "only the first of twelve pages was read: 'nothing matched' can't be claimed");
    assert.deepEqual(web.requests.map((r) => r.url), ["https://www.zooplus.pl/robots.txt", DOG]);
    assert.equal(web.requests[1]!.headers["user-agent"], "DoddyBot/1.0 (+https://doddy.lol/bot)");
  });

  test("dog and cat by default; a product on both pages is one product; the person's words never reach the shop", async () => {
    const web = shopWeb();
    const l = ok(await zooplus.read(ctx(web, ["smycz odblaskowa Kłapouch"])));
    assert.equal(l.products.length, 7, "5 on the dog page, 3 on the cat page, the wipes on both");
    assert.equal(l.products.filter((p) => p.name.includes("chusteczki")).length, 1);
    assert.deepEqual([...web.hosts()], ["www.zooplus.pl"]);
    assert.deepEqual(web.requests.map((r) => r.url).sort(), ["https://www.zooplus.pl/robots.txt", CAT, DOG].sort());
    assert.ok(web.requests.every((r) => !/smycz|odblask|k%C5%82apouch/i.test(r.url)));
    const small = ok(await zooplus.read(ctx(shopWeb(), ["siano dla królika"])));
    assert.equal(small.leaflet.url, SMALL);
    assert.equal(small.incomplete, undefined, "a single-page listing is read whole");
  });

  test(`at most ${ZOOPLUS_MAX_PAGES} pages: a fourth animal isn't read, and the read says so`, async () => {
    const web = shopWeb();
    const l = ok(await zooplus.read(ctx(web, ["karma dla psa", "karma dla kota", "siano dla królika", "ziarno dla papugi"])));
    assert.equal(web.hits("https://www.zooplus.pl/shop/"), ZOOPLUS_MAX_PAGES);
    assert.equal(web.hits(BIRDS), 0);
    assert.equal(l.incomplete, "first_page_only,page_cap");
  });

  test("fish only: no page, no request, no leaflet", async () => {
    const web = shopWeb();
    assert.deepEqual(await zooplus.read(ctx(web, ["pokarm dla rybek"])), { kind: "no_leaflet" });
    assert.equal(web.requests.length, 0);
  });

  test("a block is blocked and never worked around; robots.txt that disallows the page means no request", async () => {
    const blocked = shopWeb({ [CAT]: undefined }).on(CAT, { status: 403 });
    assert.deepEqual(await zooplus.read(ctx(blocked, ["karma dla kota"])), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(blocked.hits(CAT), 1, "not retried");

    const both = shopWeb({}).on(DOG, { status: 429 }).on(CAT, { status: 429 });
    assert.equal((await zooplus.read(ctx(both, ["smycz"]))).kind, "blocked");

    const disallowed = new FakeWeb().robots("https://www.zooplus.pl", "User-agent: *\nDisallow: /shop/\n").on(CAT, { body: page(CAT_TILES) });
    const r = await zooplus.read(ctx(disallowed, ["karma dla kota"]));
    assert.equal(r.kind, "blocked");
    assert.equal(disallowed.hits(CAT), 0);
  });

  test("no data in the page is failed; an empty listing is no leaflet; one page failing makes the read incomplete", async () => {
    const bare = shopWeb({ [CAT]: "<html><body>Promocje dla kota</body></html>" });
    assert.deepEqual(await zooplus.read(ctx(bare, ["karma dla kota"])), { kind: "failed", reason: "no_payload" });
    const empty = shopWeb({ [CAT]: page([], null) });
    assert.deepEqual(await zooplus.read(ctx(empty, ["karma dla kota"])), { kind: "no_leaflet" });
    const half = shopWeb({ [DOG]: page(DOG_TILES, null) }).on(CAT, { status: 500 });
    const l = ok(await zooplus.read(ctx(half, ["smycz"])));
    assert.equal(l.products.length, 5);
    assert.equal(l.incomplete, "some_pages_failed");
  });
});
