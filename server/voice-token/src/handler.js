// Doddy voice token server. One job: exchange a tester's access code for a short-lived
// ElevenLabs conversation token, so the agent can require authentication and the
// ElevenLabs API key never ships in the app.
//
// A body of {"provider":"openai","model":"…"} (ADR-265, default voice since ADR-442) asks for a
// one-conversation OpenAI Realtime client secret instead; the model must be on the allowlist. The secret carries only the model and voice; Doddy's prompt,
// notes and tools go from the phone straight to OpenAI, never through this server.
//
// "Hey Doddy" for everyone (ADR-328): a body of {"provider":"picovoice"} returns the owner's
// Picovoice AccessKey (PICOVOICE_ACCESS_KEY), so a tester can switch the wake word on with one
// tap instead of making their own Picovoice account. Porcupine needs the key on the phone; it is
// kept in the iPhone's Keychain. It starts no paid conversation, so it isn't counted per hour.
//
// Web-standard (Request -> Response), so the same handler runs on Vercel, Supabase Edge,
// Cloudflare Workers or Node. Logs are content-free: outcome, tester label, upstream status, ms.

const ELEVENLABS_TOKEN_URL = "https://api.elevenlabs.io/v1/convai/conversation/token";
const OPENAI_CLIENT_SECRET_URL = "https://api.openai.com/v1/realtime/client_secrets";
const UPSTREAM_TIMEOUT_MS = 10_000;
const DEFAULT_TOKENS_PER_HOUR = 30;
const HOUR_MS = 3_600_000;

/**
 * Tokens per tester per clock hour, so one tester (or a leaked code) can't use up the agent's
 * shared ElevenLabs limits for everyone. Per server instance: a best-effort brake, not a hard cap;
 * the agent's own concurrency and daily limits stay the spending cap.
 */
export function createTesterLimiter() {
  /** @type {Map<string, {window: number, count: number}>} */
  const windows = new Map();
  return {
    /** @param {string} tester @param {number} limit @param {number} nowMs */
    hit(tester, limit, nowMs) {
      const window = Math.floor(nowMs / HOUR_MS);
      const w = windows.get(tester);
      const current = w && w.window === window ? w : { window, count: 0 };
      if (current.count >= limit) return { allowed: false, retryAfterSeconds: Math.max(1, Math.ceil(((window + 1) * HOUR_MS - nowMs) / 1000)) };
      current.count += 1;
      windows.set(tester, current);
      return { allowed: true };
    },
  };
}

const sharedLimiter = createTesterLimiter();
/** Config strings whose ignored short codes were already logged by this instance. */
const reportedConfigs = new Set();

// How long the phone has to open the OpenAI connection with the secret (the session itself
// may then run longer). Short, because the secret is a bearer credential.
const OPENAI_SECRET_SECONDS = 120;
export const OPENAI_DEFAULT_MODEL = "gpt-realtime-2.1-mini";
/** The models the app may ask for. Anything else is refused, so a client can't pick a pricier one. */
export const OPENAI_ALLOWED_MODELS = Object.freeze(["gpt-realtime-2.1", "gpt-realtime-2.1-mini"]);
export const OPENAI_DEFAULT_VOICE = "marin";
/** The voices the app may ask for (ADR-483): OpenAI presets only. Anything else is refused. */
export const OPENAI_ALLOWED_VOICES = Object.freeze(["marin", "cedar", "alloy", "echo", "sage", "shimmer", "verse"]);

/**
 * @typedef {object} Env
 * @property {string} [ELEVENLABS_API_KEY]  server-only secret
 * @property {string} [ELEVENLABS_AGENT_ID] the authenticated Doddy agent
 * @property {string} [DODDY_ACCESS_CODES]  "label:code,label:code" (labels appear in logs, codes never)
 * @property {string} [DODDY_TOKENS_PER_HOUR] per tester; default 30
 * @property {string} [OPENAI_API_KEY]        server-only secret; only needed for the OpenAI test voice
 * @property {string} [OPENAI_REALTIME_MODEL] used when the app names no model; default "gpt-realtime-2.1-mini"
 * @property {string} [OPENAI_REALTIME_VOICE] default "marin"
 * @property {string} [PICOVOICE_ACCESS_KEY]  the owner's Picovoice AccessKey for "Hey Doddy" (ADR-328)
 */

/**
 * @param {Request} request
 * @param {Env} env
 * @param {{ fetch?: typeof fetch, log?: (entry: object) => void, now?: () => number,
 *   limiter?: ReturnType<typeof createTesterLimiter> }} [deps]
 * @returns {Promise<Response>}
 */
export async function handleTokenRequest(request, env, deps = {}) {
  const fetchImpl = deps.fetch ?? fetch;
  const log = deps.log ?? ((entry) => console.log(JSON.stringify(entry)));
  const now = deps.now ?? Date.now;
  const limiter = deps.limiter ?? sharedLimiter;
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
  if (provider === "openai" && requested.voice !== undefined && !OPENAI_ALLOWED_VOICES.includes(requested.voice)) {
    return finish(400, "unknown_voice", { provider });
  }

  const codes = parseAccessCodes(env.DODDY_ACCESS_CODES);
  // A code under 16 characters is ignored; say so once (labels only), or that tester just sees 401.
  const ignored = ignoredShortCodes(env.DODDY_ACCESS_CODES);
  if (ignored.length > 0 && !reportedConfigs.has(env.DODDY_ACCESS_CODES)) {
    reportedConfigs.add(env.DODDY_ACCESS_CODES);
    log({ event: "voice_token_config", ignoredShortCodes: ignored });
  }
  const perHour = tokensPerHour(env.DODDY_TOKENS_PER_HOUR);
  const providerConfigured = provider === "openai"
    ? Boolean(env.OPENAI_API_KEY)
    : provider === "picovoice"
      ? Boolean(env.PICOVOICE_ACCESS_KEY && env.PICOVOICE_ACCESS_KEY.trim())
      : Boolean(env.ELEVENLABS_API_KEY && env.ELEVENLABS_AGENT_ID);
  if (!providerConfigured || codes.length === 0 || perHour === null) {
    return finish(500, "server_not_configured", { provider });
  }

  const presented = bearer(request.headers.get("authorization"));
  const tester = presented ? await findTester(codes, presented) : null;
  if (!tester) {
    return finish(401, "invalid_access_code", { provider });
  }

  // The wake word key starts nothing paid; the app asks for it once and keeps it (ADR-328).
  if (provider === "picovoice") {
    return finish(200, null, { tester, provider }, { accessKey: env.PICOVOICE_ACCESS_KEY.trim() });
  }

  // The per-tester brake counts both voices: each token or secret starts a paid conversation.
  const decision = limiter.hit(tester, perHour, now());
  if (!decision.allowed) {
    return finish(429, "rate_limited", { tester, provider }, undefined, { "retry-after": String(decision.retryAfterSeconds) });
  }

  return provider === "openai"
    ? openAISecret(env, fetchImpl, finish, tester, requested.model, requested.voice)
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

/** @param {string | undefined} raw  set but not a positive whole number -> null (fail closed) */
function tokensPerHour(raw) {
  if (raw === undefined || raw.trim() === "") return DEFAULT_TOKENS_PER_HOUR;
  return /^[1-9][0-9]*$/.test(raw.trim()) ? Number(raw.trim()) : null;
}

/** A short-lived OpenAI Realtime client secret with model and voice set (ADR-265, ADR-442). */
async function openAISecret(env, fetchImpl, finish, tester, requestedModel, requestedVoice) {
  const model = requestedModel ?? (env.OPENAI_REALTIME_MODEL || OPENAI_DEFAULT_MODEL);
  const voice = requestedVoice ?? (env.OPENAI_REALTIME_VOICE || OPENAI_DEFAULT_VOICE);
  const fields = { tester, provider: "openai", model };

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
 * "openai", model?, voice?}`, `{provider: "picovoice"}` (ADR-328), or null when the body names something
 * else or isn't JSON. A `model` that isn't a string is returned as-is so the caller refuses it.
 * @param {Request} request
 */
async function requestedProvider(request) {
  const text = await request.text().catch(() => "");
  if (text.trim() === "") return { provider: "elevenlabs" };
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return null;
  }
  const provider = body?.provider ?? "elevenlabs";
  if (provider !== "elevenlabs" && provider !== "openai" && provider !== "picovoice") return null;
  return {
    provider,
    model: body?.model === undefined || body?.model === null ? undefined : body.model,
    voice: body?.voice === undefined || body?.voice === null ? undefined : body.voice,
  };
}

/** @param {string | undefined} raw */
export function parseAccessCodes(raw) {
  return splitAccessCodes(raw)
    // Short codes are guessable; ignore them rather than accept them.
    .filter(({ code }) => code.length >= 16);
}

/** Labels of configured codes that are too short to be used (never the codes). */
export function ignoredShortCodes(raw) {
  return splitAccessCodes(raw).filter(({ code }) => code.length < 16).map(({ label }) => label);
}

/** @param {string | undefined} raw */
function splitAccessCodes(raw) {
  return (raw ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separator = entry.indexOf(":");
      return separator > 0
        ? { label: entry.slice(0, separator).trim(), code: entry.slice(separator + 1).trim() }
        : { label: "unlabelled", code: entry };
    });
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

function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
  });
}
