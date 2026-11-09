import { randomUUID } from "node:crypto";

/**
 * The account-linked ledger of the backend's Anthropic calls (research item 1, 2026-11-09).
 *
 * One row per HTTP call to Anthropic (a document that pauses and continues makes several), with the
 * account, provider, model, feature, request id, token counters (including cache writes and reads),
 * whether it worked, and a cost worked out from the price table below. It holds NO text: no prompt,
 * no material, no answer, no provider error message. A failed call whose usage Anthropic didn't
 * report is recorded with `usageKnown: false` and no numbers; usage is never invented.
 *
 * This is the backend's Ask / chat / document / structured traffic only. Voice sessions are not
 * metered here, so the totals must not be presented as complete voice cost.
 */

export const LEDGER_PROVIDER = "anthropic";

/** What the response's `usage` object said, exactly; every counter is the provider's own number. */
export interface TokenUsage {
  /** Input after the last cache breakpoint that was neither read nor written (the provider's `input_tokens`). */
  inputTokens: number;
  outputTokens: number;
  /** Everything written to the cache by this call, any lifetime. */
  cacheCreationTokens: number;
  /** Of `cacheCreationTokens`, what was written with the one-hour lifetime (priced higher). */
  cacheCreation1hTokens: number;
  cacheReadTokens: number;
}

export type CallKind = "initial" | "continuation" | "retry";

export interface LedgerEvent {
  userId: string;
  provider: string;
  model: string;
  feature: string;
  requestId: string;
  seq: number;
  kind: CallKind;
  outcome: "succeeded" | "failed";
  /** A content-free code (`rate_limited`, `provider_timeout`…), never a provider message. */
  errorCode: string | null;
  /** The provider's `stop_reason` when it is a plain word (`end_turn`, `refusal`…). */
  stopReason: string | null;
  /** Null: the provider didn't tell us (an error, a timeout), which is not the same as zero. */
  usage: TokenUsage | null;
  /** Nano-US-dollars (1e-9 USD) from `priceVersion`'s table; null when usage or the model's price is unknown. */
  costNanoUsd: number | null;
  priceVersion: string | null;
  at: number;
}

export interface UsageRecorder {
  record(event: LedgerEvent): Promise<void>;
}

// ------------------------------------------------------------------ prices

/**
 * Prices in USD per million tokens, read from platform.claude.com/docs/en/about-claude/pricing on
 * 9 Nov 2026. A 5-minute cache write costs 1.25x base input; a read 0.1x (0.05x on Sonnet 5.5 and
 * Opus 5.5); a 1-hour write 2x. Code-execution container time (documents made with skills) is billed
 * by execution time, separately from tokens, and is NOT in these numbers.
 */
export const PRICE_VERSION = "anthropic-2026-11-09";

interface Rate {
  input: number;
  write5m: number;
  write1h: number;
  read: number;
  output: number;
}
interface ModelPrice {
  /** Prefix of the model id this row prices (a dated snapshot id carries a suffix). */
  prefix: string;
  base: Rate;
  /** Haiku 5.5 is dearer for prompts over 100,000 input tokens. */
  longRate?: { aboveTokens: number; rate: Rate };
}

const rate = (input: number, output: number, readMultiplier = 0.1): Rate => ({ input, write5m: input * 1.25, write1h: input * 2, read: input * readMultiplier, output });

/** Longest prefix first, so `claude-sonnet-5-5` wins over `claude-sonnet-5`. */
export const PRICES: readonly ModelPrice[] = [
  { prefix: "claude-opus-5-5", base: rate(4, 20, 0.05) },
  { prefix: "claude-opus-5", base: rate(5, 25) },
  { prefix: "claude-opus-4-8", base: rate(5, 25) },
  { prefix: "claude-opus-4-7", base: rate(5, 25) },
  { prefix: "claude-opus-4-6", base: rate(5, 25) },
  { prefix: "claude-opus-4-5", base: rate(5, 25) },
  { prefix: "claude-sonnet-5-5", base: rate(2, 10, 0.05) },
  { prefix: "claude-sonnet-5", base: rate(2, 10) },
  { prefix: "claude-sonnet-4-6", base: rate(3, 15) },
  { prefix: "claude-sonnet-4-5", base: rate(3, 15) },
  { prefix: "claude-haiku-5-5", base: rate(0.1, 0.5), longRate: { aboveTokens: 100_000, rate: rate(0.5, 2.5) } },
  { prefix: "claude-haiku-4-5", base: rate(1, 5) },
].sort((a, b) => b.prefix.length - a.prefix.length);

/** `claude-sonnet-5-5-20261001` prices as `claude-sonnet-5-5`; a model not in the table has no price. */
export function priceFor(model: string): ModelPrice | null {
  return PRICES.find((p) => model === p.prefix || model.startsWith(`${p.prefix}-`)) ?? null;
}

/**
 * Cost in nano-US-dollars (an integer; 1 token at $1/MTok is 1000), or null when the model has no
 * price in the table. Total input for the long-prompt tier is input + cache reads + cache writes.
 */
export function costNanoUsd(model: string, usage: TokenUsage): number | null {
  const price = priceFor(model);
  if (!price) return null;
  const totalInput = usage.inputTokens + usage.cacheReadTokens + usage.cacheCreationTokens;
  const r = price.longRate && totalInput > price.longRate.aboveTokens ? price.longRate.rate : price.base;
  const write1h = Math.min(usage.cacheCreation1hTokens, usage.cacheCreationTokens);
  const write5m = usage.cacheCreationTokens - write1h;
  // $/MTok x tokens / 1e6 = USD; x 1e9 = nano-USD, so $/MTok x tokens x 1000.
  return Math.round((usage.inputTokens * r.input + write5m * r.write5m + write1h * r.write1h + usage.cacheReadTokens * r.read + usage.outputTokens * r.output) * 1000);
}

// ------------------------------------------------------------------ reading a response

const count = (n: unknown): number => (typeof n === "number" && Number.isSafeInteger(n) && n >= 0 ? n : 0);

/**
 * The counters of a response's `usage` object, or null when it has none (then the usage is unknown,
 * not zero). A usage object that is present but lacks a counter means that counter was 0.
 */
export function readUsage(raw: unknown): TokenUsage | null {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return null;
  const u = raw as Record<string, unknown>;
  if (u.input_tokens === undefined && u.output_tokens === undefined) return null;
  const created = typeof u.cache_creation === "object" && u.cache_creation !== null ? (u.cache_creation as Record<string, unknown>) : null;
  const cacheCreationTokens = count(u.cache_creation_input_tokens);
  return {
    inputTokens: count(u.input_tokens),
    outputTokens: count(u.output_tokens),
    cacheCreationTokens,
    cacheCreation1hTokens: created ? Math.min(count(created.ephemeral_1h_input_tokens), cacheCreationTokens) : 0,
    cacheReadTokens: count(u.cache_read_input_tokens),
  };
}

export const zeroUsage = (): TokenUsage => ({ inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 0 });

export function addUsage(a: TokenUsage, b: TokenUsage): TokenUsage {
  return {
    inputTokens: a.inputTokens + b.inputTokens,
    outputTokens: a.outputTokens + b.outputTokens,
    cacheCreationTokens: a.cacheCreationTokens + b.cacheCreationTokens,
    cacheCreation1hTokens: a.cacheCreation1hTokens + b.cacheCreation1hTokens,
    cacheReadTokens: a.cacheReadTokens + b.cacheReadTokens,
  };
}

// ------------------------------------------------------------------ the scope of one logical request

/**
 * Who a call is for and which feature, made once per logical request by the caller. The provider asks
 * it to number each call: a call after the first that isn't a pause-turn continuation is a retry.
 */
export class UsageScope {
  private seq = 0;
  /** The usage of every call so far in this scope, so a caller can log a request's total. */
  total: TokenUsage = zeroUsage();

  constructor(
    readonly userId: string,
    readonly feature: string,
    readonly requestId: string = randomUUID(),
  ) {}

  begin(continuation: boolean): { seq: number; kind: CallKind } {
    const seq = this.seq++;
    return { seq, kind: seq === 0 ? "initial" : continuation ? "continuation" : "retry" };
  }
}

/** Plain words only: a stop reason or error code from the provider is kept only if it looks like one. */
export const plainWord = (v: unknown): string | null => (typeof v === "string" && /^[a-z_]{1,40}$/.test(v) ? v : null);

/** Builds and records one event; a recording failure is logged without content and never reaches the caller's request. */
export async function recordCall(
  recorder: UsageRecorder | null | undefined,
  log: ((line: Record<string, unknown>) => void) | undefined,
  scope: UsageScope | undefined,
  call: { seq: number; kind: CallKind },
  model: string,
  result: { outcome: "succeeded" | "failed"; errorCode?: string | null; stopReason?: unknown; usage: TokenUsage | null },
  now: number = Date.now(),
): Promise<void> {
  if (!recorder || !scope) return;
  if (result.usage) scope.total = addUsage(scope.total, result.usage);
  const priced = result.usage ? costNanoUsd(model, result.usage) : null;
  const event: LedgerEvent = {
    userId: scope.userId,
    provider: LEDGER_PROVIDER,
    model,
    feature: scope.feature,
    requestId: scope.requestId,
    seq: call.seq,
    kind: call.kind,
    outcome: result.outcome,
    errorCode: result.errorCode ?? null,
    stopReason: plainWord(result.stopReason),
    usage: result.usage,
    costNanoUsd: priced,
    priceVersion: priced === null ? null : PRICE_VERSION,
    at: now,
  };
  try {
    await recorder.record(event);
  } catch {
    log?.({ level: "warn", event: "claude_usage_not_recorded", feature: scope.feature, outcome: result.outcome });
  }
}
