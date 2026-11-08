// Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account, a Supabase
// Auth user made with Apple, Google or a code sent by email (ADR-526). This server checks that
// account's access token itself, against the project's published keys: no shared secret.
//
// The rules are the backend's (`backend/src/auth.ts`, SupabaseSessionVerifier) and the voice token
// server's (`server/voice-token/src/doddy-account.js`):
// - ES256 or RS256 only, signed by a key the project publishes;
// - issuer `<project>/auth/v1`, audience `authenticated`, role `authenticated`, not anonymous;
// - not expired, and not issued in the future;
// - made with Apple, Google or email, and never with a password.
import { createPublicKey, type KeyObject, verify as verifySignature } from "node:crypto";

export interface AccountVerifier {
  /** `{ sub }` for a valid Doddy account token, or null. Throws AccountCheckUnavailable only when it can't be checked now. */
  verify(token: string, nowMs?: number): Promise<{ sub: string } | null>;
}

/** The project's signing keys could not be read and none is cached: "try again", never "signed out". */
export class AccountCheckUnavailable extends Error {}

const PROVIDERS = new Set(["apple", "google", "email"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SEGMENT = /^[A-Za-z0-9_-]+$/;
type Key = { alg: "ES256" | "RS256"; key: KeyObject };
type FetchLike = (url: string, init: { signal: AbortSignal }) => Promise<{ ok: boolean; json(): Promise<unknown> }>;

/** True when Supabase's `amr` (how the session was made) names a password, as a string or `{ method }`. */
export function madeWithPassword(amr: unknown): boolean {
  if (!Array.isArray(amr)) return false;
  return amr.some((entry) => {
    const method = typeof entry === "string" ? entry : entry && typeof entry === "object" ? (entry as Record<string, unknown>).method : undefined;
    return typeof method === "string" && method.toLowerCase() === "password";
  });
}

function parseSegment(text: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(Buffer.from(text, "base64url").toString("utf8")) as unknown;
    return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function publicKey(jwk: Record<string, unknown>): Key | null {
  try {
    if (jwk.kty === "EC" && jwk.crv === "P-256" && (jwk.alg === undefined || jwk.alg === "ES256")) {
      return { alg: "ES256", key: createPublicKey({ key: { kty: "EC", crv: "P-256", x: jwk.x as string, y: jwk.y as string }, format: "jwk" }) };
    }
    if (jwk.kty === "RSA" && (jwk.alg === undefined || jwk.alg === "RS256")) {
      const key = createPublicKey({ key: { kty: "RSA", n: jwk.n as string, e: jwk.e as string }, format: "jwk" });
      return (key.asymmetricKeyDetails?.modulusLength ?? 0) >= 2048 ? { alg: "RS256", key } : null;
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
export function createAccountVerifier(options: {
  projectUrl: string;
  fetch?: FetchLike;
  keysTtlMs?: number;
  refetchMinMs?: number;
  timeoutMs?: number;
}): AccountVerifier {
  const fetchImpl: FetchLike = options.fetch ?? ((url, init) => fetch(url, init));
  const keysTtlMs = options.keysTtlMs ?? 10 * 60_000;
  const refetchMinMs = options.refetchMinMs ?? 30_000;
  const timeoutMs = options.timeoutMs ?? 5_000;
  const issuer = `${new URL(options.projectUrl).origin}/auth/v1`;
  const jwksUrl = `${issuer}/.well-known/jwks.json`;
  let keys = new Map<string, Key>();
  let fetchedAt = Number.NEGATIVE_INFINITY;
  let lastAttempt = Number.NEGATIVE_INFINITY;

  async function refresh(nowMs: number): Promise<void> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetchImpl(jwksUrl, { signal: controller.signal });
      if (!response.ok) return;
      const body = (await response.json()) as { keys?: unknown };
      if (!Array.isArray(body?.keys)) return;
      const next = new Map<string, Key>();
      for (const jwk of body.keys as Record<string, unknown>[]) {
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

  async function keyFor(kid: string, nowMs: number): Promise<Key | null> {
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
    async verify(token, nowMs = Date.now()) {
      if (typeof token !== "string" || token.length > 8_192) return null;
      const parts = token.split(".");
      if (parts.length !== 3 || !parts.every((p) => SEGMENT.test(p))) return null;
      const [headerPart, claimsPart, signaturePart] = parts as [string, string, string];
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
          || !Number.isSafeInteger(claims.exp) || (claims.exp as number) <= nowSeconds
          || (claims.iat !== undefined && (!Number.isSafeInteger(claims.iat) || (claims.iat as number) > nowSeconds + 60))) return null;
      const meta = claims.app_metadata;
      const provider = meta && typeof meta === "object" ? (meta as Record<string, unknown>).provider : undefined;
      if (typeof provider !== "string" || !PROVIDERS.has(provider)) return null;
      if (madeWithPassword(claims.amr)) return null;
      return { sub: claims.sub };
    },
  };
}
