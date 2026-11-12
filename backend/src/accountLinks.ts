import { createHash, randomBytes } from "node:crypto";
import { z } from "zod";
import { type AuthenticatedUser, bearer, type SessionVerifier, sessionTokenIssuedAt, type TokenFloors } from "./auth.js";
import { AppError } from "./errors.js";
import type { AccountLinkOutcome, LinkEnded } from "./store.js";

/**
 * Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account (a Supabase
 * user: Apple, Google or a code by email). An iPhone that used Doddy before has its data under its
 * own device user id (`deviceUserId`); its first sign-in links that data to the account, once, and
 * never merges two accounts (ADR-600).
 *
 * The iPhone itself starts the link, a moment before: its own device session asks for a one-time code
 * (`POST /v1/account/link-device/start`), and only that code, with the account's sign-in, links
 * (`POST /v1/account/link-device`). A code lasts LINK_CODE_TTL_MS, works once and is kept only as a
 * hash, so a device token copied somewhere earlier is not enough on its own: whoever links must hold
 * a live device session and act within minutes. A guest's device session (`scp: "ask"`) has no data to
 * link and gets no code. For a day after, the iPhone can take its data back with its device token
 * (`POST /v1/account/link-device/undo`); after that only the operator can (`npm run account:unlink`).
 */

export interface AccountLinkStore {
  linkedUserOf(subject: string): Promise<string | null>;
  isLinkedUser(userId: string): Promise<boolean>;
  createAccountLinkCode(userId: string, codeHash: string, now: number, ttlMs: number): Promise<void>;
  linkAccountWithCode(subject: string, codeHash: string, now: number): Promise<AccountLinkOutcome | "bad_code">;
  undoAccountLink(userId: string, now: number, windowMs: number): Promise<{ outcome: "undone" | "not_linked" | "too_late"; ended: LinkEnded | null }>;
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

/** A link code: 32 random bytes, base64url. */
const LINK_CODE = /^[A-Za-z0-9_-]{43}$/;

/**
 * The body of `POST /v1/account/link-device`: the code the iPhone's own device session just got. The
 * one-step form that carried the device token itself (`{ deviceToken }`) is refused: a token alone
 * doesn't show that the iPhone is taking part now.
 */
export const LinkDeviceRequest = z.object({ linkCode: z.string().regex(LINK_CODE) }).strict();

/** At most this many link tries per account per hour: a right code links on the first. */
export const LINK_TRIES_PER_HOUR = 10;

/** How long a link code works, once. */
export const LINK_CODE_TTL_MS = 5 * 60_000;

/** Link codes and undo tries per iPhone per hour. */
export const LINK_CODES_PER_HOUR = 10;

/** For this long after a link, the iPhone can take its data back with its own device token. */
export const LINK_UNDO_WINDOW_MS = 24 * 3_600_000;

const CONFLICT_MESSAGES = {
  subject_taken: "This Doddy account already has another iPhone's earlier data, so nothing was linked.",
  user_taken: "This iPhone's earlier data already belongs to another Doddy account, so nothing was linked.",
  account_has_data: "This Doddy account already has data of its own, so this iPhone's earlier data wasn't added to it. Accounts are never merged.",
} as const;

const codeHash = (code: string) => createHash("sha256").update(`doddy-account-link:v1:${code}`).digest("hex");

/**
 * The three account-link routes:
 * - `POST /v1/account/link-device/start` (the iPhone's device token): a one-time code for this iPhone;
 * - `POST /v1/account/link-device` (the account's token, the code in the body): the account takes
 *   over the data of the iPhone the code was issued to. A repeat of a done link (a lost answer, with a
 *   new code) is answered the same way;
 * - `POST /v1/account/link-device/undo` (the iPhone's device token): within LINK_UNDO_WINDOW_MS, the
 *   iPhone's data is its own again.
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

  /** `POST /v1/account/link-device/start`: this iPhone's own session asks for a one-time code. */
  async start(authorization: string | undefined, now: Date): Promise<{ linkCode: string; expiresAt: string }> {
    const device = await this.device(authorization, now);
    await this.countDeviceTry(device.userId, now);
    const code = randomBytes(32).toString("base64url");
    await this.deps.store.createAccountLinkCode(device.userId, codeHash(code), now.getTime(), LINK_CODE_TTL_MS);
    this.deps.log?.({ level: "info", event: "account_link_code" });
    return { linkCode: code, expiresAt: new Date(now.getTime() + LINK_CODE_TTL_MS).toISOString() };
  }

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
    if (!parsed.success) {
      throw new AppError("invalid_request", { message: "Linking this iPhone's earlier data needs a code from this iPhone. Update Doddy and try again." });
    }

    // Counted before the code is looked at, right or wrong. An hour's count, under a `day:` period like the
    // server's other hourly counts, so `prune` drops it.
    const allowed = await store.reserveUsage(
      [{ counter: `account_link:${account.userId}`, period: `day:${now.toISOString().slice(0, 13)}`, limit: LINK_TRIES_PER_HOUR }],
      1,
    );
    if (!allowed) throw new AppError("rate_limited", { message: "Too many tries to link this iPhone. Try again in an hour.", retryAfterSeconds: 3_600 });

    const outcome = await store.linkAccountWithCode(account.userId, codeHash(parsed.data.linkCode), now.getTime());
    // Content-free: the outcome only, never an id.
    this.deps.log?.({ level: "info", event: "account_link", outcome });
    if (outcome === "linked" || outcome === "already") return { linked: true };
    if (outcome === "bad_code") {
      throw new AppError("attempt_invalid", { message: "That link code isn't valid any more. The iPhone asks for a new one and tries again." });
    }
    throw new AppError("account_conflict", { message: CONFLICT_MESSAGES[outcome] });
  }

  /**
   * `POST /v1/account/link-device/undo`: the iPhone's own device token takes its data back from the
   * account, within LINK_UNDO_WINDOW_MS of the link. The answer is the state afterwards: not linked.
   */
  async undo(authorization: string | undefined, now: Date): Promise<{ linked: false }> {
    const device = await this.device(authorization, now);
    await this.countDeviceTry(device.userId, now);
    const { outcome, ended } = await this.deps.store.undoAccountLink(device.userId, now.getTime(), LINK_UNDO_WINDOW_MS);
    // Content-free: the outcome and counts only, never an id.
    this.deps.log?.({ level: "info", event: "account_link_undo", outcome, ...(ended ?? {}) });
    if (outcome === "too_late") {
      throw new AppError("account_conflict", {
        message: "This iPhone's earlier data was linked to a Doddy account more than a day ago, so it can't be taken back from the iPhone any more.",
      });
    }
    return { linked: false };
  }

  /** The iPhone behind a device token (`ds1`), valid and not cut off. A guest's token has no data to link. */
  private async device(authorization: string | undefined, now: Date): Promise<AuthenticatedUser> {
    const { accounts, devices } = this.deps;
    if (!accounts || !devices) throw new AppError("live_not_configured", { message: "Doddy accounts aren't set up on this server yet." });
    if (sessionTokenIssuedAt(authorization) === undefined) throw new AppError("unauthenticated");
    const device = await devices.verify(authorization, now);
    if (!device) throw new AppError("unauthenticated", { message: "This iPhone's earlier sign-in isn't valid any more, so there is nothing to link." });
    if (device.scope === "ask") {
      throw new AppError("permission_insufficient", { message: "A guest sign-in keeps no data on Doddy's server, so there is nothing to link." });
    }
    return device;
  }

  private async countDeviceTry(userId: string, now: Date): Promise<void> {
    const allowed = await this.deps.store.reserveUsage(
      [{ counter: `account_link_device:${userId}`, period: `day:${now.toISOString().slice(0, 13)}`, limit: LINK_CODES_PER_HOUR }],
      1,
    );
    if (!allowed) throw new AppError("rate_limited", { message: "Too many tries to link this iPhone. Try again in an hour.", retryAfterSeconds: 3_600 });
  }
}
