// Provider cost ledger (migration 026): what each Claude call cost, per Doddy account, feature and model.
// Numbers and ids only: no prompt, answer, note or user text ever reaches this file's queries.
//
// Rules this file keeps:
// - Unknown usage is NULL and flagged `usage_known = false`, never 0 (a timed-out call may still have been billed).
// - A model without a price below has a NULL cost and `cost_basis = 'unknown_model'`, never an invented price.
// - Cache reads and writes are counted apart from plain input, because they are priced apart.
// - Recording is best effort: a ledger failure is logged by code and never fails the user's request.
import type { Db } from "./db.js";
import { log } from "./log.js";

/** Anthropic list prices read from https://platform.claude.com/docs/en/about-claude/pricing on 9 Nov 2026. */
export const PRICE_VERSION = "anthropic-list-2026-11-09";

interface Tier { input: number; output: number; cacheRead: number }
interface Price extends Tier {
  /** Prompts longer than `from` tokens (input + cache reads + cache writes) are billed at `tier`. Haiku 5.5 only. */
  long?: { from: number; tier: Tier };
}

// USD per million tokens. 5-minute cache write = 1.25 x input, 1-hour write = 2 x input (both from the same page).
const PRICES: Record<string, Price> = {
  "claude-fable-5-1": { input: 10, output: 50, cacheRead: 0.25 },
  "claude-fable-5": { input: 10, output: 50, cacheRead: 1 },
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2 },
  "claude-opus-5": { input: 5, output: 25, cacheRead: 0.5 },
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.1 },
  "claude-sonnet-5": { input: 2, output: 10, cacheRead: 0.2 },
  "claude-haiku-5-5": {
    input: 0.1, output: 0.5, cacheRead: 0.01,
    long: { from: 100_000, tier: { input: 0.5, output: 2.5, cacheRead: 0.05 } },
  },
};

/** The model id without a trailing date stamp (`claude-haiku-5-5-20261001` is `claude-haiku-5-5`). */
export const baseModel = (model: string): string => model.replace(/-\d{8}$/, "");

export const hasPrice = (model: string): boolean => baseModel(model) in PRICES;

/** What the provider reported for one call. Absent fields mean the provider did not report them. */
export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  /** The part of `cacheWriteTokens` written with the 1-hour lifetime (billed at 2x). 0 when only 5-minute writes. */
  cacheWrite1hTokens?: number;
}

const n = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.trunc(v) : 0);

/**
 * Reads an Anthropic `usage` object, keeping the cache counters. Returns undefined when the provider sent no
 * usage at all (so the ledger records "unknown", not zero).
 */
export function usageFromAnthropic(u: unknown): TokenUsage | undefined {
  if (!u || typeof u !== "object") return undefined;
  const r = u as Record<string, unknown>;
  if (typeof r.input_tokens !== "number" && typeof r.output_tokens !== "number") return undefined;
  const creation = r.cache_creation && typeof r.cache_creation === "object" ? r.cache_creation as Record<string, unknown> : undefined;
  return {
    inputTokens: n(r.input_tokens),
    outputTokens: n(r.output_tokens),
    cacheReadTokens: n(r.cache_read_input_tokens),
    cacheWriteTokens: n(r.cache_creation_input_tokens),
    cacheWrite1hTokens: Math.min(n(creation?.ephemeral_1h_input_tokens), n(r.cache_creation_input_tokens)),
  };
}

/** Cost in USD from the list prices, or null when the model has no price here. Not rounded. */
export function costUsd(model: string, u: TokenUsage): number | null {
  const p = PRICES[baseModel(model)];
  if (!p) return null;
  const prompt = u.inputTokens + u.cacheReadTokens + u.cacheWriteTokens;
  const t: Tier = p.long && prompt > p.long.from ? p.long.tier : p;
  const w1h = Math.min(u.cacheWrite1hTokens ?? 0, u.cacheWriteTokens);
  const w5m = u.cacheWriteTokens - w1h;
  return (u.inputTokens * t.input + u.outputTokens * t.output + u.cacheReadTokens * t.cacheRead
    + w5m * t.input * 1.25 + w1h * t.input * 2) / 1_000_000;
}

export type CostOutcome = "success" | "refused" | "unparsed" | "failure" | "retry";

export interface CostEvent {
  accountId: string | null;
  provider?: "anthropic" | "openai";
  model: string;
  feature: string;
  providerRequestId?: string | null;
  refId?: string | null;
  outcome: CostOutcome;
  attempts?: number;
  errorCode?: string | null;
  /** Undefined: the provider reported nothing, so the ledger stores "unknown". */
  usage?: TokenUsage;
  occurredAt?: Date;
}

// Only ids and short codes are stored: anything else in these fields is cut, so free text cannot slip in.
const ID = /^[A-Za-z0-9_.:-]{1,128}$/;
const idOrNull = (v: string | null | undefined) => (v && ID.test(v) ? v : null);

/** Writes one ledger row. Never throws: a ledger problem must not fail the user's request. Returns true if written. */
export async function recordCost(db: Db, e: CostEvent): Promise<boolean> {
  try {
    const known = e.usage !== undefined;
    const cost = known ? costUsd(e.model, e.usage!) : null;
    const basis = !known ? "unknown_usage" : cost === null ? "unknown_model" : "list_price";
    await db.query(
      `INSERT INTO provider_cost_events
         (occurred_at, account_id, provider, model, feature, provider_request_id, ref_id, outcome, attempts, error_code,
          usage_known, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, cost_usd, cost_basis, price_version)
       VALUES (COALESCE($1, now()), $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)`,
      [e.occurredAt ?? null, e.accountId, e.provider ?? "anthropic", e.model.slice(0, 64), e.feature,
        idOrNull(e.providerRequestId), idOrNull(e.refId), e.outcome, Math.max(1, e.attempts ?? 1), e.errorCode ? e.errorCode.slice(0, 40) : null,
        known, known ? e.usage!.inputTokens : null, known ? e.usage!.outputTokens : null,
        known ? e.usage!.cacheReadTokens : null, known ? e.usage!.cacheWriteTokens : null,
        cost, basis, cost === null ? null : PRICE_VERSION]);
    return true;
  } catch (err) {
    log("cost ledger write failed", { feature: e.feature, code: (err as { code?: string }).code ?? (err as Error).name });
    return false;
  }
}

/** Earlier attempts of a call that was tried again: one `retry` row each, usage unknown (a failed attempt reports none). */
export async function recordRetries(db: Db, base: Omit<CostEvent, "outcome" | "usage" | "attempts">, attempts: number): Promise<void> {
  for (let i = 1; i < attempts; i++) await recordCost(db, { ...base, outcome: "retry", attempts: i, providerRequestId: null });
}

/** The error class and HTTP status of a failed call as a short code, never the message (which may echo input). */
export function errorCode(err: unknown): string {
  const e = err as { status?: unknown; name?: unknown; code?: unknown };
  if (typeof e?.status === "number") return `http_${e.status}`;
  if (typeof e?.code === "string" && /^[A-Z0-9_]{2,30}$/.test(e.code)) return e.code.toLowerCase();
  return typeof e?.name === "string" ? e.name.toLowerCase().replace(/[^a-z0-9]+/g, "_").slice(0, 30) : "error";
}

// ---------- reading it back ----------

export interface CostRange { from: Date; to: Date }

export interface CostRow {
  feature: string; model: string;
  calls: number; failures: number; retries: number;
  /** Rows whose usage the provider never reported: their cost is not in `costUsd`. */
  unknownUsageCalls: number;
  inputTokens: number; outputTokens: number; cacheReadTokens: number; cacheWriteTokens: number;
  costUsd: number;
}

const SUM = `
  count(*) FILTER (WHERE outcome <> 'retry')::int AS calls,
  count(*) FILTER (WHERE outcome = 'failure')::int AS failures,
  count(*) FILTER (WHERE outcome = 'retry')::int AS retries,
  count(*) FILTER (WHERE NOT usage_known)::int AS unknown_usage_calls,
  COALESCE(sum(input_tokens), 0)::text AS input_tokens, COALESCE(sum(output_tokens), 0)::text AS output_tokens,
  COALESCE(sum(cache_read_tokens), 0)::text AS cache_read_tokens, COALESCE(sum(cache_write_tokens), 0)::text AS cache_write_tokens,
  COALESCE(sum(cost_usd), 0)::text AS cost_usd`;

const toRow = (r: Record<string, string | number>): CostRow => ({
  feature: String(r.feature), model: String(r.model), calls: Number(r.calls), failures: Number(r.failures), retries: Number(r.retries),
  unknownUsageCalls: Number(r.unknown_usage_calls), inputTokens: Number(r.input_tokens), outputTokens: Number(r.output_tokens),
  cacheReadTokens: Number(r.cache_read_tokens), cacheWriteTokens: Number(r.cache_write_tokens), costUsd: Number(r.cost_usd),
});

/** One account's costs by feature and model. Only that account's rows: the id is always a query parameter. */
export async function accountCosts(db: Db, accountId: string, range: CostRange): Promise<CostRow[]> {
  const { rows } = await db.query(
    `SELECT feature, model, ${SUM} FROM provider_cost_events
     WHERE account_id = $1 AND occurred_at >= $2 AND occurred_at < $3 GROUP BY feature, model ORDER BY feature, model`,
    [accountId, range.from, range.to]);
  return rows.map(toRow);
}

/** Every account together, for the owner: by feature and model, plus the part no account owns any more. */
export async function serverCosts(db: Db, range: CostRange): Promise<CostRow[]> {
  const { rows } = await db.query(
    `SELECT feature, model, ${SUM} FROM provider_cost_events
     WHERE occurred_at >= $1 AND occurred_at < $2 GROUP BY feature, model ORDER BY feature, model`,
    [range.from, range.to]);
  return rows.map(toRow);
}

/** The accounts that cost the most in the range (owner view), highest first. Deleted accounts are one NULL group. */
export async function topAccountsByCost(db: Db, range: CostRange, limit = 20): Promise<{ accountId: string | null; costUsd: number; calls: number }[]> {
  const { rows } = await db.query<{ account_id: string | null; cost_usd: string; calls: number }>(
    `SELECT account_id, COALESCE(sum(cost_usd), 0)::text AS cost_usd, count(*) FILTER (WHERE outcome <> 'retry')::int AS calls
     FROM provider_cost_events WHERE occurred_at >= $1 AND occurred_at < $2
     GROUP BY account_id ORDER BY sum(cost_usd) DESC NULLS LAST LIMIT $3`,
    [range.from, range.to, Math.min(Math.max(1, Math.trunc(limit)), 200)]);
  return rows.map((r) => ({ accountId: r.account_id, costUsd: Number(r.cost_usd), calls: r.calls }));
}
