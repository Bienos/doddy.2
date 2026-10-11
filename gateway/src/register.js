import { loadConfig } from './config.js';
import { errorResponse, json, readJson, clientAddress } from './http.js';
import { logEvent } from './logging.js';
import { methodNotAllowed } from './assist.js';
import { StoreUnavailableError } from './store.js';
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
  /** Shared store configured but unreachable: refuse (fail closed). */
  /** @param {string} key @param {number} limit @param {number} window */
  const hit = async (key, limit, window) => {
    try { return await deps.limiter.hit(key, limit, window, nowMs); } catch (err) {
      if (err instanceof StoreUnavailableError) return null;
      throw err;
    }
  };
  const address = clientAddress(request);
  // Without the platform's address headers every client shares one bucket; make that visible.
  const noAddress = address === 'unknown' ? { cause: 'noClientAddress' } : {};
  const perAddress = await hit(`reg-ip:${address}`, 20, 3600);
  if (!perAddress) return fail('providerUnavailable', { cause: 'limitStore' });
  if (!perAddress.allowed) return fail('rateLimited', noAddress, { retryAfterSeconds: perAddress.retryAfterSeconds });

  const body = await readJson(request, 1024);
  if (!body.ok) return fail(body.code, noAddress);
  const parsed = validateRegisterRequest(body.value);
  if (!parsed.ok) return fail('invalidRequest', noAddress);

  const tag = inviteTag(parsed.value.inviteCode, config.tokenSecret);
  if (!config.inviteTags.has(tag)) return fail('notAuthorized', noAddress);
  const perInvite = await hit(`reg-inv:${tag}`, 300, 86_400);
  if (!perInvite) return fail('providerUnavailable', { cause: 'limitStore' });
  if (!perInvite.allowed) return fail('rateLimited', {}, { retryAfterSeconds: perInvite.retryAfterSeconds });

  const { token, expiresAtMs } = issueToken(
    { deviceId: parsed.value.deviceId, inviteTag: tag }, config.tokenSecret, Math.floor(nowMs / 1000), config.tokenTtlSeconds);
  log({ status: 200, deviceTag: deviceTag(parsed.value.deviceId), ...noAddress });
  return json(200, { schemaVersion: 1, token, expiresAtMs });
}
