// Doddy voice token server. It exchanges a valid DODDY voice session for a short-lived
// ElevenLabs conversation token or OpenAI Realtime client secret. Provider keys never ship in app.
//
// A body of {"provider":"openai","model":"…"} (ADR-265, default voice since ADR-442) asks for a
// one-conversation OpenAI Realtime client secret instead; the model must be on the allowlist. The secret carries only the model and voice; Doddy's prompt,
// notes and tools go from the phone straight to OpenAI, never through this server.
//
// "Hey Doddy" for everyone (ADR-328): a body of {"provider":"picovoice"} returns the owner's
// Picovoice AccessKey (PICOVOICE_ACCESS_KEY), so an authenticated user can switch the wake word on with one
// tap instead of making their own Picovoice account. Porcupine needs the key on the phone; it is
// kept in the iPhone's Keychain. It starts no paid conversation, so it isn't counted per hour.
//
// Web-standard (Request -> Response), so the same handler runs on Vercel, Supabase Edge,
// Cloudflare Workers or Node. Logs are content-free: outcome, provider, upstream status, ms.

const ELEVENLABS_TOKEN_URL = "https://api.elevenlabs.io/v1/convai/conversation/token";
const OPENAI_CLIENT_SECRET_URL = "https://api.openai.com/v1/realtime/client_secrets";
const UPSTREAM_TIMEOUT_MS = 10_000;
import { authenticateVoiceSession, sessionStoreFromEnv, VoiceAuthStoreUnavailable } from "./voice-auth.js";

const DEFAULT_TOKENS_PER_HOUR = 30;
const DEFAULT_GLOBAL_TOKENS_PER_HOUR = 100;

// How long the phone has to open the OpenAI connection with the secret (the session itself
// may then run longer). Short, because the secret is a bearer credential.
const OPENAI_SECRET_SECONDS = 120;
export const OPENAI_DEFAULT_MODEL = "gpt-realtime-2.1-mini";
/** The models the app may ask for. Anything else is refused, so a client can't pick a pricier one. */
export const OPENAI_ALLOWED_MODELS = Object.freeze(["gpt-realtime-2.1", "gpt-realtime-2.1-mini"]);
export const OPENAI_DEFAULT_VOICE = "cedar";

/**
 * @typedef {object} Env
 * @property {string} [ELEVENLABS_API_KEY]  server-only secret
 * @property {string} [ELEVENLABS_AGENT_ID] the authenticated Doddy agent
 * @property {string} [DODDY_TOKENS_PER_HOUR] per DODDY account; default 30
 * @property {string} [DODDY_GLOBAL_TOKENS_PER_HOUR] global shared limit; default 100
 * @property {string} [OPENAI_API_KEY]        server-only secret; only needed for the OpenAI test voice
 * @property {string} [OPENAI_REALTIME_MODEL] used when the app names no model; default "gpt-realtime-2.1-mini"
 * @property {string} [OPENAI_REALTIME_VOICE] default "cedar"
 * @property {string} [PICOVOICE_ACCESS_KEY]  the owner's Picovoice AccessKey for "Hey Doddy" (ADR-328)
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

  let store;
  let session;
  try {
    store = deps.authStore ?? sessionStoreFromEnv(env, { fetch: deps.storeFetch });
    session = deps.authenticateSession
      ? await deps.authenticateSession(request)
      : await authenticateVoiceSession(request, env, { store, now: now() });
  } catch (error) {
    if (error instanceof VoiceAuthStoreUnavailable) return finish(503, "server_not_configured", { provider });
    return finish(503, "server_not_configured", { provider });
  }
  if (!session) return finish(401, "session_expired", { provider });

  const perHour = tokensPerHour(env.DODDY_TOKENS_PER_HOUR, DEFAULT_TOKENS_PER_HOUR);
  const globalPerHour = tokensPerHour(env.DODDY_GLOBAL_TOKENS_PER_HOUR, DEFAULT_GLOBAL_TOKENS_PER_HOUR);
  const providerConfigured = provider === "openai"
    ? Boolean(env.OPENAI_API_KEY)
    : provider === "picovoice"
      ? Boolean(env.PICOVOICE_ACCESS_KEY && env.PICOVOICE_ACCESS_KEY.trim())
      : Boolean(env.ELEVENLABS_API_KEY && env.ELEVENLABS_AGENT_ID);
  if (!providerConfigured || perHour === null || globalPerHour === null || !store.hitLimits) {
    return finish(500, "server_not_configured", { provider });
  }

  let decision;
  try {
    decision = await store.hitLimits(session.userId, perHour, globalPerHour, now());
  } catch {
    return finish(503, "server_not_configured", { provider });
  }
  if (!decision.allowed) {
    return finish(429, "rate_limited", { provider }, undefined, { "retry-after": String(decision.retryAfterSeconds) });
  }

  // The wake word key starts nothing paid; the app asks for it once and keeps it (ADR-328).
  if (provider === "picovoice") {
    return finish(200, null, { provider }, { accessKey: env.PICOVOICE_ACCESS_KEY.trim() });
  }

  return provider === "openai"
    ? openAISecret(env, fetchImpl, finish, requested.model)
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
async function openAISecret(env, fetchImpl, finish, requestedModel) {
  const model = requestedModel ?? (env.OPENAI_REALTIME_MODEL || OPENAI_DEFAULT_MODEL);
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
 * "openai", model?}`, `{provider: "picovoice"}` (ADR-328), or null when the body names something
 * else or isn't JSON. A `model` that isn't a string is returned as-is so the caller refuses it.
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
  if (provider !== "elevenlabs" && provider !== "openai" && provider !== "picovoice") return null;
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
