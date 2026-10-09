// Doddy voice token server. One job: exchange a tester's access code for a short-lived
// ElevenLabs conversation token, so the agent can require authentication and the
// ElevenLabs API key never ships in the app.
//
// Web-standard (Request -> Response), so the same handler runs on Vercel, Supabase Edge,
// Cloudflare Workers or Node. Logs are content-free: outcome, tester label, upstream status, ms.

const ELEVENLABS_TOKEN_URL = "https://api.elevenlabs.io/v1/convai/conversation/token";
const UPSTREAM_TIMEOUT_MS = 10_000;

/**
 * @typedef {object} Env
 * @property {string} [ELEVENLABS_API_KEY]  server-only secret
 * @property {string} [ELEVENLABS_AGENT_ID] the authenticated Doddy agent
 * @property {string} [DODDY_ACCESS_CODES]  "label:code,label:code" (labels appear in logs, codes never)
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

  const codes = parseAccessCodes(env.DODDY_ACCESS_CODES);
  if (!env.ELEVENLABS_API_KEY || !env.ELEVENLABS_AGENT_ID || codes.length === 0) {
    return finish(500, "server_not_configured");
  }

  const presented = bearer(request.headers.get("authorization"));
  const tester = presented ? await findTester(codes, presented) : null;
  if (!tester) {
    return finish(401, "invalid_access_code");
  }

  const url = new URL(ELEVENLABS_TOKEN_URL);
  url.searchParams.set("agent_id", env.ELEVENLABS_AGENT_ID);

  let upstream;
  try {
    upstream = await fetchImpl(url, {
      method: "GET",
      headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (error) {
    const timedOut = error?.name === "TimeoutError" || error?.name === "AbortError";
    return finish(timedOut ? 504 : 502, timedOut ? "upstream_timeout" : "upstream_unreachable", { tester });
  }

  if (!upstream.ok) {
    // 429 = ElevenLabs concurrency/daily limit reached: tell the app to try later.
    const status = upstream.status === 429 ? 503 : 502;
    return finish(status, upstream.status === 429 ? "voice_busy" : "upstream_failed", {
      tester,
      upstreamStatus: upstream.status,
    });
  }

  const token = await upstream.json().then((body) => body?.token, () => undefined);
  if (typeof token !== "string" || token.length === 0) {
    return finish(502, "upstream_bad_response", { tester, upstreamStatus: upstream.status });
  }
  return finish(200, null, { tester }, { token });
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
