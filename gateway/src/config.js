import { inviteTag } from './token.js';

/**
 * @typedef {object} Config
 * @property {string} openaiKey
 * @property {string} model
 * @property {string} tokenSecret
 * @property {Set<string>} inviteTags
 * @property {number} perMinute
 * @property {number} perDay
 * @property {number} globalPerDay
 * @property {number} invitePerDay
 * @property {number} tokenTtlSeconds
 * @property {number} providerTimeoutMs
 * @property {number} providerDeadlineMs
 * @property {{url: string, token: string} | null} sharedStore   null = per-instance memory limits (dev only)
 * @property {number} dailyBudgetMicros       everyone, per UTC day
 * @property {number} installBudgetMicros     one install (device id), per UTC day
 * @property {import('./budget.js').Prices} prices
 */

/** Deliberately pessimistic placeholders, NOT any model's real price (none could be verified). */
export const DEFAULT_PRICES = Object.freeze({ inputPerMTok: 10, outputPerMTok: 40 });
export const DEFAULT_DAILY_BUDGET_USD = 1;
export const DEFAULT_INSTALL_BUDGET_USD = 0.25;

/**
 * Shared rate-limit/budget store (ADR-124). Upstash names first, Vercel KV names as a fallback.
 * Half a configuration is an error, never a silent fallback to per-instance memory.
 * @param {Record<string, string | undefined>} env
 * @returns {{store: {url: string, token: string} | null, problems: string[], required: boolean}}
 */
export function sharedStoreEnv(env) {
  const url = (env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL || '').trim();
  const token = (env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN || '').trim();
  const required = (env.REQUIRE_SHARED_LIMITS ?? '').trim() === '1';
  const problems = [];
  if (url && !/^https:\/\/[^\s/]+/.test(url)) problems.push('UPSTASH_REDIS_REST_URL');
  if (url && !token) problems.push('UPSTASH_REDIS_REST_TOKEN');
  if (!url && token) problems.push('UPSTASH_REDIS_REST_URL');
  if (!url && !token && required) problems.push('UPSTASH_REDIS_REST_URL', 'UPSTASH_REDIS_REST_TOKEN');
  return { store: url && token && problems.length === 0 ? { url, token } : null, problems, required };
}

/**
 * Positive decimal from env, or the fallback when unset. A value that is set but invalid is an error.
 * @param {string | undefined} value @param {number} fallback @returns {number | null}
 */
const positive = (value, fallback) => {
  if (value === undefined || value.trim() === '') return fallback;
  const n = Number(value.trim());
  return Number.isFinite(n) && n > 0 ? n : null;
};

/** @param {string | undefined} value @param {number} fallback */
const int = (value, fallback) => {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isInteger(n) && n > 0 ? n : fallback;
};

/**
 * @param {Record<string, string | undefined>} env
 * @returns {{ok: true, config: Config} | {ok: false, missing: string[]}}
 */
export function loadConfig(env) {
  const missing = [];
  const openaiKey = (env.OPENAI_API_KEY ?? '').trim();
  const model = (env.OPENAI_MODEL ?? '').trim();
  const tokenSecret = env.GATEWAY_TOKEN_SECRET ?? '';
  const invites = (env.GATEWAY_INVITE_CODES ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  if (!openaiKey) missing.push('OPENAI_API_KEY');
  if (!model) missing.push('OPENAI_MODEL');
  if (tokenSecret.length < 32) missing.push('GATEWAY_TOKEN_SECRET');
  // Invite codes are the only credential, so short ones are refused outright (fail closed).
  if (invites.length === 0 || invites.some((code) => code.length < 16)) missing.push('GATEWAY_INVITE_CODES');
  const shared = sharedStoreEnv(env);
  missing.push(...shared.problems);
  const dailyUsd = positive(env.DAILY_BUDGET_USD, DEFAULT_DAILY_BUDGET_USD);
  const installUsd = positive(env.DAILY_BUDGET_PER_INSTALL_USD, DEFAULT_INSTALL_BUDGET_USD);
  const inputPrice = positive(env.OPENAI_PRICE_INPUT_PER_MTOK_USD, DEFAULT_PRICES.inputPerMTok);
  const outputPrice = positive(env.OPENAI_PRICE_OUTPUT_PER_MTOK_USD, DEFAULT_PRICES.outputPerMTok);
  if (dailyUsd === null) missing.push('DAILY_BUDGET_USD');
  if (installUsd === null) missing.push('DAILY_BUDGET_PER_INSTALL_USD');
  if (inputPrice === null) missing.push('OPENAI_PRICE_INPUT_PER_MTOK_USD');
  if (outputPrice === null) missing.push('OPENAI_PRICE_OUTPUT_PER_MTOK_USD');
  if (missing.length > 0 || dailyUsd === null || installUsd === null || inputPrice === null || outputPrice === null) {
    return { ok: false, missing };
  }
  return {
    ok: true,
    config: {
      openaiKey,
      model,
      tokenSecret,
      inviteTags: new Set(invites.map((code) => inviteTag(code, tokenSecret))),
      perMinute: int(env.GATEWAY_RATE_PER_MINUTE, 10),
      perDay: int(env.GATEWAY_RATE_PER_DAY, 200),
      globalPerDay: int(env.GATEWAY_GLOBAL_PER_DAY, 2000),
      invitePerDay: int(env.GATEWAY_INVITE_PER_DAY, 600),
      tokenTtlSeconds: 24 * 3600,
      providerTimeoutMs: 20_000,
      // Whole-request budget; vercel.json maxDuration is 30 s.
      providerDeadlineMs: 26_000,
      sharedStore: shared.store,
      dailyBudgetMicros: Math.round(dailyUsd * 1_000_000),
      installBudgetMicros: Math.round(installUsd * 1_000_000),
      prices: { inputPerMTok: inputPrice, outputPerMTok: outputPrice },
    },
  };
}
