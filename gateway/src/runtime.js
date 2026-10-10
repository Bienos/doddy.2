import { MemoryRateLimiter } from './ratelimit.js';

// One limiter per function instance (see ratelimit.js for why that is not a spend guarantee).
const limiter = new MemoryRateLimiter();

/** @returns {import('./assist.js').Deps} */
export function defaultDeps() {
  return { env: process.env, fetch: globalThis.fetch, now: () => Date.now(), limiter };
}
