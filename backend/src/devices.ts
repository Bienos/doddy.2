import { randomUUID } from "node:crypto";
import { type AuthenticatedUser, type DeviceTokenGate, TokenFloors } from "./auth.js";
import { AppError } from "./errors.js";
import type { AccountDeviceRegistration, AccountDeviceResult, DeviceListRow, DeviceStateRow, Store } from "./store.js";
import type { DeviceView } from "./web/contracts.js";

/**
 * Stored iPhones: a list, a revoke, and joins that expire (decision 2026-11-12-account-and-device-tokens, part c).
 *
 * What is kept. Each iPhone that signs in with its device id (`POST /v1/session/device`, ADR-563) has one row in `devices`:
 * a random id, its own user id, when it was first and last seen, and when it was revoked. Nothing else: no token, no hash
 * of one, no content. The account it uses is not copied into the row, so there is one place for it: the iPhone's join
 * (`device_joins`, ADR-819) while that join is on, else its own user id. A person sees and revokes the iPhones that use
 * their account, and only those.
 *
 * How a token finds its iPhone. A device token made for a stored iPhone carries that row's id in a signed claim (`dev`,
 * `auth.ts`); how the token is signed is unchanged. `RevocableSessionVerifier` asks `allows` on every request, which is how a
 * revoke ends one iPhone's tokens and no one else's, the way the cut-off ends a whole person's (ADR-709):
 *  - a token of an iPhone that is revoked, or whose row is gone, is refused;
 *  - a token of an account the iPhone joined is refused once that join has ended: left, unlinked, its account erased, or
 *    not renewed within `joinMs` (DODDY_DEVICE_JOIN_DAYS, 90). A token for the iPhone's own account is not affected by a join;
 *  - a token that names no iPhone (made before iPhones were stored, 30 days at most) can't be tied to one, so it is ended
 *    by the account's `device_cutoffs` second, written by a revoke and by an unlink that ended joins: the iPhones on that
 *    account that were not revoked sign in again by themselves and get a token that names them. This part can go once no
 *    such token can be alive (30 days after the first deploy).
 *
 * The rule for a revoked iPhone. A revoke is final for the device-session path: `POST /v1/session/device` refuses it, with
 * a plain message, however often it asks, and no route clears it. A person brings the iPhone back by signing in on it with
 * the account's own Apple or Google sign-in, which is a different token that names no iPhone, so nothing here stands in
 * its way. What is not allowed is the quiet way back: the app's automatic renewal with the device id.
 *
 * An iPhone's account session (`POST /v1/session/account`, decision 2026-11-12-one-token-per-server) is a row here too, with
 * the account it is for (`account_id`) and a key derived from the account and the device id together as its `device_user_id`,
 * so the device-session rule above never applies to it and it never shares a row with it. Its token names the row (`dev`) and
 * the account (`acc`, `sub`); `allows` accepts it only on a live row of that account. A revoke (the list's, or the iPhone's
 * own sign-out, which is the same call) marks the row, and the very next request is refused. The way back is the exchange with
 * a fresh Supabase token of the account: it gives the row a NEW id, so no token made before the revoke comes back with it.
 *
 * A join that has ended sends the iPhone back to its own account at its next sign-in, as Leave does (ADR-819). It is made
 * again by signing in with the same Apple or Google (`POST /v1/web/oauth/join`), which renews it, and only while that
 * sign-in is still linked to the account.
 *
 * What each call remembers: an iPhone's state for 30 seconds, and every change this instance makes (a revoke, a join made or
 * ended, an account erased) clears it at once (`Store.onDevicesChanged`), so a change counts on the very next request here.
 */

export const DAY_MS = 86_400_000;
/** How long a join lasts unless the iPhone signs in with the same Apple or Google again (DODDY_DEVICE_JOIN_DAYS). */
export const DEVICE_JOIN_DAYS = 90;
/** An iPhone's last-seen time is written at most this often. */
export const DEVICE_SEEN_EVERY_MS = 3_600_000;
/** An iPhone not seen for this long, and never revoked, is dropped (its tokens last 30 days and its join 90). */
export const DEVICE_KEPT_DAYS = 180;

const STATE_REMEMBERED_MS = 30_000;
const MAX_STATES_REMEMBERED = 10_000;
const MAX_DEVICES_LISTED = 100;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** What a device sign-in (`deviceSession.ts`) needs from the stored iPhones. */
export interface DeviceSignIns {
  /** Throws when this iPhone (its own user id) was revoked. */
  assertNotRevoked(deviceUserId: string): Promise<void>;
  /** Stores or finds the iPhone's row, notes it as seen, and returns the row's id for the token. Throws when it was revoked. */
  signedIn(deviceUserId: string, nowMs: number): Promise<string>;
}

const removed = () =>
  new AppError("unauthenticated", { message: "This iPhone was removed from the Doddy account. Sign in with Apple or Google on it to use Doddy again." });

export class DeviceRegistry implements DeviceSignIns, DeviceTokenGate {
  readonly joinMs: number;
  private readonly states = new Map<string, { state: DeviceStateRow | null; at: number }>();
  private readonly cutoffs: TokenFloors;
  private lastSeenWarning = Number.NEGATIVE_INFINITY;

  constructor(
    private readonly store: Store,
    private readonly options: {
      /** DODDY_DEVICE_JOIN_DAYS in milliseconds. */
      joinMs?: number;
      /** Operational log: a word for what happened, never an id, a token or an account. */
      log?: (line: Record<string, unknown>) => void;
    } = {},
  ) {
    this.joinMs = options.joinMs ?? DEVICE_JOIN_DAYS * DAY_MS;
    this.cutoffs = new TokenFloors({ tokenFloor: (userId) => store.deviceCutoff(userId) });
    store.onDevicesChanged((change) => {
      this.states.clear();
      for (const cutoff of change.cutoffs) this.cutoffs.remember(cutoff.userId, cutoff.validAfter);
    });
  }

  // ------------------------------------------------------------ signing in

  async assertNotRevoked(deviceUserId: string): Promise<void> {
    if (await this.store.isDeviceRevoked(deviceUserId)) throw removed();
  }

  async signedIn(deviceUserId: string, nowMs: number): Promise<string> {
    const id = await this.store.registerDevice(deviceUserId, nowMs, randomUUID());
    if (id === null) throw removed();
    this.states.delete(id);
    return id;
  }

  /**
   * An iPhone signs in with the Doddy account's token (`POST /v1/session/account`, `accountSession.ts`). The answer is what the
   * store wrote and read back in one transaction: the row's id, how it came to be (`new`, `renewed`, or `returned`: a revoked
   * iPhone signing in again with the account's fresh token, which gets a new id), or why there is none (`limit`, `cut_off`).
   */
  accountSignedIn(input: Omit<AccountDeviceRegistration, "id">): Promise<AccountDeviceResult> {
    return this.store.registerAccountDevice({ ...input, id: randomUUID() });
  }

  // ------------------------------------------------------------ every request

  async allows(user: AuthenticatedUser, issuedAt: number, nowMs: number): Promise<boolean> {
    // Made before iPhones were stored: tied to no iPhone, so only the account's cut-off can end it.
    if (user.deviceId === undefined) return issuedAt >= (await this.cutoffs.floorOf(user.userId, nowMs));
    const state = await this.stateOf(user.deviceId, nowMs);
    if (!state || state.revoked_at !== null) return false;
    if (user.account !== undefined) {
      // An account session is good only on the row this account signed in with an account session. A device token never
      // names such a row, and an account session never names a device-session row or another account's.
      if (state.account_id !== user.account) return false;
    } else if (state.account_id !== null) {
      return false;
    } else if (user.userId !== state.device_user_id) {
      // A token of a joined account is good only while that iPhone's join to that account is on.
      const on = state.join_user_id === user.userId && state.join_renewed_at !== null && Number(state.join_renewed_at) > nowMs - this.joinMs;
      if (!on) return false;
    }
    await this.noteSeen(user.deviceId, state, nowMs);
    return true;
  }

  private async stateOf(deviceId: string, nowMs: number): Promise<DeviceStateRow | null> {
    const hit = this.states.get(deviceId);
    if (hit && nowMs >= hit.at && nowMs - hit.at < STATE_REMEMBERED_MS) return hit.state;
    const state = await this.store.deviceState(deviceId);
    this.remember(deviceId, state, nowMs);
    return state;
  }

  private remember(deviceId: string, state: DeviceStateRow | null, at: number): void {
    this.states.delete(deviceId);
    if (this.states.size >= MAX_STATES_REMEMBERED) {
      const oldest = this.states.keys().next();
      if (!oldest.done) this.states.delete(oldest.value);
    }
    this.states.set(deviceId, { state, at });
  }

  /** Last seen, written at most once an hour per iPhone. A note that can't be written never fails the request. */
  private async noteSeen(deviceId: string, state: DeviceStateRow, nowMs: number): Promise<void> {
    if (nowMs - state.last_seen_at < DEVICE_SEEN_EVERY_MS) return;
    try {
      await this.store.touchDevice(deviceId, nowMs, DEVICE_SEEN_EVERY_MS);
    } catch {
      // Tried again by the next request that reads the state afresh. Said in the log, rarely, so it can't go unseen for good.
      if (this.options.log && nowMs - this.lastSeenWarning >= 600_000) {
        this.lastSeenWarning = nowMs;
        this.options.log({ level: "warn", event: "device_seen_failed" });
      }
    }
    const hit = this.states.get(deviceId);
    this.remember(deviceId, { ...state, last_seen_at: nowMs }, hit?.at ?? nowMs);
  }

  // ------------------------------------------------------------ the list and the revoke

  /** The iPhones that use `accountId` now, oldest first. `thisDeviceId`: the row of the iPhone asking, if it is one. */
  async list(accountId: string, thisDeviceId: string | null, now: Date): Promise<DeviceView[]> {
    const rows = await this.store.listDevices(accountId, now.getTime() - this.joinMs, MAX_DEVICES_LISTED);
    return rows.map((row) => this.view(row, thisDeviceId));
  }

  /**
   * Revokes one iPhone of the account asking. The answer is made from what the store read back after the write: if the store
   * didn't confirm it, this throws and nobody is told it was done (DOD-08). Unknown and foreign ids are both `not_found`.
   */
  async revoke(accountId: string, deviceId: string, now: Date): Promise<{ revoked: true; revokedAt: string }> {
    if (!UUID.test(deviceId)) throw new AppError("not_found");
    const at = await this.store.revokeDevice(accountId, deviceId, now.getTime() - this.joinMs, now.getTime());
    if (at === null) throw new AppError("not_found");
    this.options.log?.({ level: "info", event: "device_revoked" });
    return { revoked: true, revokedAt: new Date(at).toISOString() };
  }

  private view(row: DeviceListRow, thisDeviceId: string | null): DeviceView {
    const joined =
      row.join_provider !== null && row.join_created_at !== null && row.join_renewed_at !== null
        ? {
            provider: row.join_provider === "apple" ? ("apple" as const) : ("google" as const),
            since: new Date(Number(row.join_created_at)).toISOString(),
            expiresAt: new Date(Number(row.join_renewed_at) + this.joinMs).toISOString(),
          }
        : null;
    return {
      id: row.device_id,
      label: null,
      firstSeenAt: new Date(row.first_seen_at).toISOString(),
      lastSeenAt: new Date(row.last_seen_at).toISOString(),
      current: row.device_id === thisDeviceId,
      joined,
      revokedAt: row.revoked_at === null ? null : new Date(row.revoked_at).toISOString(),
    };
  }
}
