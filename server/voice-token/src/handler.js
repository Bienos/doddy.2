// Doddy voice token server. It exchanges a valid DODDY voice session for a short-lived
// ElevenLabs conversation token. The provider key never ships in the app.
//
// Deleting an account also deletes its voice conversations (decision 2026-11-12-voice-conversations-per-account),
// so each token the server hands out is tied to its account first: the conversation id ElevenLabs answers with is
// recorded under a keyed hash of the account, and the answer adds `userId`, another keyed hash, which the app gives
// ElevenLabs as the conversation's user. If the id can't be recorded the token is not handed out.
//
// ElevenLabs is the only voice (owner decision, 9 Nov 2026: OpenAI voice removed). A body that names
// any other provider, including the old {"provider":"openai"} an earlier app build sends, gets a 400.
//
// Web-standard (Request -> Response), so the same handler runs on Vercel, Supabase Edge,
// Cloudflare Workers or Node. Logs are content-free: outcome, provider, upstream status, ms.

const ELEVENLABS_TOKEN_URL = "https://api.elevenlabs.io/v1/convai/conversation/token";
const UPSTREAM_TIMEOUT_MS = 10_000;
// The translator-only agent "Doddy 6 · Tłumacz": no tools at all (owner, 12 Nov 2026, decision
// 2026-11-12-translator-agent). Its id is public, like the main agent's (the repo's docs name both), so
// it is the default here (`DEFAULT_TRANSLATOR_AGENT_ID`, shared with the deletion of its conversations) and nothing
// has to be set on Vercel; ELEVENLABS_TRANSLATOR_AGENT_ID overrides it.
import {
  authenticateVoiceSession, DEFAULT_TOKENS_PER_DAY, limitSetting, sessionStoreFromEnv, VoiceAuthStoreUnavailable,
} from "./voice-auth.js";
import { AccountCheckUnavailable, authenticateDoddyAccount } from "./doddy-account.js";
import {
  conversationIdentity, DEFAULT_TRANSLATOR_AGENT_ID, MAX_RECORDED_CONVERSATIONS, validConversationId,
} from "./conversations.js";

const DEFAULT_TOKENS_PER_HOUR = 30;
const DEFAULT_GLOBAL_TOKENS_PER_HOUR = 100;

/**
 * @typedef {object} Env
 * @property {string} [ELEVENLABS_API_KEY]  server-only secret
 * @property {string} [ELEVENLABS_AGENT_ID] the authenticated Doddy agent
 * @property {string} [ELEVENLABS_TRANSLATOR_AGENT_ID] the authenticated translator-only agent; defaults to DEFAULT_TRANSLATOR_AGENT_ID
 * @property {string} [DODDY_SESSION_SIGNING_KEY] also makes the keyed hashes that tie a conversation to its account
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
  if (requested.agent === null) {
    return finish(400, "unknown_agent");
  }
  const { provider, agent } = requested;

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
  // Which agent this conversation talks to: the main one (no body, as ever), or the translator-only one.
  const agentId = agent === "translator" ? (env.ELEVENLABS_TRANSLATOR_AGENT_ID || DEFAULT_TRANSLATOR_AGENT_ID) : env.ELEVENLABS_AGENT_ID;
  const providerConfigured = Boolean(env.ELEVENLABS_API_KEY && agentId);
  // Without the key that makes the account's hashes, or a store that can record, a conversation could not be
  // deleted later, so none is started.
  const identity = conversationIdentity(env, userId);
  if (!providerConfigured || perHour === null || perDay === null || globalPerHour === null || !store.hitLimits
      || !identity || typeof store.recordConversation !== "function") {
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

  return elevenLabsToken(env, agentId, agent, fetchImpl, finish, { store, identity, now });
}

async function elevenLabsToken(env, agentId, agent, fetchImpl, finish, { store, identity, now }) {
  const url = new URL(ELEVENLABS_TOKEN_URL);
  url.searchParams.set("agent_id", agentId);

  const upstream = await callUpstream(fetchImpl, url, {
    method: "GET",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
  });
  if (upstream.failed) return finish(upstream.status, upstream.error, { provider: "elevenlabs", agent });

  const response = upstream.response;
  if (!response.ok) {
    // 429 = ElevenLabs concurrency/daily limit reached: tell the app to try later.
    const status = response.status === 429 ? 503 : 502;
    return finish(status, response.status === 429 ? "voice_busy" : "upstream_failed", {
      provider: "elevenlabs",
      agent,
      upstreamStatus: response.status,
    });
  }

  const answer = await response.json().then((body) => body, () => undefined);
  const token = answer?.token;
  if (typeof token !== "string" || token.length === 0) {
    return finish(502, "upstream_bad_response", { provider: "elevenlabs", agent, upstreamStatus: response.status });
  }
  // ElevenLabs names the conversation when it issues the token (GET /v1/convai/conversation/token answers
  // `{ token, conversation_id }`). Keep it under the account so deleting the account can delete it. If it can't be
  // kept, nobody gets a token: a conversation the server can't delete later must not start. If ElevenLabs sent no
  // usable id, the token is still handed out; `userId` below lets the deletion find that conversation by listing.
  // Logged as a fixed word, never the id.
  const conversationId = validConversationId(answer?.conversation_id);
  if (conversationId) {
    try {
      await store.recordConversation(identity.recordKey, conversationId, now(), MAX_RECORDED_CONVERSATIONS);
    } catch {
      return finish(503, "server_not_configured", { provider: "elevenlabs", agent, conversation_id: "not_recorded" });
    }
  }
  return finish(200, null, { provider: "elevenlabs", agent, conversation_id: conversationId ? "recorded" : "missing" },
    { token, userId: identity.userId });
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
 * `{provider: "elevenlabs", agent: "main"}` (no body, or a body that names it), `agent: "translator"` for
 * `{"agent": "translator"}`, `agent: null` for any other agent name (a 400), or null when the body names
 * another provider or isn't JSON: a build from before 9 Nov 2026 that asks for `{provider: "openai"}`,
 * or from before ADR-549 for `{provider: "picovoice"}`, gets a 400. A build from before 12 Nov 2026 sends no
 * body and gets the main agent, which is also what a translator start gets from a server that predates this.
 * @param {Request} request
 */
async function requestedProvider(request) {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > 4_096) return null;
  const reader = request.body?.getReader();
  if (!reader) return { provider: "elevenlabs", agent: "main" };
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
  if (text.trim() === "") return { provider: "elevenlabs", agent: "main" };
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return null;
  }
  const provider = body?.provider ?? "elevenlabs";
  if (provider !== "elevenlabs") return null;
  const agent = body?.agent ?? "main";
  if (agent !== "main" && agent !== "translator") return { provider, agent: null };
  return { provider, agent };
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
