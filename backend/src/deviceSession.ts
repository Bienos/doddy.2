import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { SignedSessionVerifier } from "./auth.js";
import { clientKey } from "./clientAddress.js";
import type { OwnerClaim } from "./config.js";
import { AppError } from "./errors.js";

/**
 * Device sessions for the beta (ADR-563).
 *
 * Why this exists: until 21 Oct 2026 the app could reach this server only with a session token the
 * owner minted by hand and pasted into Settings, because the app has no Supabase sign-in yet and
 * Sign in with Apple needs a paid Apple team. So web search and every online account answered
 * "not set up" on the phone and never left it (Render logs from 19 to 21 Oct show no
 * `/v1/tools/run` call at all).
 *
 * How it works: the app makes one random device ID (a UUID kept in its Keychain) and posts it. The
 * server derives a stable user ID from it with its signing key and returns an ordinary owner-format
 * session token (`ds1`), which the existing `SignedSessionVerifier` already accepts. The device ID
 * itself is never stored.
 *
 * Who may sign in (owner, 21 Oct: "just make it free for now, only me using it"):
 *  - `first-device`: the first device to sign in owns the server; every other device is refused.
 *    Nothing secret has to be built into the app, which matters because the repository is public.
 *  - an invite code from `DODDY_DEVICE_INVITE_CODES`, for a second device later.
 *  - `open` (ADR-587, owner 22 Oct: Ask Doddy "available for everyone using anthropic key"): the
 *    first device still owns the server, and every other iPhone gets a guest session that is good
 *    for Ask Doddy only (`scp: "ask"`). Guests never reach the owner's online accounts, web search
 *    or documents. New guest sessions are limited per network and per day, so nobody can mint
 *    endless accounts to multiply the per-user Ask cap; the service-wide Ask cap bounds the bill.
 * The per-user and whole-service daily caps still apply. Development only (config refuses it in
 * production, where Supabase sign-in is the only way in).
 *
 * Who may claim an EMPTY server (ADR-707): "the first device owns the server" is only safe while
 * the owner row cannot be empty by accident. A wiped or restored database, a changed DATABASE_URL,
 * or the minutes between the first deploy and the owner's first sign-in all leave it empty, and the
 * app cannot carry a secret to prove it is the owner (public repository). So `DODDY_OWNER_CLAIM`
 * decides: `open` (mock mode) lets the first caller claim as before; `closed` (live mode) lets
 * nobody, and the operator opens it by hand for the one sign-in that claims the server. A server
 * that already has an owner behaves the same either way.
 *
 * Invite codes (ADR-709): every try that brings a code is counted per client before the code is
 * looked at, and one code may mint only so many sessions a day and sign in only so many iPhones. A valid
 * code with no room left mints nothing more, but it does not lock anyone out: the sign-in goes on as if
 * no code had come (the owner is the owner, another iPhone is a guest or is refused), and only a server
 * that has no other way in tells the caller the code is full.
 */

export const DEVICE_SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;

export type DeviceSignup = "off" | "first-device" | "open";

/** New guest sessions (ADR-587): per client network per hour, and for the whole server per UTC day. */
export const GUEST_LIMITS = Object.freeze({ perClientPerHour: 20, servicePerDay: 1_000 });
export type GuestLimits = { perClientPerHour: number; servicePerDay: number };

/**
 * Invite codes (ADR-709). `triesPerClientPerHour`: tries that bring a code, right or wrong, per client
 * network. `sessionsPerCodePerDay`: sessions one valid code may mint per UTC day. `devicesPerCode`:
 * distinct iPhones one valid code may sign in.
 */
export const INVITE_LIMITS: InviteLimits = Object.freeze({ triesPerClientPerHour: 20, sessionsPerCodePerDay: 20, devicesPerCode: 5 });
export type InviteLimits = { triesPerClientPerHour: number; sessionsPerCodePerDay: number; devicesPerCode: number };

/** `owner_unclaimed` and `invite_code_full` are each logged at most this often per process, so a flood of sign-ins can't flood the log (ADR-707, ADR-709). */
export const OWNER_UNCLAIMED_LOG_EVERY_MS = 10 * 60_000;

export const DeviceSessionRequest = z
  .object({
    deviceId: z.string().regex(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/),
    inviteCode: z.string().max(128).optional(),
  })
  .strict();

export interface DeviceSessionResponse {
  token: string;
  expiresAt: string;
  /** `full`: the owner or an invited device. `ask`: a guest, Ask Doddy only (ADR-587). */
  access: "full" | "ask";
}

/** The store calls device sessions need. */
export interface DeviceOwnerStore {
  /**
   * The owner's user ID. With `allowClaim` the first caller becomes the owner (one atomic insert);
   * without it nothing is written and an empty server answers null (ADR-707).
   */
  claimDeviceOwner(userId: string, now: number, allowClaim: boolean): Promise<string | null>;
  /** ADR-819: the account this iPhone chose to use instead of its own (Google or Apple on the iPhone). */
  deviceJoin?(deviceUserId: string): Promise<{ user_id: string } | null>;
  reserveUsage(checks: readonly { counter: string; period: string; limit: number }[], units: number): Promise<boolean>;
  /** Tokens issued before this many seconds since 1970 no longer work for the user (ADR-709); 0: none. */
  tokenFloor(userId: string): Promise<number>;
  /** Counts one session of an invite code, atomically, against its per-day and per-iPhone caps (ADR-709). */
  useInviteCode(input: { codeId: string; userId: string; now: number; maxDevices: number; maxSessionsPerDay: number }): Promise<"ok" | "devices_full" | "day_full">;
}

export class DeviceSessionIssuer {
  private readonly signer: SignedSessionVerifier;
  private readonly codes: Buffer[];
  /** Per configured code, an ID for its counters: keyed with the server's secret, so it is not the code and can't be turned back into it. */
  private readonly codeIds: string[];
  private lastUnclaimedLog = Number.NEGATIVE_INFINITY;
  private lastFullLog = Number.NEGATIVE_INFINITY;

  constructor(
    private readonly key: Buffer,
    private readonly options: {
      signup: DeviceSignup;
      inviteCodes: readonly string[];
      store: DeviceOwnerStore;
      /**
       * May the first caller claim an empty server (ADR-707)? Config decides (closed in live mode)
       * and the server always passes it. Left out, it is `open`, the behaviour before ADR-707, for
       * tests and tools that build an issuer by hand; a test builds the real app to prove the wiring.
       */
      ownerClaim?: OwnerClaim;
      ttlSeconds?: number;
      guestLimits?: GuestLimits;
      inviteLimits?: InviteLimits;
      /** Operational log: names and counts only, never a device, a user or an address. */
      log?: (line: Record<string, unknown>) => void;
    },
  ) {
    if (options.signup === "off" && options.inviteCodes.length === 0) throw new Error("device sessions need first-device sign-up or an invite code");
    this.signer = new SignedSessionVerifier(key);
    // Compared as HMAC digests so every comparison is the same length (no length leak).
    this.codes = options.inviteCodes.map((code) => digest(code));
    this.codeIds = options.inviteCodes.map((code) => createHmac("sha256", key).update(`doddy-invite-id:v1:${code}`).digest("base64url").slice(0, 22));
  }

  /** `client`: the caller's address (see `clientAddress`), for the guest and invite limits. */
  async issue(body: unknown, now: Date, client = "unknown"): Promise<DeviceSessionResponse> {
    const parsed = DeviceSessionRequest.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");
    const userId = deviceUserId(this.key, parsed.data.deviceId.toLowerCase());
    // ADR-819: an iPhone that signed in to an account with Google or Apple keeps getting that account.
    const joined = await this.options.store.deviceJoin?.(userId);
    if (joined) return this.mint(joined.user_id, now);
    const code = parsed.data.inviteCode?.trim() ?? "";
    // A valid code that has no room left (ADR-709): what to say if nothing else lets this iPhone in.
    let full: AppError | null = null;
    if (code !== "") {
      // Counted before the code is looked at, right or wrong, so a burst of parallel guesses can't
      // get past the limit (ADR-709; the web sign-in does the same).
      await this.countInviteTry(now, client);
      const matched = this.matchingCode(code);
      if (matched !== null) {
        const session = await this.inviteSession(userId, now, matched);
        if (!(session instanceof AppError)) return session;
        full = session;
      }
    }
    if (this.options.signup === "first-device" || this.options.signup === "open") {
      const owner = await this.options.store.claimDeviceOwner(userId, now.getTime(), (this.options.ownerClaim ?? "open") === "open");
      if (owner === userId) return this.mint(userId, now);
      if (owner === null) {
        // A closed server with no owner yet (ADR-707): nobody is claimed, and the operator is told once in a while.
        this.logUnclaimed(now);
        if (this.options.signup === "open") return this.guest(userId, now, client);
        throw new AppError("unauthenticated", { message: "This Doddy server has no owner yet. The operator must open the owner claim." });
      }
      if (this.options.signup === "open") return this.guest(userId, now, client);
      throw full ?? new AppError("unauthenticated", { message: "This Doddy server already belongs to another iPhone." });
    }
    throw full ?? new AppError("unauthenticated", { message: code === "" ? "An invite code is needed." : "That invite code isn't valid." });
  }

  /** One line per `OWNER_UNCLAIMED_LOG_EVERY_MS`: what is wrong and what the operator does about it. No device, no user, no address. */
  private logUnclaimed(now: Date): void {
    const at = now.getTime();
    if (!this.options.log || at - this.lastUnclaimedLog < OWNER_UNCLAIMED_LOG_EVERY_MS) return;
    this.lastUnclaimedLog = at;
    this.options.log({
      level: "warn",
      event: "owner_unclaimed",
      ownerClaim: "closed",
      action: "This server has no owner. Set DODDY_OWNER_CLAIM=open, sign in once on the owner's iPhone, then remove the setting.",
    });
  }

  /** Said once in a while when a valid invite code has no room left: which limit, never which code or who. */
  private logFull(now: Date, limit: "iphones" | "sessions_today"): void {
    const at = now.getTime();
    if (!this.options.log || at - this.lastFullLog < OWNER_UNCLAIMED_LOG_EVERY_MS) return;
    this.lastFullLog = at;
    this.options.log({
      level: "warn",
      event: "invite_code_full",
      limit,
      action: "A valid invite code has no room left, so it signed nobody in. Raise DODDY_INVITE_DEVICES_PER_CODE or DODDY_INVITE_SESSIONS_PER_CODE_PER_DAY, or give out another code.",
    });
  }

  /** A guest's session: Ask Doddy only. Counted before it is made, atomically. */
  private async guest(userId: string, now: Date, client: string): Promise<DeviceSessionResponse> {
    const limits = this.options.guestLimits ?? GUEST_LIMITS;
    const iso = now.toISOString();
    const network = createHash("sha256").update(`guest-client:${clientKey(client)}`).digest("base64url");
    const allowed = await this.options.store.reserveUsage(
      [
        { counter: `guest_sessions:${network}`, period: `day:${iso.slice(0, 13)}`, limit: limits.perClientPerHour },
        { counter: "guest_sessions:service", period: `day:${iso.slice(0, 10)}`, limit: limits.servicePerDay },
      ],
      1,
    );
    if (!allowed) throw new AppError("rate_limited", { message: "Too many new sign-ins right now. Try again later.", retryAfterSeconds: 3_600 });
    return this.mint(userId, now, "ask");
  }

  /** This device's own user ID (ADR-819), or null for something that isn't a device ID. */
  userIdFor(deviceId: unknown): string | null {
    const parsed = DeviceSessionRequest.shape.deviceId.safeParse(deviceId);
    return parsed.success ? deviceUserId(this.key, parsed.data.toLowerCase()) : null;
  }

  /** One try with an invite code, per client network per hour (ADR-709). */
  private async countInviteTry(now: Date, client: string): Promise<void> {
    const limits = this.options.inviteLimits ?? INVITE_LIMITS;
    const network = createHash("sha256").update(`invite-client:${clientKey(client)}`).digest("base64url");
    const allowed = await this.options.store.reserveUsage(
      [{ counter: `invite_tries:${network}`, period: `day:${now.toISOString().slice(0, 13)}`, limit: limits.triesPerClientPerHour }],
      1,
    );
    if (!allowed) throw new AppError("rate_limited", { message: "Too many tries with an invite code. Try again later.", retryAfterSeconds: 3_600 });
  }

  /**
   * A valid code's session: full access, within the code's own caps (ADR-709). A code with no room left
   * answers with the error to give if nothing else lets this iPhone in; it is returned, not thrown, so
   * the owner and a guest are never turned away by someone else's use of the code.
   */
  private async inviteSession(userId: string, now: Date, codeIndex: number): Promise<DeviceSessionResponse | AppError> {
    const limits = this.options.inviteLimits ?? INVITE_LIMITS;
    const used = await this.options.store.useInviteCode({
      codeId: this.codeIds[codeIndex]!,
      userId,
      now: now.getTime(),
      maxDevices: limits.devicesPerCode,
      maxSessionsPerDay: limits.sessionsPerCodePerDay,
    });
    if (used === "devices_full") {
      this.logFull(now, "iphones");
      return new AppError("unauthenticated", { message: "This invite code is already in use on as many iPhones as it allows." });
    }
    if (used === "day_full") {
      this.logFull(now, "sessions_today");
      return new AppError("rate_limited", { message: "This invite code has been used too many times today. Try again tomorrow.", retryAfterSeconds: secondsToUtcMidnight(now) });
    }
    return this.mint(userId, now);
  }

  /**
   * Index of the configured code that matches, or null. Every code is compared every time, in constant
   * time, so neither the answer nor where the match sits shows in how long this takes.
   */
  private matchingCode(code: string): number | null {
    const given = digest(code);
    let matched: number | null = null;
    for (const [index, candidate] of this.codes.entries()) {
      if (timingSafeEqual(candidate, given)) matched = index;
    }
    return matched;
  }

  private async mint(userId: string, now: Date, scope?: "ask"): Promise<DeviceSessionResponse> {
    const ttl = this.options.ttlSeconds ?? DEVICE_SESSION_TTL_SECONDS;
    // A token is never dated before the moment this person's earlier tokens were cut off (ADR-709), so
    // signing in again right after deleting the account works even within the same second.
    const floor = await this.options.store.tokenFloor(userId);
    const issuedAt = new Date(Math.max(Math.floor(now.getTime() / 1000), floor) * 1000);
    const token = this.signer.mint(userId, issuedAt, ttl, scope);
    const expiresAt = new Date(issuedAt.getTime() + ttl * 1000).toISOString();
    return { token, expiresAt, access: scope ?? "full" };
  }
}

/**
 * Stable user ID for a device: HMAC of the device ID with the server's signing key, shaped as a
 * version-4 UUID so the rest of the server treats it like any other user. Without the key nobody
 * can link a user ID back to a device.
 *
 * Rotating the signing key changes every device's user ID: all tokens stop working (their
 * signatures no longer match) and the stored owner is a user ID that no iPhone produces any more.
 * That is how it has always worked and is unchanged by ADR-707 and ADR-709: after a rotation the
 * operator must clear the owner row by hand and open `DODDY_OWNER_CLAIM` for the owner's next sign-in.
 */
export function deviceUserId(key: Buffer, deviceId: string): string {
  const bytes = createHmac("sha256", key).update(`doddy-device:v1:${deviceId}`).digest().subarray(0, 16);
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

function digest(value: string): Buffer {
  return createHmac("sha256", "doddy-invite-compare").update(value).digest();
}

/** Whole seconds until the next UTC midnight (at least 1), for a limit that resets daily. */
function secondsToUtcMidnight(now: Date): number {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
}
