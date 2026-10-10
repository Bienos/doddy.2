import { loadConfig } from './config.js';
import { errorResponse, json, bearerToken, readJson } from './http.js';
import { logEvent } from './logging.js';
import { callProvider } from './openai.js';
import { buildInput, buildInstructions, buildSchema } from './prompt.js';
import { deviceTag, shortTag, verifyToken } from './token.js';
import { LIMITS, validateAssistRequest } from './validate.js';

/**
 * @typedef {object} Deps
 * @property {Record<string, string | undefined>} env
 * @property {typeof fetch} fetch
 * @property {() => number} now           milliseconds
 * @property {import('./ratelimit.js').RateLimiter} limiter
 * @property {(line: string) => void} [logSink]
 */

const MAX_ANSWER = 4_000;

export function methodNotAllowed() {
  return json(405, { schemaVersion: 1, error: { code: 'invalidRequest', message: 'Use POST.' } }, { allow: 'POST' });
}

/**
 * Never lets an unexpected error escape: an uncaught throw would give the platform's bare 500 and
 * put a stack trace in the platform logs, outside the content-free logging allow-list.
 * @param {Request} request @param {Deps} deps
 */
export async function handleAssist(request, deps) {
  try {
    return await assist(request, deps);
  } catch {
    logEvent({ evt: 'assist', code: 'providerUnavailable' }, deps.logSink);
    return errorResponse('providerUnavailable');
  }
}

/** @param {Request} request @param {Deps} deps */
async function assist(request, deps) {
  const started = deps.now();
  /** @param {Record<string, unknown>} fields */
  const log = (fields) => logEvent({ evt: 'assist', ms: deps.now() - started, ...fields }, deps.logSink);
  /** @param {import('./errors.js').ErrorCode} code @param {Record<string, unknown>} [fields] @param {{requestId?: string, retryAfterSeconds?: number}} [opts] */
  const fail = (code, fields = {}, opts = {}) => {
    log({ code, ...fields });
    return errorResponse(code, opts);
  };

  if (request.method !== 'POST') return methodNotAllowed();

  const loaded = loadConfig(deps.env);
  if (!loaded.ok) return fail('notConfigured', { configMissing: loaded.missing });
  const config = loaded.config;

  // 1. Authenticate before reading the body.
  const token = bearerToken(request);
  const claims = token ? verifyToken(token, config.tokenSecret, Math.floor(deps.now() / 1000)) : null;
  if (!claims || !config.inviteTags.has(claims.inviteTag)) return fail('notAuthorized');
  const tag = deviceTag(claims.deviceId);

  // 2. Rate limits (per device per minute and per day, plus a global daily brake).
  const nowMs = deps.now();
  /** @type {[string, number, number][]} */
  const checks = [
    [`dev:${claims.deviceId}`, config.perMinute, 60],
    [`dev:${claims.deviceId}`, config.perDay, 86_400],
    // Device ids are chosen by the client, so one invite's total is capped too.
    [`inv:${claims.inviteTag}`, config.invitePerDay, 86_400],
    ['global', config.globalPerDay, 86_400],
  ];
  for (const [key, limit, window] of checks) {
    const decision = await deps.limiter.hit(key, limit, window, nowMs);
    if (!decision.allowed) return fail('rateLimited', { deviceTag: tag }, { retryAfterSeconds: decision.retryAfterSeconds });
  }

  // 3. Parse and validate (size-capped, strict).
  const body = await readJson(request, LIMITS.bodyBytes);
  if (!body.ok) return fail(body.code, { deviceTag: tag });
  const parsed = validateAssistRequest(body.value);
  if (!parsed.ok) return fail('invalidRequest', { deviceTag: tag });
  const req = parsed.value;
  const counts = { deviceTag: tag, requestId: shortTag('request', req.requestId), memoryCount: req.memories.length, turnCount: req.turns.length };

  // 4. Call the provider.
  const { input, aliasToId } = buildInput(req);
  const result = await callProvider(
    { fetch: deps.fetch, apiKey: config.openaiKey, model: config.model, timeoutMs: config.providerTimeoutMs, deadlineMs: config.providerDeadlineMs },
    { instructions: buildInstructions(req.locale), input, schema: buildSchema([...aliasToId.keys()]) },
  );
  if (result.kind === 'refused') return fail('refused', counts, { requestId: req.requestId });
  if (result.kind === 'error') {
    return fail(result.code, { ...counts, providerStatus: result.providerStatus }, { requestId: req.requestId, retryAfterSeconds: result.retryAfterSeconds });
  }

  // 5. Check the model output. Anything unexpected is an error, never a guess.
  let output;
  try { output = JSON.parse(result.text); } catch { output = null; }
  if (!output || typeof output.answer !== 'string' || output.answer.trim() === '' || [...output.answer].length > MAX_ANSWER) {
    return fail('providerUnavailable', { ...counts, providerStatus: 200 }, { requestId: req.requestId });
  }
  const sources = output.sources ?? [];
  if (!Array.isArray(sources) || new Set(sources).size !== sources.length || !sources.every((s) => typeof s === 'string' && aliasToId.has(s))) {
    return fail('invalidCitations', counts, { requestId: req.requestId });
  }

  /** @type {Record<string, unknown>} */
  const responseBody = {
    schemaVersion: 1,
    requestId: req.requestId,
    text: output.answer,
    citedMemoryIDs: sources.map((s) => aliasToId.get(s)),
  };
  if (Number.isInteger(result.inputTokens) && Number.isInteger(result.outputTokens)) {
    responseBody.usage = { inputTokens: result.inputTokens, outputTokens: result.outputTokens };
  }
  log({ status: 200, ...counts, inputTokens: result.inputTokens, outputTokens: result.outputTokens });
  return json(200, responseBody);
}
