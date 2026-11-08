import { z } from "zod";
import { type AuthenticatedUser, bearer, type SessionVerifier, sessionTokenIssuedAt, type TokenFloors } from "./auth.js";
import { AppError } from "./errors.js";

/**
 * Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account (a Supabase
 * user: Apple, Google or a code by email). An iPhone that used Doddy before has its data under its
 * own device user id (`deviceUserId`); its first sign-in links that data to the account, once, with
 * proof (the device's own token), and never merges two accounts (ADR-600).
 */

export interface AccountLinkStore {
  linkedUserOf(subject: string): Promise<string | null>;
  isLinkedUser(userId: string): Promise<boolean>;
  linkAccount(subject: string, userId: string, now: number): Promise<"linked" | "already" | "subject_taken" | "user_taken" | "account_has_data">;
  reserveUsage(checks: readonly { counter: string; period: string; limit: number }[], units: number): Promise<boolean>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** A Supabase access token's claims, read without checking them: call it only on a header a verifier accepted. */
function jwtClaims(header: string | undefined): Record<string, unknown> | null {
  const token = bearer(header);
  if (!token) return null;
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] === "ds1") return null;
  try {
    const claims = JSON.parse(Buffer.from(parts[1]!, "base64url").toString("utf8")) as unknown;
    return typeof claims === "object" && claims !== null ? (claims as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/**
 * The Doddy account (Supabase user id) behind an Authorization header the server's verifier already
 * accepted, or null when it is another kind of sign-in (a device token, a test's dev token). Its user
 * id may differ from the account's: an account that took over an iPhone's data works on that data.
 */
export function accountSubjectOf(acceptedHeader: string | undefined): string | null {
  const sub = jwtClaims(acceptedHeader)?.sub;
  return typeof sub === "string" && UUID.test(sub) ? sub : null;
}

/**
 * Wraps the server's verifier:
 * - a Doddy account that took over an iPhone's data works on that data (its user id becomes the
 *   linked one);
 * - an account deleted a moment ago stops at once (its cut-off second, like a device token's, ADR-709);
 * - a device token whose data now belongs to an account is refused: the iPhone signs in with the
 *   account, and the device id stops being a key to the data.
 */
export class LinkedAccountVerifier implements SessionVerifier {
  constructor(
    private readonly inner: SessionVerifier,
    private readonly links: Pick<AccountLinkStore, "linkedUserOf" | "isLinkedUser">,
    private readonly floors: TokenFloors,
  ) {}

  async verify(header: string | undefined, now: Date): Promise<AuthenticatedUser | null> {
    const user = await this.inner.verify(header, now);
    if (!user) return null;
    try {
      if (sessionTokenIssuedAt(header) !== undefined) {
        // A device token (ds1): retired once an account took over its data.
        return (await this.links.isLinkedUser(user.userId)) ? null : user;
      }
      const claims = jwtClaims(header);
      if (!claims || claims.sub !== user.userId) return user; // not a Supabase account (a test's dev token)
      const issuedAt = claims.iat;
      if (Number.isSafeInteger(issuedAt) && (issuedAt as number) < (await this.floors.floorOf(user.userId, now.getTime()))) return null;
      const linked = await this.links.linkedUserOf(user.userId);
      return linked ? { ...user, userId: linked } : user;
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError("provider_unavailable", { message: "Doddy couldn't check your sign-in right now. Try again shortly." });
    }
  }
}

export const LinkDeviceRequest = z.object({ deviceToken: z.string().min(1).max(4096) }).strict();

/** At most this many link tries per account per hour: a right pair links on the first. */
export const LINK_TRIES_PER_HOUR = 10;

const CONFLICT_MESSAGES = {
  subject_taken: "This Doddy account already has another iPhone's earlier data, so nothing was linked.",
  user_taken: "This iPhone's earlier data already belongs to another Doddy account, so nothing was linked.",
  account_has_data: "This Doddy account already has data of its own, so this iPhone's earlier data wasn't added to it. Accounts are never merged.",
} as const;

/**
 * `POST /v1/account/link-device`: the Doddy account in the Authorization header takes over the data of
 * the iPhone whose device token is in the body. Both must be valid now; a repeat of a done link is
 * answered the same way, so the iPhone can safely try again after a lost answer.
 */
export class AccountLinker {
  constructor(
    private readonly deps: {
      store: AccountLinkStore;
      /** Supabase sign-ins only (not the linked mapping): who is asking. Null when this server has no Supabase project. */
      accounts: SessionVerifier | null;
      /** Device tokens only, with their cut-off (ADR-709), and not refused for being linked (a repeat must pass). */
      devices: SessionVerifier | null;
      floors: TokenFloors;
      log?: (line: Record<string, unknown>) => void;
    },
  ) {}

  async link(authorization: string | undefined, body: unknown, now: Date): Promise<{ linked: true }> {
    const { accounts, devices, store } = this.deps;
    if (!accounts || !devices) throw new AppError("live_not_configured", { message: "Doddy accounts aren't set up on this server yet." });
    const account = await accounts.verify(authorization, now);
    const claims = jwtClaims(authorization);
    if (!account || !claims || claims.sub !== account.userId) throw new AppError("unauthenticated");
    if (Number.isSafeInteger(claims.iat) && (claims.iat as number) < (await this.deps.floors.floorOf(account.userId, now.getTime()))) {
      throw new AppError("unauthenticated");
    }
    const parsed = LinkDeviceRequest.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");
    const deviceHeader = `Bearer ${parsed.data.deviceToken}`;
    if (sessionTokenIssuedAt(deviceHeader) === undefined) throw new AppError("invalid_request");
    const device = await devices.verify(deviceHeader, now);
    if (!device) throw new AppError("unauthenticated", { message: "This iPhone's earlier sign-in isn't valid any more, so there is nothing to link." });

    const allowed = await store.reserveUsage(
      [{ counter: `account_link:${account.userId}`, period: `hour:${now.toISOString().slice(0, 13)}`, limit: LINK_TRIES_PER_HOUR }],
      1,
    );
    if (!allowed) throw new AppError("rate_limited", { message: "Too many tries to link this iPhone. Try again in an hour.", retryAfterSeconds: 3_600 });

    const outcome = await store.linkAccount(account.userId, device.userId, now.getTime());
    // Content-free: the outcome only, never an id.
    this.deps.log?.({ level: "info", event: "account_link", outcome });
    if (outcome === "linked" || outcome === "already") return { linked: true };
    throw new AppError("account_conflict", { message: CONFLICT_MESSAGES[outcome] });
  }
}
