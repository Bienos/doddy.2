// Doddy voice token server. It exchanges a valid DODDY voice session for a short-lived
// ElevenLabs conversation token or OpenAI Realtime client secret. Provider keys never ship in app.
//
// A body of {"provider":"openai","model":"…"} (ADR-265, default voice since ADR-442) asks for a
// one-conversation OpenAI Realtime client secret instead; the model must be on the allowlist. The secret carries only the model and voice; Doddy's prompt,
// notes and tools go from the phone straight to OpenAI, never through this server.
//
// Web-standard (Request -> Response), so the same handler runs on Vercel, Supabase Edge,
// Cloudflare Workers or Node. Logs are content-free: outcome, provider, upstream status, ms.

const ELEVENLABS_TOKEN_URL = "https://api.elevenlabs.io/v1/convai/conversation/token";
const OPENAI_CLIENT_SECRET_URL = "https://api.openai.com/v1/realtime/client_secrets";
const UPSTREAM_TIMEOUT_MS = 10_000;
import { beginVoiceSessionCheck, sessionStoreFromEnv, VoiceAuthStoreUnavailable } from "./voice-auth.js";

const DEFAULT_TOKENS_PER_HOUR = 30;
const DEFAULT_GLOBAL_TOKENS_PER_HOUR = 100;
const DEFAULT_VOICE_DAILY_PER_USER = 100;
const DEFAULT_VOICE_DAILY_FULL_MODEL_PER_USER = 10;

// How long the phone has to open the OpenAI connection with the secret (the session itself
// may then run longer). Short, because the secret is a bearer credential.
const OPENAI_SECRET_SECONDS = 120;
export const OPENAI_DEFAULT_MODEL = "gpt-realtime-2.1-mini";
/** The models the app may ask for. Anything else is refused, so a client can't pick a pricier one. */
export const OPENAI_ALLOWED_MODELS = Object.freeze(["gpt-realtime-2.1", "gpt-realtime-2.1-mini"]);
/** The full model has its own, tighter daily limit per user. */
export const OPENAI_FULL_MODEL = "gpt-realtime-2.1";
export const OPENAI_DEFAULT_VOICE = "marin";

/**
 * @typedef {object} Env
 * @property {string} [ELEVENLABS_API_KEY]  server-only secret
 * @property {string} [ELEVENLABS_AGENT_ID] the authenticated Doddy agent
 * @property {string} [DODDY_TOKENS_PER_HOUR] per DODDY account; default 30
 * @property {string} [DODDY_GLOBAL_TOKENS_PER_HOUR] global shared limit; default 100
 * @property {string} [VOICE_DAILY_PER_USER] voice tokens per account per UTC day, any provider; default 100
 * @property {string} [VOICE_DAILY_FULL_MODEL_PER_USER] full-model OpenAI secrets per account per UTC day; default 10
 * @property {string} [OPENAI_API_KEY]        server-only secret; only needed for the OpenAI test voice
 * @property {string} [OPENAI_REALTIME_MODEL] used when the app names no model; default "gpt-realtime-2.1-mini"
 * @property {string} [OPENAI_REALTIME_VOICE] default "marin"
 */

/**
 * @param {Request} request
 * @param {Env} env
 * @param {{ fetch?: typeof fetch, log?: (entry: object) => void, now?: () => number,
 *   authStore?: object, authenticateSession?: (request: Request) => Promise<{userId:string,sessionId:string}|null> }} [deps]
 * @returns {Promise<Response>}
 */
export async function handleTokenRequest(request, env, deps = {}) {
  const fetchImpl = deps.fetch ?? fetch;
  const log = deps.log ?? ((entry) => console.log(JSON.stringify(entry)));
  const now = deps.now ?? Date.now;
  const started = now();
  // `fields` go to the log; `body` (which may hold the token) never does.
  const finish = (status, error, fields = {}, body = { error }, headers = {}) => {
    log({ event: "voice_token", status, error: error ?? null, ms: now() - started, ...fields });
    return json(status, body, headers);
  };

  if (request.method !== "POST") {
    return finish(405, "method_not_allowed", {}, undefined, { allow: "POST" });
  }

  const requested = await requestedProvider(request);
  if (requested === null) {
    return finish(400, "unknown_provider");
  }
  const { provider } = requested;
  if (provider === "openai" && requested.model !== undefined && !OPENAI_ALLOWED_MODELS.includes(requested.model)) {
    return finish(400, "unknown_model", { provider });
  }
  const model = provider === "openai" ? requested.model ?? (env.OPENAI_REALTIME_MODEL || OPENAI_DEFAULT_MODEL) : undefined;

  let store;
  let check;
  try {
    store = deps.authStore ?? sessionStoreFromEnv(env, { fetch: deps.storeFetch });
    check = deps.authenticateSession
      ? { session: Promise.resolve(deps.authenticateSession(request)) }
      : beginVoiceSessionCheck(request, env, { store, now: now() });
  } catch (error) {
    if (error instanceof VoiceAuthStoreUnavailable) return finish(503, "server_not_configured", { provider });
    return finish(503, "server_not_configured", { provider });
  }
  if (!check) return finish(401, "session_expired", { provider });

  const perHour = tokensPerHour(env.DODDY_TOKENS_PER_HOUR, DEFAULT_TOKENS_PER_HOUR);
  const globalPerHour = tokensPerHour(env.DODDY_GLOBAL_TOKENS_PER_HOUR, DEFAULT_GLOBAL_TOKENS_PER_HOUR);
  const dailyLimit = tokensPerHour(env.VOICE_DAILY_PER_USER, DEFAULT_VOICE_DAILY_PER_USER);
  const fullModelDailyLimit = tokensPerHour(env.VOICE_DAILY_FULL_MODEL_PER_USER, DEFAULT_VOICE_DAILY_FULL_MODEL_PER_USER);
  const providerConfigured = provider === "openai"
    ? Boolean(env.OPENAI_API_KEY)
    : Boolean(env.ELEVENLABS_API_KEY && env.ELEVENLABS_AGENT_ID);
  const configured = providerConfigured && perHour !== null && globalPerHour !== null && dailyLimit !== null
      && fullModelDailyLimit !== null && Boolean(store.hitLimits);

  // The session lookup and the limit count go to the store at the same time: the token's
  // signature already names the account. So a revoked but correctly signed token (only someone
  // who once signed in has one, and only for its 10 minutes) may use up one count per request
  // (its account's hourly and daily ones, and the global hourly one) before its 401.
  const count = async (userId) => store.hitLimits(userId, perHour, globalPerHour, now(),
    { dailyLimit, fullModelDailyLimit, fullModel: model === OPENAI_FULL_MODEL });
  const counting = !configured ? undefined
    : check.userId !== undefined ? count(check.userId)
      // An injected session (tests) names no account up front, so it is counted after.
      : check.session.then((session) => (session ? count(session.userId) : undefined));
  const [looked, counted] = await Promise.allSettled([check.session, counting]);
  // Same outcomes, in the same order, as checking one after the other.
  if (looked.status === "rejected") return finish(503, "server_not_configured", { provider });
  if (!looked.value) return finish(401, "session_expired", { provider });
  if (!configured) return finish(500, "server_not_configured", { provider });
  if (counted.status === "rejected") return finish(503, "server_not_configured", { provider });
  const decision = counted.value;
  if (!decision.allowed) {
    const retryAfter = { "retry-after": String(decision.retryAfterSeconds) };
    if (decision.limit === "voice" || decision.limit === "full_model") {
      // Today's (UTC) allowance is used up: for all voice, or only for the full model, so the
      // app can offer the mini model or say "tomorrow". The model is never switched here.
      return finish(429, "daily_limit", { provider, limit: decision.limit }, { error: "daily_limit", limit: decision.limit }, retryAfter);
    }
    return finish(429, "rate_limited", { provider }, undefined, retryAfter);
  }

  return provider === "openai"
    ? openAISecret(env, fetchImpl, finish, model)
    : elevenLabsToken(env, fetchImpl, finish);
}

async function elevenLabsToken(env, fetchImpl, finish) {
  const url = new URL(ELEVENLABS_TOKEN_URL);
  url.searchParams.set("agent_id", env.ELEVENLABS_AGENT_ID);

  const upstream = await callUpstream(fetchImpl, url, {
    method: "GET",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
  });
  if (upstream.failed) return finish(upstream.status, upstream.error, { provider: "elevenlabs" });

  const response = upstream.response;
  if (!response.ok) {
    // 429 = ElevenLabs concurrency/daily limit reached: tell the app to try later.
    const status = response.status === 429 ? 503 : 502;
    return finish(status, response.status === 429 ? "voice_busy" : "upstream_failed", {
      provider: "elevenlabs",
      upstreamStatus: response.status,
    });
  }

  const token = await response.json().then((body) => body?.token, () => undefined);
  if (typeof token !== "string" || token.length === 0) {
    return finish(502, "upstream_bad_response", { provider: "elevenlabs", upstreamStatus: response.status });
  }
  return finish(200, null, { provider: "elevenlabs" }, { token });
}

/** A non-empty invalid setting fails closed; defaults are conservative shared limits. */
function tokensPerHour(raw, fallback) {
  if (raw === undefined || raw.trim() === "") return fallback;
  return /^[1-9][0-9]*$/.test(raw.trim()) && Number(raw.trim()) <= 10_000 ? Number(raw.trim()) : null;
}

/** A short-lived OpenAI Realtime client secret with model and voice set (ADR-265, ADR-442). */
async function openAISecret(env, fetchImpl, finish, model) {
  const voice = env.OPENAI_REALTIME_VOICE || OPENAI_DEFAULT_VOICE;
  const fields = { provider: "openai", model };

  const upstream = await callUpstream(fetchImpl, OPENAI_CLIENT_SECRET_URL, {
    method: "POST",
    headers: { authorization: `Bearer ${env.OPENAI_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      expires_after: { anchor: "created_at", seconds: OPENAI_SECRET_SECONDS },
      session: { type: "realtime", model, audio: { output: { voice } } },
    }),
  });
  if (upstream.failed) return finish(upstream.status, upstream.error, fields);

  const response = upstream.response;
  if (!response.ok) {
    // 429 = rate limit or no quota left on the OpenAI project.
    const status = response.status === 429 ? 503 : 502;
    return finish(status, response.status === 429 ? "voice_busy" : "upstream_failed", {
      ...fields,
      upstreamStatus: response.status,
    });
  }

  const body = await response.json().catch(() => undefined);
  const token = body?.value;
  if (typeof token !== "string" || token.length === 0) {
    return finish(502, "upstream_bad_response", { ...fields, upstreamStatus: response.status });
  }
  const usedModel = typeof body?.session?.model === "string" ? body.session.model : model;
  return finish(200, null, fields, { token, provider: "openai", model: usedModel });
}

async function callUpstream(fetchImpl, url, init) {
  try {
    const response = await fetchImpl(url, { ...init, signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) });
    return { failed: false, response };
  } catch (error) {
    const timedOut = error?.name === "TimeoutError" || error?.name === "AbortError";
    return { failed: true, status: timedOut ? 504 : 502, error: timedOut ? "upstream_timeout" : "upstream_unreachable" };
  }
}

/**
 * `{provider: "elevenlabs"}` (no body, as every app build before ADR-265 sends), `{provider:
 * "openai", model?}`, or null when the body names something else or isn't JSON (a build from
 * before ADR-549 that asks for `{provider: "picovoice"}` gets a 400). A `model` that isn't a string is returned as-is so the caller refuses it.
 * @param {Request} request
 */
async function requestedProvider(request) {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > 4_096) return null;
  const reader = request.body?.getReader();
  if (!reader) return { provider: "elevenlabs" };
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 4_096) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  } catch { return null; }
  const text = new TextDecoder().decode(concat(chunks, size));
  if (text.trim() === "") return { provider: "elevenlabs" };
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return null;
  }
  const provider = body?.provider ?? "elevenlabs";
  if (provider !== "elevenlabs" && provider !== "openai") return null;
  return { provider, model: body?.model === undefined || body?.model === null ? undefined : body.model };
}

function concat(chunks, size) {
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.byteLength; }
  return result;
}

function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
  });
}
