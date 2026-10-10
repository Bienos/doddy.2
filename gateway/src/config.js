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
 */

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
  if (missing.length > 0) return { ok: false, missing };
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
    },
  };
}
