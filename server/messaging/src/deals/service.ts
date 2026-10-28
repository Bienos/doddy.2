// POST /v1/deals/search, the work behind the route (SHOPPING.md §2): each requested chain is read in parallel
// and on its own (one chain failing never stops another), the whole search within about 25 s. A chain's own
// data finds products or the pages worth reading; image pages go to the reader; the code matches items to
// products, computes unit prices and decides `check`; the model may then pick among the code's candidates
// by id. Every price comes from the chain's data or the reader's read of a page, parsed by the code.
// Nothing is stored: no page, image or offer outlives the request. Logs carry counts, codes and timings only.
import { biedronka } from "./chains/biedronka.js";
import { dayMonth, mapLimit, warsawDay } from "./chains/common.js";
import { dino } from "./chains/dino.js";
import { lidl } from "./chains/lidl.js";
import { rossmann } from "./chains/rossmann.js";
import { PoliteFetcher, type PageFetcher } from "./fetcher.js";
import {
  headMention, MATCH_THRESHOLD, MAX_PICK_CANDIDATES, matchScore, normalize, parsePrintedUnitPrice, parseSize, pickWithModel, terms,
  unitPrice, unitPricesAgree, type Terms,
} from "./match.js";
import { prepareImage, readPage, type ReadDate, type ReadProduct } from "./vision.js";
import {
  CHAIN_NAMES, isReadChain, LINK_ONLY_URLS, READ_CHAINS, type Chain, type ChainAdapter, type ChainRow, type ChainStatus,
  type Condition, type DataProduct, type DealsModelApi, type DealsResponse, type DealsSettings, type LeafletInfo, type LeafletPage,
  type LinkChain, type ModelUsage, type Money, type Offer, type PagesRead, type ReadChain, type UnitPrice,
} from "./types.js";

export const ADAPTERS: Record<ReadChain, ChainAdapter> = { biedronka, lidl, dino, rossmann };

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
export const MAX_OFFERS_PER_ITEM = 6;

// ---------- words for conditions (written by the code, never by the model) ----------

const APP: Record<"pl" | "en", Partial<Record<ReadChain, string>> & { default: string }> = {
  pl: { biedronka: "z aplikacją Moja Biedronka", lidl: "z Lidl Plus", rossmann: "z aplikacją Rossmann", default: "z aplikacją sieci" },
  en: { biedronka: "with the Moja Biedronka app", lidl: "with Lidl Plus", rossmann: "with the Rossmann app", default: "with the chain's app" },
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
  }
}

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
  if (o.lowest30d && o.lowest30d.minor < o.price.minor) doubts.push("lowest30d_below_price");
  const printed = parsePrintedUnitPrice(o.printedUnitPrice);
  if (printed && (!unit || !unitPricesAgree(unit, printed))) doubts.push("unit_price_disagrees");
  const conditions = [...new Set(o.conditions.map((c) => conditionText(c, o.chain, language)).filter((t): t is string => !!t))]
    .map((t) => t.slice(0, 80)).slice(0, 4);
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
  };
  return { offer, doubts };
}

/** Dates the reader read, as days: inside the leaflet's dates they are used, outside they make the offer doubtful. */
function readDates(p: ReadProduct, leaflet: LeafletInfo, today: string): { validFrom?: string; validTo?: string; outside: boolean } {
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

interface ChainResult {
  chain: ReadChain;
  status: Exclude<ChainStatus, "link_only">;
  leaflet?: LeafletInfo;
  candidates: Candidate[];
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
  const done = (r: Omit<ChainResult, "chain" | "pagesRead" | "usage" | "complete">, complete = false): ChainResult => {
    env.log("deals chain read", {
      chain, status: r.status, reason: r.reason, candidates: r.candidates.length, pagesRead, pagesWanted: r.pages?.of,
      inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, ms: Date.now() - started,
    });
    return { chain, pagesRead, usage, complete, ...r };
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
    const key = (li: number, page: number) => `${li}:${page}`;
    await mapLimit(jobs, env.readConcurrency, async (job) => {
      if (signal.aborted || env.chainDeadline - Date.now() < MIN_READ_TIME_MS) { unread++; reasons.add("time"); return; }
      const f = await env.fetcher.fetchPage(job.page.imageUrl, { accept: "image/avif;q=0,image/webp,image/png,image/jpeg,image/*;q=0.8", aiInput: true, signal });
      if (f.kind !== "ok") { unread++; reasons.add(`image_${f.kind}`); return; }
      const image = prepareImage(f.body);
      if ("error" in image) { unread++; reasons.add(`image_${image.error}`); return; }
      pagesRead++;
      try {
        const r = await readPage(env.model!, image, { chain, queries: env.queries, signal });
        if (r.usage) { usage.inputTokens += r.usage.inputTokens; usage.outputTokens += r.usage.outputTokens; }
        if (r.kind === "ok") reads.set(key(job.li, job.page.number), r.products);
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

    const complete = unread === 0 && !read.incomplete;
    // Pages whose offers only an image read can find (all of Biedronka's, Lidl's that name an item): when some
    // weren't read, the row says how many were (Biedronka's leaflet of 26 Oct had 97 against the cap of 40).
    // Dino's pages only confirm offers its data already gave, which say `check` until then, so they don't count.
    const hiding = allJobs.filter((j) => read.leaflets[j.li]!.strategy !== "confirm");
    const got = hiding.filter((j) => reads.has(key(j.li, j.page.number))).length;
    const pages = got < hiding.length ? { pages: { read: got, of: hiding.length } } : {};
    if (candidates.length === 0) {
      // "Nothing matched" only when everything that should have been read was read.
      return complete
        ? done({ status: "no_match", candidates }, true)
        : done({ status: "failed", reason: [...reasons].join(",") || "incomplete", candidates, ...pages });
    }
    // The chain's row names the leaflet most of its offers came from.
    const counts = new Map<number, number>();
    for (const c of candidates) { const li = leafletOf.get(c.id) ?? 0; counts.set(li, (counts.get(li) ?? 0) + 1); }
    const main = [...counts].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0]![0];
    return done({
      status: "checked", leaflet: read.leaflets[main]!.leaflet, candidates,
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

/** The unit most of an item's offers have a unit price in (kg before l before szt on a tie), if any. */
export function mainUnit(offers: readonly Offer[]): UnitPrice["per"] | undefined {
  const counts = new Map<UnitPrice["per"], number>();
  for (const o of offers) if (o.unitPrice) counts.set(o.unitPrice.per, (counts.get(o.unitPrice.per) ?? 0) + 1);
  let best: UnitPrice["per"] | undefined;
  for (const per of UNIT_ORDER) if ((counts.get(per) ?? 0) > (best ? counts.get(best)! : 0)) best = per;
  return best;
}

/** Best value first: offers with a unit price in `per`, lowest first; then the rest, by price. A pack of a
 * size Doddy couldn't read can't be called cheaper per kg, so it comes after the ones it can compare. */
const byValue = (per: UnitPrice["per"] | undefined) => (a: Candidate, b: Candidate) => {
  const ua = per && a.offer.unitPrice?.per === per ? a.offer.unitPrice.minor : undefined;
  const ub = per && b.offer.unitPrice?.per === per ? b.offer.unitPrice.minor : undefined;
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
      chain, status: "failed", reason: "error", candidates: [], pagesRead: 0, usage: { inputTokens: 0, outputTokens: 0 }, complete: false,
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

  const items = queries.map((query, i) => ({ query, offers: selectOffers(chosen[i] ?? []) }));
  const offered = new Set(items.flatMap((i) => i.offers.map((o) => o.chain)));
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
