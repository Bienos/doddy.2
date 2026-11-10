// Doddy voice token server. It exchanges a valid DODDY voice session for a short-lived
// ElevenLabs conversation token. The provider key never ships in the app.
//
// ElevenLabs is the only voice (owner decision, 9 Nov 2026: OpenAI voice removed). A body that names
// any other provider, including the old {"provider":"openai"} an earlier app build sends, gets a 400.
//
// Web-standard (Request -> Response), so the same handler runs on Vercel, Supabase Edge,
// Cloudflare Workers or Node. Logs are content-free: outcome, provider, upstream status, ms.

const ELEVENLABS_TOKEN_URL = "https://api.elevenlabs.io/v1/convai/conversation/token";
const UPSTREAM_TIMEOUT_MS = 10_000;
import {
  authenticateVoiceSession, DEFAULT_TOKENS_PER_DAY, limitSetting, sessionStoreFromEnv, VoiceAuthStoreUnavailable,
} from "./voice-auth.js";
import { AccountCheckUnavailable, authenticateDoddyAccount } from "./doddy-account.js";

const DEFAULT_TOKENS_PER_HOUR = 30;
const DEFAULT_GLOBAL_TOKENS_PER_HOUR = 100;

/**
 * @typedef {object} Env
 * @property {string} [ELEVENLABS_API_KEY]  server-only secret
 * @property {string} [ELEVENLABS_AGENT_ID] the authenticated Doddy agent
 * @property {string} [DODDY_TOKENS_PER_HOUR] per DODDY account; default 30
 * @property {string} [DODDY_TOKENS_PER_DAY] per DODDY account per UTC day; default 150
 * @property {string} [DODDY_GLOBAL_TOKENS_PER_HOUR] global shared limit; default 100
 */

/**
 * @param {Request} request
 * @param {Env} env
 * @param {{ fetch?: typeof fetch, log?: (entry: object) => void, now?: () => number,
 *   authStore?: object, authenticateSession?: (request: Request) => Promise<{userId:string,sessionId:string|null}|null>,
 *   accountFetch?: typeof fetch }} [deps] `accountFetch`: where the Supabase project's signing keys are read (tests)
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

  let store;
  let session;
  try {
    store = deps.authStore ?? sessionStoreFromEnv(env, { fetch: deps.storeFetch });
    // A Doddy account (decision 2026-11-08-required-account) first, then this server's own Apple
    // sign-in (ADR-522) while phones move over.
    session = deps.authenticateSession
      ? await deps.authenticateSession(request)
      : (await authenticateDoddyAccount(request, env, { ...(deps.accountFetch ? { fetch: deps.accountFetch } : {}), now: now() }))
        ?? await authenticateVoiceSession(request, env, { store, now: now() });
  } catch (error) {
    // The account's keys couldn't be read: "try again", never "signed out" (which would send the app to sign in again).
    if (error instanceof AccountCheckUnavailable) return finish(503, "account_check_unavailable", { provider });
    if (error instanceof VoiceAuthStoreUnavailable) return finish(503, "server_not_configured", { provider });
    return finish(503, "server_not_configured", { provider });
  }
  // Every voice request needs a Doddy account session.
  if (!session) return finish(401, "session_expired", { provider });
  const userId = session.userId;

  const perHour = limitSetting(env.DODDY_TOKENS_PER_HOUR, DEFAULT_TOKENS_PER_HOUR);
  const perDay = limitSetting(env.DODDY_TOKENS_PER_DAY, DEFAULT_TOKENS_PER_DAY);
  const globalPerHour = limitSetting(env.DODDY_GLOBAL_TOKENS_PER_HOUR, DEFAULT_GLOBAL_TOKENS_PER_HOUR);
  const providerConfigured = Boolean(env.ELEVENLABS_API_KEY && env.ELEVENLABS_AGENT_ID);
  if (!providerConfigured || perHour === null || perDay === null || globalPerHour === null || !store.hitLimits) {
    return finish(500, "server_not_configured", { provider });
  }

  let decision;
  try {
    decision = await store.hitLimits(userId, perHour, globalPerHour, now(), perDay);
  } catch {
    return finish(503, "server_not_configured", { provider });
  }
  if (!decision.allowed) {
    // `limit` (which of the three said no) is a fixed word, never an id.
    return finish(429, "rate_limited", { provider, limit: decision.limit }, undefined, { "retry-after": String(decision.retryAfterSeconds) });
  }

  return elevenLabsToken(env, fetchImpl, finish);
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
 * `{provider: "elevenlabs"}` (no body, or a body that names it), or null when the body names
 * anything else or isn't JSON: a build from before 9 Nov 2026 that asks for `{provider: "openai"}`,
 * or from before ADR-549 for `{provider: "picovoice"}`, gets a 400.
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
  if (provider !== "elevenlabs") return null;
  return { provider };
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
