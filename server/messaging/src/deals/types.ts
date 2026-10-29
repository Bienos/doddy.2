// Leaflets ("gazetki"), shopping mode stage 1 (docs/implementation/SHOPPING.md §2): the shapes shared by the
// fetcher, the chain adapters, the page reader, the matcher and the route. Money is integer minor units
// (grosze) with its currency; every price on the wire comes from a chain's own data or from a page the
// reader read, never from anything else.
import type { PageFetcher } from "./fetcher.js";
import type { PageOutput, ScreenOutput } from "./vision.js";
import type { PickOutput } from "./match.js";

/** Chains whose leaflets Doddy reads on request (Aldi and Żabka since ADR-660). */
export const READ_CHAINS = ["biedronka", "lidl", "dino", "rossmann", "aldi", "zabka"] as const;
/** Chains that only get a link to their official leaflet page (bot walls, or no published data). */
export const LINK_CHAINS = ["kaufland", "carrefour", "auchan", "netto"] as const;
export const CHAINS = [...READ_CHAINS, ...LINK_CHAINS] as const;
export type ReadChain = (typeof READ_CHAINS)[number];
export type LinkChain = (typeof LINK_CHAINS)[number];
export type Chain = (typeof CHAINS)[number];

export const isReadChain = (c: string): c is ReadChain => (READ_CHAINS as readonly string[]).includes(c);

/** Official leaflet pages for the link-only chains (Netto checked 2026-10-24; Kaufland and Carrefour answer
 * bots with a challenge, so their addresses come from the research note, not a fetch). */
export const LINK_ONLY_URLS: Record<LinkChain, string> = {
  kaufland: "https://www.kaufland.pl/gazetka-promocyjna.html",
  carrefour: "https://www.carrefour.pl/gazetki",
  auchan: "https://www.auchan.pl/pl/gazetki",
  netto: "https://netto.pl/gazetka-netto/",
};

export const CHAIN_NAMES: Record<Chain, string> = {
  biedronka: "Biedronka", lidl: "Lidl", dino: "Dino", rossmann: "Rossmann", aldi: "Aldi",
  kaufland: "Kaufland", carrefour: "Carrefour", auchan: "Auchan", netto: "Netto", zabka: "Żabka",
};

export interface Money { minor: number; currency: "PLN" }
export type SizeUnit = "g" | "kg" | "ml" | "l" | "szt";
export interface Size { value: number; unit: SizeUnit }
export interface UnitPrice { minor: number; per: "kg" | "l" | "szt" }
export interface LeafletInfo { title?: string; url: string; validFrom?: string; validTo?: string }

export type ChainStatus = "checked" | "no_match" | "no_leaflet" | "blocked" | "failed" | "link_only";

/** One offer on the wire (fixture deals_search_v1.json). */
export interface Offer {
  chain: ReadChain;
  product: string;
  price: Money;
  size?: Size;
  unitPrice?: UnitPrice;
  regularPrice?: Money;
  lowest30d?: Money;
  conditions: string[];
  validFrom?: string;
  validTo?: string;
  source: { url: string; page?: number };
  readBy: "leaflet_data" | "page_image";
  ean?: string;
  check: boolean;
  /** What the price needs or carries, for the app's checklist and filters (ADR-661). */
  flags?: OfferFlag[];
  /** The price of one piece when buying `quantity` under the offer's mechanic ("2+1", "drugi za 5 zł",
   * "co druga −50%", "przy zakupie 2 szt."), worked out by the code and rounded up to the grosz. */
  effective?: { price: Money; quantity: number; unitPrice?: UnitPrice };
  /** The real reduction against the leaflet's own lowest price of the last 30 days (Omnibus), when that is
   * above the price. Never computed from a "regular" price. Not for multi-buy offers. */
  cut?: { percent: number };
  /** At most this many per customer, as the leaflet says. */
  limit?: number;
}

/** app/card: the price needs the chain's app or loyalty card; deposit: a container deposit is added at the
 * till; stock: while stocks last; selected_stores: only in some shops; not_a_cut: the leaflet's own 30-day
 * lowest price is not above this price, so it isn't a real reduction. */
export type OfferFlag = "app" | "card" | "deposit" | "stock" | "selected_stores" | "not_a_cut";

/** A promotion printed without a price ("1+1 na wszystkie proszki Persil z aplikacją"): its range and
 * mechanic, as the code wrote them from the reader's read. Never a price for a product (ADR-661). */
export interface Promotion {
  chain: ReadChain;
  /** The range as printed, at most 120 characters. */
  text: string;
  /** The mechanic in the code's words: "1+1", "druga sztuka za 5,00 zł", "co druga sztuka −50%", "−30%". */
  mechanic: string;
  conditions: string[];
  flags?: OfferFlag[];
  validFrom?: string;
  validTo?: string;
  source: { url: string; page?: number };
}

/** Sent only when fewer pages were read than were worth reading (the page cap, time, an image that
 * couldn't be fetched or read): `of` is every page where only an image read can find offers (all of an
 * image-only leaflet such as Biedronka's, Lidl's pages that name an item; not Dino's, which only confirm
 * offers its data gave), `read` those the reader read. A cheaper offer may be on the rest. */
export interface PagesRead { read: number; of: number }

export type ChainRow =
  | { chain: Chain; status: "checked"; leaflet: LeafletInfo; pages?: PagesRead }
  | { chain: Chain; status: "link_only"; leafletUrl: string }
  | { chain: Chain; status: "failed"; pages?: PagesRead }
  | { chain: Chain; status: "no_match" | "no_leaflet" | "blocked" };

/** "Search further" (ADR-666): addresses for the person to open, never fetched. `buyUrl` is the same search
 * page through an affiliate network, only where a programme covers the shop (ADR-612). */
export interface SearchLink { shop: string; url: string; buyUrl?: string }
export interface Further {
  /** Chains Doddy doesn't read that weren't asked for, with their leaflet page. */
  leaflets: { chain: LinkChain; url: string }[];
  /** Per item, in the request's order: its search page at each shop set, in the setting's order. */
  searches: { item: string; links: SearchLink[] }[];
}

export interface DealsResponse {
  checkedAt: string;
  chains: ChainRow[];
  /** `similar` (ADR-662): products of another kind in the same family ("masło roślinne" for "masło"), at most
   * three, labelled as not the item; the basket never counts them. */
  items: { query: string; offers: Offer[]; promotions?: Promotion[]; similar?: Offer[] }[];
  /** Absent when there is nothing to suggest, and from a server older than ADR-666. */
  further?: Further;
}

/** What the shopper must do for a price. Turned into words by the code, never by the model. */
export type ConditionKind =
  | "app" | "card" | "min_quantity" | "multi_buy" | "limit" | "other"
  // ADR-661: "drugi za 5 zł", "co n-ta −k%", a container deposit, while stocks last, only some shops.
  | "second_for" | "nth_discount" | "deposit" | "stock" | "selected_stores";
/** multi_buy: text "a+b"; min_quantity/limit: quantity; second_for: price (the second piece's);
 * nth_discount: quantity n and percent k (every n-th piece k% off). */
export interface Condition { kind: ConditionKind; quantity?: number; text?: string; price?: Money; percent?: number }

/** A product as the chain's own data gives it (name and price published by the chain). */
export interface DataProduct {
  name: string;
  price: Money;
  regularPrice?: Money;
  lowest30d?: Money;
  /** Pack size as the chain wrote it ("52 szt.", "250g"); the name is parsed when absent. */
  sizeText?: string;
  /** The chain's own unit price text ("1 szt. = 1,25 zł"), only to cross-check the code's. */
  printedUnitPrice?: string;
  ean?: string;
  conditions: Condition[];
  page?: number;
  url: string;
  validFrom?: string;
  validTo?: string;
  /** The data carries no conditions (Dino's hotspots): the price is confirmed against the page image. */
  confirmOnPage?: boolean;
}

/** One leaflet page the reader may read. `text` is the chain's own text for the page (Lidl). */
export interface LeafletPage { number: number; imageUrl: string; url: string; text?: string }

/** How the service picks pages to read: every page in order (image-only leaflets), pages whose published
 * text matches an item, pages holding a matched data product (to confirm its conditions), or none. */
export type PageStrategy = "all" | "text" | "confirm" | "none";

export interface LeafletRead {
  leaflet: LeafletInfo;
  products: DataProduct[];
  pages: LeafletPage[];
  strategy: PageStrategy;
}

export type ChainRead =
  /** `incomplete`: part of the chain couldn't be read, so "nothing matched" can't be claimed. */
  | { kind: "ok"; leaflets: LeafletRead[]; incomplete?: string }
  | { kind: "no_leaflet" }
  | { kind: "blocked" | "failed"; reason: string };

export interface ChainContext {
  fetcher: PageFetcher;
  /** The person's items, as sent. Only Rossmann's adapter sends them to the chain (as a search term). */
  queries: readonly string[];
  /** Today in Warsaw, YYYY-MM-DD. */
  today: string;
  signal: AbortSignal;
}

export interface ChainAdapter {
  readonly chain: ReadChain;
  /** The only hosts this adapter fetches from; addresses found in the chain's data must be on them. */
  readonly hosts: readonly string[];
  read(ctx: ChainContext): Promise<ChainRead>;
}

// ---------- the model (Claude Haiku), behind an interface so tests use fakes ----------

export type ImageMediaType = "image/jpeg" | "image/png" | "image/webp" | "image/gif";
export interface PageImage { data: Buffer; mediaType: ImageMediaType; width: number; height: number }
export interface ModelUsage { inputTokens: number; outputTokens: number }
export type ModelReply<T> =
  | { kind: "ok"; output: T; usage: ModelUsage }
  | { kind: "refused"; usage: ModelUsage }
  | { kind: "unparsed"; usage?: ModelUsage };

export interface PickCandidate { id: string; chain: string; name: string; size?: string }

export interface DealsModelApi {
  readonly model: string;
  /** Reads one leaflet page. Throws on API errors (network, HTTP, abort). */
  readPage(req: { image: PageImage; chain: ReadChain; queries: readonly string[] }, signal: AbortSignal): Promise<ModelReply<PageOutput>>;
  /** Says which candidates are each item, by id only. Throws on API errors. */
  pick(req: { queries: readonly string[]; candidates: PickCandidate[][] }, signal: AbortSignal): Promise<ModelReply<PickOutput>>;
  /** Says which of several page images could hold each item (ADR-662), without reading them. Throws on API
   * errors. A model without it reads image-only leaflets page by page, as before. */
  screenPages?(req: { images: readonly PageImage[]; chain: ReadChain; queries: readonly string[] }, signal: AbortSignal): Promise<ModelReply<ScreenOutput>>;
}

/** Leaflet switches and caps (SHOPPING.md §2). `enabled` is the env switch only. */
export interface DealsSettings {
  enabled: boolean;
  visionModel: string;
  /** Pages sent to the reader per chain per request. */
  maxPages: number;
  /** Pages of an image-only leaflet screened per chain per request before the full reads (ADR-662); 0: no
   * screening, every page read in order up to `maxPages`. */
  screenPages: number;
  dailyPerAccount: number;
  dailyPerServer: number;
}

/** Settings for an injected DealsDeps without its own (tests). The environment's DEALS_ENABLED defaults to "0". */
export const DEFAULT_DEALS_SETTINGS: DealsSettings = {
  enabled: true, visionModel: "claude-haiku-5-5", maxPages: 40, screenPages: 120, dailyPerAccount: 30, dailyPerServer: 1000,
};
