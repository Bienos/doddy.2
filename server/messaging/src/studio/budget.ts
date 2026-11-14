// The job's dollar limit, enforced BEFORE each paid call (ADR-742 follow-up; changes/studio-precall-budget.md).
// Until now the limit was read after a call, so one call could cross it by its whole cost (a 64,000-token
// research request on Opus is $1.28 of output alone). Now, before every call:
//   1. a worst-case CEILING is computed: the estimated prompt at the step model's prices (cache-write price for
//      requests that cache, long-prompt tier where a model has one), the web searches the request may still run,
//      and max_tokens at the output price;
//   2. max_tokens is clamped DOWN so that ceiling fits what is left of the job's limit; if even a minimal useful
//      reply (MIN_USEFUL_OUTPUT_TOKENS) cannot fit, the job stops as `cost_limit` and nothing is sent;
//   3. the ceiling is RESERVED in the job's ledger; after the reply it is SETTLED from the usage the provider
//      reported (the reservation is dropped and the real cost counted);
//   4. a call that fails, times out or is cancelled AFTER it was sent has an unknown outcome: it may have been
//      billed, so UNKNOWN_OUTCOME_SHARE of its ceiling stays counted (never treated as free).
// Overrun margin (documented, not hidden): output is capped exactly by max_tokens, but the prompt is only
// ESTIMATED (CHARS_PER_TOKEN, REQUEST_OVERHEAD_TOKENS, CEILING_MARGIN) and server-side tool content in a research
// request is only bounded by the task budget the model was told. If the estimate is low, the real usage can
// exceed the ceiling by the error; the existing check after each call (`withinLimit`) still ends the job then.
// The server's day and month reservations are untouched: approval still commits the whole job limit once
// (`reserved_usd`), the job never plans to spend more than that limit, and `releaseUnspent` gives back what the
// final cost (including unknown-outcome allowances) did not use.
import { PER_SEARCH_USD, priceTier, STEP_MAX_OUTPUT, type StudioStep } from "./models.js";

/** A token is rarely under 3 characters in JSON or Polish text; 2 over-counts on purpose. */
export const CHARS_PER_TOKEN = 2;
/** System prompt, tool definitions and the output schema are added by the API request itself. */
export const REQUEST_OVERHEAD_TOKENS = 4_000;
/** Extra headroom on everything estimated (not on max_tokens, which is exact). */
export const CEILING_MARGIN = 1.05;
/** What stays counted for a call that was sent and whose outcome is unknown. */
export const UNKNOWN_OUTCOME_SHARE = 0.5;
/** Research results enter the prompt inside the request; the model is told the task budget, so count 1.5 times it. */
export const TOOL_INPUT_FACTOR = 1.5;
/** Fewer output tokens than this cannot produce a useful reply for the step, so the call is not sent. */
export const MIN_USEFUL_OUTPUT_TOKENS: Record<StudioStep, number> = { plan: 2_000, research: 8_000, pack: 4_000, write: 6_000, make: 4_000 };

export interface CallSpec {
  step: StudioStep;
  model: string;
  /** Characters of the system prompt, the messages and anything else sent as text. */
  inputChars: number;
  /** The request caches its prompt (research, make): priced as a cache write, 1.25 times. */
  cacheWrite?: boolean;
  /** Web searches this request may still run (each costs PER_SEARCH_USD). */
  searchesLeft?: number;
  /** Tokens of web content the request may add to its own prompt. */
  toolInputTokens?: number;
}

export interface CallPlan { maxTokens: number; ceilingUsd: number; inputUsd: number; searchUsd: number }

/** The worst-case cost of `spec` with `maxTokens` of output. */
export function ceilingUsd(spec: CallSpec, maxTokens: number): CallPlan {
  const inputTokens = Math.ceil(spec.inputChars / CHARS_PER_TOKEN) + REQUEST_OVERHEAD_TOKENS + Math.ceil(spec.toolInputTokens ?? 0);
  const t = priceTier(spec.model, inputTokens);
  const inputUsd = inputTokens * t.input * (spec.cacheWrite ? 1.25 : 1) * CEILING_MARGIN / 1_000_000;
  const searchUsd = (spec.searchesLeft ?? 0) * PER_SEARCH_USD;
  return { maxTokens, inputUsd, searchUsd, ceilingUsd: inputUsd + searchUsd + maxTokens * t.output / 1_000_000 };
}

/**
 * The largest max_tokens (at most the step's usual one) whose ceiling fits in `remainingUsd`, or undefined when even
 * the step's minimum useful reply doesn't fit.
 */
export function planCall(spec: CallSpec, remainingUsd: number): CallPlan | undefined {
  const base = ceilingUsd(spec, 0);
  const inputTokens = Math.ceil(spec.inputChars / CHARS_PER_TOKEN) + REQUEST_OVERHEAD_TOKENS + Math.ceil(spec.toolInputTokens ?? 0);
  const outPerToken = priceTier(spec.model, inputTokens).output / 1_000_000;
  const room = remainingUsd - base.ceilingUsd;
  if (!(room > 0)) return undefined;
  const maxTokens = Math.min(STEP_MAX_OUTPUT[spec.step], Math.floor(room / outPerToken));
  if (maxTokens < MIN_USEFUL_OUTPUT_TOKENS[spec.step]) return undefined;
  return ceilingUsd(spec, maxTokens);
}

/** What a job has reserved for calls in flight, and what it keeps counted for calls whose outcome is unknown. All operations are idempotent per call id. */
export class JobReservations {
  private readonly open = new Map<string, number>();
  private readonly closed = new Set<string>();
  unknownUsd = 0;

  get openUsd(): number {
    let n = 0;
    for (const v of this.open.values()) n += v;
    return n;
  }
  /** False (and nothing counted twice) when `id` was already reserved or finished. */
  reserve(id: string, usd: number): boolean {
    if (this.open.has(id) || this.closed.has(id)) return false;
    this.open.set(id, usd);
    return true;
  }
  /** The reply arrived with usage: the reservation is dropped (the pipeline counts the real cost). */
  settle(id: string): boolean {
    if (!this.open.delete(id)) return false;
    this.closed.add(id);
    return true;
  }
  /** Never sent: the whole reservation goes back. */
  release(id: string): boolean { return this.settle(id); }
  /** Sent, outcome unknown (error, timeout, cancel, or a reply without usage): UNKNOWN_OUTCOME_SHARE of the ceiling stays counted. */
  unknown(id: string): boolean {
    const usd = this.open.get(id);
    if (usd === undefined) return false;
    this.open.delete(id);
    this.closed.add(id);
    this.unknownUsd += usd * UNKNOWN_OUTCOME_SHARE;
    return true;
  }
}
