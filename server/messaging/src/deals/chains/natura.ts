// Drogerie Natura (drugstore; observed 29 and 30 Oct 2026). drogerienatura.pl is a Magento shop (Hyvä theme) whose
// pages are rendered on the server with the shop's own facts on each product tile, so no page is read by a model:
//   <form data-product-id="{sku}" class="… product_addtocart_form …"> <input name="product" value="{id}">
//   <a class="product-item-link" href="/produkt/{slug}">name</a>
//   <span data-price-amount="15.49" data-price-type="finalPrice"> "Cena promocyjna"
//   <span data-price-amount="19.99" data-price-type="oldPrice"> "Cena regularna"
//   <div class="historical-price"> "Najniższa cena towaru w okresie 30 dni przed wprowadzeniem obniżki" <span> 15,99 zł
//   <div class="capacity-per-price"> "1 ml / 0.03 zł"
// and, after the form, the shop's labels for that product, keyed by its numeric id (data-amlabel-config
// {"product": "{id}", …} and <div class="amlabel-text">): "1+1 za 50%", "Tylko online", "OKAZJA", "BESTSELLER", …
// Two pages are read, in this order, and nothing else (robots.txt, `User-agent: *`, allows both; it disallows
// /catalogsearch/, `/*?q*` and `/*?p*`, so neither the shop's search nor a second listing page is ever asked):
//   /gazetka-promocyjna: the heading "Gazetka promocyjna ważna od 15.10 do 2.11.2026" (the leaflet's dates) and
//     the carousel "Promocje z gazetki" (7 products on 30 Oct). The leaflet itself is a 20-page PDF flipbook on
//     heyzine.com, not the shop's host, so it isn't read: the carousel is only part of the leaflet.
//   /kategoria/promocje-4949: the online shop's promotions, first page only ("Pozycje od 1 do 56 ze 11177"). Its
//     tiles carry no dates. On 30 Oct this page was 3.8 MB (3.9 MB on 13 Nov), over the fetcher's 3 MB cap, so every
//     read said `some_pages_failed`; since 13 Nov 2026 both pages are asked for with a cap of NATURA_MAX_BYTES (the
//     leaflet page was 2.4 MB).
// Every page also carries a site-wide "Nie zapomnij o:" carousel (forms with a `product-…-popup` class): not part
// of either list, so skipped. A tile whose price depends on a variant (a "from" price) is skipped.
// The shop's tooltips are not read: on 30 Oct a blank label on 50 products carried "Drugi produkt za 50% ceny".
// The product slug ends in what looks like an EAN, but nothing on the page says so, so no EAN is given.
// Nothing of the person's words reaches the shop. Because the leaflet is read only in part and the promotions only
// on their first page, every read says `incomplete`: finding nothing at Natura is never "no match".
import { currentWeek, dayMonth, decodeEntities, fetchOfficial, isObject, moneyOf, officialUrl, str } from "./common.js";
import { elements, findFrom, firstElement, forwardFinder, startTags, stripTags } from "../../htmlScan.js";
import { packSize } from "./maxizoo.js";
import { parsePrintedUnitPrice, parseSize } from "../match.js";
import { parsePrice } from "../vision.js";
import type { ChainAdapter, ChainRead, Condition, DataProduct, LeafletRead, Money, SizeUnit, UnitPrice } from "../types.js";

export const NATURA_HOSTS = ["drogerienatura.pl", "www.drogerienatura.pl"] as const;
const ORIGIN = "https://drogerienatura.pl";
export const NATURA_LEAFLET = `${ORIGIN}/gazetka-promocyjna`;
export const NATURA_PROMOTIONS = `${ORIGIN}/kategoria/promocje-4949`;
/** Natura's two pages are server-rendered HTML of 2.4 and 3.9 MB (13 Nov 2026); this cap leaves them room to grow. */
export const NATURA_MAX_BYTES = 6 * 1024 * 1024;

// ---------- text ----------

/** Latin-1 entities Magento writes by name ("w&#322;os&oacute;w"); the rest are numeric (common.decodeEntities). */
const NAMED: Record<string, string> = {
  oacute: "ó", Oacute: "Ó", eacute: "é", Eacute: "É", aacute: "á", Aacute: "Á", iacute: "í", uacute: "ú",
  auml: "ä", Auml: "Ä", ouml: "ö", Ouml: "Ö", uuml: "ü", Uuml: "Ü", szlig: "ß", ccedil: "ç", egrave: "è", agrave: "à",
  ntilde: "ñ", reg: "®", copy: "©", trade: "™", deg: "°", micro: "µ", middot: "·", bull: "•", ndash: "–", mdash: "—",
  lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", bdquo: "„", laquo: "«", raquo: "»", hellip: "…", shy: "",
};

/** Tags out, entities decoded, spaces (and no-break spaces) collapsed. */
export function plainText(html: string): string {
  const named = stripTags(html).replace(/&([a-z]+);/gi, (all, n: string) => NAMED[n] ?? all);
  return decodeEntities(named).replace(/[\s ]+/g, " ").trim();
}

/** The attributes of one start tag, values decoded ("class", "href", "data-price-amount", …). */
function attributes(tag: string): Record<string, string> {
  const out: Record<string, string> = {};
  // A name is only tried from its first character: from the middle of a name it can't match where the whole name
  // failed, and retrying every position made a long run of letters cost its square.
  for (const m of tag.matchAll(/(?<![\w:@.-])([\w:@.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
    const name = m[1]!.toLowerCase();
    if (!(name in out)) out[name] = decodeEntities(m[2] ?? m[3] ?? "");
  }
  return out;
}

/** The first start tag of `name` in `html` whose attributes pass `test`, with where its element's content starts. */
function findTag(html: string, name: string, test: (a: Record<string, string>) => boolean): { attrs: Record<string, string>; end: number } | undefined {
  for (const tag of startTags(html, new RegExp(`<${name}\\b`, "gi"))) {
    const attrs = attributes(tag.text);
    if (test(attrs)) return { attrs, end: tag.end };
  }
  return undefined;
}

/**
 * The content of the first <div> whose class attribute names `cls`, up to the first "</div>" after its start tag:
 * what /<div\b[^>]*class\s*=\s*"[^"]*\bCLS\b[^"]*"[^>]*>([\s\S]*?)<\/div>/i finds, in linear time. As there, a ">"
 * inside the class value (a Tailwind class such as `[&>svg]:w-4`) doesn't end the tag.
 */
function classDiv(html: string, cls: string): string | undefined {
  const named = new RegExp(String.raw`\b${cls}\b`, "i");
  for (let from = 0; ;) {
    const open = findFrom(html, /<div\b/gi, from);
    if (!open) return undefined;
    const gt = html.indexOf(">", open.end);
    if (gt < 0) return undefined;
    // The class attribute starts before the first ">"; the last one that names `cls` wins, as the regex's greedy
    // `[^>]*` had it. Its value runs to the next quote, past a ">" if need be.
    let valueEnd = -1;
    for (const a of html.slice(open.end, gt).matchAll(/class\s*=\s*"/gi)) {
      const start = open.end + a.index + a[0].length;
      const close = html.indexOf('"', start);
      if (close >= 0 && named.test(html.slice(start, close))) valueEnd = close;
    }
    if (valueEnd >= 0) {
      const tagEnd = html.indexOf(">", valueEnd + 1);
      const c = tagEnd < 0 ? undefined : findFrom(html, /<\/div>/gi, tagEnd + 1);
      return c ? html.slice(tagEnd + 1, c.index) : undefined;
    }
    from = gt + 1; // a <div inside this tag has a subset of its class attributes, so it can't match either
  }
}

/** The product id in a tile's `<input name="product" value="…">`: what
 * /<input\b[^>]*name\s*=\s*"product"[^>]*value\s*=\s*"(\d{1,10})"/i finds, in linear time. */
function inputProductId(html: string): string | undefined {
  for (let from = 0; ;) {
    const open = findFrom(html, /<input\b/gi, from);
    if (!open) return undefined;
    const gt = html.indexOf(">", open.end);
    const tag = html.slice(open.end, gt < 0 ? undefined : gt);
    const name = /name\s*=\s*"product"/i.exec(tag);
    // The last value after the first name="product", as the regex's greedy `[^>]*` had it.
    const values = name ? [...tag.slice(name.index + name[0].length).matchAll(/value\s*=\s*"(\d{1,10})"/gi)] : [];
    const last = values[values.length - 1];
    if (last) return last[1];
    if (gt < 0) return undefined;
    from = gt + 1;
  }
}

const hasClass = (a: Record<string, string>, c: string) => (a.class ?? "").split(/\s+/).includes(c);

// ---------- the shop's labels ----------

/** Each product's label texts, by the shop's numeric product id. */
export function productLabels(html: string): Map<string, string[]> {
  const out = new Map<string, string[]>();
  const configs = [...html.matchAll(/data-amlabel-config\s*=\s*(?:"([^"]*)"|'([^']*)')/g)];
  configs.forEach((m, i) => {
    let config: unknown;
    try { config = JSON.parse(decodeEntities(m[1] ?? m[2] ?? "")); } catch { return; }
    const product = isObject(config) ? str(typeof config.product === "number" ? String(config.product) : config.product) : undefined;
    if (!product || !/^\d{1,10}$/.test(product)) return;
    // The label's text is the first amlabel-text after its config and before the next label's.
    const rest = html.slice(m.index + m[0].length, configs[i + 1]?.index ?? m.index + m[0].length + 8000);
    const text = classDiv(rest, "amlabel-text");
    const label = text !== undefined ? plainText(text).slice(0, 80) : "";
    if (!label) return;
    const list = out.get(product) ?? [];
    if (!list.includes(label)) list.push(label);
    out.set(product, list);
  });
  return out;
}

/** What a label's text asks of the shopper, in the code's words, or undefined for a label that names no mechanic
 * ("OKAZJA", "BESTSELLER", "Tylko w Natura", "NOWOŚĆ", a brand, a shade, a bare "-30%" the price already holds). */
export function labelCondition(label: string): Condition | undefined {
  const t = label.replace(/\s+/g, " ").trim();
  // "1+1 za 50%": the next piece at half price; "1+1 za 5 zł": the second for 5 zł.
  const plusPercent = /(?<!\d)(\d)\s*\+\s*(\d)\s*za\s*(\d{1,2})\s*%/i.exec(t);
  if (plusPercent) {
    const [buy, extra, percent] = [Number(plusPercent[1]), Number(plusPercent[2]), Number(plusPercent[3])];
    if (buy >= 1 && extra === 1 && percent >= 1) return { kind: "nth_discount", quantity: buy + 1, percent };
    return { kind: "other", text: t };
  }
  const plusPrice = /(?<!\d)(\d)\s*\+\s*(\d)\s*za\s*(\d{1,4}(?:[.,]\d{2})?)\s*(zł|gr\b|grosz)/i.exec(t);
  if (plusPrice) {
    const grosze = /^g/i.test(plusPrice[4]!) && /^\d{1,2}$/.test(plusPrice[3]!) ? Number(plusPrice[3]) : undefined;
    const price: Money | undefined = grosze ? { minor: grosze, currency: "PLN" } : /^g/i.test(plusPrice[4]!) ? undefined : parsePrice(plusPrice[3]);
    if (plusPrice[1] === "1" && plusPrice[2] === "1" && price) return { kind: "second_for", price };
    return { kind: "other", text: t };
  }
  // Any other "a+b za …" is a mechanic the code can't state exactly: shown as printed.
  if (/(?<!\d)\d\s*\+\s*\d\s*za\b/i.test(t)) return { kind: "other", text: t };
  const second = /drug[aiy]\s+(?:sztuk[aię]\s+|produkt\s+)?(?:za\s+)?[-−–]?\s*(\d{1,2})\s*%/i.exec(t);
  if (second) return { kind: "nth_discount", quantity: 2, percent: Number(second[1]) };
  const plus = /(?<![\d,.])(\d)\s*\+\s*(\d)(?![\d%])/.exec(t);
  if (plus) return { kind: "multi_buy", text: `${plus[1]}+${plus[2]}` };
  const threeForTwo = /(?<![\d,.])(\d)\s*za\s*(\d)(?![\d,.%]|\s*zł)/i.exec(t);
  if (threeForTwo && Number(threeForTwo[1]) > Number(threeForTwo[2]) && Number(threeForTwo[2]) >= 1) {
    return { kind: "multi_buy", text: `${threeForTwo[2]}+${Number(threeForTwo[1]) - Number(threeForTwo[2])}` };
  }
  const quantity = /przy\s+zakupie\s+(\d{1,2})|od\s+(\d{1,2})\s*szt/i.exec(t);
  if (quantity && Number(quantity[1] ?? quantity[2]) >= 2) return { kind: "min_quantity", quantity: Number(quantity[1] ?? quantity[2]) };
  if (/aplikac/i.test(t)) return { kind: "app" };
  if (/natura\s*club|\bklub|z\s+kart[aąy]/i.test(t)) return { kind: "card" };
  if (/^tylko\s+online$|tylko\s+w\s+sklepie\s+internetowym/i.test(t)) return { kind: "other", text: "tylko online" };
  return undefined;
}

// ---------- the product tiles ----------

const BASE: Record<SizeUnit, UnitPrice["per"]> = { g: "kg", kg: "kg", ml: "l", l: "l", szt: "szt" };

/**
 * The shop's "1 ml / 0.03 zł" as text the matcher reads ("0,03 zł/1 ml"), only when it can cross-check the code's
 * own unit price: the size is known and in the same unit, and the shop's rounding to the grosz is within the
 * matcher's 2 %. "1 ml / 0.03 zł" for a 500 ml shampoo at 15,49 zł is 30,00 zł/l against the real 30,98, and
 * "1 g / 0.00 zł" says nothing, so those are left out rather than raise a false doubt.
 */
export function printedUnit(text: string | undefined, sizeText: string | undefined): string | undefined {
  const m = text ? /^(\d{1,4}(?:[.,]\d{1,3})?)\s*(ml|l|g|kg|szt)\.?\s*\/\s*(\d{1,6}(?:[.,]\d{1,2})?)\s*z[łl]$/i.exec(text.trim()) : null;
  const size = parseSize(sizeText);
  if (!m || !size) return undefined;
  const per = `${m[1]!.replace(".", ",")} ${m[2]!.toLowerCase()}`;
  const printed = `${m[3]!.replace(".", ",")} zł/${per}`;
  const unit = parsePrintedUnitPrice(printed);
  const grosz = parsePrintedUnitPrice(`0,01 zł/${per}`);
  if (!unit || !grosz || BASE[size.unit] !== unit.per) return undefined;
  return grosz.minor / 2 <= Math.max(2, Math.round(unit.minor * 0.02)) ? printed : undefined;
}

/** A product page on the shop's host ("/produkt/…"), without query or fragment. */
function productUrl(href: string | undefined): string | undefined {
  const u = officialUrl(href, NATURA_HOSTS, ORIGIN);
  return u && u.pathname.startsWith("/produkt/") && u.pathname.length > "/produkt/".length && !u.pathname.includes("//")
    ? `${u.origin}${u.pathname}` : undefined;
}

/** A price span's amount ("data-price-type" = type). */
function priceOf(tile: string, type: string): Money | undefined {
  const tag = findTag(tile, "span", (a) => a["data-price-type"] === type);
  return tag ? moneyOf(tag.attrs["data-price-amount"]) : undefined;
}

/** "Najniższa cena towaru w okresie 30 dni przed wprowadzeniem obniżki 15,99 zł": only a price labelled so. */
function lowest30dOf(tile: string): Money | undefined {
  const box = classDiv(tile, "historical-price");
  if (box === undefined) return undefined;
  // The label before the box's first <span>, the price inside it (/^([\s\S]*?)<span\b[^>]*>([\s\S]*?)<\/span>/i).
  const span = firstElement(box, /<span\b/gi, /<\/span>/gi);
  if (!span || !/najni[żz]sza\s+cena[\s\S]{0,60}\b30\s+dni/i.test(plainText(box.slice(0, span.tag.index)))) return undefined;
  return parsePrice(plainText(span.content).replace(/(\d)\s(?=\d{3}(?:\D|$))/g, "$1"));
}

/** One tile as a data product, or undefined (the site-wide carousel, a variant's "from" price, no price or page). */
function tileProduct(form: string, body: string, labels: Map<string, string[]>): DataProduct | undefined {
  const attrs = attributes(form);
  const classes = attrs.class ?? "";
  if (!classes.split(/\s+/).includes("product_addtocart_form") || !attrs["data-product-id"]) return undefined;
  if (/(^|\s)product-\S+-popup(\s|$)/.test(classes) || /\b(configurable|bundle|grouped)\b/.test(classes)) return undefined;
  if (/data-price-type\s*=\s*"(minPrice|maxPrice)"/.test(body)) return undefined;
  const link = findTag(body, "a", (a) => hasClass(a, "product-item-link"));
  const url = productUrl(link?.attrs.href);
  const close = link ? body.indexOf("</a>", link.end) : -1;
  const name = link && close > 0 ? plainText(body.slice(link.end, close)).slice(0, 160) : "";
  const price = priceOf(body, "finalPrice");
  if (!url || !name || !price) return undefined;
  const regular = priceOf(body, "oldPrice");
  const lowest30d = lowest30dOf(body);
  const size = packSize(name);
  const unitBox = classDiv(body, "capacity-per-price");
  const unitText = printedUnit(unitBox !== undefined ? plainText(unitBox) : undefined, size);
  const id = inputProductId(body) ?? /\/product\/(\d{1,10})\//.exec(attrs.action ?? "")?.[1];
  const conditions = new Map<string, Condition>();
  for (const label of (id ? labels.get(id) : undefined) ?? []) {
    const c = labelCondition(label);
    if (c && !conditions.has(c.kind)) conditions.set(c.kind, c);
  }
  return {
    name, price, url, conditions: [...conditions.values()],
    ...(size ? { sizeText: size } : {}),
    ...(unitText ? { printedUnitPrice: unitText } : {}),
    // Printed as "Cena regularna"; kept only above the price.
    ...(regular && regular.minor > price.minor ? { regularPrice: regular } : {}),
    ...(lowest30d ? { lowest30d } : {}),
  };
}

/** Every product tile on a page, in its order, one per product page. */
function pageProducts(html: string): DataProduct[] {
  const labels = productLabels(html);
  const out = new Map<string, DataProduct>();
  const forms = [...startTags(html, /<form\b/gi)];
  const closeAt = forwardFinder(html, "</form>");
  forms.forEach((form, i) => {
    // A form's content runs to its "</form>", and never past the next form (forms don't nest), so a page of
    // unclosed forms isn't read to its end once per form.
    const end = Math.min(closeAt(form.end)?.index ?? html.length, forms[i + 1]?.index ?? html.length);
    const product = tileProduct(form.text, html.slice(form.end, end), labels);
    if (product && !out.has(product.url)) out.set(product.url, product);
  });
  return [...out.values()];
}

/** Whether the page has a product tile: what /<form\b[^>]*\bproduct_addtocart_form\b/i finds, in linear time. */
function hasTiles(html: string): boolean {
  for (let from = 0; ;) {
    const open = findFrom(html, /<form\b/gi, from);
    if (!open) return false;
    const gt = html.indexOf(">", open.end);
    if (/\bproduct_addtocart_form\b/i.test(html.slice(open.end, gt < 0 ? undefined : gt))) return true;
    if (gt < 0) return false;
    from = gt + 1;
  }
}

// ---------- the two pages ----------

export interface NaturaLeaflet { products: DataProduct[]; validFrom?: string; validTo?: string }

/** "ważna od 15.10 do 2.11.2026" in a heading: the leaflet's first and last day. */
export function leafletDates(html: string, today: string): { validFrom?: string; validTo?: string } {
  for (const h of elements(html, /<h[1-3]\b/gi, /<\/h[1-3]>/gi)) {
    const d = /wa[żz]n[aey]\s+od\s+(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?\s*(?:r\.?\s*)?do\s+(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?/i.exec(plainText(h.content));
    if (!d) continue;
    const [fd, fm, fy, td, tm, ty] = d.slice(1).map((x) => (x === undefined ? undefined : Number(x)));
    const validTo = dayMonth(td!, tm!, today, ty);
    // A start without a year is in the end's year, or the year before when it runs over New Year.
    const fromYear = fy ?? (ty ? (fm! > tm! ? ty - 1 : ty) : undefined);
    const validFrom = dayMonth(fd!, fm!, today, fromYear);
    return validFrom && validTo && validFrom <= validTo ? { validFrom, validTo } : {};
  }
  return {};
}

/** The leaflet page: its dates and the products of its carousel, or undefined when the page holds neither. */
export function parseNaturaLeaflet(html: string, today: string): NaturaLeaflet | undefined {
  const dates = leafletDates(html, today);
  if (!dates.validTo && !hasTiles(html)) return undefined;
  const products = pageProducts(html).map((p) => ({ ...p, ...dates }));
  return { products, ...dates };
}

export interface NaturaListing { products: DataProduct[]; more: boolean }

/** The promotions page: its products and whether its listing has more pages than this one. */
export function parseNaturaPromotions(html: string): NaturaListing | undefined {
  const amount = firstElement(html, /<p\b/gi, /<\/p>/gi, (tag) => /\bid\s*=\s*"toolbar-amount"/i.test(tag.text));
  if (!amount && !hasTiles(html)) return undefined;
  // "Pozycje od 1 do 56 ze 11177"
  const n = amount ? /do\s+([\d\s]+?)\s+z[e]?\s+([\d\s]+)$/i.exec(plainText(amount.content)) : null;
  const shown = n ? Number(n[1]!.replace(/\s/g, "")) : NaN;
  const total = n ? Number(n[2]!.replace(/\s/g, "")) : NaN;
  const more = Number.isFinite(shown) && Number.isFinite(total) ? total > shown : /\bpages-item-next\b/.test(html);
  return { products: pageProducts(html), more };
}

// ---------- the adapter ----------

export const natura: ChainAdapter = {
  chain: "natura",
  hosts: NATURA_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const failures: ChainRead[] = [];
    const reasons = new Set<string>();
    const leaflets: LeafletRead[] = [];
    const seen = new Set<string>();
    const fresh = (products: DataProduct[]) => products.filter((p) => !seen.has(p.url) && seen.add(p.url));

    const leafletPage = await fetchOfficial(ctx, NATURA_LEAFLET, NATURA_HOSTS, "text/html", { maxBytes: NATURA_MAX_BYTES });
    if (!leafletPage.ok) failures.push(leafletPage.read);
    else {
      const l = parseNaturaLeaflet(leafletPage.body.toString("utf8"), ctx.today);
      if (!l) failures.push({ kind: "failed", reason: "no_payload" });
      else {
        // The carousel is only part of the 20-page leaflet (a PDF on heyzine.com, never read).
        reasons.add("leaflet_in_part");
        // An ended leaflet's products aren't offered; the same product on the promotions page still is.
        const products = currentWeek(l.validFrom, l.validTo, ctx.today) ? fresh(l.products) : [];
        if (products.length) {
          leaflets.push({
            leaflet: { title: "Gazetka Natura", url: NATURA_LEAFLET, ...(l.validFrom ? { validFrom: l.validFrom } : {}), ...(l.validTo ? { validTo: l.validTo } : {}) },
            products, pages: [], strategy: "none",
          });
        }
      }
    }

    // Once the shop has said no, nothing more is asked of it in this request.
    if (failures.some((f) => f.kind === "blocked") || ctx.signal.aborted) failures.push({ kind: "failed", reason: "not_asked" });
    else {
      const listPage = await fetchOfficial(ctx, NATURA_PROMOTIONS, NATURA_HOSTS, "text/html", { maxBytes: NATURA_MAX_BYTES });
      if (!listPage.ok) failures.push(listPage.read);
      else {
        const list = parseNaturaPromotions(listPage.body.toString("utf8"));
        if (!list) failures.push({ kind: "failed", reason: "no_payload" });
        else {
          if (list.more) reasons.add("first_page_only");
          const products = fresh(list.products);
          if (products.length) leaflets.push({ leaflet: { title: "Promocje Natura", url: NATURA_PROMOTIONS }, products, pages: [], strategy: "none" });
        }
      }
    }

    if (failures.length) reasons.add("some_pages_failed");
    if (leaflets.length === 0) {
      if (failures.length === 0) return { kind: "no_leaflet" };
      return failures.find((f) => f.kind === "blocked") ?? failures.find((f) => !(f.kind === "failed" && f.reason === "not_asked")) ?? failures[0]!;
    }
    return { kind: "ok", leaflets, incomplete: [...reasons].join(",") };
  },
};
