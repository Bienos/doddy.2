// Reading fetched pages and feeds in linear time (src/htmlScan.ts). Regexes such as /<[^>]*x[^>]*>/g or
// /<x>([\s\S]*?)<\/x>/g start again at every "<" and read on to the end each time, so a page full of "<" without ">"
// took seconds per 100 KB. Here every public parser that reads a fetched page or feed runs on 2 to 3 MB of such
// input in well under 200 ms, and typical pages and feeds give the same results as the regexes did.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { capHtml, elements, forwardFinder, replaceSpans, spans, startTags, stripTags } from "../src/htmlScan.js";
import { checkOfferPage, fromJsonLd, fromMicrodata, fromOpenGraph, MAX_JSON_LD_CHARS } from "../src/shopping/pagecheck.js";
import { FEED_TEXT_MAX_CHARS, firstImgSrc, itemImage, parseFeed, plainText } from "../src/news/feeds.js";
import { hasBlockedTitle, looksLikeChallenge } from "../src/deals/fetcher.js";
import { productLabels, parseNaturaLeaflet, parseNaturaPromotions } from "../src/deals/chains/natura.js";
import { parseCccPage } from "../src/deals/chains/ccc.js";
import { parseDeichmannPage } from "../src/deals/chains/deichmann.js";
import { parseListing as parseLeclercListing } from "../src/deals/chains/leclerc.js";
import { parseOverview } from "../src/deals/chains/lidl.js";
import { findLeaflet } from "../src/deals/chains/komfort.js";
import { flightRows as actionFlightRows } from "../src/deals/chains/action.js";
import { flightRows as zooplusFlightRows } from "../src/deals/chains/zooplus.js";
import { parseMaxiZooPage } from "../src/deals/chains/maxizoo.js";
import { nuxtLeaflets } from "../src/deals/chains/dino.js";
import { parsePromotions } from "../src/deals/chains/rossmann.js";
import { parseGazetki } from "../src/deals/chains/delikatesy.js";
import { nextFlightPushes, scriptText } from "../src/deals/chains/common.js";

const MB = 1024 * 1024;
const TODAY = "2026-11-12";
/** `token` repeated to `size` characters. */
const fill = (token: string, size = 3 * MB) => token.repeat(Math.ceil(size / token.length)).slice(0, size);
const LT_3MB = fill("<");
const LT_2MB = fill("<", 2 * MB);
/** Well under the 200 ms the brief allows; the regexes took minutes on these inputs. */
const LIMIT_MS = 200;

function fast(label: string, run: () => unknown): void {
  const t = performance.now();
  run();
  const ms = performance.now() - t;
  assert.ok(ms < LIMIT_MS, `${label} took ${ms.toFixed(0)} ms`);
}

describe("the helpers find what the regexes they replace found", () => {
  const corpus = [
    "", "plain text", "<p>a</p>", "a < b and c > d", "x < y < z > w", "<a <b>c</a>", "<<<>>>", "<img alt=\"a<b\" src='x'>", "<", ">", "<a", "a>",
    "<div class=\"x\">one</div><div>two</div>", "<p>unclosed <b>bold", "<!-- c --><br/><hr >", "<SCRIPT>x</SCRIPT><script>y</script>",
    "<span>1</span><span x>2</span><span>3", "<a href=\"/x\">l</a><A HREF='/y'>m</A>", "<form <form a>b</form>",
  ];

  test("stripTags is s.replace(/<[^>]*>/g, by)", () => {
    for (const s of corpus) {
      assert.equal(stripTags(s), s.replace(/<[^>]*>/g, " "), JSON.stringify(s));
      assert.equal(stripTags(s, ""), s.replace(/<[^>]*>/g, ""), JSON.stringify(s));
    }
  });

  test("startTags gives the matches of /<name[^>]*>/g, also with an attribute test", () => {
    for (const s of corpus) {
      assert.deepEqual([...startTags(s, /</g)].map((t) => [t.index, t.text]), [...s.matchAll(/<[^>]*>/g)].map((m) => [m.index, m[0]]), JSON.stringify(s));
      assert.deepEqual([...startTags(s, /<a\b/gi)].map((t) => t.text), [...s.matchAll(/<a\b[^>]*>/gi)].map((m) => m[0]), JSON.stringify(s));
      assert.deepEqual([...startTags(s, /</g)].filter((t) => /href=/i.test(t.text)).map((t) => t.text),
        [...s.matchAll(/<[^>]*href=[^>]*>/gi)].map((m) => m[0]), JSON.stringify(s));
    }
  });

  test("elements give the matches of /<x\\b[^>]*>([\\s\\S]*?)<\\/x>/g", () => {
    for (const s of corpus) {
      assert.deepEqual([...elements(s, /<span\b/g, "</span>")].map((e) => e.content), [...s.matchAll(/<span\b[^>]*>([\s\S]*?)<\/span>/g)].map((m) => m[1]), JSON.stringify(s));
      assert.deepEqual([...elements(s, /<script/gi, /<\/script>/gi)].map((e) => e.content), [...s.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)].map((m) => m[1]), JSON.stringify(s));
    }
  });

  test("spans and replaceSpans match /OPEN[\\s\\S]*?CLOSE/g", () => {
    for (const s of corpus) {
      assert.deepEqual([...spans(s, /<div/g, "</div>")].map((x) => s.slice(x.index, x.end)), [...s.matchAll(/<div[\s\S]*?<\/div>/g)].map((m) => m[0]), JSON.stringify(s));
      assert.equal(replaceSpans(s, /<b/gi, /<\/b>/gi, "_"), s.replace(/<b[\s\S]*?<\/b>/gi, "_"), JSON.stringify(s));
    }
  });

  test("forwardFinder answers like indexOf, reusing an answer it already has", () => {
    const s = "a>b>>c";
    const next = forwardFinder(s, ">");
    for (const from of [0, 1, 2, 3, 4, 5, 6, 2, 0]) assert.equal(next(from)?.index ?? -1, s.indexOf(">", from), String(from));
  });

  test("capHtml cuts at the limit and drops a tag the cut splits", () => {
    assert.equal(capHtml("short", 10), "short");
    assert.equal(capHtml("<p>hello</p> world", 15), "<p>hello</p> wo");
    assert.equal(capHtml("<p>hello <a href='x'>link</a>", 15), "<p>hello ");
  });
});

describe("pages and feeds of 2 to 3 MB are read in linear time", () => {
  test("check_offer_page's structured-data readers", async () => {
    for (const html of [LT_3MB, fill('<script type="application/ld+json">'), fill("<script "), fill('<x itemprop="price" '), fill('<meta property="og:price:amount" ')]) {
      fast("fromJsonLd", () => fromJsonLd(html));
      fast("fromMicrodata", () => fromMicrodata(html));
      fast("fromOpenGraph", () => fromOpenGraph(html));
    }
    const fetcher = { fetchPage: async () => ({ kind: "ok" as const, status: 200, contentType: "text/html", body: Buffer.from(LT_3MB), finalUrl: "https://shop.example/p" }) };
    const t = performance.now();
    assert.equal((await checkOfferPage("https://shop.example/p", fetcher)).kind, "no_price");
    assert.ok(performance.now() - t < LIMIT_MS);
  });

  test("feed text, feed pictures and a feed with a 2 MB field", () => {
    for (const html of [LT_2MB, fill("<img ", 2 * MB), fill('<img src="a', 2 * MB), fill("<img src=", 2 * MB)]) {
      fast("plainText", () => plainText(html, 300));
      fast("itemImage", () => itemImage({}, html));
      fast("firstImgSrc", () => firstImgSrc(html));
    }
    const rss = `<rss><channel><title>T</title><item><title>A</title><link>https://a.example/1</link><description><![CDATA[${LT_2MB}]]></description></item></channel></rss>`;
    const atom = `<feed><title>T</title><entry><title>A</title><link href="https://a.example/1"/><content><![CDATA[${fill("<img ", 2 * MB)}]]></content></entry></feed>`;
    fast("parseFeed rss", () => assert.equal(parseFeed(rss, "x").items.length, 1));
    fast("parseFeed atom", () => assert.equal(parseFeed(atom, "x").items.length, 1));
  });

  test("the fetcher's challenge check", () => {
    const html = fill("<title>captcha");
    fast("hasBlockedTitle", () => assert.equal(hasBlockedTitle(html), false));
    fast("looksLikeChallenge", () => looksLikeChallenge(new Headers({ "content-type": "text/html" }), Buffer.from(html)));
  });

  test("the chains' page readers", () => {
    const pages = [LT_3MB, fill("<script "), fill("<form "), fill('<div class="'), fill("<span "), fill("<a "), fill("<h2 "), fill("<p "), fill("<input ")];
    const readers: [string, (html: string) => unknown][] = [
      ["natura leaflet", (h) => parseNaturaLeaflet(h, TODAY)], ["natura promotions", (h) => parseNaturaPromotions(h)], ["natura labels", (h) => productLabels(h)],
      ["ccc", (h) => parseCccPage(h, "buty")], ["ccc tile", (h) => parseCccPage(`<o-product-box>${h}`, "buty")],
      ["deichmann", (h) => parseDeichmannPage(h, "buty")], ["deichmann tile", (h) => parseDeichmannPage(`<deich-lib-product-tile>${h}`, "buty")],
      ["leclerc", (h) => parseLeclercListing(`class="newspapers-list"${h}`, TODAY)], ["lidl", (h) => parseOverview(h)], ["komfort", (h) => findLeaflet(h)],
      ["action", (h) => actionFlightRows(h)], ["zooplus", (h) => zooplusFlightRows(h)], ["maxi zoo", (h) => parseMaxiZooPage(h)], ["dino", (h) => nuxtLeaflets(h)],
      ["rossmann", (h) => parsePromotions(h, TODAY)], ["delikatesy", (h) => parseGazetki(h, TODAY)],
    ];
    for (const [name, read] of readers) for (const page of pages) fast(name, () => read(page));
    // Inputs aimed at each reader's own markers, 1 MB each: some make tens of thousands of small tiles, each read in
    // full, so 3 MB of them comes close to the limit on a slow machine. The regexes took minutes on these too.
    const marks = (token: string) => fill(token, MB);
    fast("natura forms", () => parseNaturaLeaflet(marks('<form class="product_addtocart_form" data-product-id="1"><div class="historical-price">'), TODAY));
    fast("natura labels", () => productLabels(marks('data-amlabel-config="{&quot;product&quot;:&quot;1&quot;}"<div class="amlabel-text')));
    fast("natura attributes", () => parseNaturaLeaflet(`<form class="product_addtocart_form" data-product-id="1" ${marks("a")}>`, TODAY));
    fast("ccc tile markers", () => parseCccPage(`<o-product-box>${marks('<span id="model-1"<shared-atoms-pricing<shared-molecules-sticker')}`, "buty"));
    fast("deichmann tile markers", () => parseDeichmannPage(`<deich-lib-product-tile>${marks('<h2 class="brandname"<span data-id="selling-price"<a href="')}`, "buty"));
    fast("leclerc articles", () => parseLeclercListing(`class="newspapers-list"${marks('<article id="newspaper-1">var pagesDesktop = [')}`, TODAY));
    fast("lidl links", () => parseOverview(marks('<a href="https://www.lidl.pl/l/pl/gazetki/a/ar/1" class="flyer"')));
    fast("komfort button", () => findLeaflet(marks('<a href="https://view.publitas.com/sklepy-komfort-sa/x-1/" ')));
    fast("next pushes", () => nextFlightPushes(marks("<script>self.__next_f.push([")));
    fast("nuxt payload", () => scriptText(marks('<script id="__NUXT_DATA__">'), (t) => /__NUXT_DATA__/.test(t), true));
    fast("next data", () => parsePromotions(marks('<script id="__NEXT_DATA__" type="application/json">'), TODAY));
  });
});

describe("typical pages and feeds read as before", () => {
  const offer = (o: object, extra: object = {}) => JSON.stringify({ "@context": "https://schema.org", "@type": "Product", name: "Lodówka", ...extra, offers: o });

  test("JSON-LD among other scripts, in any case and quoting, comments and a breadcrumb block included", () => {
    const head = `<head><script>var a = "<b>";</script><script type="application/ld+json">{"@type":"BreadcrumbList"}</script>`;
    const pages = [
      `${head}<SCRIPT TYPE='application/ld+json' id="p">${offer({ "@type": "Offer", price: "1899.00", priceCurrency: "PLN" })}</SCRIPT></head>`,
      `${head}<script data-x="1" type = "application/ld+json"><!--${offer({ "@type": "Offer", price: 1899, priceCurrency: "pln" })}--></script>`,
      `<html><body>${"<div>x</div>".repeat(2000)}<script type="application/ld+json">\n${offer({ "@type": "Offer", price: "1899", priceCurrency: "PLN" })}\n</script></body></html>`,
    ];
    for (const p of pages) assert.deepEqual(fromJsonLd(p), { name: "Lodówka", price: { minor: 189900, currency: "PLN" }, availability: undefined, gtin: undefined, seller: undefined, source: "json_ld" });
    assert.equal(fromJsonLd(`<script type="application/ld+json">${offer({ price: 1, priceCurrency: "PLN" })}`), undefined, "a block that never closes is not read");
  });

  test("a JSON-LD block over 256 KB is skipped; the next one is still read", () => {
    const big = `<script type="application/ld+json">${offer({ price: 5, priceCurrency: "PLN" }, { description: "x".repeat(MAX_JSON_LD_CHARS) })}</script>`;
    const small = `<script type="application/ld+json">${offer({ price: 7, priceCurrency: "PLN" })}</script>`;
    assert.equal(fromJsonLd(big), undefined);
    assert.equal(fromJsonLd(big + small)?.price.minor, 700);
  });

  test("microdata and Open Graph tags, whatever comes before them", () => {
    const micro = `<p>Cena < 2000 zł</p><div itemscope itemtype="https://schema.org/Offer"><span itemprop="price" content="1899.00">1 899 zł</span>`
      + `<meta itemprop="priceCurrency" content="PLN"></div>`;
    assert.deepEqual(fromMicrodata(micro), { price: { minor: 189900, currency: "PLN" }, source: "microdata" });
    assert.equal(fromMicrodata(micro + '<span ITEMPROP="price" content="5">'), undefined, "two prices are none");
    const og = '<meta charset="utf-8"><META property="og:price:amount" content="2299"><meta name="x" property="og:price:currency" content="pln">';
    assert.deepEqual(fromOpenGraph(og), { price: { minor: 229900, currency: "PLN" }, source: "open_graph" });
    assert.equal(fromOpenGraph(og + '<metadata property="og:price:amount" content="1">'), undefined, "as before, <metadata counts as a meta tag");
  });

  test("feed text: tags out, CDATA and entities decoded, cut at the limit", () => {
    // The regexes plainText used before, kept here as the reference.
    const before = (s: string, max: number) => {
      let t = s.replace(/<!\[CDATA\[|\]\]>/g, "").replace(/<[^>]*>/g, " ");
      t = t.replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16))).replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
        .replace(/&([a-z]+);/gi, (m, n: string) => ({ amp: "&", lt: "<", gt: ">", quot: '"', nbsp: " ", hellip: "…" } as Record<string, string>)[n.toLowerCase()] ?? m);
      t = t.replace(/\s+/g, " ").trim();
      return t.length > max ? t.slice(0, max - 1).trimEnd() + "…" : t;
    };
    const texts = [
      "<p>Rząd przyjął <b>projekt</b> ustawy &amp; budżet</p>", "<![CDATA[<p>Tytuł &#x41;&#66; &hellip;</p>]]>", "a < b and c > d", "<img src=\"x.jpg\"><br/>Tekst\n\n  dalej",
      `<p>${"Słowo ".repeat(200)}</p>`, "&lt;b&gt; zostaje", "x < y < z > w",
    ];
    for (const s of texts) for (const max of [300, 40]) assert.equal(plainText(s, max), before(s, max), JSON.stringify(s));
  });

  test("a feed field over the limit: the start is read, a tag the cut splits is dropped", () => {
    const start = "<p>Na początku tekst.</p>";
    const long = start + "<p>" + "x".repeat(FEED_TEXT_MAX_CHARS) + "</p>";
    assert.equal(plainText(long, 30), "Na początku tekst. xxxxxxxxxx…");
    const split = start + " ".repeat(FEED_TEXT_MAX_CHARS - start.length - 5) + '<a href="https://a.example/x">link</a>';
    assert.equal(plainText(split, 300), "Na początku tekst.");
  });

  test("feed pictures: the first <img> with an address, as the regex chose it", () => {
    const before = (s: string) => /<img[^>]+src=["']([^"']+)["']/i.exec(s)?.[1];
    const html = [
      '<p>x</p><img src="https://a.example/1.jpg" alt="a">', "<IMG class='hero' SRC='https://a.example/2.png'>", '<img alt="x" src="https://a.example/3.jpg" data-src="https://a.example/4.jpg">',
      '<img src="">' + '<img src="https://a.example/5.jpg">', "<img>", '<img src="https://a.example/6.jpg', '<imgsrc="https://a.example/7.jpg">', '<img alt="a>b" src="https://a.example/8.jpg">',
      `<img data-x='y' src="https://a.example/9.jpg'>`, "no picture",
    ];
    for (const s of html) assert.equal(firstImgSrc(s), before(s), s);
    assert.equal(itemImage({}, '<p><img src="https://a.example/1.jpg"></p>'), "https://a.example/1.jpg");
    assert.equal(itemImage({}, '<img src="http://a.example/1.jpg">'), undefined, "https only");
  });

  test("a challenge title is still recognised", () => {
    const html = (title: string) => Buffer.from(`<html><head><title>${title}</title></head><body></body></html>`);
    const headers = new Headers({ "content-type": "text/html" });
    assert.equal(looksLikeChallenge(headers, html("Captcha check")), true);
    assert.equal(looksLikeChallenge(headers, html("Dostęp zablokowany")), true);
    assert.equal(looksLikeChallenge(headers, html("Sklep: lodówki")), false);
    assert.equal(hasBlockedTitle("<TITLE> access denied </TITLE>"), true);
    assert.equal(hasBlockedTitle("<title>captcha<b></b></title>"), false, "the regex wanted the title's text to run straight to </title>");
  });

  test("Next.js pushes and payload scripts", () => {
    const page = '<script src="/a.js"></script><script>self.__next_f.push([1,"0:{\\"a\\":1}\\n"])</script> <script>\nself.__next_f.push([0]) ;\n</script><script>self.__next_f.push([1,"x"])x</script>';
    assert.deepEqual(nextFlightPushes(page), ['[1,"0:{\\"a\\":1}\\n"]', "[0]"]);
    assert.deepEqual(nextFlightPushes(page), [...page.matchAll(/<script[^>]*>\s*self\.__next_f\.push\((\[[\s\S]*?\])\)\s*;?\s*<\/script>/g)].map((m) => m[1]));
    assert.equal(scriptText('<script>1</script><SCRIPT type="application/json" ID="__NUXT_DATA__">[2]</SCRIPT>', (t) => /\bid="__NUXT_DATA__"/i.test(t), true), "[2]");
  });
});
