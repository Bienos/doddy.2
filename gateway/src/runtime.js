import { MemorySpendCap, SharedSpendCap } from './budget.js';
import { sharedStoreEnv } from './config.js';
import { logEvent } from './logging.js';
import { MemoryRateLimiter, SharedRateLimiter } from './ratelimit.js';
import { createRestStore } from './store.js';

/**
 * Picks the limit adapters once per function instance (ADR-124, ADR-125).
 * - Shared store configured: shared counters and shared daily budget. If the store is down, requests
 *   are refused (the adapters throw; handlers answer 503). No silent fallback to memory.
 * - Half-configured, or REQUIRE_SHARED_LIMITS=1 without a store: `loadConfig` reports the variable
 *   names and every request is answered `503 notConfigured`. The memory adapters returned here are
 *   never reached in that case.
 * - Nothing configured: per-instance memory (local development), with a startup warning in the logs.
 * @param {Record<string, string | undefined>} env
 * @param {{fetch: typeof fetch, logSink?: (line: string) => void}} io
 * @returns {{limiter: import('./ratelimit.js').RateLimiter, spend: import('./budget.js').SpendCap, shared: boolean}}
 */
export function createLimits(env, io) {
  const { store, problems } = sharedStoreEnv(env);
  // Spend is still capped, but against pessimistic placeholder prices (config.js DEFAULT_PRICES).
  if (!env.OPENAI_PRICE_INPUT_PER_MTOK_USD || !env.OPENAI_PRICE_OUTPUT_PER_MTOK_USD) {
    logEvent({ evt: 'startup', code: 'placeholderPrices' }, io.logSink);
  }
  if (store) {
    const rest = createRestStore({ url: store.url, token: store.token, fetch: io.fetch });
    const keySecret = env.GATEWAY_TOKEN_SECRET ?? '';
    return { limiter: new SharedRateLimiter({ store: rest, keySecret }), spend: new SharedSpendCap({ store: rest, keySecret }), shared: true };
  }
  if (problems.length > 0) {
    logEvent({ evt: 'startup', code: 'notConfigured', configMissing: problems }, io.logSink);
  } else {
    logEvent({ evt: 'startup', code: 'limitsPerInstance' }, io.logSink);
  }
  return { limiter: new MemoryRateLimiter(), spend: new MemorySpendCap(), shared: false };
}

/** Built once per function instance, on first use (the warning is logged once per instance). */
/** @type {ReturnType<typeof createLimits> | undefined} */
let limits;

/** @returns {import('./assist.js').Deps} */
export function defaultDeps() {
  limits ??= createLimits(process.env, { fetch: (...args) => globalThis.fetch(...args) });
  return { env: process.env, fetch: globalThis.fetch, now: () => Date.now(), limiter: limits.limiter, spend: limits.spend };
}
