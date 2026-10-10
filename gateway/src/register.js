import { loadConfig } from './config.js';
import { errorResponse, json, readJson, clientAddress } from './http.js';
import { logEvent } from './logging.js';
import { methodNotAllowed } from './assist.js';
import { deviceTag, inviteTag, issueToken } from './token.js';
import { validateRegisterRequest } from './validate.js';

/** Exchanges an invite code + random device id for a short-lived bearer token. No account is created. */
/** @param {Request} request @param {import('./assist.js').Deps} deps */
export async function handleRegister(request, deps) {
  try {
    return await register(request, deps);
  } catch {
    logEvent({ evt: 'register', code: 'providerUnavailable' }, deps.logSink);
    return errorResponse('providerUnavailable');
  }
}

/** @param {Request} request @param {import('./assist.js').Deps} deps */
async function register(request, deps) {
  const started = deps.now();
  /** @param {Record<string, unknown>} fields */
  const log = (fields) => logEvent({ evt: 'register', ms: deps.now() - started, ...fields }, deps.logSink);
  /** @param {import('./errors.js').ErrorCode} code @param {Record<string, unknown>} [fields] @param {{requestId?: string, retryAfterSeconds?: number}} [opts] */
  const fail = (code, fields = {}, opts = {}) => { log({ code, ...fields }); return errorResponse(code, opts); };

  if (request.method !== 'POST') return methodNotAllowed();
  const loaded = loadConfig(deps.env);
  if (!loaded.ok) return fail('notConfigured', { configMissing: loaded.missing });
  const config = loaded.config;

  const nowMs = deps.now();
  const perAddress = await deps.limiter.hit(`reg-ip:${clientAddress(request)}`, 20, 3600, nowMs);
  if (!perAddress.allowed) return fail('rateLimited', {}, { retryAfterSeconds: perAddress.retryAfterSeconds });

  const body = await readJson(request, 1024);
  if (!body.ok) return fail(body.code);
  const parsed = validateRegisterRequest(body.value);
  if (!parsed.ok) return fail('invalidRequest');

  const tag = inviteTag(parsed.value.inviteCode, config.tokenSecret);
  if (!config.inviteTags.has(tag)) return fail('notAuthorized');
  const perInvite = await deps.limiter.hit(`reg-inv:${tag}`, 300, 86_400, nowMs);
  if (!perInvite.allowed) return fail('rateLimited', {}, { retryAfterSeconds: perInvite.retryAfterSeconds });

  const { token, expiresAtMs } = issueToken(
    { deviceId: parsed.value.deviceId, inviteTag: tag }, config.tokenSecret, Math.floor(nowMs / 1000), config.tokenTtlSeconds);
  log({ status: 200, deviceTag: deviceTag(parsed.value.deviceId) });
  return json(200, { schemaVersion: 1, token, expiresAtMs });
}
