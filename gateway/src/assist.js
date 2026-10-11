import { costMicros, estimateMicros } from './budget.js';
import { loadConfig } from './config.js';
import { errorResponse, json, bearerToken, readJson } from './http.js';
import { logEvent } from './logging.js';
import { callProvider, MAX_ATTEMPTS, MAX_OUTPUT_TOKENS } from './openai.js';
import { buildInput, buildInstructions, buildSchema } from './prompt.js';
import { StoreUnavailableError } from './store.js';
import { deviceTag, shortTag, verifyToken } from './token.js';
import { LIMITS, validateAssistRequest } from './validate.js';

/**
 * @typedef {object} Deps
 * @property {Record<string, string | undefined>} env
 * @property {typeof fetch} fetch
 * @property {() => number} now           milliseconds
 * @property {import('./ratelimit.js').RateLimiter} limiter
 * @property {import('./budget.js').SpendCap} spend
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
    // cause=unexpected tells a gateway bug apart from a provider outage in the logs.
    logEvent({ evt: 'assist', code: 'providerUnavailable', cause: 'unexpected' }, deps.logSink);
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
  // Checked in order and stopped at the first refusal, so a device flooding past its per-minute limit
  // never consumes the invite or global counters (no denial of service on other testers).
  for (const [key, limit, window] of checks) {
    let decision;
    try {
      decision = await deps.limiter.hit(key, limit, window, nowMs);
    } catch (err) {
      // Shared store configured but unreachable: refuse (fail closed), never fall back to memory.
      if (err instanceof StoreUnavailableError) return fail('providerUnavailable', { deviceTag: tag, cause: 'limitStore' });
      throw err;
    }
    if (!decision.allowed) return fail('rateLimited', { deviceTag: tag }, { retryAfterSeconds: decision.retryAfterSeconds });
  }

  // 3. Parse and validate (size-capped, strict).
  const body = await readJson(request, LIMITS.bodyBytes);
  if (!body.ok) return fail(body.code, { deviceTag: tag });
  const parsed = validateAssistRequest(body.value);
  if (!parsed.ok) return fail('invalidRequest', { deviceTag: tag });
  const req = parsed.value;
  const counts = { deviceTag: tag, requestId: shortTag('request', req.requestId), memoryCount: req.memories.length, turnCount: req.turns.length };

  // 4. Reserve the worst-case cost against today's budgets (ADR-125) before spending anything.
  const { input, aliasToId } = buildInput(req);
  const instructions = buildInstructions(req.locale);
  const schema = buildSchema([...aliasToId.keys()]);
  const promptBytes = Buffer.byteLength(instructions) + Buffer.byteLength(input) + Buffer.byteLength(JSON.stringify(schema));
  const estimate = estimateMicros(promptBytes, MAX_OUTPUT_TOKENS, config.prices);
  // Worst case is every attempt billed at the estimate (a 5xx may be billed and is retried once).
  const worstCase = estimate * MAX_ATTEMPTS;
  let reserved;
  try {
    reserved = await deps.spend.reserve([
      { scope: 'all', capMicros: config.dailyBudgetMicros },
      { scope: `dev:${claims.deviceId}`, capMicros: config.installBudgetMicros },
      { scope: `inv:${claims.inviteTag}`, capMicros: config.inviteBudgetMicros },
    ], worstCase, nowMs);
  } catch (err) {
    if (err instanceof StoreUnavailableError) return fail('providerUnavailable', { ...counts, cause: 'limitStore' }, { requestId: req.requestId });
    throw err;
  }
  if (!reserved.ok) return fail('dailyLimitReached', counts, { requestId: req.requestId, retryAfterSeconds: reserved.retryAfterSeconds });

  // 5. Call the provider, then replace the estimate with the real cost.
  const result = await callProvider(
    { fetch: deps.fetch, apiKey: config.openaiKey, model: config.model, timeoutMs: config.providerTimeoutMs, deadlineMs: config.providerDeadlineMs },
    { instructions, input, schema },
  );
  // Each retried 5xx keeps its estimate booked, the same rule actualCost applies to a final 5xx.
  const spent = actualCost(result, estimate, config.prices) + result.failedAttempts * estimate;
  try {
    await deps.spend.settle(reserved.reservation, spent);
  } catch (err) {
    // The answer is already paid for; keep it. The estimate stays booked, which over-counts (safe side)
    // unless real usage exceeded the worst-case estimate.
    if (!(err instanceof StoreUnavailableError)) throw err;
    log({ ...counts, cause: 'settleFailed' });
  }
  Object.assign(counts, { costMicros: spent });
  if (result.kind === 'refused') return fail('refused', counts, { requestId: req.requestId });
  if (result.kind === 'error') {
    return fail(result.code, { ...counts, providerStatus: result.providerStatus, cause: result.cause }, { requestId: req.requestId, retryAfterSeconds: result.retryAfterSeconds });
  }

  // 6. Check the model output. Anything unexpected is an error, never a guess.
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

/**
 * What this call cost, in micro-dollars. Provider-reported usage when there is any; nothing when the
 * provider rejected the request outright (4xx, not billed); otherwise (timeout, 5xx, network error,
 * no usage reported) the worst-case estimate stays booked, because the call may have been billed.
 * @param {import('./openai.js').ProviderResult} result @param {number} estimate @param {import('./budget.js').Prices} prices
 */
function actualCost(result, estimate, prices) {
  // Reported usage wins whenever there is any (an incomplete answer is billed too).
  if (Number.isInteger(result.inputTokens) && Number.isInteger(result.outputTokens)) {
    return costMicros({ inputTokens: /** @type {number} */ (result.inputTokens), outputTokens: /** @type {number} */ (result.outputTokens) }, prices);
  }
  if (result.kind === 'error' && (result.providerStatus ?? 0) >= 400 && (result.providerStatus ?? 0) < 500) return 0;
  return estimate;
}
