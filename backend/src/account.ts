import { CLEANUP_RETRY, type QueuedCleanup, type Store, type UserErasure } from "./store.js";

/**
 * Deleting a Doddy account on the server (ADR-674): everything this backend keeps for the person
 * goes in one transaction (`Store.eraseUser`), then every online account they connected is removed
 * at the provider. The answer says exactly what happened: a removal that failed, or whose outcome
 * isn't known, is `pending`, never done, and stays queued for the hourly sweeps to retry.
 */

/** Removes one connection at the provider that made it (Composio for the calendar, or for the tools). */
export interface ConnectionRemover {
  /** The `provider` values of `connections` rows this remover handles (`google_calendar`, `gmail`, …). */
  providers: readonly string[];
  remove(connectionId: string, signal: AbortSignal): Promise<"removed" | "failed">;
}

export interface AccountErasure {
  /** True only when no row of the person was left and every online account was removed at its provider. */
  complete: boolean;
  /** Rows deleted per table (zeros included, so the list shows what was looked at). */
  deleted: UserErasure["deleted"];
  /** Rows of the person still found after the delete (0 unless something is wrong). */
  remaining: number;
  /** Online accounts, by kind (`gmail`, `google_calendar`, …): removed at the provider, or still owed. */
  onlineAccounts: { removed: string[]; pending: string[] };
  /** What the server keeps on purpose, in words (`KEPT_ON_ERASE` and the counters). */
  kept: string[];
  erasedAt: string;
}

export const KEPT_EXPLAINED = [
  "Which iPhone this server belongs to, so no one else can claim it.",
  "Counts of use per day and month (numbers only), until their period ends, so deleting can't reset a daily limit.",
  "Removals still owed at an online account's provider, until the provider confirms them.",
] as const;

export class AccountEraser {
  constructor(
    private readonly deps: {
      store: Store;
      removers: readonly ConnectionRemover[];
      timeoutMs: number;
      now?: () => number;
      log?: (line: Record<string, unknown>) => void;
    },
  ) {}

  async erase(userId: string): Promise<AccountErasure> {
    const now = this.deps.now?.() ?? Date.now();
    const erased = await this.deps.store.eraseUser(userId, now);
    const removed: string[] = [];
    const pending: string[] = [];
    for (const cleanup of erased.cleanups) {
      if ((await this.remove(cleanup)) === "removed") removed.push(cleanup.provider);
      else pending.push(cleanup.provider);
    }
    const complete = erased.remaining === 0 && pending.length === 0;
    // Content-free: counts and the outcome only, never the user ID or a provider ID.
    this.deps.log?.({
      level: "info",
      event: "account_erased",
      complete,
      rows: Object.values(erased.deleted).reduce((a, b) => a + b, 0),
      remaining: erased.remaining,
      removed: removed.length,
      pending: pending.length,
    });
    return {
      complete,
      deleted: erased.deleted,
      remaining: erased.remaining,
      onlineAccounts: { removed, pending },
      kept: [...KEPT_EXPLAINED],
      erasedAt: new Date(now).toISOString(),
    };
  }

  /**
   * Hourly (app.ts): retries removals owed after a deletion for `providers` that have no sweep of
   * their own (ADR-700: a person's Supabase sign-in). Same rules as the other sweeps (CLEANUP_RETRY).
   */
  async sweep(providers: readonly string[]): Promise<void> {
    const now = this.deps.now?.() ?? Date.now();
    const due = await this.deps.store.cleanupsToRetry([...providers], now - CLEANUP_RETRY.afterMs, CLEANUP_RETRY.maxTries, CLEANUP_RETRY.perSweep);
    for (const cleanup of due) await this.remove(cleanup);
  }

  /** Removed and dequeued, or kept as `failed` for the sweep. A provider with no remover here stays queued. */
  private async remove(cleanup: QueuedCleanup): Promise<"removed" | "failed"> {
    const remover = this.deps.removers.find((r) => r.providers.includes(cleanup.provider));
    if (!remover) return "failed";
    let result: "removed" | "failed";
    try {
      result = await remover.remove(cleanup.connectionId, AbortSignal.timeout(this.deps.timeoutMs));
    } catch {
      result = "failed";
    }
    if (result === "removed") await this.deps.store.finishCleanup(cleanup.connectionId);
    else await this.deps.store.failCleanup(cleanup.connectionId, "remote_cleanup_failed");
    return result;
  }
}
