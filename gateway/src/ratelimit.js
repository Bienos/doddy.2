// Fixed-window limiter behind a small port (ADR-114, ADR-124).
// - MemoryRateLimiter: per function instance. On serverless it is a best-effort brake only; used for
//   local development and when no shared store is configured (a startup warning is logged).
// - SharedRateLimiter: counters in a shared Redis-compatible store, so every instance sees the same
//   counts. If the store cannot be reached it throws StoreUnavailableError and the handler refuses the
//   request (fail closed); it never falls back to per-instance memory.
// Neither is a spend cap: that is SpendCap (budget.js, ADR-125) plus a hard limit on the OpenAI project.

import { createHmac } from 'node:crypto';
import { asInt } from './store.js';

/**
 * @typedef {{allowed: true} | {allowed: false, retryAfterSeconds: number}} Decision
 * @typedef {{hit(key: string, limit: number, windowSeconds: number, nowMs: number): Promise<Decision>}} RateLimiter
 * `hit` may throw StoreUnavailableError (shared adapter only); callers must then refuse the request.
 */

const MAX_KEYS = 10_000;

/** @implements {RateLimiter} */
export class MemoryRateLimiter {
  /** @type {Map<string, {count: number, resetAtMs: number}>} */
  #windows = new Map();

  /** @returns {Promise<Decision>} */
  async hit(/** @type {string} */ key, /** @type {number} */ limit, /** @type {number} */ windowSeconds, /** @type {number} */ nowMs) {
    const slot = `${key}|${windowSeconds}`;
    let w = this.#windows.get(slot);
    if (!w || w.resetAtMs <= nowMs) {
      if (this.#windows.size >= MAX_KEYS) this.#evict(nowMs);
      w = { count: 0, resetAtMs: nowMs + windowSeconds * 1000 };
      this.#windows.set(slot, w);
    }
    if (w.count >= limit) {
      return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((w.resetAtMs - nowMs) / 1000)) };
    }
    w.count += 1;
    return { allowed: true };
  }

  /** @param {number} nowMs */
  /** Drops expired windows, then the oldest ones. Never touches the global brake, so flooding the map cannot reset it. */
  #evict(/** @type {number} */ nowMs) {
    for (const [k, w] of this.#windows) if (w.resetAtMs <= nowMs) this.#windows.delete(k);
    for (const k of this.#windows.keys()) {
      if (this.#windows.size < MAX_KEYS * 0.9) break;
      if (!k.startsWith('global|')) this.#windows.delete(k);
    }
  }
}

/**
 * Fixed windows aligned to the epoch (window index = floor(now / window)), one Redis key per
 * (bucket, window, index): INCR + EXPIRE in one MULTI/EXEC, so concurrent instances count atomically.
 * Bucket names are HMAC-ed with a server secret before they reach the store, so the store never holds
 * a device id, invite tag or client IP address.
 * @implements {RateLimiter}
 */
export class SharedRateLimiter {
  #store;
  #keySecret;
  #prefix;

  /** @param {{store: import('./store.js').SharedStore, keySecret: string, prefix?: string}} opts */
  constructor(opts) {
    this.#store = opts.store;
    this.#keySecret = opts.keySecret;
    this.#prefix = opts.prefix ?? 'doddy:rl';
  }

  /** @returns {Promise<Decision>} */
  async hit(/** @type {string} */ key, /** @type {number} */ limit, /** @type {number} */ windowSeconds, /** @type {number} */ nowMs) {
    const windowMs = windowSeconds * 1000;
    const index = Math.floor(nowMs / windowMs);
    const bucket = createHmac('sha256', this.#keySecret).update(`ratelimit:${key}`).digest('hex').slice(0, 32);
    const redisKey = `${this.#prefix}:${bucket}:${windowSeconds}:${index}`;
    // The key name carries the window index, so a plain EXPIRE (no NX, works on any Redis) is enough:
    // the TTL only has to outlive the window. +60 s absorbs clock skew between instances.
    const [count] = await this.#store.exec([['INCR', redisKey], ['EXPIRE', redisKey, windowSeconds + 60]]);
    if (asInt(count) > limit) {
      const resetAtMs = (index + 1) * windowMs;
      return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil((resetAtMs - nowMs) / 1000)) };
    }
    return { allowed: true };
  }
}
