/**
 * How long a device token of a Doddy account lives (decision 2026-11-12-account-and-device-tokens, part d).
 *
 * A token runs out when its iPhone has not used it for `idleDays`, or `maxAgeDays` after it was issued (a rotation issues a
 * new one), whichever comes first. A rotation (`POST /v1/accounts/sign-in` with the current token) keeps the token it replaced
 * working for `overlapSeconds`, so an answer that never arrived does not sign the iPhone out.
 *
 * Only tokens of a Doddy account (`accounts.auth_subject` set) run out. An anonymous account's token is its only way in, and
 * `ANONYMOUS_ACCOUNTS` is off, so no new ones are made.
 */
export interface DeviceTokenPolicy {
  /** DEVICE_TOKEN_EXPIRY: false stops tokens running out (the clocks are still kept, so switching it on later is exact). */
  enforce: boolean;
  /** DEVICE_TOKEN_IDLE_DAYS: unseen for this long and the token is refused. */
  idleDays: number;
  /** DEVICE_TOKEN_MAX_AGE_DAYS: this long after it was issued the token is refused, however recently it was used. */
  maxAgeDays: number;
  /** DEVICE_TOKEN_OVERLAP_SECONDS: how long a replaced token still works. */
  overlapSeconds: number;
}

export const DEFAULT_DEVICE_TOKEN_POLICY: DeviceTokenPolicy = { enforce: true, idleDays: 60, maxAgeDays: 180, overlapSeconds: 300 };

/** The defaults with whatever a deployment (or a test) sets over them. */
export function deviceTokenPolicy(over: Partial<DeviceTokenPolicy> = {}): DeviceTokenPolicy {
  const d = DEFAULT_DEVICE_TOKEN_POLICY;
  return {
    enforce: over.enforce ?? d.enforce, idleDays: over.idleDays ?? d.idleDays,
    maxAgeDays: over.maxAgeDays ?? d.maxAgeDays, overlapSeconds: over.overlapSeconds ?? d.overlapSeconds,
  };
}

export const DAY_SECONDS = 86_400;

/** When a token issued at `issuedAt` stops working however it is used, as the sign-in tells the iPhone; null while nothing expires. */
export function expiresAt(policy: DeviceTokenPolicy, issuedAt: Date): string | null {
  return policy.enforce ? new Date(issuedAt.getTime() + policy.maxAgeDays * DAY_SECONDS * 1000).toISOString() : null;
}
