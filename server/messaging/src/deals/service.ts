// POST /v1/deals/search, the work behind the route (SHOPPING.md §2): each requested chain is read in parallel
// and on its own (one chain failing never stops another), the whole search within about 25 s. A chain's own
// data finds products or the pages worth reading; image pages go to the reader; the code matches items to
// products, computes unit prices and decides `check`; the model may then pick among the code's candidates
// by id. Every price comes from the chain's data or the reader's read of a page, parsed by the code.
// Nothing is stored: no page, image or offer outlives the request. Logs carry counts, codes and timings only.
import { aldi } from "./chains/aldi.js";
import { biedronka } from "./chains/biedronka.js";
import { dayMonth, mapLimit, warsawDay } from "./chains/common.js";
import { dino } from "./chains/dino.js";
import { lidl } from "./chains/lidl.js";
import { rossmann } from "./chains/rossmann.js";
import { zabka } from "./chains/zabka.js";
import { PoliteFetcher, type PageFetcher } from "./fetcher.js";
import {
  headMention, MATCH_THRESHOLD, MAX_PICK_CANDIDATES, matchScore, normalize, parsePrintedUnitPrice, parseSize, pickWithModel, terms,
  unitPrice, unitPricesAgree, type Terms,
} from "./match.js";
import { prepareImage, readPage, type Mechanic, type ReadDate, type ReadProduct, type ReadPromotion } from "./vision.js";
import {
  CHAIN_NAMES, isReadChain, LINK_ONLY_URLS, READ_CHAINS, type Chain, type ChainAdapter, type ChainRow, type ChainStatus,
  type Condition, type DataProduct, type DealsModelApi, type DealsResponse, type DealsSettings, type LeafletInfo, type LeafletPage,
  type LinkChain, type ModelUsage, type Money, type Offer, type OfferFlag, type PagesRead, type Promotion, type ReadChain, type UnitPrice,
} from "./types.js";

export const ADAPTERS: Record<ReadChain, ChainAdapter> = { biedronka, lidl, dino, rossmann, aldi, zabka };

/** What the leaflet search needs. Without `model` (no Anthropic key) chains that publish product data still
 * answer; image pages can't be read, so those chains come back `failed`. */
export interface DealsDeps {
  settings: DealsSettings;
  fetcher?: PageFetcher;
  model?: DealsModelApi;
  /** For tests: a fixed clock for `checkedAt` and "today". */
  now?: () => Date;
  /** The whole search, chains and pick included. Default 25 s. */
  budgetMs?: number;
  /** Pages read at once per chain. Default 10. */
  readConcurrency?: number;
  /** For tests: other adapters in place of the real ones. */
  adapters?: Partial<Record<ReadChain, ChainAdapter>>;
  /** Where per-chain log lines go (codes and counts only). */
  log?: (msg: string, extra?: object) => void;
}

export interface SearchInput { items: string[]; chains?: Chain[]; language: string }

export interface SearchStats {
  chains: number;
  statuses: Partial<Record<ChainStatus, number>>;
  offers: number;
  checks: number;
  pagesRead: number;
  inputTokens: number;
  outputTokens: number;
  picked: "model" | "code";
  ms: number;
}

export const DEFAULT_BUDGET_MS = 25_000;
/** Kept back from the chains for the model's pick and the reply. */
const PICK_RESERVE_MS = 3_000;
/** A page read isn't started with less time than this left: it would be paid for and thrown away. */
const MIN_READ_TIME_MS = 2_500;
/** How long to wait before asking once more for a page image that came over the size cap. */
const RETRY_WAIT_MS = 2_000;
export const MAX_PROMOTIONS_PER_ITEM = 3;
export const MAX_OFFERS_PER_ITEM = 6;

// ---------- words for conditions (written by the code, never by the model) ----------

const APP: Record<"pl" | "en", Partial<Record<ReadChain, string>> & { default: string }> = {
  pl: { biedronka: "z aplikacją Moja Biedronka", lidl: "z Lidl Plus", rossmann: "z aplikacją Rossmann", zabka: "z aplikacją Żappka", default: "z aplikacją sieci" },
  en: { biedronka: "with the Moja Biedronka app", lidl: "with Lidl Plus", rossmann: "with the Rossmann app", zabka: "with the Żappka app", default: "with the chain's app" },
};
const CARD: Record<"pl" | "en", Partial<Record<ReadChain, string>> & { default: string }> = {
  pl: { biedronka: "z kartą Moja Biedronka", default: "z kartą lojalnościową" },
  en: { biedronka: "with the Moja Biedronka card", default: "with a loyalty card" },
};

export function conditionText(c: Condition, chain: ReadChain, language: string): string | undefined {
  const l = language === "pl" ? "pl" : "en";
  switch (c.kind) {
    case "app": return APP[l][chain] ?? APP[l].default;
    case "card": return CARD[l][chain] ?? CARD[l].default;
    case "min_quantity": return c.quantity ? (l === "pl" ? `przy zakupie ${c.quantity} szt.` : `when buying ${c.quantity}`) : undefined;
    case "limit": return c.quantity ? (l === "pl" ? `max ${c.quantity} szt.` : `max ${c.quantity} per customer`) : undefined;
    case "multi_buy": return c.text;
    case "other": return c.text?.slice(0, 80);
    case "second_for": return c.price ? (l === "pl" ? `druga sztuka za ${zl(c.price)}` : `the second for ${zl(c.price)}`) : undefined;
    case "nth_discount": return c.quantity && c.percent ? everyNth(c.quantity, c.percent, l) : undefined;
    case "deposit": return l === "pl" ? "plus kaucja za opakowanie" : "plus a container deposit";
    case "stock": return l === "pl" ? "do wyczerpania zapasów" : "while stocks last";
    case "selected_stores": return l === "pl" ? "w wybranych sklepach" : "in selected stores";
  }
}

/** "4,99 zł", from grosze. */
export const zl = (m: Money) => `${Math.floor(m.minor / 100)},${String(m.minor % 100).padStart(2, "0")} zł`;

const ORDINAL_PL: Record<number, string> = { 2: "druga", 3: "trzecia", 4: "czwarta", 5: "piąta", 6: "szósta" };
function everyNth(n: number, percent: number, l: "pl" | "en"): string {
  if (l === "pl") return `co ${ORDINAL_PL[n] ?? `${n}.`} sztuka −${percent}%`;
  const ordinal = n === 2 ? "second" : n === 3 ? "third" : `${n}th`;
  return `every ${ordinal} one −${percent}%`;
}

/** A promotion's mechanic in the code's words. */
export function mechanicText(m: Mechanic, language: string): string {
  const l = language === "pl" ? "pl" : "en";
  switch (m.kind) {
    case "multi_buy": return `${m.buy}+${m.free}`;
    case "second_for": return l === "pl" ? `druga sztuka za ${zl(m.price)}` : `the second for ${zl(m.price)}`;
    case "nth_discount": return everyNth(m.n, m.percent, l);
    case "percent_off": return `−${m.percent}%`;
  }
}

const FLAG_OF: Partial<Record<Condition["kind"], OfferFlag>> = { app: "app", card: "card", deposit: "deposit", stock: "stock", selected_stores: "selected_stores" };

/** The flags a list of conditions carries, in a fixed order. */
export function flagsOf(conditions: readonly Condition[]): OfferFlag[] {
  const set = new Set(conditions.map((c) => FLAG_OF[c.kind]).filter((f): f is OfferFlag => !!f));
  return (["app", "card", "deposit", "stock", "selected_stores"] as const).filter((f) => set.has(f));
}

/**
 * The price of one piece when buying the quantity the mechanic needs, rounded up to the grosz (ADR-661):
 * "a+b" → p·a/(a+b) for a+b; "drugi za X" → (p+X)/2 for 2; "co n-ta −k%" → p·(1−k/(100n)) for n;
 * "przy zakupie N szt." → p for N (the leaflet's price already is the price at N).
 */
export function effectivePrice(price: Money, conditions: readonly Condition[]): { price: Money; quantity: number } | undefined {
  const per = (minor: number, quantity: number) => ({ price: { minor: Math.ceil(minor), currency: price.currency }, quantity });
  for (const c of conditions) {
    if (c.kind === "multi_buy") {
      const m = /^(\d{1,2})\+(\d{1,2})$/.exec(c.text ?? "");
      const a = m ? Number(m[1]) : 0;
      const b = m ? Number(m[2]) : 0;
      if (a >= 1 && b >= 1) return per((price.minor * a) / (a + b), a + b);
    }
  }
  for (const c of conditions) if (c.kind === "second_for" && c.price && c.price.minor < price.minor) return per((price.minor + c.price.minor) / 2, 2);
  for (const c of conditions) {
    if (c.kind === "nth_discount" && c.quantity && c.percent) return per((price.minor * (100 * c.quantity - c.percent)) / (100 * c.quantity), c.quantity);
  }
  for (const c of conditions) if (c.kind === "min_quantity" && c.quantity && c.quantity >= 2) return per(price.minor, c.quantity);
  return undefined;
}

/** Offers whose price comes from buying several ("2+1", "drugi za", "co druga"): Omnibus' 30-day rule
 * doesn't apply to them (UOKiK), so no "cut" is stated. */
const isMultiBuy = (conditions: readonly Condition[]) => conditions.some((c) => c.kind === "multi_buy" || c.kind === "second_for" || c.kind === "nth_discount");

// ---------- building one offer, with the code's checks ----------

interface OfferInput {
  chain: ReadChain;
  name: string;
  price: Money;
  sizeText?: string;
  regularPrice?: Money;
  lowest30d?: Money;
  printedUnitPrice?: string;
  conditions: Condition[];
  validFrom?: string;
  validTo?: string;
  source: { url: string; page?: number };
  readBy: Offer["readBy"];
  ean?: string;
  /** Reasons the code already has for `check` (a low-confidence read, dates outside the leaflet, …). */
  doubts: string[];
}

/** The wire offer. `check` is true whenever the code can't stand behind the price as shown (contract rules). */
export function buildOffer(o: OfferInput, language: string): { offer: Offer; doubts: string[] } {
  const doubts = [...o.doubts];
  const size = parseSize(o.sizeText) ?? parseSize(o.name);
  const unit = unitPrice(o.price, size);
  if (o.regularPrice && o.regularPrice.minor <= o.price.minor) doubts.push("regular_not_above_price");
  // Under "the second for X" the price is the price of one bought alone (Aldi's regular price), which may well be
  // above the 30-day low; under every other price a 30-day low below it is a misread.
  const secondFor = o.conditions.some((c) => c.kind === "second_for");
  if (o.lowest30d && o.lowest30d.minor < o.price.minor && !secondFor) doubts.push("lowest30d_below_price");
  const printed = parsePrintedUnitPrice(o.printedUnitPrice);
  if (printed && (!unit || !unitPricesAgree(unit, printed))) doubts.push("unit_price_disagrees");
  const conditions = [...new Set(o.conditions.map((c) => conditionText(c, o.chain, language)).filter((t): t is string => !!t))]
    .map((t) => t.slice(0, 80)).slice(0, 4);
  const flags = flagsOf(o.conditions);
  let cut: Offer["cut"];
  if (o.lowest30d && !isMultiBuy(o.conditions)) {
    if (o.lowest30d.minor > o.price.minor) {
      const percent = Math.round((1 - o.price.minor / o.lowest30d.minor) * 100);
      if (percent >= 1) cut = { percent };
    } else flags.push("not_a_cut");
  }
  const eff = effectivePrice(o.price, o.conditions);
  const effUnit = eff ? unitPrice(eff.price, size) : undefined;
  const limit = o.conditions.find((c) => c.kind === "limit" && c.quantity)?.quantity;
  const offer: Offer = {
    chain: o.chain,
    product: o.name.slice(0, 160),
    price: o.price,
    ...(size ? { size } : {}),
    ...(unit ? { unitPrice: unit } : {}),
    ...(o.regularPrice ? { regularPrice: o.regularPrice } : {}),
    ...(o.lowest30d ? { lowest30d: o.lowest30d } : {}),
    conditions,
    ...(o.validFrom ? { validFrom: o.validFrom } : {}),
    ...(o.validTo ? { validTo: o.validTo } : {}),
    source: { url: o.source.url, ...(o.source.page ? { page: o.source.page } : {}) },
    readBy: o.readBy,
    ...(o.ean ? { ean: o.ean } : {}),
    check: doubts.length > 0,
    ...(flags.length ? { flags } : {}),
    ...(eff ? { effective: { ...eff, ...(effUnit ? { unitPrice: effUnit } : {}) } } : {}),
    ...(cut ? { cut } : {}),
    ...(limit ? { limit } : {}),
  };
  return { offer, doubts };
}

/** Dates the reader read, as days: inside the leaflet's dates they are used, outside they make the offer doubtful. */
function readDates(p: Pick<ReadProduct, "validFrom" | "validTo">, leaflet: LeafletInfo, today: string): { validFrom?: string; validTo?: string; outside: boolean } {
  const anchor = leaflet.validFrom ?? today;
  const day = (d: ReadDate | undefined) => (d ? dayMonth(d.day, d.month, anchor, d.year) : undefined);
  const from = day(p.validFrom);
  const to = day(p.validTo);
  const inside = (d: string | undefined) => !d || ((!leaflet.validFrom || d >= leaflet.validFrom) && (!leaflet.validTo || d <= leaflet.validTo));
  const outside = !inside(from) || !inside(to) || (!!from && !!to && to < from);
  return {
    validFrom: !outside && from ? from : leaflet.validFrom,
    validTo: !outside && to ? to : leaflet.validTo,
    outside,
  };
}

// ---------- one chain ----------

interface Candidate { id: string; chain: ReadChain; offer: Offer; doubts: string[]; scores: number[] }
interface PromotionCandidate { promotion: Promotion; scores: number[] }

interface ChainResult {
  chain: ReadChain;
  status: Exclude<ChainStatus, "link_only">;
  leaflet?: LeafletInfo;
  candidates: Candidate[];
  /** Promotions printed without a price that fit an item (ADR-661). */
  promotions: PromotionCandidate[];
  pagesRead: number;
  usage: ModelUsage;
  reason?: string;
  /** Every page and search that should have been read was read. */
  complete: boolean;
  /** Fewer pages read than were worth reading. */
  pages?: PagesRead;
}

interface Env {
  fetcher: PageFetcher;
  model?: DealsModelApi;
  queries: string[];
  queryTerms: Terms[];
  today: string;
  language: string;
  maxPages: number;
  readConcurrency: number;
  chainDeadline: number;
  signal: AbortSignal;
  nextId: () => string;
  log: (msg: string, extra?: object) => void;
}

const best = (scores: number[]) => scores.reduce((a, b) => Math.max(a, b), 0);

async function runChain(chain: ReadChain, adapter: ChainAdapter, env: Env): Promise<ChainResult> {
  const started = Date.now();
  const usage: ModelUsage = { inputTokens: 0, outputTokens: 0 };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), Math.max(0, env.chainDeadline - Date.now()));
  const onAbort = () => controller.abort();
  if (env.signal.aborted) onAbort();
  env.signal.addEventListener("abort", onAbort);
  const signal = controller.signal;
  let pagesRead = 0;
  const done = (r: Omit<ChainResult, "chain" | "pagesRead" | "usage" | "complete" | "promotions"> & { promotions?: PromotionCandidate[] }, complete = false): ChainResult => {
    env.log("deals chain read", {
      chain, status: r.status, reason: r.reason, candidates: r.candidates.length, pagesRead, pagesWanted: r.pages?.of,
      inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, ms: Date.now() - started,
    });
    return { chain, pagesRead, usage, complete, ...r, promotions: r.promotions ?? [] };
  };
  try {
    let read;
    try {
      read = await adapter.read({ fetcher: env.fetcher, queries: env.queries, today: env.today, signal });
    } catch {
      return done({ status: "failed", reason: "adapter_error", candidates: [] });
    }
    if (read.kind === "no_leaflet") return done({ status: "no_leaflet", candidates: [] });
    if (read.kind !== "ok") return done({ status: read.kind, reason: read.reason, candidates: [] });
    if (read.leaflets.length === 0) return done({ status: "no_leaflet", candidates: [] });

    let unread = 0;
    const reasons = new Set<string>(read.incomplete ? [read.incomplete] : []);
    const score = (text: string) => { const t = terms(text); return env.queryTerms.map((q) => matchScore(q, t)); };

    // The data products that fit an item, and the pages worth reading.
    const leaflets = read.leaflets.map((l, li) => {
      const data = l.products.map((p) => ({ p, scores: score(p.name) })).filter((x) => best(x.scores) >= MATCH_THRESHOLD);
      let jobs: { li: number; page: LeafletPage; score: number }[] = [];
      if (l.strategy === "all") jobs = l.pages.map((page) => ({ li, page, score: 0 }));
      else if (l.strategy === "text") {
        // A page is worth reading when its own text names the thing asked for; ordered by how well it fits.
        jobs = l.pages.flatMap((page) => {
          const t = terms(page.text ?? "");
          const mention = best(env.queryTerms.map((q) => headMention(q, t)));
          return mention > 0 ? [{ li, page, score: mention + best(env.queryTerms.map((q) => matchScore(q, t))) }] : [];
        });
      } else if (l.strategy === "confirm") {
        const byPage = new Map<number, number>();
        for (const d of data) if (d.p.confirmOnPage && d.p.page) byPage.set(d.p.page, Math.max(byPage.get(d.p.page) ?? 0, best(d.scores)));
        jobs = l.pages.filter((page) => byPage.has(page.number)).map((page) => ({ li, page, score: byPage.get(page.number)! }));
      }
      return { l, data, jobs };
    });
    const allJobs = leaflets.flatMap((x) => x.jobs).sort((a, b) => b.score - a.score || a.li - b.li || a.page.number - b.page.number);
    let jobs = allJobs.slice(0, env.maxPages);
    if (allJobs.length > jobs.length) { unread += allJobs.length - jobs.length; reasons.add("pages_over_cap"); }
    if (jobs.length && !env.model) { unread += jobs.length; reasons.add("no_reader"); jobs = []; }

    // Read the pages: fetch the image (the fetcher checks robots.txt and its content signals), hand it to
    // the reader, forget it.
    const reads = new Map<string, ReadProduct[]>();
    const promos = new Map<string, ReadPromotion[]>();
    const key = (li: number, page: number) => `${li}:${page}`;
    await mapLimit(jobs, env.readConcurrency, async (job) => {
      if (signal.aborted || env.chainDeadline - Date.now() < MIN_READ_TIME_MS) { unread++; reasons.add("time"); return; }
      const accept = "image/avif;q=0,image/webp,image/png,image/jpeg,image/*;q=0.8";
      let f = await env.fetcher.fetchPage(job.page.imageUrl, { accept, aiInput: true, signal });
      // A page not yet in the image host's cache can come as a full-size PNG over the size cap (Biedronka's
      // were 6.19 MB cold, 0.3 MB as WebP once cached): asked for once more, a moment later.
      if (f.kind === "failed" && f.reason === "too_large" && env.chainDeadline - Date.now() > MIN_READ_TIME_MS + RETRY_WAIT_MS && !signal.aborted) {
        await new Promise((r) => setTimeout(r, RETRY_WAIT_MS));
        f = await env.fetcher.fetchPage(job.page.imageUrl, { accept, aiInput: true, signal });
      }
      if (f.kind !== "ok") { unread++; reasons.add(`image_${f.kind}`); return; }
      const image = prepareImage(f.body);
      if ("error" in image) { unread++; reasons.add(`image_${image.error}`); return; }
      pagesRead++;
      try {
        const r = await readPage(env.model!, image, { chain, queries: env.queries, signal });
        if (r.usage) { usage.inputTokens += r.usage.inputTokens; usage.outputTokens += r.usage.outputTokens; }
        if (r.kind === "ok") { reads.set(key(job.li, job.page.number), r.products); promos.set(key(job.li, job.page.number), r.promotions); }
        else { unread++; reasons.add(`read_${r.kind}`); }
      } catch {
        unread++;
        reasons.add(signal.aborted ? "time" : "read_error");
      }
    });

    // Offers: data products (confirmed against their page where needed), then what the reader found.
    const candidates: Candidate[] = [];
    const seen = new Set<string>();
    const leafletOf = new Map<string, number>();
    const add = (input: OfferInput, scores: number[], li: number) => {
      const dedupe = `${normalize(input.name)}|${input.price.minor}|${input.validFrom ?? ""}`;
      if (seen.has(dedupe)) return;
      seen.add(dedupe);
      const { offer, doubts } = buildOffer(input, env.language);
      const id = env.nextId();
      candidates.push({ id, chain, offer, doubts, scores });
      leafletOf.set(id, li);
    };
    leaflets.forEach(({ l, data }, li) => {
      const used = new Set<ReadProduct>();
      for (const { p, scores } of data) {
        const doubts: string[] = [];
        let extra: Partial<DataProduct> & { lowConfidence?: boolean } = {};
        if (p.confirmOnPage) {
          const onPage = p.page ? reads.get(key(li, p.page)) : undefined;
          if (!onPage) doubts.push("conditions_unconfirmed");
          else {
            const nameTerms = terms(p.name);
            const same = onPage.filter((v) => !used.has(v) && matchScore(terms(v.name), nameTerms) >= MATCH_THRESHOLD);
            const confirmed = same.find((v) => v.price.minor === p.price.minor);
            if (confirmed) {
              used.add(confirmed);
              extra = {
                conditions: confirmed.conditions,
                ...(confirmed.regularPrice ? { regularPrice: confirmed.regularPrice } : {}),
                ...(confirmed.lowest30d ? { lowest30d: confirmed.lowest30d } : {}),
                ...(confirmed.printedUnitPrice ? { printedUnitPrice: confirmed.printedUnitPrice } : {}),
                ...(!p.sizeText && confirmed.sizeText ? { sizeText: confirmed.sizeText } : {}),
                lowConfidence: confirmed.lowConfidence,
              };
              if (confirmed.lowConfidence) doubts.push("low_confidence_read");
            } else {
              doubts.push(same.length ? "page_price_differs" : "conditions_unconfirmed");
              for (const v of same) used.add(v);
            }
          }
        }
        const { lowConfidence: _lc, ...merged } = { ...p, ...extra };
        add({
          chain, name: merged.name, price: p.price, sizeText: merged.sizeText, regularPrice: merged.regularPrice, lowest30d: merged.lowest30d,
          printedUnitPrice: merged.printedUnitPrice, conditions: merged.conditions, validFrom: p.validFrom, validTo: p.validTo,
          source: { url: p.url, ...(p.page ? { page: p.page } : {}) }, readBy: "leaflet_data", ean: p.ean, doubts,
        }, scores, li);
      }
      for (const page of l.pages) {
        for (const v of reads.get(key(li, page.number)) ?? []) {
          if (used.has(v)) continue;
          const scores = score(v.name);
          if (best(scores) < MATCH_THRESHOLD) continue;
          const dates = readDates(v, l.leaflet, env.today);
          add({
            chain, name: v.name, price: v.price, sizeText: v.sizeText, regularPrice: v.regularPrice, lowest30d: v.lowest30d,
            printedUnitPrice: v.printedUnitPrice, conditions: v.conditions, validFrom: dates.validFrom, validTo: dates.validTo,
            source: { url: page.url, page: page.number }, readBy: "page_image",
            doubts: [...(v.lowConfidence ? ["low_confidence_read"] : []), ...(dates.outside ? ["dates_outside_leaflet"] : [])],
          }, scores, li);
        }
      }
    });

    // Promotions printed without a price whose range fits an item: said as a mechanic, never as a price.
    const promotions: PromotionCandidate[] = [];
    const seenPromo = new Set<string>();
    leaflets.forEach(({ l }, li) => {
      for (const page of l.pages) {
        for (const p of promos.get(key(li, page.number)) ?? []) {
          const scores = score(p.range);
          if (best(scores) < MATCH_THRESHOLD) continue;
          const mechanic = mechanicText(p.mechanic, env.language);
          const dedupe = `${normalize(p.range)}|${mechanic}`;
          if (seenPromo.has(dedupe)) continue;
          seenPromo.add(dedupe);
          const dates = readDates(p, l.leaflet, env.today);
          const conditions = [...new Set(p.conditions.map((c) => conditionText(c, chain, env.language)).filter((t): t is string => !!t))].slice(0, 4);
          const flags = flagsOf(p.conditions);
          promotions.push({
            scores,
            promotion: {
              chain, text: p.range, mechanic, conditions, ...(flags.length ? { flags } : {}),
              ...(dates.validFrom ? { validFrom: dates.validFrom } : {}), ...(dates.validTo ? { validTo: dates.validTo } : {}),
              source: { url: page.url, page: page.number },
            },
          });
        }
      }
    });

    const complete = unread === 0 && !read.incomplete;
    // Pages whose offers only an image read can find (all of Biedronka's, Lidl's that name an item): when some
    // weren't read, the row says how many were (Biedronka's leaflet of 26 Oct had 97 against the cap of 40).
    // Dino's pages only confirm offers its data already gave, which say `check` until then, so they don't count.
    const hiding = allJobs.filter((j) => read.leaflets[j.li]!.strategy !== "confirm");
    const got = hiding.filter((j) => reads.has(key(j.li, j.page.number))).length;
    const pages = got < hiding.length ? { pages: { read: got, of: hiding.length } } : {};
    if (candidates.length === 0 && promotions.length === 0) {
      // "Nothing matched" only when everything that should have been read was read.
      return complete
        ? done({ status: "no_match", candidates }, true)
        : done({ status: "failed", reason: [...reasons].join(",") || "incomplete", candidates, ...pages });
    }
    // The chain's row names the leaflet most of its offers came from.
    const counts = new Map<number, number>();
    for (const c of candidates) { const li = leafletOf.get(c.id) ?? 0; counts.set(li, (counts.get(li) ?? 0) + 1); }
    const main = [...counts].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0]?.[0] ?? 0;
    return done({
      status: "checked", leaflet: read.leaflets[main]!.leaflet, candidates, promotions,
      ...(reasons.size ? { reason: [...reasons].join(",") } : {}), ...pages,
    }, complete);
  } finally {
    clearTimeout(timer);
    env.signal.removeEventListener("abort", onAbort);
  }
}

// ---------- choosing the offers ----------

const byPrice = (a: Candidate, b: Candidate) =>
  a.offer.price.minor - b.offer.price.minor
  || (a.offer.unitPrice?.minor ?? Number.MAX_SAFE_INTEGER) - (b.offer.unitPrice?.minor ?? Number.MAX_SAFE_INTEGER)
  || a.chain.localeCompare(b.chain) || a.offer.product.localeCompare(b.offer.product);

const UNIT_ORDER: UnitPrice["per"][] = ["kg", "l", "szt"];

/** The unit price an offer is ranked by: the price per piece under its mechanic when it has one ("2+1"),
 * else its own. */
const rankUnit = (o: Offer): UnitPrice | undefined => o.effective?.unitPrice ?? o.unitPrice;

/** The unit most of an item's offers have a unit price in (kg before l before szt on a tie), if any. */
export function mainUnit(offers: readonly Offer[]): UnitPrice["per"] | undefined {
  const counts = new Map<UnitPrice["per"], number>();
  for (const o of offers) { const u = rankUnit(o); if (u) counts.set(u.per, (counts.get(u.per) ?? 0) + 1); }
  let best: UnitPrice["per"] | undefined;
  for (const per of UNIT_ORDER) if ((counts.get(per) ?? 0) > (best ? counts.get(best)! : 0)) best = per;
  return best;
}

/** What an offer asks of the shopper, each 5% on its unit price for ranking only (ADR-661): the chain's app
 * or card, and buying more than one. A price anyone can get wins a near tie; a clearly better deal still wins. */
export const CONDITION_PENALTY = 0.05;
export function rankValue(o: Offer, per: UnitPrice["per"]): number | undefined {
  const u = rankUnit(o);
  if (!u || u.per !== per) return undefined;
  const asks = (o.flags?.some((f) => f === "app" || f === "card") ? 1 : 0) + ((o.effective?.quantity ?? 1) > 1 ? 1 : 0);
  return u.minor * (1 + CONDITION_PENALTY * asks);
}

/** Best value first: offers with a unit price in `per` (under their mechanic, with the condition penalty),
 * lowest first; then the rest, by price. A pack of a size Doddy couldn't read can't be called cheaper per kg,
 * so it comes after the ones it can compare. */
const byValue = (per: UnitPrice["per"] | undefined) => (a: Candidate, b: Candidate) => {
  const ua = per ? rankValue(a.offer, per) : undefined;
  const ub = per ? rankValue(b.offer, per) : undefined;
  if (ua !== undefined && ub !== undefined) return ua - ub || byPrice(a, b);
  if (ua !== undefined) return -1;
  if (ub !== undefined) return 1;
  return byPrice(a, b);
};

/** Up to six offers, best value first (price per kg, l or piece), with every chain's lowest price among them:
 * the basket buys one pack of each item, so it needs each chain's cheapest pack. */
export function selectOffers(cands: Candidate[]): Offer[] {
  const cheapest = [...cands].sort(byPrice);
  const picked: Candidate[] = [];
  const chains = new Set<ReadChain>();
  for (const c of cheapest) if (!chains.has(c.chain)) { chains.add(c.chain); picked.push(c); }
  const value = byValue(mainUnit(cands.map((c) => c.offer)));
  for (const c of [...cands].sort(value)) {
    if (picked.length >= MAX_OFFERS_PER_ITEM) break;
    if (!picked.includes(c)) picked.push(c);
  }
  return picked.slice(0, MAX_OFFERS_PER_ITEM).sort(value).map((c) => c.offer);
}

// ---------- the search ----------

export async function searchDeals(deps: DealsDeps, input: SearchInput, signal: AbortSignal = new AbortController().signal):
  Promise<{ response: DealsResponse; stats: SearchStats }> {
  const started = Date.now();
  const now = deps.now ?? (() => new Date());
  const log = deps.log ?? (() => {});
  const budget = deps.budgetMs ?? DEFAULT_BUDGET_MS;
  const fetcher = deps.fetcher ?? new PoliteFetcher();
  const queries = input.items.map((q) => q.trim());
  const requested = [...new Set(input.chains ?? READ_CHAINS)];
  let n = 0;
  const env: Env = {
    fetcher, model: deps.model, queries, queryTerms: queries.map((q) => terms(q)), today: warsawDay(now()), language: input.language,
    maxPages: deps.settings.maxPages, readConcurrency: deps.readConcurrency ?? 10,
    chainDeadline: started + budget - (deps.model ? PICK_RESERVE_MS : 500), signal, nextId: () => `c${++n}`, log,
  };

  const results = await Promise.all(requested.filter(isReadChain).map((chain) => {
    const adapter = deps.adapters?.[chain] ?? ADAPTERS[chain];
    return runChain(chain, adapter, env).catch((): ChainResult => ({
      chain, status: "failed", reason: "error", candidates: [], promotions: [], pagesRead: 0, usage: { inputTokens: 0, outputTokens: 0 }, complete: false,
    }));
  }));
  const usage: ModelUsage = { inputTokens: 0, outputTokens: 0 };
  for (const r of results) { usage.inputTokens += r.usage.inputTokens; usage.outputTokens += r.usage.outputTokens; }

  // The code's candidates per item, best first; then the model may say which of the top ones are the item.
  const all = results.flatMap((r) => r.candidates);
  const perItem = queries.map((_, qi) => all.filter((c) => (c.scores[qi] ?? 0) >= MATCH_THRESHOLD)
    .sort((a, b) => (b.scores[qi] ?? 0) - (a.scores[qi] ?? 0) || byPrice(a, b)));
  let chosen = perItem;
  let picked: SearchStats["picked"] = "code";
  const left = started + budget - Date.now();
  if (deps.model && perItem.some((l) => l.length > 0) && left > 1500 && !signal.aborted) {
    const top = perItem.map((l) => l.slice(0, MAX_PICK_CANDIDATES));
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.min(5000, left - 1000));
    const onAbort = () => controller.abort();
    signal.addEventListener("abort", onAbort);
    try {
      const r = await pickWithModel(deps.model, queries, top.map((l) => l.map((c) => ({
        id: c.id, chain: CHAIN_NAMES[c.chain], name: c.offer.product, ...(c.offer.size ? { size: `${c.offer.size.value} ${c.offer.size.unit}` } : {}),
      }))), controller.signal);
      if (r.usage) { usage.inputTokens += r.usage.inputTokens; usage.outputTokens += r.usage.outputTokens; }
      if (r.outcome === "ok") {
        chosen = top.map((l, i) => (r.picks[i] ? l.filter((c) => r.picks[i]!.has(c.id)) : perItem[i]!));
        picked = "model";
      }
    } catch {
      // The pick is optional: on any error the code's candidates stand.
    } finally {
      clearTimeout(timer);
      signal.removeEventListener("abort", onAbort);
    }
  }

  const allPromotions = results.flatMap((r) => r.promotions);
  const items = queries.map((query, i) => {
    const promotions = allPromotions.filter((p) => (p.scores[i] ?? 0) >= MATCH_THRESHOLD)
      .sort((a, b) => (b.scores[i] ?? 0) - (a.scores[i] ?? 0)).slice(0, MAX_PROMOTIONS_PER_ITEM).map((p) => p.promotion);
    return { query, offers: selectOffers(chosen[i] ?? []), ...(promotions.length ? { promotions } : {}) };
  });
  const offered = new Set(items.flatMap((i) => [...i.offers.map((o) => o.chain), ...(i.promotions ?? []).map((p) => p.chain)]));
  const byChain = new Map(results.map((r) => [r.chain, r]));
  const chains: ChainRow[] = requested.map((chain): ChainRow => {
    if (!isReadChain(chain)) return { chain, status: "link_only", leafletUrl: LINK_ONLY_URLS[chain as LinkChain] };
    const r = byChain.get(chain)!;
    const pages = r.pages ? { pages: r.pages } : {};
    if (r.status === "failed" || (r.status === "checked" && !r.leaflet)) return { chain, status: "failed", ...pages };
    if (r.status !== "checked") return { chain, status: r.status };
    // Read, but the pick kept none of its products: nothing matched (if it was all read).
    if (!offered.has(chain)) return r.complete ? { chain, status: "no_match" } : { chain, status: "failed", ...pages };
    return { chain, status: "checked", leaflet: r.leaflet!, ...pages };
  });
  const statuses: SearchStats["statuses"] = {};
  for (const c of chains) statuses[c.status] = (statuses[c.status] ?? 0) + 1;
  const offers = items.flatMap((i) => i.offers);
  return {
    response: { checkedAt: now().toISOString(), chains, items },
    stats: {
      chains: chains.length, statuses, offers: offers.length, checks: offers.filter((o) => o.check).length,
      pagesRead: results.reduce((s, r) => s + r.pagesRead, 0), ...usage, picked, ms: Date.now() - started,
    },
  };
}
