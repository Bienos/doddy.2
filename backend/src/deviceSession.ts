import { createHmac, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { SignedSessionVerifier } from "./auth.js";
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
 * The per-user and whole-service daily caps still apply. Development only (config refuses it in
 * production, where Supabase sign-in is the only way in).
 */

export const DEVICE_SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;

export type DeviceSignup = "off" | "first-device";

export const DeviceSessionRequest = z
  .object({
    deviceId: z.string().regex(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/),
    inviteCode: z.string().max(128).optional(),
  })
  .strict();

export interface DeviceSessionResponse {
  token: string;
  expiresAt: string;
}

/** The one store call device sessions need. */
export interface DeviceOwnerStore {
  claimDeviceOwner(userId: string, now: number): Promise<string>;
}

export class DeviceSessionIssuer {
  private readonly signer: SignedSessionVerifier;
  private readonly codes: Buffer[];

  constructor(
    private readonly key: Buffer,
    private readonly options: { signup: DeviceSignup; inviteCodes: readonly string[]; store: DeviceOwnerStore; ttlSeconds?: number },
  ) {
    if (options.signup === "off" && options.inviteCodes.length === 0) throw new Error("device sessions need first-device sign-up or an invite code");
    this.signer = new SignedSessionVerifier(key);
    // Compared as HMAC digests so every comparison is the same length (no length leak).
    this.codes = options.inviteCodes.map((code) => digest(code));
  }

  async issue(body: unknown, now: Date): Promise<DeviceSessionResponse> {
    const parsed = DeviceSessionRequest.safeParse(body);
    if (!parsed.success) throw new AppError("invalid_request");
    const userId = deviceUserId(this.key, parsed.data.deviceId.toLowerCase());
    const code = parsed.data.inviteCode?.trim() ?? "";
    if (code !== "" && this.codeMatches(code)) return this.mint(userId, now);
    if (this.options.signup === "first-device") {
      const owner = await this.options.store.claimDeviceOwner(userId, now.getTime());
      if (owner === userId) return this.mint(userId, now);
      throw new AppError("unauthenticated", { message: "This Doddy server already belongs to another iPhone." });
    }
    throw new AppError("unauthenticated", { message: code === "" ? "An invite code is needed." : "That invite code isn't valid." });
  }

  private codeMatches(code: string): boolean {
    const given = digest(code);
    let ok = false;
    for (const candidate of this.codes) ok = timingSafeEqual(candidate, given) || ok;
    return ok;
  }

  private mint(userId: string, now: Date): DeviceSessionResponse {
    const ttl = this.options.ttlSeconds ?? DEVICE_SESSION_TTL_SECONDS;
    const token = this.signer.mint(userId, now, ttl);
    const expiresAt = new Date(Math.floor(now.getTime() / 1000) * 1000 + ttl * 1000).toISOString();
    return { token, expiresAt };
  }
}

/**
 * Stable user ID for a device: HMAC of the device ID with the server's signing key, shaped as a
 * version-4 UUID so the rest of the server treats it like any other user. Without the key nobody
 * can link a user ID back to a device.
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
