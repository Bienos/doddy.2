// Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account, a Supabase
// Auth user made with Apple, Google or a code sent by email (ADR-526). The iPhone sends that
// account's access token here, and this server checks it itself against the project's published keys:
// no shared secret, and nothing to store. The server's own Apple sign-in (ADR-522) keeps working next to it
// while phones move over.
//
// The rules are the backend's (`backend/src/auth.ts`, SupabaseSessionVerifier):
// - ES256 or RS256 only, signed by a key the project publishes;
// - issuer `<project>/auth/v1`, audience `authenticated`, role `authenticated`, not anonymous;
// - not expired, and not issued in the future;
// - made with Apple, Google or email, and never with a password.
import { createPublicKey, verify as verifySignature } from "node:crypto";

const KEYS_TTL_MS = 10 * 60_000;
const REFETCH_MIN_MS = 30_000;
const TIMEOUT_MS = 5_000;
const PROVIDERS = new Set(["apple", "google", "email"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SEGMENT = /^[A-Za-z0-9_-]+$/;

/** The project's signing keys could not be read and none is cached: "try again", never "signed out". */
export class AccountCheckUnavailable extends Error {}

/** True when Supabase's `amr` (how the session was made) names a password, as a string or `{ method }`. */
export function madeWithPassword(amr) {
  if (!Array.isArray(amr)) return false;
  return amr.some((entry) => {
    const method = typeof entry === "string" ? entry : entry && typeof entry === "object" ? entry.method : undefined;
    return typeof method === "string" && method.toLowerCase() === "password";
  });
}

function parseSegment(text) {
  try {
    const value = JSON.parse(Buffer.from(text, "base64url").toString("utf8"));
    return value && typeof value === "object" && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

function publicKey(jwk) {
  try {
    if (jwk?.kty === "EC" && jwk.crv === "P-256" && (jwk.alg === undefined || jwk.alg === "ES256")) {
      return { alg: "ES256", key: createPublicKey({ key: { kty: "EC", crv: "P-256", x: jwk.x, y: jwk.y }, format: "jwk" }) };
    }
    if (jwk?.kty === "RSA" && (jwk.alg === undefined || jwk.alg === "RS256")) {
      const key = createPublicKey({ key: { kty: "RSA", n: jwk.n, e: jwk.e }, format: "jwk" });
      return key.asymmetricKeyDetails?.modulusLength >= 2048 ? { alg: "RS256", key } : null;
    }
  } catch {
    return null;
  }
  return null;
}

/**
 * A checker for one Supabase project. Keys are cached for 10 minutes; an unknown key ID fetches them
 * again at most every 30 seconds, so junk tokens can't make this server flood Supabase.
 */
export function createAccountVerifier({ projectUrl, fetch: fetchImpl = fetch, keysTtlMs = KEYS_TTL_MS, refetchMinMs = REFETCH_MIN_MS, timeoutMs = TIMEOUT_MS }) {
  const origin = new URL(projectUrl).origin;
  const issuer = `${origin}/auth/v1`;
  const jwksUrl = `${issuer}/.well-known/jwks.json`;
  let keys = new Map();
  let fetchedAt = Number.NEGATIVE_INFINITY;
  let lastAttempt = Number.NEGATIVE_INFINITY;

  async function refresh(nowMs) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetchImpl(jwksUrl, { signal: controller.signal });
      if (!response.ok) return;
      const body = await response.json();
      if (!Array.isArray(body?.keys)) return;
      const next = new Map();
      for (const jwk of body.keys) {
        const parsed = publicKey(jwk);
        if (parsed && typeof jwk.kid === "string") next.set(jwk.kid, parsed);
      }
      keys = next;
      fetchedAt = nowMs;
    } catch {
      // Unreachable: the cached keys keep working.
    } finally {
      clearTimeout(timer);
    }
  }

  async function keyFor(kid, nowMs) {
    const known = keys.get(kid);
    if (known && nowMs - fetchedAt < keysTtlMs) return known;
    if (nowMs - lastAttempt >= refetchMinMs) {
      lastAttempt = nowMs;
      await refresh(nowMs);
    }
    const entry = keys.get(kid);
    if (entry) return entry;
    if (keys.size === 0) throw new AccountCheckUnavailable();
    return null;
  }

  return {
    /** `{ sub }` for a valid Doddy account token, or null. Throws AccountCheckUnavailable only when it can't be checked now. */
    async verify(token, nowMs = Date.now()) {
      if (typeof token !== "string" || token.length > 8_192) return null;
      const parts = token.split(".");
      if (parts.length !== 3 || !parts.every((p) => SEGMENT.test(p))) return null;
      const [headerPart, claimsPart, signaturePart] = parts;
      const header = parseSegment(headerPart);
      if (!header || (header.alg !== "ES256" && header.alg !== "RS256") || typeof header.kid !== "string") return null;
      const entry = await keyFor(header.kid, nowMs);
      if (!entry || entry.alg !== header.alg) return null;
      const data = Buffer.from(`${headerPart}.${claimsPart}`);
      const signature = Buffer.from(signaturePart, "base64url");
      const valid = entry.alg === "ES256"
        ? verifySignature("sha256", data, { key: entry.key, dsaEncoding: "ieee-p1363" }, signature)
        : verifySignature("RSA-SHA256", data, entry.key, signature);
      if (!valid) return null;
      const claims = parseSegment(claimsPart);
      if (!claims) return null;
      const nowSeconds = Math.floor(nowMs / 1_000);
      const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
      if (claims.iss !== issuer || !audience.includes("authenticated") || claims.role !== "authenticated"
          || claims.is_anonymous === true || typeof claims.sub !== "string" || !UUID.test(claims.sub)
          || !Number.isSafeInteger(claims.exp) || claims.exp <= nowSeconds
          || (claims.iat !== undefined && (!Number.isSafeInteger(claims.iat) || claims.iat > nowSeconds + 60))) return null;
      const provider = claims.app_metadata && typeof claims.app_metadata === "object" ? claims.app_metadata.provider : undefined;
      if (typeof provider !== "string" || !PROVIDERS.has(provider)) return null;
      if (madeWithPassword(claims.amr)) return null;
      return { sub: claims.sub };
    },
  };
}

// One checker per project for the life of this instance, so its key cache is shared across requests.
const verifiers = new Map();

/** The checker for SUPABASE_URL, or null when this server has no Supabase project. */
export function accountVerifierFor(env, deps = {}) {
  const projectUrl = typeof env.SUPABASE_URL === "string" ? env.SUPABASE_URL.trim() : "";
  if (!projectUrl) return null;
  let origin;
  try {
    const url = new URL(projectUrl);
    if (url.protocol !== "https:") return null;
    origin = url.origin;
  } catch {
    return null;
  }
  if (deps.fetch) return createAccountVerifier({ projectUrl: origin, fetch: deps.fetch });
  if (!verifiers.has(origin)) verifiers.set(origin, createAccountVerifier({ projectUrl: origin }));
  return verifiers.get(origin);
}

/**
 * The Doddy account behind the request's Bearer token, as this server's limit bucket
 * (`account:<Supabase user id>`, separate from the Apple voice accounts' ids), or null when the token
 * isn't one (the voice server's own session then gets its turn).
 */
export async function authenticateDoddyAccount(request, env, deps = {}) {
  const verifier = accountVerifierFor(env, deps);
  if (!verifier) return null;
  const match = /^Bearer\s+(.+)$/i.exec(request.headers.get("authorization") ?? "");
  if (!match) return null;
  const account = await verifier.verify(match[1].trim(), deps.now ?? Date.now());
  return account ? { userId: `account:${account.sub}`, sessionId: null } : null;
}
