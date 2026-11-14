import { createHash, createHmac } from "node:crypto";
import { z } from "zod";
import { jwtClaims } from "./accountLinks.js";
import { type SessionVerifier, SignedSessionVerifier, type TokenFloors } from "./auth.js";
import { clientKey } from "./clientAddress.js";
import { DEVICE_SESSION_TTL_SECONDS } from "./deviceSession.js";
import type { AccountDeviceRegistration, AccountDeviceResult } from "./store.js";
import { AppError } from "./errors.js";
import type { SigningKeys } from "./signingKeys.js";

/**
 * The backend's own session for a Doddy account on one iPhone (decision 2026-11-12-one-token-per-server, item 1).
 *
 * `POST /v1/session/account` takes the Doddy account's Supabase token ONCE (in the Authorization header, checked as the
 * backend checks it for every account-bound request: the project's published keys, issuer, audience, role, expiry, no
 * anonymous and no password sign-in, and the account's cut-off if it was deleted a moment ago) and the iPhone's device
 * id, as `POST /v1/session/device` takes it. It answers with a `ds1` token of the account, signed the same way as every
 * other `ds1` token (the session key, `signingKeys.ts`), that names this iPhone's stored row (`dev`, `devices.ts`) and says
 * it is an account session (`acc`):
 *
 *  - It is that account on every route: the same user id as its Supabase token, mapped to the data the account took over
 *    when it took over an iPhone's earlier data (`LinkedAccountVerifier`), read on every request.
 *  - It lasts 30 days from the exchange. Renewing is the same exchange, with a fresh Supabase token: the app makes it two
 *    days before the expiry (`DeviceSession`) with the Supabase session it holds, and a renewal is the same row and a new
 *    token. A session that is not renewed ends by itself.
 *  - It ends at once with the iPhone's row: `DELETE /v1/web/devices/:id` (the iPhone's own session may call it, and that is
 *    the sign-out), a revoke from another of the account's iPhones or a browser, and account deletion all end it on the very
 *    next request (`RevocableSessionVerifier`, `DeviceRegistry.allows`, `Store.eraseUser`).
 *  - It is never exchanged for another: only a Supabase token is taken here, so a session that has been ended can't be
 *    used to get a new one. A revoked iPhone gets a session again only through a fresh Supabase token and a deliberate
 *    exchange, which gives its row a new id (`Store.registerAccountDevice`): what was made before the revoke stays dead.
 *
 * What is stored is ids and times: the row `devices` already has (`account_id` says whose), counters of tries (a hash of the
 * address and a hash of the account, never either) and nothing of the tokens. The iPhone's key in the row is derived from the
 * account and the device id together with the identifier key, so the device id is never stored and one iPhone has one row per
 * account, apart from the device-session path's.
 *
 * Limits, with the numbers the other sign-in routes use: tries per address per hour counted before the token is trusted
 * (20, as the guest and invite routes), exchanges per account per hour (20, as the sign-in codes and tickets), and iPhones
 * per account (20): a new iPhone beyond that is refused with a plain message, one the account already has renews as usual,
 * and revoked ones don't take a place.
 */

export const ACCOUNT_SESSION_LIMITS = Object.freeze({ perClientPerHour: 20, perAccountPerHour: 20, maxDevicesPerAccount: 20 });
export type AccountSessionLimits = { perClientPerHour: number; perAccountPerHour: number; maxDevicesPerAccount: number };

export const AccountSessionRequest = z
  .object({ deviceId: z.string().regex(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/) })
  .strict();

export interface AccountSessionResponse {
  token: string;
  /** When the token stops working: the expiry the server wrote into it. */
  expiresAt: string;
  access: "full";
  /** This iPhone's stored row, read back from the store: the `id` the device list shows and the revoke (the sign-out) names. Not the device id the iPhone keeps. */
  deviceListId: string;
}

/** What the exchange needs from the store. */
export interface AccountSessionStore {
  reserveUsage(checks: readonly { counter: string; period: string; limit: number }[], units: number): Promise<boolean>;
}

/** What the exchange needs from the stored iPhones (`DeviceRegistry`). */
export interface AccountDeviceSignIns {
  accountSignedIn(input: Omit<AccountDeviceRegistration, "id">): Promise<AccountDeviceResult>;
}

export class AccountSessionIssuer {
  private readonly signer: SignedSessionVerifier;
  private readonly limits: AccountSessionLimits;

  constructor(
    private readonly options: {
      /** Supabase sign-ins only: nothing else is taken here. */
      accounts: SessionVerifier;
      /** The signing keys for the session tokens (`signingKeys.ts`), or a master key alone. */
      keys: SigningKeys | Buffer;
      /** `DODDY_IDENTIFIER_KEY`, or the master key when that is not set: derives the iPhone's key in its row. Not rotated with the signing keys. */
      identifierKey: Buffer;
      store: AccountSessionStore;
      /** The accounts' cut-off seconds (ADR-709): an account deleted a moment ago gets no session. */
      floors: TokenFloors;
      devices: AccountDeviceSignIns;
      limits?: AccountSessionLimits;
      ttlSeconds?: number;
      /** Operational log: a word for what happened, never a token, a device, an account or an address. */
      log?: (line: Record<string, unknown>) => void;
    },
  ) {
    if (options.identifierKey.length < 32) throw new Error("identifier key too short");
    this.signer = new SignedSessionVerifier(options.keys);
    this.limits = options.limits ?? ACCOUNT_SESSION_LIMITS;
  }

  /**
   * `authorization`: the whole `Authorization` header. `client`: the caller's address (see `clientAddress`), for the per-address
   * limit. Every refusal is the existing error shape, and a refused token says nothing about why.
   */
  async issue(authorization: string | undefined, body: unknown, now: Date, client = "unknown"): Promise<AccountSessionResponse> {
    const hour = `day:${now.toISOString().slice(0, 13)}`;
    // Every try from this address counts, right or wrong, before the token is looked at, so guessing from one place runs out.
    const network = createHash("sha256").update(`account-session-client:${clientKey(client)}`).digest("base64url");
    await this.count(`account_session_client:${network}`, hour, this.limits.perClientPerHour, "Too many sign-ins from this network. Try again later.");
    const parsed = AccountSessionRequest.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");

    const account = await this.accountOf(authorization, now);
    const who = createHash("sha256").update(`account-session-account:${account}`).digest("base64url");
    await this.count(`account_session:${who}`, hour, this.limits.perAccountPerHour, "Too many sign-ins on this Doddy account right now. Try again later.");

    const issuedAt = Math.floor(now.getTime() / 1000);
    const stored = await this.options.devices.accountSignedIn({
      accountId: account,
      deviceKey: accountDeviceUserId(this.options.identifierKey, account, parsed.data.deviceId.toLowerCase()),
      now: now.getTime(),
      issuedAt,
      maxPerAccount: this.limits.maxDevicesPerAccount,
    });
    // The account was deleted while this ran: nothing is made, and it is the same plain refusal as any other token.
    if (stored.kind === "cut_off") throw new AppError("unauthenticated");
    if (stored.kind === "limit") {
      throw new AppError("quota_exceeded", { message: "This Doddy account is signed in on as many iPhones as it allows. Remove one in Doddy's settings, then try again." });
    }
    const ttl = this.options.ttlSeconds ?? DEVICE_SESSION_TTL_SECONDS;
    const token = this.signer.mintAccount(account, stored.id, now, ttl);
    this.options.log?.({ level: "info", event: "account_session", outcome: stored.how });
    return { token, expiresAt: new Date((issuedAt + ttl) * 1000).toISOString(), access: "full", deviceListId: stored.id };
  }

  /** The Doddy account behind a Supabase token, checked as the backend checks it for every account-bound request. Anything else: the plain 401. */
  private async accountOf(authorization: string | undefined, now: Date): Promise<string> {
    const account = await this.options.accounts.verify(authorization, now);
    const claims = jwtClaims(authorization);
    if (!account || !claims || claims.sub !== account.userId) throw new AppError("unauthenticated");
    // An account deleted a moment ago stops at once: a token dated before its cut-off second is refused (ADR-709).
    if (!Number.isSafeInteger(claims.iat) || (claims.iat as number) < (await this.floorOf(account.userId, now))) throw new AppError("unauthenticated");
    return account.userId;
  }

  private async floorOf(accountId: string, now: Date): Promise<number> {
    try {
      return await this.options.floors.floorOf(accountId, now.getTime());
    } catch {
      throw new AppError("provider_unavailable", { message: "Doddy couldn't check your sign-in right now. Try again shortly." });
    }
  }

  private async count(counter: string, period: string, limit: number, message: string): Promise<void> {
    if (!(await this.options.store.reserveUsage([{ counter, period, limit }], 1))) throw new AppError("rate_limited", { message, retryAfterSeconds: 3_600 });
  }
}

/**
 * The key of an account on an iPhone, stored as the row's `device_user_id`: an HMAC of the account and the device id with the
 * identifier key, shaped as a version-4 UUID like every other derived id. Without the key it can't be turned back into either,
 * so the device id is never stored. It is not the iPhone's own user id (`deviceUserId`): a different label, so the device-session
 * path and this one never meet in a row, and one iPhone has a row for each account that signs in on it.
 */
export function accountDeviceUserId(identifierKey: Buffer, accountId: string, deviceId: string): string {
  const bytes = createHmac("sha256", identifierKey).update(`doddy-account-device:v1:${accountId}:${deviceId}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}
