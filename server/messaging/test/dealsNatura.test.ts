// Drogerie Natura's leaflet and promotions pages, against SYNTHETIC pages built here in the shape drogerienatura.pl
// served on 2026-10-30 (Magento, Hyvä theme: product tiles as add-to-cart forms, the shop's labels after each form).
// Names, ids and prices are made up; no copy of the shop's pages is kept. Nothing reaches the network.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import {
  labelCondition, leafletDates, NATURA_LEAFLET, NATURA_MAX_BYTES, NATURA_PROMOTIONS, natura, parseNaturaLeaflet, parseNaturaPromotions, plainText,
  printedUnit, productLabels,
} from "../src/deals/chains/natura.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import type { ChainContext, ChainRead, LeafletRead } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const ORIGIN = "https://drogerienatura.pl";
// The rules that matter here, as the shop's robots.txt wrote them on 2026-10-30.
const ROBOTS = "User-agent: *\nDisallow: /catalogsearch/*\nDisallow: /checkout*\nDisallow: /club/*\nDisallow: /*?q*\nDisallow: /*?cat*\nDisallow: /*?p*\n";

// ---------- a synthetic page in the shop's shape ----------

/** The shop's escaping in names: Latin-1 letters by name (&oacute;), other Polish letters as numbers (&#380;). */
const esc = (s: string) => [...s].map((ch) => (ch === "ó" ? "&oacute;" : ch.charCodeAt(0) > 127 ? `&#${ch.codePointAt(0)};` : ch)).join("");
/** A price as the tile prints it: "15,49&nbsp;z&#322;". */
const pl = (v: number) => `${v.toFixed(2).replace(".", ",")}&nbsp;z&#322;`;

interface Label { id: number; text: string; tooltip?: string }
interface TileInput {
  id: number; sku: string; name: string; price: number; old?: number; lowest?: number; lowestLabel?: string; unit?: string;
  labels?: Label[]; url?: string; popup?: boolean; minPrice?: boolean;
}

/** One tile and its labels. `listing` writes the attributes on separate lines and the label configs entity-escaped
 * in double quotes (the category page); otherwise one line with raw JSON in single quotes (the leaflet page). */
function tile(t: TileInput, listing = false): string {
  const nl = listing ? "\n      " : " ";
  const slug = t.name.toLowerCase().replace(/ł/g, "l").normalize("NFD").replace(/\p{M}+/gu, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  const url = t.url ?? `${ORIGIN}/produkt/${slug}`;
  const kind = t.popup ? `product-${t.sku}-popup` : listing ? `product-${t.sku} flex-col${nl}simple` : `product-${t.sku}-slider flex-col`;
  const priceSpan = (type: string, v: number, label: string) =>
    `<span class="price-container "><span id="${type}-${t.id}"${nl}data-price-amount="${v}"${nl}data-price-type="${type}"${nl}class="price-wrapper "><span class="price">${pl(v)}</span></span>`
    + `<span class="price-label">${label}</span></span>`;
  const form = `<form method="post"${nl}action="${ORIGIN}/checkout/cart/add/uenc/%25uenc%25/product/${t.id}/"${nl}data-product-id="${t.sku}"${nl}`
    + `class="relative item product product-item-trustmate product-item product_addtocart_form flex${nl}${kind} w-full p-2 ">`
    + `<input name="form_key" type="hidden" value="k3y"><input type="hidden" name="product" value="${t.id}">`
    + `<div class="relative image-section"><a href="${url}" class="product photo product-item-photo"><img src="https://media.example/p.jpg" alt="${esc(t.name)}"></a>`
    + `<a href="" x-data="initWishlist" data-product-id="${t.id}" class="wishlist-icon"><svg viewbox="0 0 24 22"><path d="M1 1"></path><title>heart</title></svg></a></div>`
    + `<div class="product-info flex flex-col"><div class="category-item hidden first:flex"><span class="font-light font-sm mb-1">Wszystkie produkty</span></div>`
    + `<h3 class="mt-1 mb-2 product-item-link-box text-center"><a class="product-item-link"${nl}href="${url}">${nl}${esc(t.name)}${nl}</a></h3><hr class="mb-1">`
    + `<script>function initPriceBox__1(){return {updatePrice(d){}}}</script>`
    + `<div class="pt-1 text-center product-price-html"><div class="price-box price-final_price" data-role="priceBox" data-product-id="${t.id}">`
    + (t.minPrice ? `<span class="minimal-price">${priceSpan("minPrice", t.price, "Od")}</span>`
      : `<span class="special-price text-price">${priceSpan("finalPrice", t.price, t.old ? "Cena promocyjna" : "")}</span>`)
    + (t.old ? `<span class="old-price ">${priceSpan("oldPrice", t.old, "Cena regularna")}</span>` : "")
    + (t.lowest ? `<div class="historical-price">${nl}${t.lowestLabel ?? "Najni&#380;sza cena towaru w okresie 30 dni przed wprowadzeniem obni&#380;ki"}`
      + `${nl}<span class="price text-xs font-regular text-gray-6${nl}line-through">${nl}${pl(t.lowest)}${nl}</span></div>` : "")
    + `</div></div>`
    + (t.unit ? `<div class="capacity-per-price text-center text-sm mt-2">${nl}${t.unit}</div>` : "")
    + `<div class="add-to-cart-btn"><button class="btn btn-primary" aria-label="Dodaj do koszyka"><svg><title>cart</title></svg></button></div>`
    + `<a href="${url}" class="see-more-link">wi&#281;cej</a></div></form>`;
  const labels = (t.labels ?? []).map((l) => {
    const config = JSON.stringify({ position: "bottom-left", size: "24", mode: "cat", move: 0, product: String(t.id), label: l.id, order: 9, redirect_url: "",
      tooltip: { backgroundColor: "", color: "#333333", status: 1, content: encodeURIComponent(l.tooltip ?? "") } });
    const attr = listing
      ? `data-amlabel-config="${config.replace(/"/g, "&quot;").replace(/:/g, "&#x3A;").replace(/\{/g, "&#x7B;").replace(/\}/g, "&#x7D;")}"`
      : `data-amlabel-config='${config}'`;
    return `<div class="amlabel-position-wrapper absolute amlabel-position-bottom-left-${t.id}-cat flex-col" x-data="initAmlabel" x-init="initLabel"${nl}${attr}${nl}>`
      + `<div x-ref="amLabel" class="group relative amasty-label-container amasty-label-container-${l.id}-${t.id}-cat amasty-label-for-${t.id}" data-amlabel-order="9">`
      + `<div style="height&#x3A;&#x20;20px;"><div${nl}class="amlabel-text text-center whitespace-nowrap">${nl}${esc(l.text)}${nl}</div></div></div></div>`;
  }).join("");
  return form + labels;
}

/** The site-wide "Nie zapomnij o:" carousel every page carries. */
const POPUP = [
  { id: 900, sku: "PP0001", name: "Pilnik do paznokci szary", price: 3.89, old: 6.99, lowest: 3.99, popup: true },
  { id: 13, sku: "LK0013", name: "Lśniąca Botanika szampon odżywczy do włosów 500ml", price: 9.99, popup: true },
];
const popup = (listing = false) => `<div class="aov-promo-products-pop-up"><h2 class="text-xl lg:text-2xl font-bold text-center">Nie zapomnij o:</h2>`
  + `<div class="glider-contain">${POPUP.map((t) => tile(t, listing)).join("")}</div></div>`;

const LEAFLET_TILES: TileInput[] = [
  { id: 11, sku: "PR0011", name: "Perełka sypki puder do twarzy Matowy 6 g", price: 16.99, unit: "1 g / 2.83 z&#322;", labels: [{ id: 15, text: "Tylko w Natura" }, { id: 2, text: "OKAZJA" }] },
  { id: 13, sku: "LK0013", name: "Lśniąca Botanika szampon odżywczy do włosów 500ml", price: 15.49, old: 19.99, lowest: 15.99, unit: "1 ml / 0.03 z&#322;", labels: [{ id: 208, text: "WŁOSY" }] },
  { id: 14, sku: "ZL0014", name: "Zielony Las płyn do płukania 2000 ml", price: 8.99, old: 9.99, lowest: 9.99, unit: "1 ml / 0.00 z&#322;" },
];

function leafletPage(tiles: TileInput[] = LEAFLET_TILES, heading = "Gazetka promocyjna wa&#380;na od 15.10 do 2.11.2026"): string {
  return `<!doctype html><html lang="pl"><head><title>Gazetka Promocyjna Drogerie Natura</title>`
    + `<style>.page-products form.promo-product { order: -1; } .amasty-label-container { border-radius: 50px; }</style></head><body>`
    // An Alpine template form the page carries for its own scripts: no product.
    + `<template><form action="/checkout/cart/add" method="post" :class="\`product_addtocart_form-\${index}\`"><span x-text="product.name"></span></form></template>`
    + `<div data-content-type="row"><h2 data-content-type="heading" data-appearance="default" data-element="main">${heading}</h2>`
    + `<iframe allowfullscreen src="https://heyzine.com/flip-book/abc123.html"></iframe>`
    + `<h2 class="text-2xl font-medium text-gray-900 title-font text-center">Promocje z gazetki</h2>`
    + `<div class="glider-contain product-items widget-product-carousel">${tiles.map((t) => tile(t)).join("")}</div></div>`
    + popup() + `</body></html>`;
}

const LISTING_TILES: TileInput[] = [
  { id: 13, sku: "LK0013", name: "Lśniąca Botanika szampon odżywczy do włosów 500ml", price: 15.49, old: 19.99, lowest: 15.99 },
  { id: 21, sku: "KR0021", name: "Kwiat Róży woda perfumowana damska 100 ml", price: 168.99, old: 189.99, lowest: 189.99, unit: "1 ml / 1.69 zł" },
  { id: 22, sku: "SK0022", name: "Skórka krem nawilżający z kwasem hialuronowym 50 ml", price: 18.89, unit: "1 ml / 0.38 zł",
    labels: [{ id: 2, text: "OKAZJA" }, { id: 210, text: "1+1 za 50%", tooltip: "Drugi produkt za 50% ceny" }, { id: 76, text: "", tooltip: "Drugi produkt za 50% ceny" }] },
  { id: 23, sku: "CW0023", name: "Czysta Woda wkład filtrujący 6 sztuk", price: 104.99, old: 129.99, lowest: 106.99, unit: "1 szt / 17.50 zł", labels: [{ id: 107, text: "Tylko online" }] },
  // A blank label whose tooltip names a mechanic: the tile shows none, so it is no condition.
  { id: 24, sku: "BR0024", name: "Biała Perła pasta do zębów 75 ml", price: 13.99, old: 23.99, lowest: 14.99, unit: "1 ml / 0.19 zł",
    labels: [{ id: 76, text: "", tooltip: "Drugi produkt za 50% ceny" }, { id: 205, text: "PERŁA", tooltip: "Drugi produkt za 50% ceny" }] },
  { id: 25, sku: "OB0025", name: "Obcy adres 100 ml", price: 5, url: "https://evil.example/produkt/obcy-100-ml" },
  { id: 26, sku: "KF0026", name: "Kategoria zamiast produktu 100 ml", price: 5, url: `${ORIGIN}/kategoria/promocje-4949` },
  { id: 27, sku: "WR0027", name: "Paleta cieni w wariantach 18 g", price: 39.99, minPrice: true },
];

function listingPage(tiles: TileInput[] = LISTING_TILES, shown = 56, total = 11177): string {
  return `<!doctype html><html lang="pl"><head><title>Promocje - Drogerie Natura</title></head><body>`
    + `<div class="toolbar toolbar-products"><p class="toolbar-amount text-sm leading-5" id="toolbar-amount">\n Pozycje od <span class="toolbar-number">1</span>`
    + ` do <span class="toolbar-number">${shown}</span> ze <span class="toolbar-number">${total}</span>\n</p>`
    + (total > shown ? `<nav class="pages"><ol class="items pages-items"><li class="item pages-item-next"><a href="${ORIGIN}/kategoria/promocje-4949?p=2" class="action next">Dalej</a></li></ol></nav>` : "")
    + `</div><div class="products wrapper mode-grid products-grid"><div class="grid product-grid">${tiles.map((t) => tile(t, true)).join("\n")}</div></div>`
    + popup(true) + `</body></html>`;
}

function shopWeb(pages: Partial<Record<string, string>> = { [NATURA_LEAFLET]: leafletPage(), [NATURA_PROMOTIONS]: listingPage() }): FakeWeb {
  const web = new FakeWeb().robots(ORIGIN, ROBOTS);
  for (const [url, body] of Object.entries(pages)) if (body !== undefined) web.on(url, { headers: { "content-type": "text/html; charset=UTF-8" }, body });
  return web;
}
const ctx = (web: FakeWeb, queries: string[] = ["szampon"], fetcher = new PoliteFetcher({ fetch: web.fetch })): ChainContext => ({
  fetcher, queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): { leaflets: LeafletRead[]; incomplete?: string } => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? r : (undefined as never);
};

// ---------- the parsers ----------

describe("Natura: the leaflet page", () => {
  test("its dates from the heading and each carousel tile as a product, with the leaflet's dates", () => {
    const l = parseNaturaLeaflet(leafletPage(), TODAY)!;
    assert.equal(l.validFrom, "2026-10-15");
    assert.equal(l.validTo, "2026-11-02");
    assert.equal(l.products.length, 3, "the site-wide 'Nie zapomnij o:' tiles and the script template aren't the leaflet's");
    assert.deepEqual(l.products[1], {
      name: "Lśniąca Botanika szampon odżywczy do włosów 500ml", price: { minor: 1549, currency: "PLN" },
      url: "https://drogerienatura.pl/produkt/lsniaca-botanika-szampon-odzywczy-do-wlosow-500ml", conditions: [],
      sizeText: "500ml", regularPrice: { minor: 1999, currency: "PLN" }, lowest30d: { minor: 1599, currency: "PLN" },
      validFrom: "2026-10-15", validTo: "2026-11-02",
    });
    assert.ok(!("printedUnitPrice" in l.products[1]!), "'1 ml / 0.03 zł' is rounded too far to cross-check 30,98 zł/l");
    assert.ok(l.products.every((p) => p.ean === undefined), "nothing on the page is labelled an EAN");
  });

  test("a price without a regular price is the leaflet's price alone; a unit price precise enough is kept as the matcher reads it", () => {
    const [powder, , rinse] = parseNaturaLeaflet(leafletPage(), TODAY)!.products;
    assert.equal(powder!.name, "Perełka sypki puder do twarzy Matowy 6 g");
    assert.deepEqual(powder!.price, { minor: 1699, currency: "PLN" });
    assert.equal(powder!.regularPrice, undefined);
    assert.equal(powder!.lowest30d, undefined);
    assert.equal(powder!.printedUnitPrice, "2,83 zł/1 g");
    assert.deepEqual(powder!.conditions, [], "'Tylko w Natura' and 'OKAZJA' name no mechanic");
    assert.equal(rinse!.printedUnitPrice, undefined, "'1 ml / 0.00 zł' says nothing");
    assert.deepEqual(rinse!.lowest30d, { minor: 999, currency: "PLN" }, "a 30-day price equal to the regular one is still the shop's fact");
  });

  test("dates: a leaflet over New Year, a start without a year, a heading that isn't a leaflet's", () => {
    assert.deepEqual(leafletDates("<h2>Gazetka promocyjna ważna od 20.12 do 5.01.2027</h2>", "2026-12-28"), { validFrom: "2026-12-20", validTo: "2027-01-05" });
    assert.deepEqual(leafletDates("<h2>Gazetka promocyjna wa&#380;na od 29.10.2026 do 11.11.2026</h2>", TODAY), { validFrom: "2026-10-29", validTo: "2026-11-11" });
    assert.deepEqual(leafletDates("<h2>Gazetka ważna od 15.10 do 2.11</h2>", TODAY), { validFrom: "2026-10-15", validTo: "2026-11-02" });
    assert.deepEqual(leafletDates("<h2>Promocje z gazetki</h2><p>ważna od 1.10 do 2.10.2026</p>", TODAY), {}, "only a heading gives the dates");
    assert.deepEqual(leafletDates("<h3>ważna od 12.11.2026 do 2.11.2026</h3>", TODAY), {}, "an end before the start is no range");
    const undated = parseNaturaLeaflet(leafletPage(LEAFLET_TILES, "Gazetka promocyjna"), TODAY)!;
    assert.equal(undated.products.length, 3);
    assert.ok(undated.products.every((p) => p.validFrom === undefined && p.validTo === undefined), "no dates made up");
  });

  test("a page with neither the leaflet's heading nor product tiles is no payload", () => {
    assert.equal(parseNaturaLeaflet("<html><body><h1>Strona nie została znaleziona</h1></body></html>", TODAY), undefined);
  });
});

describe("Natura: the promotions page", () => {
  test("its tiles, and whether the listing has more pages (the toolbar's count, else a next link)", () => {
    const list = parseNaturaPromotions(listingPage())!;
    assert.equal(list.more, true);
    assert.deepEqual(list.products.map((p) => p.name), [
      "Lśniąca Botanika szampon odżywczy do włosów 500ml", "Kwiat Róży woda perfumowana damska 100 ml",
      "Skórka krem nawilżający z kwasem hialuronowym 50 ml", "Czysta Woda wkład filtrujący 6 sztuk", "Biała Perła pasta do zębów 75 ml",
    ], "an off-host link, a category link and a variant's 'from' price are skipped");
    assert.ok(list.products.every((p) => p.validFrom === undefined && p.validTo === undefined), "the shop's tiles carry no dates");
    assert.equal(parseNaturaPromotions(listingPage(LISTING_TILES.slice(0, 2), 2, 2))!.more, false);
    const noCount = listingPage().replace(/<p class="toolbar-amount[\s\S]*?<\/p>/, "");
    assert.equal(parseNaturaPromotions(noCount)!.more, true, "a next-page link says there's more");
    assert.equal(parseNaturaPromotions("<html><body>Brak produktów</body></html>"), undefined);
  });

  test("labels that name a mechanic are conditions; a tooltip isn't read; an exact unit price is kept", () => {
    const [, perfume, cream, filter, paste] = parseNaturaPromotions(listingPage())!.products;
    assert.deepEqual(cream!.conditions, [{ kind: "nth_discount", quantity: 2, percent: 50 }]);
    assert.equal(cream!.regularPrice, undefined);
    assert.equal(cream!.printedUnitPrice, "0,38 zł/1 ml");
    assert.deepEqual(filter!.conditions, [{ kind: "other", text: "tylko online" }]);
    assert.equal(filter!.sizeText, "6 sztuk");
    assert.equal(filter!.printedUnitPrice, "17,50 zł/1 szt");
    assert.deepEqual(paste!.conditions, [], "a blank label's tooltip ('Drugi produkt za 50% ceny') is not the tile's");
    assert.equal(paste!.printedUnitPrice, undefined, "0,19 zł a ml is rounded by more than 2 %");
    assert.equal(perfume!.printedUnitPrice, "1,69 zł/1 ml");
    assert.deepEqual(perfume!.lowest30d, { minor: 18999, currency: "PLN" });
  });

  test("the 30-day price only when the page labels it so", () => {
    const other = listingPage([{ id: 31, sku: "X31", name: "Krem 50 ml", price: 10, old: 15, lowest: 12, lowestLabel: "Cena sprzed obniżki" }], 1, 1);
    const [p] = parseNaturaPromotions(other)!.products;
    assert.equal(p!.lowest30d, undefined);
    assert.deepEqual(p!.regularPrice, { minor: 1500, currency: "PLN" });
    const lower = listingPage([{ id: 32, sku: "X32", name: "Krem 50 ml", price: 10, old: 9 }], 1, 1);
    assert.equal(parseNaturaPromotions(lower)!.products[0]!.regularPrice, undefined, "an old price not above the price isn't kept");
  });

  test("labels are found by the shop's product id in both of its escapings", () => {
    const labels = productLabels(listingPage() + leafletPage());
    assert.deepEqual(labels.get("22"), ["OKAZJA", "1+1 za 50%"]);
    assert.deepEqual(labels.get("11"), ["Tylko w Natura", "OKAZJA"]);
    assert.deepEqual(labels.get("13"), ["WŁOSY"]);
    assert.deepEqual(labels.get("24"), ["PERŁA"], "blank labels aren't kept");
  });
});

describe("Natura: label texts and unit prices", () => {
  test("a label that names a mechanic, in the code's words; others are no condition", () => {
    assert.deepEqual(labelCondition("1+1 za 50%"), { kind: "nth_discount", quantity: 2, percent: 50 });
    assert.deepEqual(labelCondition("2+1 za 50%"), { kind: "nth_discount", quantity: 3, percent: 50 });
    assert.deepEqual(labelCondition("1+1 za 5 zł"), { kind: "second_for", price: { minor: 500, currency: "PLN" } });
    assert.deepEqual(labelCondition("1+1 za 1 grosz"), { kind: "second_for", price: { minor: 1, currency: "PLN" } });
    assert.deepEqual(labelCondition("2+1 za 1 zł"), { kind: "other", text: "2+1 za 1 zł" }, "shown as printed: no kind states it");
    assert.deepEqual(labelCondition("2+1 gratis"), { kind: "multi_buy", text: "2+1" });
    assert.deepEqual(labelCondition("3 za 2"), { kind: "multi_buy", text: "2+1" });
    assert.deepEqual(labelCondition("Druga sztuka -40%"), { kind: "nth_discount", quantity: 2, percent: 40 });
    assert.deepEqual(labelCondition("-20% przy zakupie 2 szt."), { kind: "min_quantity", quantity: 2 });
    assert.deepEqual(labelCondition("Cena w aplikacji"), { kind: "app" });
    assert.deepEqual(labelCondition("Cena z Natura Club"), { kind: "card" });
    assert.deepEqual(labelCondition("Tylko online"), { kind: "other", text: "tylko online" });
    for (const none of ["OKAZJA", "BESTSELLER", "Tylko w Natura", "NOWOŚĆ", "BOO", "-30%", "do -50%", "Retinobaza 17 000", "SPF 50+", "Krem pod makijaż"]) {
      assert.equal(labelCondition(none), undefined, none);
    }
  });

  test("the shop's unit price as the matcher reads it, only when the size is known, in the same unit, and precise enough", () => {
    assert.equal(printedUnit("1 g / 2.83 zł", "6 g"), "2,83 zł/1 g");
    assert.equal(printedUnit("1 szt / 0.45 zł", "24 sztuki"), "0,45 zł/1 szt");
    assert.equal(printedUnit("1 ml / 0.38 zł", "50 ml"), "0,38 zł/1 ml", "a grosz is 1.3 % of 0,38 zł");
    assert.equal(printedUnit("1 ml / 0.19 zł", "75 ml"), undefined, "half a grosz is 2.6 % of 0,19 zł");
    assert.equal(printedUnit("1 ml / 0.00 zł", "2000 ml"), undefined);
    assert.equal(printedUnit("1 ml / 0.50 zł", "30 g"), undefined, "priced per ml for a pack in grams");
    assert.equal(printedUnit("1 szt / 10.49 zł", undefined), undefined, "no size, nothing to cross-check");
    assert.equal(printedUnit("ok. 1 zł", "50 ml"), undefined);
  });

  test("text: tags out, the shop's named and numbered entities decoded", () => {
    assert.equal(plainText("Botanika <b>Szampon</b> Od&#380;ywczy do w&#322;os&oacute;w&nbsp;500ml"), "Botanika Szampon Odżywczy do włosów 500ml");
  });
});

// ---------- the adapter ----------

describe("Natura: reading the shop", () => {
  test("robots.txt, the leaflet page, the promotions' first page: nothing else, nothing of the person's words", async () => {
    const web = shopWeb();
    const r = ok(await natura.read(ctx(web, ["szampon do włosów", "pasta do zębów"])));
    assert.deepEqual(web.requests.map((q) => q.url), [`${ORIGIN}/robots.txt`, NATURA_LEAFLET, NATURA_PROMOTIONS]);
    assert.ok(web.requests.every((q) => q.headers["user-agent"] === "DoddyBot/1.0 (+https://doddy.lol/bot)"));
    assert.ok(web.requests.every((q) => !/szampon|pasta|%20|\?/.test(q.url)), "no search, no second page");
    assert.equal(web.hits(`${NATURA_PROMOTIONS}?p=`), 0);
    assert.deepEqual([...web.hosts()], ["drogerienatura.pl"]);

    const [leaflet, promotions] = r.leaflets;
    assert.deepEqual(leaflet!.leaflet, { title: "Gazetka Natura", url: NATURA_LEAFLET, validFrom: "2026-10-15", validTo: "2026-11-02" });
    assert.equal(leaflet!.strategy, "none");
    assert.deepEqual(leaflet!.pages, []);
    assert.equal(leaflet!.products.length, 3);
    assert.deepEqual(promotions!.leaflet, { title: "Promocje Natura", url: NATURA_PROMOTIONS });
    assert.equal(promotions!.strategy, "none");
    assert.deepEqual(promotions!.products.map((p) => p.name), [
      "Kwiat Róży woda perfumowana damska 100 ml", "Skórka krem nawilżający z kwasem hialuronowym 50 ml",
      "Czysta Woda wkład filtrujący 6 sztuk", "Biała Perła pasta do zębów 75 ml",
    ], "the shampoo on both pages is the leaflet's, with its dates");
    assert.equal(r.incomplete, "leaflet_in_part,first_page_only", "the carousel is part of the leaflet; one page of the promotions");
  });

  test("a promotions page over Natura's own cap (6 MB): the leaflet alone, read in part", async () => {
    const big = listingPage() + `<!-- ${"x".repeat(NATURA_MAX_BYTES)} -->`;
    const web = shopWeb({ [NATURA_LEAFLET]: leafletPage(), [NATURA_PROMOTIONS]: big });
    const r = ok(await natura.read(ctx(web, ["szampon"], new PoliteFetcher({ fetch: web.fetch }))));
    assert.equal(r.leaflets.length, 1);
    assert.equal(r.leaflets[0]!.leaflet.url, NATURA_LEAFLET);
    assert.equal(r.incomplete, "leaflet_in_part,some_pages_failed");
    assert.equal(web.hits(NATURA_PROMOTIONS), 1, "not retried");
  });

  test("the 3.9 MB promotions page of 13 Nov 2026 is read: past the fetcher's 3 MB, inside Natura's 6 MB", async () => {
    const page = listingPage() + `<!-- ${"x".repeat(3_900_000 - listingPage().length)} -->`;
    const web = shopWeb({ [NATURA_LEAFLET]: leafletPage(), [NATURA_PROMOTIONS]: page });
    const r = ok(await natura.read(ctx(web, ["szampon"], new PoliteFetcher({ fetch: web.fetch }))));
    assert.deepEqual(r.leaflets.map((l) => l.leaflet.url), [NATURA_LEAFLET, NATURA_PROMOTIONS]);
    assert.equal(r.incomplete, "leaflet_in_part,first_page_only", "no page failed; the leaflet's PDF is still not read");
  });

  test("an ended leaflet's products aren't offered; the promotions still are, the shampoo among them", async () => {
    const web = shopWeb({ [NATURA_LEAFLET]: leafletPage(LEAFLET_TILES, "Gazetka promocyjna ważna od 1.10 do 14.10.2026"), [NATURA_PROMOTIONS]: listingPage() });
    const r = ok(await natura.read(ctx(web)));
    assert.equal(r.leaflets.length, 1);
    assert.equal(r.leaflets[0]!.leaflet.url, NATURA_PROMOTIONS);
    assert.equal(r.leaflets[0]!.products[0]!.name, "Lśniąca Botanika szampon odżywczy do włosów 500ml");
    assert.equal(r.leaflets[0]!.products[0]!.validTo, undefined);
  });

  test("a block is blocked and never worked around: after it nothing more is asked; robots.txt that disallows means no request", async () => {
    const blocked = shopWeb({ [NATURA_PROMOTIONS]: listingPage() }).on(NATURA_LEAFLET, { status: 403 });
    assert.deepEqual(await natura.read(ctx(blocked)), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(blocked.hits(NATURA_LEAFLET), 1, "not retried");
    assert.equal(blocked.hits(NATURA_PROMOTIONS), 0, "the shop said no: the promotions aren't asked");

    const late = shopWeb({ [NATURA_LEAFLET]: leafletPage() }).on(NATURA_PROMOTIONS, { status: 429 });
    const r = ok(await natura.read(ctx(late)));
    assert.equal(r.leaflets.length, 1);
    assert.equal(r.incomplete, "leaflet_in_part,some_pages_failed");

    const disallowed = new FakeWeb().robots(ORIGIN, "User-agent: *\nDisallow: /\n").on(NATURA_LEAFLET, { body: leafletPage() }).on(NATURA_PROMOTIONS, { body: listingPage() });
    assert.equal((await natura.read(ctx(disallowed))).kind, "blocked");
    assert.equal(disallowed.hits(NATURA_LEAFLET) + disallowed.hits(NATURA_PROMOTIONS), 0);
  });

  test("pages without the shop's data are failed; pages with no products are no leaflet; one page failing still reads the other", async () => {
    const bare = shopWeb({ [NATURA_LEAFLET]: "<html><body>Gazetka</body></html>", [NATURA_PROMOTIONS]: "<html><body>Promocje</body></html>" });
    assert.deepEqual(await natura.read(ctx(bare)), { kind: "failed", reason: "no_payload" });
    const empty = shopWeb({ [NATURA_LEAFLET]: leafletPage([]), [NATURA_PROMOTIONS]: listingPage([], 0, 0) });
    assert.deepEqual(await natura.read(ctx(empty)), { kind: "no_leaflet" });
    const gone = shopWeb({ [NATURA_PROMOTIONS]: listingPage() }).on(NATURA_LEAFLET, { status: 404 });
    const r = ok(await natura.read(ctx(gone)));
    assert.equal(r.leaflets[0]!.leaflet.url, NATURA_PROMOTIONS);
    assert.equal(r.leaflets[0]!.products.length, 5);
    assert.equal(r.incomplete, "first_page_only,some_pages_failed");
  });
});
