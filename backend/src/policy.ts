import { createHash } from "node:crypto";
import type { CapabilityDefinition } from "./capabilities.js";
import type { Limits } from "./config.js";
import { AppError } from "./errors.js";
import type { Store } from "./store.js";

/** Canonical JSON (sorted keys) so the same arguments always produce the same digest. */
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export const argumentDigest = (args: unknown) => createHash("sha256").update(canonicalJson(args)).digest("hex");

/**
 * Confirmation foundation for future consequential capabilities. An approval is bound server-side
 * to user, capability, account, the validated-argument digest, an expiry and a single execution.
 * Changing any argument produces a different digest and the approval no longer matches.
 */
export class ConfirmationPolicy {
  constructor(
    private readonly store: Store,
    private readonly ttlSeconds = 120,
  ) {}

  /** Records that the user saw this exact preview. Returns the token the client sends back. */
  approve(input: { userId: string; capability: CapabilityDefinition; accountId: string; args: unknown; now: number }) {
    if (input.capability.confirmation !== "fresh_per_execution") throw new Error("capability does not take approvals");
    return this.store.createApproval({
      userId: input.userId,
      capability: input.capability.id,
      accountId: input.accountId,
      argsDigest: argumentDigest(input.args),
      now: input.now,
      ttlSeconds: this.ttlSeconds,
    });
  }

  /** Throws unless a matching, unexpired, unused approval exists; consumes it atomically. */
  require(input: {
    userId: string;
    capability: CapabilityDefinition;
    accountId: string;
    args: unknown;
    approvalId: string | undefined;
    now: number;
  }): void {
    if (input.capability.confirmation === "none") return;
    const ok =
      input.approvalId !== undefined &&
      this.store.consumeApproval({
        approvalId: input.approvalId,
        userId: input.userId,
        capability: input.capability.id,
        accountId: input.accountId,
        argsDigest: argumentDigest(input.args),
        now: input.now,
      });
    if (!ok) throw new AppError("capability_disabled", { message: "This action needs a fresh confirmation." });
  }
}

const day = (now: number) => new Date(now).toISOString().slice(0, 10);
const month = (now: number) => new Date(now).toISOString().slice(0, 7);

/**
 * Doddy's own ceilings (not provider quotas). Daily/monthly counters are durable (SQLite, UTC
 * periods) and reserved atomically before any provider call; each page and retry reserves again.
 * Concurrency is per process: this backend is designed to run as a single instance.
 */
export class UsageLimiter {
  private readonly active = new Map<string, number>();
  private serviceActive = 0;

  constructor(
    private readonly store: Store,
    private readonly limits: Limits,
  ) {}

  /** One provider-call unit for this user. Throws quota_exceeded without calling anyone. */
  reserveCall(userId: string, now: number): void {
    const ok = this.store.reserveUsage(
      [
        // A read may need up to maxPages pages, each with up to two retries — but one user may never
        // use more than a quarter of the service-wide daily allowance.
        {
          counter: `user:${userId}:calls`,
          period: `day:${day(now)}`,
          limit: Math.max(1, Math.min(this.limits.userDailyReads * this.limits.maxPages * 3, Math.floor(this.limits.serviceDailyCalls / 4))),
        },
        { counter: "service:calls", period: `day:${day(now)}`, limit: this.limits.serviceDailyCalls },
        { counter: "service:calls", period: `month:${month(now)}`, limit: this.limits.serviceMonthlyCalls },
      ],
      1,
    );
    if (!ok) throw new AppError("quota_exceeded");
  }

  /**
   * Any events request, counted before anything is written (including blocked receipts), so a
   * client looping on a refused request cannot grow the database without bound.
   */
  reserveRequest(userId: string, now: number): void {
    const ok = this.store.reserveUsage(
      [{ counter: `user:${userId}:requests`, period: `day:${day(now)}`, limit: this.limits.userDailyReads * 4 }],
      1,
    );
    if (!ok) throw new AppError("quota_exceeded");
  }

  /** One user-visible read request (counted separately from the provider calls it causes). */
  reserveRead(userId: string, now: number): void {
    const ok = this.store.reserveUsage(
      [{ counter: `user:${userId}:reads`, period: `day:${day(now)}`, limit: this.limits.userDailyReads }],
      1,
    );
    if (!ok) throw new AppError("quota_exceeded");
  }

  /** Per-user and service-wide concurrency for provider work. */
  async withSlot<T>(userId: string, fn: () => Promise<T>): Promise<T> {
    const mine = this.active.get(userId) ?? 0;
    if (mine >= this.limits.userConcurrency || this.serviceActive >= this.limits.serviceConcurrency) {
      throw new AppError("busy", { retryAfterSeconds: 2 });
    }
    this.active.set(userId, mine + 1);
    this.serviceActive += 1;
    try {
      return await fn();
    } finally {
      const left = (this.active.get(userId) ?? 1) - 1;
      if (left <= 0) this.active.delete(userId);
      else this.active.set(userId, left);
      this.serviceActive -= 1;
    }
  }
}
