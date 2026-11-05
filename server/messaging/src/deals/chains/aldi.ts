// Aldi (observed 2026-10-28): www.aldi.pl/oferty.html is a Next.js page whose __NEXT_DATA__ carries this week's
// offers as Aldi's own data, so no page is read by a model. props.pageProps.apiData is a JSON string:
//   [["OFFER_GET", {req: {week: "current"}, res: {algoliaDataMap: {id: {name, salesUnit, currentPrice: {priceValue,
//   basePrice: [{basePriceValue, basePriceScale, basePriceAdditionalInformation}], priceTagLabels: {promoText1,
//   textualAddition, bestPricesWithin30daysText}}, promotionPrices: [{validFromLocalDate, validUntilLocalDate}],
//   hierarchicalCategories, categoryIDs}}, categories: [{title, startDate, endDate}]}}]]
// 66 offers that day. robots.txt (User-agent: *) allows /oferty.html.
// The mechanics, as Aldi's data writes them:
//   "-20% PRZY ZAKUPIE 2 SZT.": priceValue is the price of one when buying two; "Cena regularna: 6,99 zł/szt." of one.
//   "-91% CO DRUGA SZT.": priceValue is the second item's price (2,99 zł for a 36,99 zł jar). The offer's price is
//     the price of one (the regular 36,99 zł) with "druga sztuka za 2,99 zł" as a condition, and the service works out
//     the price per piece when buying two (ADR-661). Without the regular price it can't be stated, so it's left out.
//   "1+1 GRATIS": priceValue is the price of one; "1+1" is a condition.
//   "Cena za kg", "Cena za 100 g": the price is per that weight.
//   "… to najniższa cena z 30 dni przed obniżką" is the 30-day price; "… sprzed pierwszej obniżki" (perishables) is the
//   price before the first cut, kept as the regular price.
// Alcohol is skipped.
import { currentWeek, fetchOfficial, isObject, isoDay, moneyOf, str } from "./common.js";
import { parseSize } from "../match.js";
import { parsePrice } from "../vision.js";
import type { ChainAdapter, ChainRead, Condition, DataProduct, LeafletInfo, Money } from "../types.js";

export const ALDI_HOSTS = ["www.aldi.pl"] as const;
export const ALDI_OFFERS = "https://www.aldi.pl/oferty.html";

const ALCOHOL = /alkohol|\bpiw[ao]?\b|\bwin[ao]?\b|w[oó]dk|whisk|likier|\bgin\b|\brum\b|szampan|prosecco/i;

/** The offers object in the page's payload, or undefined when it isn't there. */
function offerPayload(html: string): Record<string, unknown> | undefined {
  const m = /<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/.exec(html);
  if (!m) return undefined;
  let data: unknown;
  try { data = JSON.parse(m[1]!); } catch { return undefined; }
  const props = isObject(data) && isObject(data.props) && isObject(data.props.pageProps) ? data.props.pageProps : undefined;
  let api: unknown = props?.apiData;
  if (typeof api === "string") { try { api = JSON.parse(api); } catch { return undefined; } }
  if (!Array.isArray(api)) return undefined;
  const entry = api.find((e) => Array.isArray(e) && e[0] === "OFFER_GET");
  const body = Array.isArray(entry) && isObject(entry[1]) ? entry[1] : undefined;
  return body && isObject(body.res) ? body.res : undefined;
}

/** A price printed in Aldi's text: "6,99 zł", "6.99 zł". */
function priceIn(text: string | undefined, re: RegExp): Money | undefined {
  const m = text ? re.exec(text) : null;
  return m ? parsePrice(m[1]!) : undefined;
}

/** "Cena za kg" is a price per kilo; "Cena za 100 g" per 100 g; otherwise the pack as written. */
function sizeText(salesUnit: string | undefined): string | undefined {
  if (!salesUnit) return undefined;
  if (/^cena za kg$/i.test(salesUnit.trim())) return "1 kg";
  if (/^cena za (l|litr)$/i.test(salesUnit.trim())) return "1 l";
  return salesUnit.replace(/^cena za\s+/i, "").replace(/\s+/g, " ").trim();
}

/** The price per unit Aldi printed, as text the matcher's cross-check reads ("32,88 zł/kg", "23,3 zł/1 kg"). */
function printedUnit(basePrice: unknown): string | undefined {
  const b = Array.isArray(basePrice) && isObject(basePrice[0]) ? basePrice[0] : undefined;
  const value = b && typeof b.basePriceValue === "number" ? b.basePriceValue : undefined;
  const scale = b ? str(b.basePriceScale) : undefined;
  if (!value || !scale) return undefined;
  return `${String(value).replace(".", ",")} zł/${scale.replace(/\.$/, "")}`;
}

/** This week's offers in the payload, as the chain's data products. */
export function aldiOffers(res: Record<string, unknown>, today: string): { products: DataProduct[]; leaflet: LeafletInfo } {
  const products: DataProduct[] = [];
  const map = isObject(res.algoliaDataMap) ? res.algoliaDataMap : {};
  for (const raw of Object.values(map)) {
    if (!isObject(raw)) continue;
    const name = str(raw.name);
    const current = isObject(raw.currentPrice) ? raw.currentPrice : undefined;
    const value = current ? moneyOf(current.priceValue) : undefined;
    if (!name || !current || !value) continue;
    const categories = [
      ...(Array.isArray(raw.categoryIDs) ? raw.categoryIDs : []),
      ...(isObject(raw.hierarchicalCategories) && Array.isArray(raw.hierarchicalCategories.lvl0) ? raw.hierarchicalCategories.lvl0 : []),
    ].filter((c): c is string => typeof c === "string");
    if (ALCOHOL.test(name) || categories.some((c) => ALCOHOL.test(c))) continue;
    const promo = Array.isArray(raw.promotionPrices) && isObject(raw.promotionPrices[0]) ? raw.promotionPrices[0] : undefined;
    const validFrom = isoDay(promo?.validFromLocalDate);
    const validTo = isoDay(promo?.validUntilLocalDate);
    if (!currentWeek(validFrom, validTo, today)) continue;

    const labels = isObject(current.priceTagLabels) ? current.priceTagLabels : {};
    const promoText = [str(labels.promoText1), str(labels.textualAddition)].filter(Boolean).join(" ");
    const base = Array.isArray(current.basePrice) && isObject(current.basePrice[0]) ? current.basePrice[0] : undefined;
    const info = base ? str(base.basePriceAdditionalInformation) : undefined;
    const thirtyText = str(labels.bestPricesWithin30daysText);
    const regular = priceIn(info, /cena regularna:\s*(\d{1,4}[.,]\d{2})\s*z/i)
      ?? priceIn(thirtyText, /(\d{1,4}[.,]\d{2})\s*zł\s+to\s+najniższa\s+cena\s+sprzed\s+pierwszej/i);
    const lowest30d = priceIn(thirtyText, /(\d{1,4}[.,]\d{2})\s*zł\s+to\s+najniższa\s+cena\s+z\s+30\s+dni/i);
    const conditions: Condition[] = [];
    let price = value;
    let unitText = printedUnit(current.basePrice);
    if (/co\s+druga/i.test(promoText)) {
      // The data's price is the second item's: without the price of the first, the offer can't be stated honestly.
      if (!regular || regular.minor <= value.minor) continue;
      price = regular;
      conditions.push({ kind: "second_for", price: value });
      unitText = undefined; // Aldi's unit price is the second item's
    } else {
      const qty = /przy\s+zakupie\s+(\d{1,2})\s*szt/i.exec(`${promoText} ${info ?? ""}`);
      if (qty && Number(qty[1]) >= 2) conditions.push({ kind: "min_quantity", quantity: Number(qty[1]) });
      const multi = /(\d{1,2})\s*\+\s*(\d{1,2})\s*gratis/i.exec(promoText);
      if (multi) conditions.push({ kind: "multi_buy", text: `${Number(multi[1])}+${Number(multi[2])}` });
    }
    if (/aplikac/i.test(promoText)) conditions.push({ kind: "app" });
    const size = sizeText(str(raw.salesUnit));
    // A printed unit price is only a cross-check when the pack size is known; alone it would only raise a doubt.
    const known = parseSize(size) ?? parseSize(name);
    products.push({
      name: name.slice(0, 160), price, url: ALDI_OFFERS, conditions,
      ...(size ? { sizeText: size } : {}),
      ...(known && unitText ? { printedUnitPrice: unitText } : {}),
      ...(regular && regular.minor > price.minor ? { regularPrice: regular } : {}),
      // For "co druga" the 30-day text is about the price of one, which is now the offer's price.
      ...(lowest30d ? { lowest30d } : {}),
      ...(validFrom ? { validFrom } : {}),
      ...(validTo ? { validTo } : {}),
    });
  }
  const days = (Array.isArray(res.categories) ? res.categories : [])
    .filter(isObject)
    .map((c) => ({ from: isoDay(c.startDate), to: isoDay(c.endDate) }))
    .filter((c) => currentWeek(c.from, c.to, today));
  const froms = days.map((d) => d.from).filter((d): d is string => !!d).sort();
  const tos = days.map((d) => d.to).filter((d): d is string => !!d).sort();
  return {
    products,
    leaflet: { title: "Oferty ALDI", url: ALDI_OFFERS, ...(froms[0] ? { validFrom: froms[0] } : {}), ...(tos.length ? { validTo: tos[tos.length - 1] } : {}) },
  };
}

export const aldi: ChainAdapter = {
  chain: "aldi",
  hosts: ALDI_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const r = await fetchOfficial(ctx, ALDI_OFFERS, ALDI_HOSTS, "text/html");
    if (!r.ok) return r.read;
    const res = offerPayload(r.body.toString("utf8"));
    if (!res) return { kind: "failed", reason: "no_payload" };
    const { products, leaflet } = aldiOffers(res, ctx.today);
    if (products.length === 0) return { kind: "no_leaflet" };
    return { kind: "ok", leaflets: [{ leaflet, products, pages: [], strategy: "none" }] };
  },
};
