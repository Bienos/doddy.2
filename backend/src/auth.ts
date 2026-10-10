import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

/**
 * Replaceable authenticated-session boundary. The rest of the backend only ever sees the
 * immutable internal user ID returned here; request bodies never name a user.
 *
 * Two implementations exist:
 *  - `DevSessionVerifier`: fixed loopback-only test identities for mock mode (config refuses it elsewhere).
 *  - `SignedSessionVerifier`: HMAC-SHA256 tokens minted by the owner with `npm run session:mint`.
 *    Good enough for single-owner development; a public release needs a vetted sign-in first.
 */
export interface AuthenticatedUser {
  /** Immutable internal ID (UUID). Never an email address. */
  userId: string;
}

export interface SessionVerifier {
  verify(authorizationHeader: string | undefined, now: Date): AuthenticatedUser | null;
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
