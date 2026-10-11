// Doddy voice token server. One job: exchange a tester's access code for a short-lived
// ElevenLabs conversation token, so the agent can require authentication and the
// ElevenLabs API key never ships in the app.
//
// Testing only (ADR-264): a body of {"provider":"openai"} asks for a one-conversation OpenAI
// Realtime client secret instead. The secret carries only the model and voice; Doddy's prompt,
// notes and tools go from the phone straight to OpenAI, never through this server.
//
// Web-standard (Request -> Response), so the same handler runs on Vercel, Supabase Edge,
// Cloudflare Workers or Node. Logs are content-free: outcome, tester label, upstream status, ms.

const ELEVENLABS_TOKEN_URL = "https://api.elevenlabs.io/v1/convai/conversation/token";
const OPENAI_CLIENT_SECRET_URL = "https://api.openai.com/v1/realtime/client_secrets";
const UPSTREAM_TIMEOUT_MS = 10_000;
// How long the phone has to open the OpenAI connection with the secret (the session itself
// may then run longer). Short, because the secret is a bearer credential.
const OPENAI_SECRET_SECONDS = 120;
export const OPENAI_DEFAULT_MODEL = "gpt-realtime";
export const OPENAI_DEFAULT_VOICE = "marin";

/**
 * @typedef {object} Env
 * @property {string} [ELEVENLABS_API_KEY]  server-only secret
 * @property {string} [ELEVENLABS_AGENT_ID] the authenticated Doddy agent
 * @property {string} [DODDY_ACCESS_CODES]  "label:code,label:code" (labels appear in logs, codes never)
 * @property {string} [OPENAI_API_KEY]        server-only secret; only needed for the OpenAI test voice
 * @property {string} [OPENAI_REALTIME_MODEL] default "gpt-realtime"
 * @property {string} [OPENAI_REALTIME_VOICE] default "marin"
 */

/**
 * @param {Request} request
 * @param {Env} env
 * @param {{ fetch?: typeof fetch, log?: (entry: object) => void, now?: () => number }} [deps]
 * @returns {Promise<Response>}
 */
export async function handleTokenRequest(request, env, deps = {}) {
  const fetchImpl = deps.fetch ?? fetch;
  const log = deps.log ?? ((entry) => console.log(JSON.stringify(entry)));
  const now = deps.now ?? Date.now;
  const started = now();
  // `fields` go to the log; `body` (which may hold the token) never does.
  const finish = (status, error, fields = {}, body = { error }) => {
    log({ event: "voice_token", status, error: error ?? null, ms: now() - started, ...fields });
    return json(status, body);
  };

  if (request.method !== "POST") {
    return finish(405, "method_not_allowed");
  }

  const provider = await requestedProvider(request);
  if (provider === null) {
    return finish(400, "unknown_provider");
  }

  const codes = parseAccessCodes(env.DODDY_ACCESS_CODES);
  const providerConfigured = provider === "openai"
    ? Boolean(env.OPENAI_API_KEY)
    : Boolean(env.ELEVENLABS_API_KEY && env.ELEVENLABS_AGENT_ID);
  if (!providerConfigured || codes.length === 0) {
    return finish(500, "server_not_configured", { provider });
  }

  const presented = bearer(request.headers.get("authorization"));
  const tester = presented ? await findTester(codes, presented) : null;
  if (!tester) {
    return finish(401, "invalid_access_code", { provider });
  }

  return provider === "openai"
    ? openAISecret(env, fetchImpl, finish, tester)
    : elevenLabsToken(env, fetchImpl, finish, tester);
}

async function elevenLabsToken(env, fetchImpl, finish, tester) {
  const url = new URL(ELEVENLABS_TOKEN_URL);
  url.searchParams.set("agent_id", env.ELEVENLABS_AGENT_ID);

  const upstream = await callUpstream(fetchImpl, url, {
    method: "GET",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
  });
  if (upstream.failed) return finish(upstream.status, upstream.error, { tester });

  const response = upstream.response;
  if (!response.ok) {
    // 429 = ElevenLabs concurrency/daily limit reached: tell the app to try later.
    const status = response.status === 429 ? 503 : 502;
    return finish(status, response.status === 429 ? "voice_busy" : "upstream_failed", {
      tester,
      upstreamStatus: response.status,
    });
  }

  const token = await response.json().then((body) => body?.token, () => undefined);
  if (typeof token !== "string" || token.length === 0) {
    return finish(502, "upstream_bad_response", { tester, upstreamStatus: response.status });
  }
  return finish(200, null, { tester }, { token });
}

/** Testing only (ADR-264): a short-lived OpenAI Realtime client secret with model and voice set. */
async function openAISecret(env, fetchImpl, finish, tester) {
  const model = env.OPENAI_REALTIME_MODEL || OPENAI_DEFAULT_MODEL;
  const voice = env.OPENAI_REALTIME_VOICE || OPENAI_DEFAULT_VOICE;
  const fields = { tester, provider: "openai" };

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
 * "elevenlabs" (no body, as every app build before ADR-264 sends), "openai", or null when the
 * body names something else or isn't JSON.
 * @param {Request} request
 */
async function requestedProvider(request) {
  const text = await request.text().catch(() => "");
  if (text.trim() === "") return "elevenlabs";
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return null;
  }
  const provider = body?.provider ?? "elevenlabs";
  return provider === "elevenlabs" || provider === "openai" ? provider : null;
}

/** @param {string | undefined} raw */
export function parseAccessCodes(raw) {
  return (raw ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separator = entry.indexOf(":");
      return separator > 0
        ? { label: entry.slice(0, separator).trim(), code: entry.slice(separator + 1).trim() }
        : { label: "unlabelled", code: entry };
    })
    // Short codes are guessable; ignore them rather than accept them.
    .filter(({ code }) => code.length >= 16);
}

function bearer(header) {
  const match = /^Bearer\s+(.+)$/i.exec(header ?? "");
  return match ? match[1].trim() : null;
}

/** Compares SHA-256 digests in constant time so response timing doesn't reveal codes. */
async function findTester(codes, presented) {
  const presentedDigest = await sha256(presented);
  let found = null;
  for (const { label, code } of codes) {
    if (equalBytes(presentedDigest, await sha256(code)) && found === null) found = label;
  }
  return found;
}

async function sha256(text) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
}

function equalBytes(a, b) {
  let difference = a.length ^ b.length;
  for (let i = 0; i < Math.min(a.length, b.length); i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}
