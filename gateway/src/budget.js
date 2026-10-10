// Daily spend cap (ADR-125). Before a provider call the gateway reserves a worst-case cost estimate
// against every scope (everyone today, this install today); after the call it replaces the estimate
// with the real cost from the provider's token usage. A reservation that would push any scope over its
// cap is rolled back and the request is refused with `dailyLimitReached` until the next UTC day.
//
// Money is integer micro-dollars (1 USD = 1,000,000). A price of P USD per 1M tokens is exactly
// P micro-dollars per token, so cost = tokens x price, rounded up.
//
// This is a second line of defence. The first is a hard monthly limit on the OpenAI project itself:
// prices here are whatever the owner configured, and token counts are what the provider reported.

import { createHmac } from 'node:crypto';
import { asInt } from './store.js';

/**
 * @typedef {{inputPerMTok: number, outputPerMTok: number}} Prices   USD per 1M tokens
 * @typedef {{scope: string, capMicros: number}} Scope
 * @typedef {{day: string, amountMicros: number, scopes: string[]}} Reservation
 * @typedef {{ok: true, reservation: Reservation} | {ok: false, retryAfterSeconds: number}} ReserveResult
 * @typedef {{
 *   reserve(scopes: Scope[], amountMicros: number, nowMs: number): Promise<ReserveResult>,
 *   settle(reservation: Reservation, actualMicros: number): Promise<void>,
 * }} SpendCap
 * Both methods may throw StoreUnavailableError (shared adapter only): the caller must refuse the request.
 */

/**
 * Fixed allowance for message framing and the response-format wrapper, on top of the prompt bytes.
 * Byte-level BPE tokenizers never produce more tokens than UTF-8 bytes, so bytes + this is an upper bound.
 */
export const PROMPT_OVERHEAD_TOKENS = 500;

/** @param {{inputTokens: number, outputTokens: number}} usage @param {Prices} prices */
export function costMicros(usage, prices) {
  return Math.ceil(usage.inputTokens * prices.inputPerMTok + usage.outputTokens * prices.outputPerMTok);
}

/** Worst case for one call: every prompt byte is a token and the model uses its whole output allowance. */
/** @param {number} promptBytes @param {number} maxOutputTokens @param {Prices} prices */
export function estimateMicros(promptBytes, maxOutputTokens, prices) {
  return costMicros({ inputTokens: promptBytes + PROMPT_OVERHEAD_TOKENS, outputTokens: maxOutputTokens }, prices);
}

/** UTC calendar day, e.g. "2026-10-10". */
export const utcDay = (/** @type {number} */ nowMs) => new Date(nowMs).toISOString().slice(0, 10);

/** Seconds until the next UTC midnight (at least 1). */
export function secondsUntilNextUtcDay(/** @type {number} */ nowMs) {
  const next = Math.floor(nowMs / 86_400_000 + 1) * 86_400_000;
  return Math.max(1, Math.ceil((next - nowMs) / 1000));
}

/** Per function instance. Only for local development or when no shared store is configured. */
/** @implements {SpendCap} */
export class MemorySpendCap {
  /** @type {Map<string, number>} */
  #totals = new Map();

  /** @param {Scope[]} scopes @param {number} amountMicros @param {number} nowMs @returns {Promise<ReserveResult>} */
  async reserve(scopes, amountMicros, nowMs) {
    const day = utcDay(nowMs);
    for (const k of this.#totals.keys()) if (!k.startsWith(`${day}|`)) this.#totals.delete(k);
    const over = scopes.some((s) => (this.#totals.get(`${day}|${s.scope}`) ?? 0) + amountMicros > s.capMicros);
    if (over) return { ok: false, retryAfterSeconds: secondsUntilNextUtcDay(nowMs) };
    for (const s of scopes) this.#totals.set(`${day}|${s.scope}`, (this.#totals.get(`${day}|${s.scope}`) ?? 0) + amountMicros);
    return { ok: true, reservation: { day, amountMicros, scopes: scopes.map((s) => s.scope) } };
  }

  /** @param {Reservation} reservation @param {number} actualMicros */
  async settle(reservation, actualMicros) {
    const delta = actualMicros - reservation.amountMicros;
    for (const scope of reservation.scopes) {
      const k = `${reservation.day}|${scope}`;
      if (this.#totals.has(k)) this.#totals.set(k, Math.max(0, (this.#totals.get(k) ?? 0) + delta));
    }
  }

  /** Test/inspection helper. */
  total(/** @type {string} */ scope, /** @type {number} */ nowMs) {
    return this.#totals.get(`${utcDay(nowMs)}|${scope}`) ?? 0;
  }
}

/**
 * One counter per (scope, UTC day) in the shared store. INCRBY is atomic, so a request is admitted only
 * if its own post-increment total is within every cap: concurrent admitted requests can never jointly
 * exceed a cap. A refused reservation is rolled back with DECRBY (briefly over-counting, the safe side).
 * Scope names are HMAC-ed before they reach the store (no device ids in the store).
 * @implements {SpendCap}
 */
export class SharedSpendCap {
  #store;
  #keySecret;
  #prefix;

  /** @param {{store: import('./store.js').SharedStore, keySecret: string, prefix?: string}} opts */
  constructor(opts) {
    this.#store = opts.store;
    this.#keySecret = opts.keySecret;
    this.#prefix = opts.prefix ?? 'doddy:spend';
  }

  /** @param {string} scope @param {string} day */
  key(scope, day) {
    const bucket = createHmac('sha256', this.#keySecret).update(`spend:${scope}`).digest('hex').slice(0, 32);
    return `${this.#prefix}:${bucket}:${day}`;
  }

  /** @param {Scope[]} scopes @param {number} amountMicros @param {number} nowMs @returns {Promise<ReserveResult>} */
  async reserve(scopes, amountMicros, nowMs) {
    const day = utcDay(nowMs);
    const keys = scopes.map((s) => this.key(s.scope, day));
    // Two days of TTL: the counter must outlive any reservation settled just after midnight.
    const results = await this.#store.exec(keys.flatMap((k) => [['INCRBY', k, amountMicros], ['EXPIRE', k, 2 * 86_400]]));
    const totals = keys.map((_, i) => asInt(results[i * 2]));
    if (totals.some((total, i) => total > scopes[i].capMicros)) {
      await this.#store.exec(keys.map((k) => ['DECRBY', k, amountMicros]));
      return { ok: false, retryAfterSeconds: secondsUntilNextUtcDay(nowMs) };
    }
    return { ok: true, reservation: { day, amountMicros, scopes: scopes.map((s) => s.scope) } };
  }

  /** @param {Reservation} reservation @param {number} actualMicros */
  async settle(reservation, actualMicros) {
    const delta = actualMicros - reservation.amountMicros;
    if (delta === 0) return;
    await this.#store.exec(reservation.scopes.map((s) => ['INCRBY', this.key(s, reservation.day), delta]));
  }
}
