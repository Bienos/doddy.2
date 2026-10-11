// OpenAI Responses API call (POST /v1/responses) with Structured Outputs.
// `store: false` asks OpenAI not to keep the response object. Sensitive text is never logged here.

const ENDPOINT = 'https://api.openai.com/v1/responses';
/** A retry is only worth starting if it has this long to finish. */
const MIN_RETRY_BUDGET_MS = 10_000;
/** Output allowance per call; the daily spend cap reserves this many output tokens up front. */
export const MAX_OUTPUT_TOKENS = 800;

/**
 * @typedef {{kind: 'ok', text: string, inputTokens?: number, outputTokens?: number}
 *   | {kind: 'refused', inputTokens?: number, outputTokens?: number}
 *   | {kind: 'error', code: 'rateLimited'|'providerUnavailable'|'timeout', providerStatus?: number, retryAfterSeconds?: number,
 *      cause?: string, inputTokens?: number, outputTokens?: number}} ProviderResult
 * `inputTokens`/`outputTokens` on an error are set only when the provider reported usage (a billed call).
 */

/** Reasoning models count their reasoning against max_output_tokens; keep it short so the answer fits. */
export const isReasoningModel = (/** @type {string} */ model) => /^(gpt-5|o\d)/.test(model);

/** At most this many provider calls per request (one retry); the budget reserves for all of them. */
export const MAX_ATTEMPTS = 2;

/**
 * @param {{fetch: typeof fetch, apiKey: string, model: string, timeoutMs: number, deadlineMs: number}} cfg
 * @param {{instructions: string, input: string, schema: object}} call
 * @returns {Promise<ProviderResult & {failedAttempts: number}>}
 *   failedAttempts: earlier 5xx attempts that were retried (each may have been billed).
 */
export async function callProvider(cfg, call) {
  const started = Date.now();
  const body = {
    model: cfg.model,
    instructions: call.instructions,
    input: call.input,
    store: false,
    max_output_tokens: MAX_OUTPUT_TOKENS,
    text: { format: { type: 'json_schema', name: 'doddy_answer', strict: true, schema: call.schema } },
    ...(isReasoningModel(cfg.model) ? { reasoning: { effort: 'low' } } : {}),
  };

  /** @type {ProviderResult} */
  let last = { kind: 'error', code: 'providerUnavailable' };
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 300 + Math.floor(Math.random() * 300)));
    // One deadline for the whole request, so a slow failure plus a retry cannot outlive the function's time limit.
    const remaining = cfg.deadlineMs - (Date.now() - started);
    const result = await once({ ...cfg, timeoutMs: Math.min(cfg.timeoutMs, remaining) }, body);
    // Retry once, and only on transient provider trouble. Never retry timeouts (would double the wait).
    const remainingAfter = cfg.deadlineMs - (Date.now() - started);
    if (result.kind === 'error' && result.code === 'providerUnavailable' && (result.providerStatus ?? 0) >= 500 && remainingAfter >= MIN_RETRY_BUDGET_MS) {
      last = result;
      continue;
    }
    return { ...result, failedAttempts: attempt };
  }
  return { ...last, failedAttempts: MAX_ATTEMPTS - 1 };
}

/**
 * @param {{fetch: typeof fetch, apiKey: string, model: string, timeoutMs: number}} cfg
 * @param {object} body
 * @returns {Promise<ProviderResult>}
 */
async function once(cfg, body) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs);
  try {
    const res = await cfg.fetch(ENDPOINT, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${cfg.apiKey}` },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (res.status === 429) {
      const retry = Number.parseInt(res.headers.get('retry-after') ?? '', 10);
      return { kind: 'error', code: 'rateLimited', providerStatus: 429, retryAfterSeconds: Number.isInteger(retry) && retry > 0 ? Math.min(retry, 300) : 30 };
    }
    if (res.status === 401 || res.status === 403) return { kind: 'error', code: 'providerUnavailable', providerStatus: res.status };
    if (!res.ok) return { kind: 'error', code: 'providerUnavailable', providerStatus: res.status };

    const data = await res.json();
    if (data?.status === 'incomplete' || data?.status === 'failed') {
      // Billed: keep the reported usage. Ran out of output allowance (often reasoning) gets its own cause.
      const cause = data?.incomplete_details?.reason === 'max_output_tokens' ? 'outputLimit' : undefined;
      return { kind: 'error', code: 'providerUnavailable', providerStatus: 200, cause,
        inputTokens: data?.usage?.input_tokens, outputTokens: data?.usage?.output_tokens };
    }
    const items = Array.isArray(data?.output) ? data.output : [];
    for (const item of items) {
      if (item?.type !== 'message' || !Array.isArray(item.content)) continue;
      for (const part of item.content) {
        if (part?.type === 'refusal') return { kind: 'refused', inputTokens: data?.usage?.input_tokens, outputTokens: data?.usage?.output_tokens };
        if (part?.type === 'output_text' && typeof part.text === 'string') {
          return { kind: 'ok', text: part.text, inputTokens: data?.usage?.input_tokens, outputTokens: data?.usage?.output_tokens };
        }
      }
    }
    return { kind: 'error', code: 'providerUnavailable', providerStatus: 200 };
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') return { kind: 'error', code: 'timeout' };
    return { kind: 'error', code: 'providerUnavailable' };
  } finally {
    clearTimeout(timer);
  }
}
