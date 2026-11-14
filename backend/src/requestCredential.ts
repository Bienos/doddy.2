import { AsyncLocalStorage } from "node:async_hooks";
import { bearer } from "./auth.js";

/**
 * Who the request being served was let in as, and the second (since 1970) its sign-in dates from.
 * `http.ts` sets it once the session is checked; it follows the request into everything it starts.
 *
 * Why: deleting an account (`Store.eraseUser`) sets the person's cut-off second (`token_floor`), and
 * from then on a sign-in dated before it is refused (ADR-709). A request that was let in a moment
 * BEFORE the deletion, and is still working when it commits, would otherwise write the person's rows
 * again (the `users` row, receipts, switches, documents). The store checks the same cut-off, in the
 * same transaction as each such write (`Store.refuseIfCutOff`), so that request is refused like a
 * token past its cut-off, and a sign-in made after the deletion (dated at or after it) writes as usual.
 *
 * The cut-off row is the erasure's tombstone: it is written in the erasure's own transaction for the
 * person's user id and every account behind it, and kept 31 days (`pruneTokenFloors`), far longer
 * than any request runs.
 */
export interface RequestCredential {
  userId: string;
  /** Seconds since 1970: the token's `iat`, or when a browser session was opened. */
  issuedAt: number;
}

export const requestCredential = new AsyncLocalStorage<RequestCredential>();

/**
 * The `iat` (seconds) of an Authorization header a verifier already accepted: a device token (`ds1`)
 * or a Supabase access token. Undefined for a token that carries no date (the mock mode's test
 * identities), which is then not checked. It only READS; it never decides whether a token is genuine.
 */
export function issuedAtOf(acceptedHeader: string | undefined): number | undefined {
  const token = bearer(acceptedHeader);
  const parts = token?.split(".");
  if (!parts || parts.length !== 3) return undefined;
  try {
    const iat = (JSON.parse(Buffer.from(parts[1]!, "base64url").toString("utf8")) as { iat?: unknown }).iat;
    return Number.isSafeInteger(iat) ? (iat as number) : undefined;
  } catch {
    return undefined;
  }
}
