// Stand-ins for the leaflet tests: a fake web (fetch-shaped, serving the trimmed fixtures saved from the chains'
// real pages on 2026-10-24), fake page images that carry only a header and a marker, and a fake model in place
// of Claude Haiku. Nothing here reaches the network or Anthropic.
import { readFileSync } from "node:fs";
import { z } from "zod";
import type { FetchFn } from "../src/deals/fetcher.js";
import type { PageOutput } from "../src/deals/vision.js";
import type { PickOutput } from "../src/deals/match.js";
import type { DealsModelApi, ModelReply, PageImage, PickCandidate, ReadChain } from "../src/deals/types.js";

const FIXTURES = new URL("../../test/fixtures/deals/", import.meta.url);
export const fixture = (name: string): Buffer => readFileSync(new URL(name, FIXTURES));
export const fixtureText = (name: string): string => fixture(name).toString("utf8");
export const fixtureJson = <T = unknown>(name: string): T => JSON.parse(fixtureText(name)) as T;

export interface FakeResponse { status?: number; headers?: Record<string, string>; body?: string | Buffer }
type Handler = FakeResponse | ((url: URL, init: RequestInit) => FakeResponse | Promise<FakeResponse>);

/** A fetch-shaped fake web. Unknown robots.txt answers 404 (no rules); any other unknown address 404. */
export class FakeWeb {
  readonly routes = new Map<string, Handler>();
  readonly prefixes: [string, Handler][] = [];
  readonly requests: { url: string; headers: Record<string, string> }[] = [];

  on(url: string, h: Handler): this { this.routes.set(url, h); return this; }
  onPrefix(prefix: string, h: Handler): this { this.prefixes.push([prefix, h]); return this; }
  robots(origin: string, text: string): this { return this.on(`${origin}/robots.txt`, { headers: { "content-type": "text/plain" }, body: text }); }
  hosts(): Set<string> { return new Set(this.requests.map((r) => new URL(r.url).hostname)); }
  hits(prefix: string): number { return this.requests.filter((r) => r.url.startsWith(prefix)).length; }

  readonly fetch: FetchFn = async (url, init) => {
    const headers: Record<string, string> = {};
    new Headers(init.headers).forEach((v, k) => { headers[k] = v; });
    this.requests.push({ url, headers });
    if (init.signal?.aborted) throw new DOMException("aborted", "AbortError");
    const u = new URL(url);
    // The latest prefix wins, so a test can override what chainsWeb() set up.
    const h = this.routes.get(url) ?? [...this.prefixes].reverse().find(([p]) => url.startsWith(p))?.[1];
    const r = typeof h === "function" ? await h(u, init) : h ?? { status: 404, body: "not found" };
    const status = r.status ?? 200;
    const body = r.body === undefined || (status >= 300 && status < 400) ? null : typeof r.body === "string" ? r.body : new Uint8Array(r.body);
    return new Response(body, { status, headers: r.headers });
  };
}

const MARK = "DODDYTEST:";
/** A PNG that is only a header (the reader needs the size) and a marker naming the page. */
export function fakePng(width: number, height: number, marker: string): Buffer {
  const ihdr = Buffer.alloc(25);
  ihdr.writeUInt32BE(13, 0);
  ihdr.write("IHDR", 4, "latin1");
  ihdr.writeUInt32BE(width, 8);
  ihdr.writeUInt32BE(height, 12);
  ihdr.writeUInt8(8, 16);
  ihdr.writeUInt8(6, 17);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), ihdr, Buffer.from(MARK + marker, "latin1")]);
}
/** A JPEG that is only an APP0 and a SOF0 header, and a marker. */
export function fakeJpeg(width: number, height: number, marker: string): Buffer {
  const app0 = Buffer.from([0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00]);
  const sof = Buffer.alloc(19);
  sof.writeUInt16BE(0xffc0, 0);
  sof.writeUInt16BE(17, 2);
  sof.writeUInt8(8, 4);
  sof.writeUInt16BE(height, 5);
  sof.writeUInt16BE(width, 7);
  sof.writeUInt8(3, 9);
  return Buffer.concat([Buffer.from([0xff, 0xd8]), app0, sof, Buffer.from(MARK + marker, "latin1")]);
}
export function markerOf(data: Buffer): string {
  const i = data.indexOf(MARK, 0, "latin1");
  return i < 0 ? "" : data.subarray(i + MARK.length).toString("latin1");
}

type Product = PageOutput["products"][number];
/** A reader product with defaults (only what the test says is "printed"). */
export const read = (p: Partial<Product> & Pick<Product, "name" | "price">): Product => ({
  size: null, regularPrice: null, lowest30d: null, unitPrice: null, conditions: [], validFrom: null, validTo: null, confidence: "high", ...p,
});

type PageStep = PageOutput | "refuse" | "unparsed" | "throw" | ((signal: AbortSignal) => Promise<ModelReply<PageOutput>>);

/** Stands in for Claude Haiku: page outputs by the page image's marker, and a pick that keeps every id unless told otherwise. */
export class FakeModel implements DealsModelApi {
  readonly model = "claude-haiku-5-5";
  readonly pages = new Map<string, PageStep>();
  readonly reads: { marker: string; chain: ReadChain; queries: readonly string[]; image: PageImage }[] = [];
  readonly picks: { queries: readonly string[]; candidates: PickCandidate[][] }[] = [];
  pickImpl?: (req: { queries: readonly string[]; candidates: PickCandidate[][] }) => ModelReply<PickOutput> | Promise<ModelReply<PickOutput>>;

  page(marker: string, step: PageStep): this { this.pages.set(marker, step); return this; }

  async readPage(req: { image: PageImage; chain: ReadChain; queries: readonly string[] }, signal: AbortSignal): Promise<ModelReply<PageOutput>> {
    const marker = markerOf(req.image.data);
    this.reads.push({ marker, chain: req.chain, queries: req.queries, image: req.image });
    const step = this.pages.get(marker) ?? { products: [] };
    const usage = { inputTokens: 2000, outputTokens: 150 };
    if (typeof step === "function") return step(signal);
    if (step === "refuse") return { kind: "refused", usage };
    if (step === "unparsed") return { kind: "unparsed", usage };
    if (step === "throw") throw new Error("api down");
    return { kind: "ok", output: step, usage };
  }

  async pick(req: { queries: readonly string[]; candidates: PickCandidate[][] }): Promise<ModelReply<PickOutput>> {
    this.picks.push(req);
    if (this.pickImpl) return this.pickImpl(req);
    return { kind: "ok", output: { matches: req.candidates.map((l, i) => ({ item: i, ids: l.map((c) => c.id) })) }, usage: { inputTokens: 300, outputTokens: 20 } };
  }
}

// ---------- the chains as they answered on 2026-10-24 (Aldi and Żabka on 2026-10-28), trimmed ----------

export const ROBOTS = {
  biedronka: "User-agent: *\nDisallow: /front/search*\nDisallow: /pl/search*\n",
  lidl: "User-agent: *\nDisallow: /cc.js*\nDisallow: /user-api/*\nDisallow: *search?q=*\nDisallow: *?offset=*\nDisallow: *id=*\n\nSitemap: https://www.lidl.pl/static/sitemap.xml\n",
  dino: "User-Agent: *\nDisallow: /wyszukiwarka/\nDisallow: /listy-zakupowe\nDisallow: /trigger-error\n\nSitemap: https://marketdino.pl/sitemap.xml\n",
  dinoApi: "# As a condition of accessing this website, you agree to abide by the following\n# content signals:\n# ai-input: inputting content into one or more AI models\n",
  rossmann: "User-agent: *\nDisallow: /logowanie\nDisallow: /zamowienie\nDisallow: /?q=\nDisallow: /*?utm_source=\n\nUser-agent: MJ12bot\nDisallow: /\n",
  rossmannGazetka: "User-agent: *\nDisallow: /\n",
  aldi: "User-agent: * \n\nSitemap: https://www.aldi.pl/.aldi-nord-sitemap.xml\n\nDisallow: /reg-cat.html\nDisallow: /can/\nDisallow: /bal/\nDisallow: /mds/\nDisallow: /*?*filters\nDisallow: /*?*jobId=\n",
  zabka: "User-agent: *\nDisallow: /app/\nAllow: /wp-admin/\n\nAllow: /\n\nSitemap: https://www.zabka.pl/sitemap_index.xml\n",
};

export const BIEDRONKA_PRESS = "https://www.biedronka.pl/pl/press,id,1wmtizrux,title,codziennie-niskie-ceny-p-oferta-od-22-10";
export const BIEDRONKA_API = "https://leaflet-api.prod.biedronka.cloud/api/leaflets/a95fe048-0a65-4861-8fe4-8174a88a06b5?ctx=web";
export const LIDL_LISTING = "https://www.lidl.pl/c/nasze-gazetki/s10008614";
export const lidlFlyerUrl = (slug: string) => `https://endpoints.leaflets.schwarz/v4/flyer?flyer_identifier=${slug}&region_id=0`;
export const DINO_LISTING = "https://marketdino.pl/gazetki/lista/standard";
export const rossmannSearch = (words: string) => `https://www.rossmann.pl/promocje?Search=${encodeURIComponent(words)}`;
export const ALDI_OFFERS = "https://www.aldi.pl/oferty.html";
export const ZABKA_LISTING = "https://www.zabka.pl/gazetka-promocyjna/";
export const ZABKA_SPREADS = "https://gazetka.zabka.pl/gazetka-promocyjna-43-44-2026/spreads.json";

/** A /promocje page with no products (what a search that finds nothing returns, in shape). */
export function rossmannEmpty(): string {
  const html = fixtureText("rossmann_promocje_pieluchy.html");
  return html.replace(/("items":\s*)\[[\s\S]*?\](,\s*"totalPages")/, "$1[]$2");
}

/** The fake web with every read chain answering as its fixtures do, page images included. */
export function chainsWeb(): FakeWeb {
  const web = new FakeWeb()
    .robots("https://www.biedronka.pl", ROBOTS.biedronka)
    .robots("https://www.lidl.pl", ROBOTS.lidl)
    .robots("https://marketdino.pl", ROBOTS.dino)
    .robots("https://api.marketdino.pl", ROBOTS.dinoApi)
    .robots("https://www.rossmann.pl", ROBOTS.rossmann)
    .robots("https://gazetka.rossmann.pl", ROBOTS.rossmannGazetka)
    .robots("https://www.aldi.pl", ROBOTS.aldi)
    .robots("https://www.zabka.pl", ROBOTS.zabka);
  // Biedronka: "this week" redirects twice to the press page; the leaflet API lists page images.
  web.on("https://www.biedronka.pl/pl/w-tym-tygodniu", { status: 307, headers: { location: "https://www.biedronka.pl/pl/codziennie-niskie-ceny-22-10" } });
  web.on("https://www.biedronka.pl/pl/codziennie-niskie-ceny-22-10", { status: 301, headers: { location: BIEDRONKA_PRESS } });
  web.on(BIEDRONKA_PRESS, { headers: { "content-type": "text/html; charset=UTF-8" }, body: fixture("biedronka_press.html") });
  web.on(BIEDRONKA_API, { headers: { "content-type": "application/json" }, body: fixture("biedronka_leaflet.json") });
  for (const p of fixtureJson<{ images_mobile: { page: number; image: string }[] }>("biedronka_leaflet.json").images_mobile) {
    web.on(p.image, { headers: { "content-type": "image/png" }, body: fakePng(1146, 1800, `biedronka:${p.page + 1}`) });
  }
  // Lidl: the list, the 22.10 leaflet from the flyer endpoint (the other leaflets aren't served), page images.
  web.on(LIDL_LISTING, { headers: { "content-type": "text/html;charset=utf-8" }, body: fixture("lidl_overview.html") });
  web.on(lidlFlyerUrl("gazetka-22-10-czw-kw43"), { headers: { "content-type": "application/json" }, body: fixture("lidl_flyer.json") });
  for (const p of fixtureJson<{ flyer: { pages: { number: number; zoom: string }[] } }>("lidl_flyer.json").flyer.pages) {
    web.on(p.zoom, { headers: { "content-type": "image/jpeg" }, body: fakeJpeg(1420, 2400, `lidl:${p.number}`) });
  }
  // Dino: the Nuxt page; page images are JPEGs named .webp, as on the real site.
  web.on(DINO_LISTING, { headers: { "content-type": "text/html; charset=utf-8" }, body: fixture("dino_gazetki.html") });
  web.onPrefix("https://api.marketdino.pl/media/pdf/promo_news_pages/", (u) => {
    const no = /page_\d+_(\d+)_/.exec(u.pathname)?.[1] ?? "0";
    return { headers: { "content-type": "image/jpeg" }, body: fakeJpeg(1786, 2467, `dino:${no}`) };
  });
  // Rossmann: "pieluchy rozmiar 4" finds the fixture's products; any other search finds none.
  web.on(rossmannSearch("pieluchy rozmiar 4"), { headers: { "content-type": "text/html; charset=utf-8" }, body: fixture("rossmann_promocje_pieluchy.html") });
  web.onPrefix("https://www.rossmann.pl/promocje?Search=", { headers: { "content-type": "text/html; charset=utf-8" }, body: rossmannEmpty() });
  // Aldi: one Next.js page with the week's offers. Żabka: the list, the 43-44 leaflet's spreads.json (the next
  // leaflet, 45-46, isn't this week yet on 2026-10-24) and page images on Publitas's host (no robots.txt: 404).
  web.on(ALDI_OFFERS, { headers: { "content-type": "text/html; charset=utf-8" }, body: fixture("aldi_oferty.html") });
  web.on(ZABKA_LISTING, { headers: { "content-type": "text/html; charset=UTF-8" }, body: fixture("zabka_gazetka.html") });
  web.on(ZABKA_SPREADS, { headers: { "content-type": "application/json" }, body: fixture("zabka_spreads.json") });
  for (const s of fixtureJson<{ pages: { number: number; images: { at2000: string } }[] }[]>("zabka_spreads.json")) {
    for (const p of s.pages) web.on(`https://view.publitas.com${p.images.at2000}`, { headers: { "content-type": "image/jpeg" }, body: fakeJpeg(1565, 2555, `zabka:${p.number}`) });
  }
  return web;
}

// ---------- the contract (SHOPPING.md §2, schemas/fixtures/deals_search_v1.json), strict ----------

const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const money = z.strictObject({ minor: z.number().int().positive(), currency: z.literal("PLN") });
const readChain = z.enum(["biedronka", "lidl", "dino", "rossmann", "aldi", "zabka"]);
const anyChain = z.enum(["biedronka", "lidl", "dino", "rossmann", "aldi", "zabka", "kaufland", "carrefour", "auchan", "netto"]);
export const OfferSchema = z.strictObject({
  chain: readChain,
  product: z.string().min(1).max(160),
  price: money,
  size: z.strictObject({ value: z.number().positive(), unit: z.enum(["g", "kg", "ml", "l", "szt"]) }).optional(),
  unitPrice: z.strictObject({ minor: z.number().int().positive(), per: z.enum(["kg", "l", "szt"]) }).optional(),
  regularPrice: money.optional(),
  lowest30d: money.optional(),
  conditions: z.array(z.string().min(1).max(80)).max(4),
  validFrom: day.optional(),
  validTo: day.optional(),
  source: z.strictObject({ url: z.string().url().startsWith("https://"), page: z.number().int().positive().optional() }),
  readBy: z.enum(["leaflet_data", "page_image"]),
  ean: z.string().regex(/^\d{8,14}$/).optional(),
  check: z.boolean(),
});
/** Fewer pages read than were worth reading: read is below of. */
const pagesRead = z.strictObject({ read: z.number().int().min(0), of: z.number().int().positive() }).refine((p) => p.read < p.of);
export const ResponseSchema = z.strictObject({
  checkedAt: z.string().datetime(),
  chains: z.array(z.union([
    z.strictObject({
      chain: anyChain, status: z.literal("checked"),
      leaflet: z.strictObject({ title: z.string().optional(), url: z.string().url(), validFrom: day.optional(), validTo: day.optional() }),
      pages: pagesRead.optional(),
    }),
    z.strictObject({ chain: anyChain, status: z.literal("link_only"), leafletUrl: z.string().url() }),
    z.strictObject({ chain: anyChain, status: z.literal("failed"), pages: pagesRead.optional() }),
    z.strictObject({ chain: anyChain, status: z.enum(["no_match", "no_leaflet", "blocked"]) }),
  ])),
  items: z.array(z.strictObject({ query: z.string(), offers: z.array(OfferSchema).max(6) })),
});
/** The fixture's example request and response (the contract the app builds against). */
export const contractFixture = (): { request: unknown; response: unknown; errors: Record<string, { status: number; body: unknown }> } =>
  JSON.parse(readFileSync(new URL("../../../../schemas/fixtures/deals_search_v1.json", import.meta.url), "utf8"));
