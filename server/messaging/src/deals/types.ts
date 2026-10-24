// Leaflets ("gazetki"), shopping mode stage 1 (docs/implementation/SHOPPING.md §2): the shapes shared by the
// fetcher, the chain adapters, the page reader, the matcher and the route. Money is integer minor units
// (grosze) with its currency; every price on the wire comes from a chain's own data or from a page the
// reader read, never from anything else.
import type { PageFetcher } from "./fetcher.js";
import type { PageOutput } from "./vision.js";
import type { PickOutput } from "./match.js";

/** Chains whose leaflets Doddy reads on request. */
export const READ_CHAINS = ["biedronka", "lidl", "dino", "rossmann"] as const;
/** Chains that only get a link to their official leaflet page (bot walls, or no published data). */
export const LINK_CHAINS = ["kaufland", "carrefour", "auchan", "netto", "zabka"] as const;
export const CHAINS = [...READ_CHAINS, ...LINK_CHAINS] as const;
export type ReadChain = (typeof READ_CHAINS)[number];
export type LinkChain = (typeof LINK_CHAINS)[number];
export type Chain = (typeof CHAINS)[number];

export const isReadChain = (c: string): c is ReadChain => (READ_CHAINS as readonly string[]).includes(c);

/** Official leaflet pages for the link-only chains (Netto and Żabka checked 2026-10-24; Kaufland and
 * Carrefour answer bots with 403, so their addresses come from the research note, not a fetch). */
export const LINK_ONLY_URLS: Record<LinkChain, string> = {
  kaufland: "https://www.kaufland.pl/gazetka-promocyjna.html",
  carrefour: "https://www.carrefour.pl/gazetki",
  auchan: "https://www.auchan.pl/pl/gazetki",
  netto: "https://netto.pl/gazetka-netto/",
  zabka: "https://www.zabka.pl/gazetka-promocyjna/",
};

export const CHAIN_NAMES: Record<Chain, string> = {
  biedronka: "Biedronka", lidl: "Lidl", dino: "Dino", rossmann: "Rossmann",
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
}

export type ChainRow =
  | { chain: Chain; status: "checked"; leaflet: LeafletInfo }
  | { chain: Chain; status: "link_only"; leafletUrl: string }
  | { chain: Chain; status: "no_match" | "no_leaflet" | "blocked" | "failed" };

export interface DealsResponse {
  checkedAt: string;
  chains: ChainRow[];
  items: { query: string; offers: Offer[] }[];
}

/** What the shopper must do for a price. Turned into words by the code, never by the model. */
export type ConditionKind = "app" | "card" | "min_quantity" | "multi_buy" | "limit" | "other";
export interface Condition { kind: ConditionKind; quantity?: number; text?: string }

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
}

/** Leaflet switches and caps (SHOPPING.md §2). `enabled` is the env switch only. */
export interface DealsSettings {
  enabled: boolean;
  visionModel: string;
  /** Pages sent to the reader per chain per request. */
  maxPages: number;
  dailyPerAccount: number;
  dailyPerServer: number;
}

/** Settings for an injected DealsDeps without its own (tests). The environment's DEALS_ENABLED defaults to "0". */
export const DEFAULT_DEALS_SETTINGS: DealsSettings = {
  enabled: true, visionModel: "claude-haiku-5-5", maxPages: 40, dailyPerAccount: 30, dailyPerServer: 1000,
};
