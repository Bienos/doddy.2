import { createHmac, createPublicKey, type KeyObject, randomBytes, timingSafeEqual, verify as verifySignature } from "node:crypto";
import { AppError } from "./errors.js";

/**
 * Replaceable authenticated-session boundary. The rest of the backend only ever sees the
 * immutable internal user ID returned here; request bodies never name a user.
 *
 * Three implementations exist:
 *  - `DevSessionVerifier`: fixed loopback-only test identities for mock mode (config refuses it elsewhere).
 *  - `SignedSessionVerifier`: HMAC-SHA256 tokens minted by the owner with `npm run session:mint`.
 *    Good enough for single-owner development.
 *  - `SupabaseSessionVerifier`: access tokens from Supabase Auth, where people sign in with Apple
 *    or Google (ADR-526). The user ID is the Supabase user's UUID.
 */
export interface AuthenticatedUser {
  /** Immutable internal ID (UUID). Never an email address. */
  userId: string;
}

export interface SessionVerifier {
  /** Null: not signed in. Throws `AppError` only when sign-in can't be checked right now. */
  verify(authorizationHeader: string | undefined, now: Date): AuthenticatedUser | null | Promise<AuthenticatedUser | null>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export function bearer(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer ([A-Za-z0-9._~+/=-]{8,2048})$/.exec(header);
  return match?.[1] ?? null;
}

/** Deterministic demo identities. Safe only because config limits them to loopback mock runs. */
export const DEV_IDENTITIES: Readonly<Record<string, string>> = {
  "dev-user-a": "00000000-0000-4000-8000-00000000000a",
  "dev-user-b": "00000000-0000-4000-8000-00000000000b",
};

export class DevSessionVerifier implements SessionVerifier {
  verify(header: string | undefined): AuthenticatedUser | null {
    const token = bearer(header);
    if (!token) return null;
    const userId = Object.hasOwn(DEV_IDENTITIES, token) ? DEV_IDENTITIES[token] : undefined;
    return userId ? { userId } : null;
  }
}

interface SessionClaims {
  v: 1;
  sub: string;
  iat: number;
  exp: number;
}

const b64url = (data: Buffer | string) => Buffer.from(data).toString("base64url");

export class SignedSessionVerifier implements SessionVerifier {
  constructor(private readonly key: Buffer) {
    if (key.length < 32) throw new Error("session signing key too short");
  }

  mint(userId: string, now: Date, ttlSeconds: number): string {
    if (!UUID.test(userId)) throw new Error("userId must be a UUID");
    const iat = Math.floor(now.getTime() / 1000);
    const claims: SessionClaims = { v: 1, sub: userId, iat, exp: iat + ttlSeconds };
    const payload = b64url(JSON.stringify(claims));
    return `ds1.${payload}.${this.sign(payload)}`;
  }

  verify(header: string | undefined, now: Date): AuthenticatedUser | null {
    const token = bearer(header);
    if (!token) return null;
    const parts = token.split(".");
    if (parts.length !== 3 || parts[0] !== "ds1") return null;
    const [, payload, signature] = parts as [string, string, string];
    const expected = Buffer.from(this.sign(payload));
    const given = Buffer.from(signature);
    if (expected.length !== given.length || !timingSafeEqual(expected, given)) return null;
    let claims: unknown;
    try {
      claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    } catch {
      return null;
    }
    if (!isClaims(claims)) return null;
    const nowSeconds = Math.floor(now.getTime() / 1000);
    if (claims.exp <= nowSeconds || claims.iat > nowSeconds + 60) return null;
    return { userId: claims.sub };
  }

  private sign(payload: string): string {
    return createHmac("sha256", this.key).update(`ds1.${payload}`).digest("base64url");
  }
}

function isClaims(value: unknown): value is SessionClaims {
  if (typeof value !== "object" || value === null) return false;
  const c = value as Record<string, unknown>;
  return (
    c.v === 1 &&
    typeof c.sub === "string" &&
    UUID.test(c.sub) &&
    Number.isInteger(c.iat) &&
    Number.isInteger(c.exp)
  );
}

export function newSigningKey(): string {
  return randomBytes(32).toString("base64");
}

// ------------------------------------------------------------------ Supabase Auth (ADR-526)

/** Reads a JSON document over HTTPS; injectable for tests. */
export type FetchJson = (url: string, signal: AbortSignal) => Promise<unknown>;

const defaultFetchJson: FetchJson = async (url, signal) => {
  const response = await fetch(url, { signal, headers: { accept: "application/json" } });
  if (!response.ok) throw new Error(`jwks ${response.status}`);
  return response.json();
};

interface SupabaseOptions {
  /** https://<project-ref>.supabase.co (or the project's custom domain). Origin only. */
  projectUrl: string;
  fetchJson?: FetchJson;
  /** How long fetched keys are trusted before they are fetched again. */
  keysTtlMs?: number;
  /** An unknown key ID refetches the keys at most this often, so junk tokens can't hammer Supabase. */
  refetchMinMs?: number;
  timeoutMs?: number;
}

const JWT_SEGMENT = /^[A-Za-z0-9_-]+$/;

/**
 * Checks a Supabase Auth access token: the signature against the project's published keys
 * (ES256 or RS256, never a shared secret), the issuer, the audience, the role and the expiry.
 * Anonymous Supabase users are refused: a Doddy account is always an Apple or Google sign-in.
 *
 * A signed-out session's access token stays valid until it expires (Supabase default 1 hour).
 */
export class SupabaseSessionVerifier implements SessionVerifier {
  private readonly issuer: string;
  private readonly jwksUrl: string;
  private readonly fetchJson: FetchJson;
  private readonly keysTtlMs: number;
  private readonly refetchMinMs: number;
  private readonly timeoutMs: number;
  private keys = new Map<string, { alg: "ES256" | "RS256"; key: KeyObject }>();
  private fetchedAt = Number.NEGATIVE_INFINITY;
  private lastAttempt = Number.NEGATIVE_INFINITY;
  private inFlight: Promise<void> | null = null;

  constructor(options: SupabaseOptions) {
    const origin = new URL(options.projectUrl).origin;
    this.issuer = `${origin}/auth/v1`;
    this.jwksUrl = `${this.issuer}/.well-known/jwks.json`;
    this.fetchJson = options.fetchJson ?? defaultFetchJson;
    this.keysTtlMs = options.keysTtlMs ?? 10 * 60_000;
    this.refetchMinMs = options.refetchMinMs ?? 30_000;
    this.timeoutMs = options.timeoutMs ?? 5_000;
  }

  async verify(header: string | undefined, now: Date): Promise<AuthenticatedUser | null> {
    const token = bearer(header);
    if (!token) return null;
    const parts = token.split(".");
    if (parts.length !== 3 || !parts.every((p) => JWT_SEGMENT.test(p))) return null;
    const [headerPart, claimsPart, signaturePart] = parts as [string, string, string];
    const jose = parseSegment(headerPart);
    if (!jose || (jose.alg !== "ES256" && jose.alg !== "RS256") || typeof jose.kid !== "string") return null;

    const entry = await this.keyFor(jose.kid, now.getTime());
    if (!entry || entry.alg !== jose.alg) return null;
    const data = Buffer.from(`${headerPart}.${claimsPart}`);
    const signature = Buffer.from(signaturePart, "base64url");
    const valid =
      entry.alg === "ES256"
        ? verifySignature("sha256", data, { key: entry.key, dsaEncoding: "ieee-p1363" }, signature)
        : verifySignature("RSA-SHA256", data, entry.key, signature);
    if (!valid) return null;

    const claims = parseSegment(claimsPart);
    if (!claims) return null;
    const nowSeconds = Math.floor(now.getTime() / 1000);
    const audience = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (
      claims.iss !== this.issuer ||
      !audience.includes("authenticated") ||
      claims.role !== "authenticated" ||
      claims.is_anonymous === true ||
      typeof claims.sub !== "string" ||
      !UUID.test(claims.sub) ||
      !Number.isSafeInteger(claims.exp) ||
      (claims.exp as number) <= nowSeconds ||
      (claims.iat !== undefined && (!Number.isSafeInteger(claims.iat) || (claims.iat as number) > nowSeconds + 60))
    ) {
      return null;
    }
    return { userId: claims.sub };
  }

  private async keyFor(kid: string, nowMs: number) {
    const fresh = nowMs - this.fetchedAt < this.keysTtlMs;
    const known = this.keys.get(kid);
    if (known && fresh) return known;
    // Unknown key or stale keys: fetch again, but not more than once per refetchMinMs.
    if (nowMs - this.lastAttempt >= this.refetchMinMs) {
      this.lastAttempt = nowMs;
      this.inFlight ??= this.refresh(nowMs).finally(() => {
        this.inFlight = null;
      });
    }
    if (this.inFlight) await this.inFlight;
    const entry = this.keys.get(kid);
    if (entry) return entry;
    // Never fetched successfully: say so, instead of telling a signed-in person they're signed out.
    if (this.keys.size === 0) {
      throw new AppError("provider_unavailable", { message: "Doddy couldn't check your sign-in right now. Try again shortly." });
    }
    return null;
  }

  private async refresh(nowMs: number): Promise<void> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const body = (await this.fetchJson(this.jwksUrl, controller.signal)) as { keys?: unknown };
      if (!Array.isArray(body?.keys)) return;
      const next = new Map<string, { alg: "ES256" | "RS256"; key: KeyObject }>();
      for (const jwk of body.keys as Record<string, unknown>[]) {
        const parsed = publicKey(jwk);
        if (parsed && typeof jwk.kid === "string") next.set(jwk.kid, parsed);
      }
      if (next.size > 0) {
        this.keys = next;
        this.fetchedAt = nowMs;
      }
    } catch {
      // Keep the keys we had; a later request tries again.
    } finally {
      clearTimeout(timer);
    }
  }
}

function publicKey(jwk: Record<string, unknown>): { alg: "ES256" | "RS256"; key: KeyObject } | null {
  if (jwk.use !== undefined && jwk.use !== "sig") return null;
  try {
    if (jwk.kty === "EC" && jwk.crv === "P-256" && (jwk.alg === undefined || jwk.alg === "ES256")) {
      return { alg: "ES256", key: createPublicKey({ key: { kty: "EC", crv: "P-256", x: jwk.x, y: jwk.y } as never, format: "jwk" }) };
    }
    if (jwk.kty === "RSA" && (jwk.alg === undefined || jwk.alg === "RS256")) {
      const key = createPublicKey({ key: { kty: "RSA", n: jwk.n, e: jwk.e } as never, format: "jwk" });
      return (key.asymmetricKeyDetails?.modulusLength ?? 0) >= 2048 ? { alg: "RS256", key } : null;
    }
  } catch {
    return null;
  }
  return null;
}

function parseSegment(segment: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(Buffer.from(segment, "base64url").toString("utf8"));
    return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/**
 * Accepts the first verifier that recognises the token. Used in development so the owner's
 * minted token keeps working while Apple and Google sign-in arrive (config refuses it in production).
 */
export class AnyOfSessionVerifier implements SessionVerifier {
  constructor(private readonly verifiers: readonly SessionVerifier[]) {}

  async verify(header: string | undefined, now: Date): Promise<AuthenticatedUser | null> {
    for (const verifier of this.verifiers) {
      const user = await verifier.verify(header, now);
      if (user) return user;
    }
    return null;
  }
}
