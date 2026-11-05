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
  /**
   * `ask`: a guest iPhone's device session (ADR-587), good for Ask Doddy (`POST /v1/assist`) and
   * nothing else. Absent: the full API.
   */
  scope?: "ask";
}

/**
 * Every route but Ask Doddy calls this. A guest is told the feature isn't set up for it, which is
 * what such an iPhone heard before guests existed; never 401, which would make the app sign in
 * again in a loop.
 */
export function requireFullAccess(user: AuthenticatedUser): void {
  if (user.scope === "ask") throw new AppError("live_not_configured", { message: "On this iPhone, Doddy's server answers Ask Doddy only." });
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
  /** Only on a guest's token (ADR-587). Signed with the rest, so it can't be removed. */
  scp?: "ask";
}

const b64url = (data: Buffer | string) => Buffer.from(data).toString("base64url");

export class SignedSessionVerifier implements SessionVerifier {
  constructor(private readonly key: Buffer) {
    if (key.length < 32) throw new Error("session signing key too short");
  }

  mint(userId: string, now: Date, ttlSeconds: number, scope?: "ask"): string {
    if (!UUID.test(userId)) throw new Error("userId must be a UUID");
    const iat = Math.floor(now.getTime() / 1000);
    const claims: SessionClaims = { v: 1, sub: userId, iat, exp: iat + ttlSeconds, ...(scope ? { scp: scope } : {}) };
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
    return claims.scp ? { userId: claims.sub, scope: claims.scp } : { userId: claims.sub };
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
    Number.isInteger(c.exp) &&
    (c.scp === undefined || c.scp === "ask")
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
  /** Sign-in methods that make a Doddy account (Supabase `app_metadata.provider`). */
  providers?: readonly string[];
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
 * Anonymous users and other sign-in methods (email, phone) are refused: a Doddy account is always
 * an Apple or Google sign-in, so the project's other Supabase settings can't open this server.
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
  private readonly providers: ReadonlySet<string>;
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
    this.providers = new Set(options.providers ?? ["apple", "google"]);
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
    const meta = claims.app_metadata;
    const provider = typeof meta === "object" && meta !== null ? (meta as Record<string, unknown>).provider : undefined;
    if (typeof provider !== "string" || !this.providers.has(provider)) return null;
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

// ------------------------------------------------------------------ cutting off a person's tokens (ADR-709)

/**
 * The `iat` (seconds since 1970) of a device-session token (`ds1`), `undefined` for any other kind of
 * token, and `null` for a `ds1` token whose claims can't be read. It only READS: call it for a token a
 * verifier has already accepted, never to decide whether a token is genuine.
 */
export function sessionTokenIssuedAt(header: string | undefined): number | null | undefined {
  const token = bearer(header);
  if (!token) return undefined;
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== "ds1") return undefined;
  try {
    const claims = JSON.parse(Buffer.from(parts[1]!, "base64url").toString("utf8")) as { iat?: unknown };
    return Number.isInteger(claims.iat) ? (claims.iat as number) : null;
  } catch {
    return null;
  }
}

/** Where a person's cut-off second is kept (the store). */
export interface TokenFloorSource {
  tokenFloor(userId: string): Promise<number>;
}

/**
 * A person's "tokens valid after" second, with a short memory so a busy phone doesn't cost a database
 * read on every request. A cut-off made on THIS instance is written into the memory at once
 * (`remember`), so it takes effect immediately here; another instance would see it within `ttlMs`
 * (this backend is designed to run as one instance).
 */
export class TokenFloors {
  private readonly seen = new Map<string, { floor: number; at: number }>();

  constructor(
    private readonly source: TokenFloorSource,
    private readonly ttlMs = 30_000,
    private readonly maxEntries = 10_000,
  ) {}

  async floorOf(userId: string, nowMs: number): Promise<number> {
    const hit = this.seen.get(userId);
    if (hit && nowMs >= hit.at && nowMs - hit.at < this.ttlMs) return hit.floor;
    const floor = await this.source.tokenFloor(userId);
    this.remember(userId, floor, nowMs);
    return floor;
  }

  /** The person was just cut off at `floor` (never lowers a floor already known). */
  remember(userId: string, floor: number, nowMs = Date.now()): void {
    const known = this.seen.get(userId)?.floor ?? 0;
    this.seen.delete(userId);
    // Bounded: only people holding a genuine token get here, but the memory still must not grow without end.
    if (this.seen.size >= this.maxEntries) {
      const oldest = this.seen.keys().next();
      if (!oldest.done) this.seen.delete(oldest.value);
    }
    this.seen.set(userId, { floor: Math.max(floor, known), at: nowMs });
  }
}

/**
 * Refuses a device-session token dated before its person's cut-off second. Deleting the account sets the
 * cut-off (`Store.eraseUser`), so a token minted before the deletion stops working at once, and one
 * minted by a later sign-in (dated at or after the cut-off) works. Only `ds1` tokens are covered: an
 * owner-minted or device token is the one that lasts 30 days. A Supabase access token (an hour) is
 * Supabase's to end.
 *
 * Rotating the signing key still revokes every token at once, and changes every device's user ID
 * (see `deviceUserId`); that is unchanged. If the cut-off can't be read the request is refused with
 * "can't check your sign-in right now" (never a 401, which would make the app sign in again in a loop).
 */
export class RevocableSessionVerifier implements SessionVerifier {
  constructor(
    private readonly inner: SessionVerifier,
    private readonly floors: TokenFloors,
  ) {}

  async verify(header: string | undefined, now: Date): Promise<AuthenticatedUser | null> {
    const user = await this.inner.verify(header, now);
    if (!user) return null;
    const issuedAt = sessionTokenIssuedAt(header);
    if (issuedAt === undefined) return user; // not a device-session token
    if (issuedAt === null) return null;
    let floor: number;
    try {
      floor = await this.floors.floorOf(user.userId, now.getTime());
    } catch {
      throw new AppError("provider_unavailable", { message: "Doddy couldn't check your sign-in right now. Try again shortly." });
    }
    return issuedAt < floor ? null : user;
  }
}
