// Dino (observed 2026-10-24): marketdino.pl/gazetki/lista/standard is a Nuxt page whose payload
// (<script id="__NUXT_DATA__">, devalue's flat JSON) holds every current leaflet: pinia.leaflet.leaflets =
// [{id, name, activeFrom, activeTo, promoNewsType, pages: [{no, file: {url}, hotspots: [{ean, product: {name,
// price}, isActive, isDisplayed, isAlcohol}]}]}]. The hotspots are Dino's own data: EAN, name and price per
// product, with the page it is on. They carry no conditions, and the price printed big can need "przy zakupie
// 2 sztuk" (checked by eye on page 4 of "Gazetka 43 / 2026"), so each matched product's page is read to confirm
// its conditions; until it is, the offer says `check: true`.
// The page also exposes an app token for api.marketdino.pl; Doddy doesn't use it (public page only).
// Alcohol leaflets are skipped (their hotspots were not all flagged isAlcohol).
import { currentWeek, fetchOfficial, isObject, isoDay, moneyOf, officialUrl, str, validEan } from "./common.js";
import type { ChainAdapter, ChainRead, DataProduct, LeafletPage, LeafletRead } from "../types.js";

export const DINO_HOSTS = ["marketdino.pl", "api.marketdino.pl"] as const;
export const DINO_LISTING = "https://marketdino.pl/gazetki/lista/standard";

const WRAPPERS = new Set(["Reactive", "ShallowReactive", "Ref", "ShallowRef", "EmptyRef", "EmptyShallowRef", "Object"]);
const MAX_ENTRIES = 500_000;

/**
 * Rebuilds a value from devalue's flat array (what Nuxt puts in __NUXT_DATA__): index 0 is the root, numbers
 * inside objects and arrays point to other entries, negative numbers are undefined/NaN/±Infinity/-0, and an
 * array starting with a type name is a special value (Date, Set, Map, Nuxt's Ref/Reactive wrappers, …).
 * Unknown types become undefined. Shared entries are rebuilt once.
 */
export function unflatten(flat: unknown): unknown {
  if (!Array.isArray(flat) || flat.length === 0 || flat.length > MAX_ENTRIES) return undefined;
  const done = new Map<number, unknown>();
  const hydrate = (index: unknown, depth: number): unknown => {
    if (typeof index !== "number" || !Number.isInteger(index)) return undefined;
    if (index === -3) return NaN;
    if (index === -4) return Infinity;
    if (index === -5) return -Infinity;
    if (index === -6) return -0;
    if (index < 0 || index >= flat.length || depth > 200) return undefined;
    if (done.has(index)) return done.get(index);
    const v = flat[index];
    if (Array.isArray(v)) {
      if (typeof v[0] === "string") {
        const type = v[0];
        let out: unknown;
        if (WRAPPERS.has(type)) {
          out = hydrate(v[1], depth + 1);
          if ((type === "EmptyRef" || type === "EmptyShallowRef") && typeof out === "string") {
            try { out = JSON.parse(out); } catch { /* keep the string */ }
          }
        } else if (type === "Date" || type === "BigInt" || type === "RegExp") {
          out = typeof v[1] === "string" ? v[1] : undefined;
        } else if (type === "Set") {
          out = v.slice(1).map((x) => hydrate(x, depth + 1));
        } else if (type === "Map" || type === "null") {
          const obj: Record<string, unknown> = {};
          for (let i = 1; i + 1 < v.length; i += 2) {
            const k = type === "null" ? v[i] : hydrate(v[i], depth + 1);
            if (typeof k === "string") obj[k] = hydrate(v[i + 1], depth + 1);
          }
          out = obj;
        }
        done.set(index, out);
        return out;
      }
      const arr: unknown[] = [];
      done.set(index, arr);
      for (const x of v) arr.push(hydrate(x, depth + 1));
      return arr;
    }
    if (v !== null && typeof v === "object") {
      const obj: Record<string, unknown> = {};
      done.set(index, obj);
      for (const [k, x] of Object.entries(v)) obj[k] = hydrate(x, depth + 1);
      return obj;
    }
    done.set(index, v);
    return v;
  };
  return hydrate(0, 0);
}

/** The leaflets in the page's Nuxt payload, or undefined when the payload isn't there. */
export function nuxtLeaflets(html: string): unknown[] | undefined {
  const m = /<script[^>]*\bid="__NUXT_DATA__"[^>]*>([\s\S]*?)<\/script>/i.exec(html);
  if (!m) return undefined;
  let flat: unknown;
  try { flat = JSON.parse(m[1]!); } catch { return undefined; }
  const root = unflatten(flat);
  const pinia = isObject(root) ? root.pinia : undefined;
  const leaflet = isObject(pinia) ? pinia.leaflet : undefined;
  const leaflets = isObject(leaflet) ? leaflet.leaflets : undefined;
  return Array.isArray(leaflets) ? leaflets : undefined;
}

/** This week's leaflets with their pages and hotspot products. In-store leaflet first. */
export function dinoLeaflets(raw: unknown[], today: string): LeafletRead[] {
  const out: (LeafletRead & { order: number })[] = [];
  for (const l of raw) {
    if (!isObject(l)) continue;
    const type = str(l.promoNewsType) ?? "";
    const name = str(l.name);
    if (/alcohol/i.test(type) || (name && /alkohol/i.test(name))) continue;
    const validFrom = isoDay(l.activeFrom);
    const validTo = isoDay(l.activeTo);
    if (!currentWeek(validFrom, validTo, today)) continue;
    const pages: LeafletPage[] = [];
    const products: DataProduct[] = [];
    for (const p of Array.isArray(l.pages) ? l.pages : []) {
      if (!isObject(p) || typeof p.no !== "number" || !Number.isInteger(p.no) || p.no < 1 || p.no > 1000) continue;
      const file = isObject(p.file) ? p.file : {};
      const img = officialUrl(file.url, DINO_HOSTS) ?? officialUrl(file.file, DINO_HOSTS);
      if (img) pages.push({ number: p.no, imageUrl: img.toString(), url: DINO_LISTING });
      if (p.isAlcohol === true) continue;
      for (const h of Array.isArray(p.hotspots) ? p.hotspots : []) {
        if (!isObject(h) || h.isActive === false || h.isDisplayed === false || h.isAlcohol === true || h.isOverlay === true) continue;
        const product = isObject(h.product) ? h.product : {};
        const pname = str(product.name);
        const price = moneyOf(product.price);
        if (!pname || !price) continue;
        const ean = validEan(h.ean);
        products.push({
          name: pname.slice(0, 160), price, url: DINO_LISTING, page: p.no, conditions: [], confirmOnPage: true,
          ...(ean ? { ean } : {}), ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}),
        });
      }
    }
    out.push({
      leaflet: { ...(name ? { title: name } : {}), url: DINO_LISTING, ...(validFrom ? { validFrom } : {}), ...(validTo ? { validTo } : {}) },
      products, pages: pages.sort((a, b) => a.number - b.number), strategy: "confirm",
      order: type === "in_store" ? 0 : 1,
    });
  }
  return out.sort((a, b) => a.order - b.order).map(({ order: _order, ...rest }) => rest);
}

export const dino: ChainAdapter = {
  chain: "dino",
  hosts: DINO_HOSTS,
  async read(ctx): Promise<ChainRead> {
    const r = await fetchOfficial(ctx, DINO_LISTING, DINO_HOSTS, "text/html");
    if (!r.ok) return r.read;
    const raw = nuxtLeaflets(r.body.toString("utf8"));
    if (!raw) return { kind: "failed", reason: "no_payload" };
    const leaflets = dinoLeaflets(raw, ctx.today);
    return leaflets.length ? { kind: "ok", leaflets } : { kind: "no_leaflet" };
  },
};
