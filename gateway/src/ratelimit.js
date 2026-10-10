// Fixed-window limiter behind a small port. The in-memory version is per function instance, so on
// serverless it is a best-effort brake, NOT a spend guarantee. Before any beta, back the port with a
// shared store (Vercel KV/Upstash) and set a hard budget on the provider project. See gateway/README.md.

/**
 * @typedef {{allowed: true} | {allowed: false, retryAfterSeconds: number}} Decision
 * @typedef {{hit(key: string, limit: number, windowSeconds: number, nowMs: number): Promise<Decision>}} RateLimiter
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
