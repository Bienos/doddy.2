import { AppError } from "./errors.js";

/**
 * "Do this once": a repeated request with the same account and the same request id, inside a short
 * window, gets the first one's result instead of paying for another generation (research item 10).
 * Decision and trade-offs: docs/decisions/2026-11-09-ask-request-dedup.md.
 *
 *  - Held in this process's memory only, never in the database, because the result is the user's
 *    private answer. A restart or a second instance forgets it; the worst case is then the one
 *    duplicate generation that happens today.
 *  - Keyed by account AND request id, so two accounts can never meet, and bound to a fingerprint of
 *    what was asked: the same id with a different question is refused, never answered with the old
 *    answer.
 *  - Only a success is kept. A failure, a refusal or any outcome that isn't a plain result is dropped
 *    at once, so a retry with the same id runs again; an unknown outcome is never remembered as done.
 *  - A duplicate that arrives while the first is still running waits for it and shares its outcome
 *    (success or the same error); it does not start a second generation.
 *  - Short, small and bounded: a time limit, a total cap and a per-account cap.
 *  - `forgetUser` drops everything an account has here (account deletion).
 */

export interface OnceOptions {
  ttlMs: number;
  maxEntries: number;
  maxPerUser: number;
  now?: () => number;
}

export const ASK_DEDUP = Object.freeze({ ttlMs: 10 * 60_000, maxEntries: 500, maxPerUser: 10 });

interface Entry<T> {
  userId: string;
  fingerprint: string;
  promise: Promise<T>;
  state: "running" | "done";
  expiresAt: number;
}

export class RequestOnce<T> {
  private readonly entries = new Map<string, Entry<T>>();
  private readonly now: () => number;

  constructor(private readonly options: OnceOptions) {
    this.now = options.now ?? Date.now;
  }

  /** Runs `work` unless this account already has this request id; `replayed` says which happened. */
  async run(userId: string, requestId: string, fingerprint: string, work: () => Promise<T>): Promise<{ value: T; replayed: boolean }> {
    const key = `${userId}\u0000${requestId.toLowerCase()}`;
    this.purge();
    const existing = this.entries.get(key);
    if (existing) {
      if (existing.fingerprint !== fingerprint) {
        throw new AppError("invalid_request", { message: "That request id was already used for a different question." });
      }
      return { value: await existing.promise, replayed: true };
    }
    if (!this.makeRoom(userId)) return { value: await work(), replayed: false };

    const entry: Entry<T> = { userId, fingerprint, state: "running", expiresAt: Number.POSITIVE_INFINITY, promise: undefined as unknown as Promise<T> };
    entry.promise = work().then(
      (value) => {
        entry.state = "done";
        entry.expiresAt = this.now() + this.options.ttlMs;
        return value;
      },
      (error: unknown) => {
        // Not a success: nothing is remembered, so the next try runs for real.
        if (this.entries.get(key) === entry) this.entries.delete(key);
        throw error;
      },
    );
    this.entries.set(key, entry);
    return { value: await entry.promise, replayed: false };
  }

  forgetUser(userId: string): number {
    let n = 0;
    for (const [key, entry] of this.entries) {
      if (entry.userId === userId) {
        this.entries.delete(key);
        n++;
      }
    }
    return n;
  }

  get size(): number {
    return this.entries.size;
  }

  private purge(): void {
    const now = this.now();
    for (const [key, entry] of this.entries) if (entry.state === "done" && entry.expiresAt <= now) this.entries.delete(key);
  }

  /** Room for one more entry of this account by dropping the oldest finished ones; false when only running ones are left (then the request runs without being remembered). */
  private makeRoom(userId: string): boolean {
    const drop = (match: (e: Entry<T>) => boolean, limit: number): boolean => {
      let count = 0;
      for (const e of this.entries.values()) if (match(e)) count++;
      for (const [key, e] of this.entries) {
        if (count < limit) break;
        if (e.state === "done" && match(e)) {
          this.entries.delete(key);
          count--;
        }
      }
      return count < limit;
    };
    return drop((e) => e.userId === userId, this.options.maxPerUser) && drop(() => true, this.options.maxEntries);
  }
}
