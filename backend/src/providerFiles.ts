/**
 * Files Claude makes in its container at Anthropic (a deck, a Word file…) are owed a deletion once Doddy
 * has its own copy (research item 14). The deletion is a durable debt, the way Studio keeps its own
 * (`server/messaging/src/studio/worker.ts`, `tidyAnthropicFiles`): the file id is written down BEFORE the
 * first try, a try only counts when a read-back says the file is gone, a failure sets a backoff, and a
 * file that keeps failing is reported rather than forgotten.
 *
 * The queue holds an opaque provider file id and counters. No account, no name, no content; the id is
 * never logged. Failing to delete never fails the user's request.
 */

/** Tries a sweep makes per hour at most. */
export const FILE_SWEEP_BATCH = 20;
/** After this many failed tries a file is reported as stuck (it is still retried, at the slowest pace). */
export const FILE_STUCK_AFTER = 10;
/** Wait after the first failed try, doubling each time up to the cap. */
export const FILE_BACKOFF_BASE_MS = 60_000;
export const FILE_BACKOFF_CAP_MS = 6 * 60 * 60_000;

export interface ProviderFileBacklog {
  pending: number;
  stuck: number;
  /** Age of the oldest unconfirmed deletion, 0 when there is none. */
  oldestAgeMs: number;
}

export interface ProviderFileQueue {
  /** Writes the debt down (idempotent: a file already queued keeps its place and counters). */
  queue(ids: readonly string[], now: number): Promise<void>;
  /** The provider confirmed the file is gone: the debt is paid. */
  confirm(id: string): Promise<void>;
  /** A try didn't end in confirmation: count it and set the next try with backoff. `code` is a plain word. */
  failed(id: string, code: string, now: number): Promise<void>;
  /** Ids whose next try is due, oldest first. */
  due(now: number, limit: number): Promise<string[]>;
  backlog(stuckAfter: number, now: number): Promise<ProviderFileBacklog>;
}
