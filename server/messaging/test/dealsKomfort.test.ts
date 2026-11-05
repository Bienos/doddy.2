// Komfort's leaflet reader against small SYNTHETIC stand-ins shaped like what komfort.pl and view.publitas.com served on
// 2026-10-30: the page's frame, spreads.json, and a text layer that runs grosze on without a comma and puts big price
// boxes apart from their names. Names, codes and prices are made up; Komfort's leaflet is not copied here.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { findLeaflet, KOMFORT_LISTING, komfort, komfortLeaflet, komfortLeafletUrl, komfortPages, komfortSpreads, leafletDates } from "../src/deals/chains/komfort.js";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { searchDeals } from "../src/deals/service.js";
import { DEFAULT_DEALS_SETTINGS, type ChainContext, type ChainRead, type LeafletRead } from "../src/deals/types.js";
import { fakeJpeg, FakeModel, FakeWeb, read } from "./dealsFakes.js";

const TODAY = "2026-10-30";
const SLUG = "gazetka-test-2026";
const SPREADS = komfortSpreads(SLUG);
const BASE = komfortLeafletUrl(SLUG);
/** komfort.pl's robots.txt in shape (trimmed): DoddyBot falls under `*`, which allows /st/gazetka. */
const ROBOTS = "User-agent: *\nDisallow: /search/*\nDisallow: /catalog/*\nDisallow: *klink=*\nDisallow: /cart\n\nUser-agent: ClaudeBot\nAllow: /\n";

const THIRTY = "Przekreślone ceny są najniższymi cenami z ostatnich 30 dni przed wprowadzeniem promocji.";
const frame = (src: string) => `<div class="gazetka-view">
  <div class="publitas-container">
    <iframe style="display:block;box-sizing:border-box" src="${src}" frameBorder="0" allowFullScreen=""></iframe>
  </div>
</div>`;
const button = (href: string) => `<div class="gazetka-page-wrap"><a href="${href}"><button class="gazetka-button">Sprawdź naszą ofertę w gazetce</button></a><br/></div>`;
const catalogue = '<nav><a href="https://view.publitas.com/sklepy-komfort-sa/katalog-dywanow-test">Katalog dywanów</a></nav>';
const LISTING = `<!DOCTYPE html><html><head><title>Gazetka | Komfort</title></head><body>${catalogue}
${frame(`https://view.publitas.com/sklepy-komfort-sa/${SLUG}/?publitas_embed=embedded`)}
${button(`https://view.publitas.com/sklepy-komfort-sa/${SLUG}`)}</body></html>`;

/** Page texts in the real layer's shape. "1099 749 /szt." is 1 099 zł and "4999 3999 /szt." 49,99 zł on the page image;
 * the flooring page's big price 54,97 zł/m² is "54" and "97" in runs of their own, away from its name. */
const TEXT: Record<number, string> = {
  1: `RABATY DO -30%\n\n${THIRTY}\nOferta ważna od 28.10 do 01.12.2026 r. lub do wyczerpania zapasów. Szczegóły w regulaminie.\n*\n\n`,
  2: `${THIRTY}\n\nDYWANY\n\nKOLEKCJA PRÓBNA\n229\n\n-34%\n\n149\n\nod\n\n/szt\n\n1. PRÓBNA BEIGE\n80 x 150 cm, kod: 100000001, 229 149 /szt.\n200 x 290 cm, kod: 100000002, 1099 749 /szt.\n\nWZÓR MANAUS\n60 x 120 cm, kod: 100000003, 9999 69 /szt.\n`,
  3: `${THIRTY}\n\nDYWANIKI\n\nDYWANIKI\nŁAZIENKOWE PRÓBNE\n50 x 80 cm 4999 3999 /szt.\n1. kod: 100000004\n2. kod: 100000005\n\n7999\n\n-20%\n\n6399\n/szt\n\nDYWANIK WZÓR\n60 x 90 cm\nkod: 100000006\n`,
  4: `${THIRTY}\n\n6499\n\n-15%\n\n54\n\n97\n\n4827\n/m2\n\n/m2\n\nprzy zakupie\nmontażu\n\nDĄB PRÓBNY\nkod: 100000007\n\nwodoodporne\n\nPANELE PODŁOGOWE\n\nKUPUJ PANELE 12% TANIEJ PRZY ZAKUPIE FIRMOWEGO MONTAŻU\n`,
  5: `${THIRTY}\n\nDRZWI\n\nDRZWI WEWNĘTRZNE\n\nPORTA PRÓBNA\n\n1341\n\nod\n\n/szt\n\nDRUGIE SKRZYDŁO DRZWIOWE -50%\n`,
  // A page whose text names no price at all.
  6: "Jesienne\n\nINSPIRACJE\n\nZnajdź\nswój kolor!\n",
  // A picture-only page: Publitas sends an empty text.
  7: "",
};
const imagePath = (n: number, size: string) => `/resize/rev-1/k${n}/fit-in/${size}/filters:quality(90)/production-revolution-publitas-com/1/2/pages/p-${n}.jpg`;
const spreadPage = (n: number) => ({
  images: { at2400: imagePath(n, "2072x2779"), at2000: imagePath(n, "1727x2316"), at1600: imagePath(n, "1382x1854") },
  screenshots: {}, text: TEXT[n], backgroundType: "color", backgroundColor: "#ffffff", number: n, id: 9000 + n,
});
/** Cover alone, then two pages a spread, as Publitas sends them; page 8's image is off Publitas and is dropped. */
const spreadsJson = (texts: Record<number, string> = TEXT) => [
  { pages: [{ ...spreadPage(1), text: texts[1] }] },
  { pages: [spreadPage(2), spreadPage(3)] },
  { pages: [spreadPage(4), spreadPage(5)] },
  { pages: [spreadPage(6), spreadPage(7)] },
  { pages: [{ ...spreadPage(8), images: { at2000: "https://evil.example/p-8.jpg" }, text: "PANELE PODŁOGOWE" }] },
];

function komfortWeb(spreads: unknown = spreadsJson()): FakeWeb {
  const web = new FakeWeb().robots("https://komfort.pl", ROBOTS);
  web.on(KOMFORT_LISTING, { headers: { "content-type": "text/html; charset=utf-8" }, body: LISTING });
  web.on(SPREADS, { headers: { "content-type": "application/json; charset=utf-8" }, body: JSON.stringify(spreads) });
  // Page images on Publitas's host (no robots.txt there: the fake answers 404, no rules).
  for (let n = 1; n <= 7; n++) {
    web.on(`https://view.publitas.com${imagePath(n, "1727x2316")}`, { headers: { "content-type": "image/jpeg" }, body: fakeJpeg(1727, 2316, `komfort:${n}`) });
  }
  return web;
}
const ctx = (web: FakeWeb, queries: string[] = ["panele"]): ChainContext => ({
  fetcher: new PoliteFetcher({ fetch: web.fetch }), queries, today: TODAY, signal: new AbortController().signal,
});
const ok = (r: ChainRead): LeafletRead[] => {
  assert.equal(r.kind, "ok", JSON.stringify(r));
  return r.kind === "ok" ? r.leaflets : [];
};

describe("Komfort", () => {
  test("the leaflet is the one in the page's frame, not a catalogue; the button when there's no frame; only Komfort's Publitas group", () => {
    assert.equal(findLeaflet(LISTING), SLUG);
    assert.equal(findLeaflet(`<html>${catalogue}${button(`https://view.publitas.com/sklepy-komfort-sa/${SLUG}`)}</html>`), SLUG);
    assert.equal(findLeaflet(`<html>${catalogue}</html>`), undefined, "a catalogue link alone is not the leaflet");
    assert.equal(findLeaflet(frame("https://view.publitas.com/another-shop/gazetka-2026/?publitas_embed=embedded")), undefined);
    assert.equal(findLeaflet(frame("https://evil.example/sklepy-komfort-sa/gazetka-2026/")), undefined);
  });

  test("the leaflet's dates come from its own text", () => {
    assert.deepEqual(leafletDates([TEXT[1]!]), { validFrom: "2026-10-28", validTo: "2026-12-01" });
    assert.deepEqual(leafletDates(["", "Oferta ważna od 28.12 do 10.01.2027 r."]), { validFrom: "2026-12-28", validTo: "2027-01-10" }, "a start in the year before");
    assert.deepEqual(leafletDates(["Oferta ważna od 03.11.2026 do 16.11.2026"]), { validFrom: "2026-11-03", validTo: "2026-11-16" });
    assert.deepEqual(leafletDates(["Oferta ważna do 15.11.2026 r."]), { validTo: "2026-11-15" });
    assert.deepEqual(leafletDates(["Oferta ważna od 31.02 do 05.03.2026"]), {}, "no such day");
    assert.deepEqual(leafletDates([TEXT[2]!, TEXT[6]!]), {});
  });

  test("pages carry Komfort's own text and the at2000 image on Publitas; an empty text stays empty; an image off Publitas is dropped", () => {
    const pages = komfortPages(spreadsJson(), SLUG);
    assert.deepEqual(pages.map((p) => p.number), [1, 2, 3, 4, 5, 6, 7], "page 8's image is not on view.publitas.com");
    const p4 = pages.find((p) => p.number === 4)!;
    assert.equal(p4.url, `${BASE}page/4`);
    assert.equal(p4.imageUrl, `https://view.publitas.com${imagePath(4, "1727x2316")}`);
    assert.match(p4.text!, /DĄB PRÓBNY kod: 100000007 .*PANELE PODŁOGOWE/, "whitespace collapsed, Komfort's words kept");
    assert.equal(pages.find((p) => p.number === 6)!.text, "Jesienne INSPIRACJE Znajdź swój kolor!", "a page with no price is still a page");
    assert.equal(pages.find((p) => p.number === 7)!.text, undefined);
    const atSixteen = [{ pages: [{ number: 1, text: "x", images: { at1600: imagePath(1, "1382x1854") } }] }];
    assert.equal(komfortPages(atSixteen, SLUG)[0]!.imageUrl, `https://view.publitas.com${imagePath(1, "1382x1854")}`, "at1600 when at2000 is missing");
    assert.deepEqual(komfortPages({ pages: [] }, SLUG), []);
    assert.deepEqual(komfortPages([{ pages: [{ number: 0, images: { at2000: imagePath(1, "x") } }, { number: 2.5, images: { at2000: imagePath(1, "x") } }] }], SLUG), []);
  });

  test("no price is taken from the text: 1 099 zł and 49,99 zł print alike there, so every page goes to the reader by its words", () => {
    const l = komfortLeaflet(spreadsJson(), SLUG, TODAY);
    assert.ok(l && l !== "not_current");
    assert.deepEqual(l.leaflet, { title: "Gazetka Komfort", url: BASE, validFrom: "2026-10-28", validTo: "2026-12-01" });
    assert.equal(l.strategy, "text");
    assert.deepEqual(l.products, [], "no DataProduct from a text that can't say where the grosze start");
    const texts = l.pages.map((p) => p.text ?? "").join("\n");
    assert.ok(texts.includes("1099 749 /szt.") && texts.includes("4999 3999 /szt."), "the two prices that read alike are in the text as printed");
    assert.equal(komfortLeaflet(spreadsJson(), SLUG, "2026-12-02"), "not_current");
    assert.equal(komfortLeaflet(spreadsJson(), SLUG, "2026-10-21"), "not_current", "starts more than six days ahead");
    const undated = komfortLeaflet(spreadsJson({ ...TEXT, 1: "RABATY DO -30%" }), SLUG, TODAY);
    assert.ok(undated && undated !== "not_current" && undated.leaflet.validFrom === undefined && undated.leaflet.validTo === undefined, "no printed dates: open");
    assert.equal(komfortLeaflet([], SLUG, TODAY), undefined);
  });

  test("the adapter: Komfort's page, then the leaflet's spreads.json; no image, no catalogue, nothing else", async () => {
    const web = komfortWeb();
    const [l, ...rest] = ok(await komfort.read(ctx(web)));
    assert.equal(rest.length, 0);
    assert.deepEqual(l!.leaflet, { title: "Gazetka Komfort", url: BASE, validFrom: "2026-10-28", validTo: "2026-12-01" });
    assert.equal(l!.strategy, "text");
    assert.equal(l!.pages.length, 7);
    assert.deepEqual(web.requests.map((r) => r.url), [
      "https://komfort.pl/robots.txt", KOMFORT_LISTING, "https://view.publitas.com/robots.txt", SPREADS,
    ]);
    assert.ok(web.requests.every((r) => r.headers["user-agent"]?.startsWith("DoddyBot/1.0")));
  });

  test("no leaflet on the page, or only a past one, is no_leaflet; a block is blocked; robots.txt is obeyed; a broken spreads.json fails", async () => {
    const empty = komfortWeb().on(KOMFORT_LISTING, { headers: { "content-type": "text/html" }, body: `<html>${catalogue}</html>` });
    assert.deepEqual(await komfort.read(ctx(empty)), { kind: "no_leaflet" });
    assert.equal(empty.hits("https://view.publitas.com/"), 0);
    const past = komfortWeb(spreadsJson({ ...TEXT, 1: "Oferta ważna od 01.10 do 27.10.2026 r." }));
    assert.deepEqual(await komfort.read(ctx(past)), { kind: "no_leaflet" });

    const blocked = komfortWeb().on(KOMFORT_LISTING, { status: 403 });
    assert.deepEqual(await komfort.read(ctx(blocked)), { kind: "blocked", reason: "blocked:http_403" });
    assert.equal(blocked.hits("https://view.publitas.com/"), 0, "a block isn't worked around by going to Publitas directly");
    const challenge = komfortWeb().on(SPREADS, { status: 429 });
    assert.deepEqual(await komfort.read(ctx(challenge)), { kind: "blocked", reason: "blocked:http_429" });

    const shut = komfortWeb().robots("https://komfort.pl", "User-agent: *\nDisallow: /st/\n");
    assert.deepEqual(await komfort.read(ctx(shut)), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(shut.hits(KOMFORT_LISTING), 0, "a disallowed page is never fetched");
    const publitasShut = komfortWeb().robots("https://view.publitas.com", "User-agent: *\nDisallow: /\n");
    assert.deepEqual(await komfort.read(ctx(publitasShut)), { kind: "blocked", reason: "disallowed:robots" });
    assert.equal(publitasShut.hits(SPREADS), 0);

    assert.deepEqual(await komfort.read(ctx(komfortWeb().on(SPREADS, { status: 404 }))), { kind: "failed", reason: "http_404" });
    assert.deepEqual(await komfort.read(ctx(komfortWeb({ error: "nope" }))), { kind: "failed", reason: "no_pages" });
    const offHost = komfortWeb().on(SPREADS, { status: 302, headers: { location: "https://evil.example/spreads.json" } })
      .on("https://evil.example/spreads.json", { headers: { "content-type": "application/json" }, body: JSON.stringify(spreadsJson()) });
    assert.deepEqual(await komfort.read(ctx(offHost)), { kind: "failed", reason: "redirected_off_host" }, "pages from off Komfort's hosts are not used");
  });

  test("through the search: \"panele\" sends only the page whose text names panels to the reader, and its price is the page image's", async () => {
    const web = komfortWeb();
    const model = new FakeModel().page("komfort:4", { products: [read({ name: "Panele podłogowe Dąb Próbny", price: "54,97", regularPrice: "64,99" })] });
    const { response } = await searchDeals({
      settings: DEFAULT_DEALS_SETTINGS, fetcher: new PoliteFetcher({ fetch: web.fetch }), model, now: () => new Date("2026-10-30T09:00:00Z"),
      adapters: { komfort },
    }, { items: ["panele"], chains: ["komfort"], language: "pl" });
    assert.deepEqual(model.reads.map((r) => r.marker), ["komfort:4"], "pages 2, 3, 5, 6 and 7 don't name panels; page 8 had no image on Publitas");
    assert.deepEqual(response.chains, [{ chain: "komfort", status: "checked", leaflet: { title: "Gazetka Komfort", url: BASE, validFrom: "2026-10-28", validTo: "2026-12-01" } }]);
    const [offer, ...more] = response.items[0]!.offers;
    assert.equal(more.length, 0);
    assert.equal(offer!.chain, "komfort");
    assert.equal(offer!.product, "Panele podłogowe Dąb Próbny");
    assert.deepEqual(offer!.price, { minor: 5497, currency: "PLN" });
    assert.equal(offer!.readBy, "page_image");
    assert.deepEqual(offer!.source, { url: `${BASE}page/4`, page: 4 });
  });
});
