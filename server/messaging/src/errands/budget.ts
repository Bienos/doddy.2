// The research budget of one errand (security review 4 Nov 2026, ADR-702). Both runners (errands/researcher.ts
// and shopping/runner.ts) resume a paused turn until the model finishes or the time limit passes, and Anthropic's
// `max_uses` counts per request, so on its own it would give every resumed request a fresh allowance. The budget
// is therefore counted over the whole errand and handed to each request as what is left. A limit of 0 means
// no limit and is reachable only by setting the environment value to 0 on purpose; the defaults are finite.

export interface ResearchBudget {
  /** web_search uses per errand (ERRAND_MAX_SEARCHES). 0: no limit. */
  maxSearches: number;
  /** web_fetch uses per errand (ERRAND_MAX_FETCHES). 0: no limit. */
  maxFetches: number;
  /** Research requests per errand: the first and every resume after a pause (ERRAND_MAX_REQUESTS). 0: no limit. */
  maxRequests: number;
  /** Output tokens over all research requests of one errand (ERRAND_MAX_OUTPUT_TOKENS). 0: no limit. */
  maxOutputTokens: number;
}

/** Generous for real research (a trip is some dozen look-ups), finite for a run that never settles. */
export const DEFAULT_RESEARCH_BUDGET: ResearchBudget = { maxSearches: 40, maxFetches: 40, maxRequests: 30, maxOutputTokens: 300_000 };

/** What one more research request may still use; a missing field means no limit. */
export interface BudgetLeft { searches?: number; fetches?: number; outputTokens?: number }

export interface BudgetUsed { requests: number; searches: number; fetches: number; outputTokens: number }

export type BudgetLimit = "requests" | "searches" | "fetches" | "output_tokens";

/** Below this many output tokens a request can't say anything useful, so the budget counts as used up. */
export const MIN_REQUEST_TOKENS = 2_000;
/** The most one request may write; the budget only ever lowers it. */
export const MAX_REQUEST_TOKENS = 64_000;

/** The room left for the next request, or the limit that is already reached. */
export function budgetLeft(b: ResearchBudget, used: BudgetUsed): { left: BudgetLeft } | { reached: BudgetLimit } {
  const left: BudgetLeft = {};
  if (b.maxRequests > 0 && used.requests >= b.maxRequests) return { reached: "requests" };
  if (b.maxSearches > 0) {
    left.searches = b.maxSearches - used.searches;
    if (left.searches <= 0) return { reached: "searches" };
  }
  if (b.maxFetches > 0) {
    left.fetches = b.maxFetches - used.fetches;
    if (left.fetches <= 0) return { reached: "fetches" };
  }
  if (b.maxOutputTokens > 0) {
    left.outputTokens = b.maxOutputTokens - used.outputTokens;
    if (left.outputTokens < MIN_REQUEST_TOKENS) return { reached: "output_tokens" };
  }
  return { left };
}

export type WebTool = { readonly type: string; readonly name: string };

/**
 * The most web searches, or web fetches, one request may make. The tools must be byte for byte the same on every
 * request of one errand (12 Nov 2026): Claude Haiku 5.5 and Claude Opus 5.5 refuse with a 400 a request that sends
 * back a thinking block after `system`, `tools` or earlier messages changed, and lowering `max_uses` to what was
 * left changed `tools` on every resumed request (the live shopping errand of 11 Nov failed that way on its second
 * request). So `max_uses` stays fixed for the errand, and the errand-wide count is the code's: `budgetLeft` stops
 * the research before a request once a limit is reached, which bounds the whole errand at the limit plus at most
 * one request's worth.
 */
export const WEB_USES_PER_REQUEST = 20;

/**
 * The most of one fetched page (or PDF) a web fetch brings into the conversation, in tokens (12 Nov 2026). Every
 * web_fetch definition sends it: errands, shopping and Studio. Without it one long document can fill a request, and
 * each later request of the run pays for it again. About 15,000 words: a long article, a report's chapters, a product
 * page with its specification. A constant, so the tools stay byte for byte the same on every request of one run.
 */
export const WEB_FETCH_MAX_CONTENT_TOKENS = 20_000;

/** The web tools with a fixed `max_uses`: the errand's limit, at most `WEB_USES_PER_REQUEST`; none when the limit is 0
 * (no limit). The same for every request of one errand, whatever was used already. */
export function withMaxUses(tools: readonly WebTool[], b: ResearchBudget): Array<WebTool & { max_uses?: number }> {
  return tools.map((t) => {
    const limit = t.name === "web_search" ? b.maxSearches : t.name === "web_fetch" ? b.maxFetches : 0;
    return limit > 0 ? { ...t, max_uses: Math.min(limit, WEB_USES_PER_REQUEST) } : { ...t };
  });
}

/** `max_tokens` for one request: its usual ceiling (`ceiling`), lowered to what the budget still allows. */
export function requestTokens(left: BudgetLeft | undefined, b: ResearchBudget, ceiling = MAX_REQUEST_TOKENS): number {
  const room = left?.outputTokens ?? (b.maxOutputTokens > 0 ? b.maxOutputTokens : ceiling);
  return Math.max(MIN_REQUEST_TOKENS, Math.min(ceiling, room));
}
