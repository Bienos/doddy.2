// Daily caps on digests the AI writer writes (manual "send me one now", the scheduled digest and On my radar's daily
// summary), the same way Messages caps its requests (src/assistant/usage.ts): per account, for the whole server, and a
// smaller pool that accounts still new share inside the server's cap (ADR-702). A digest is counted before the writer
// is asked, so a flood cannot spend more than the caps, and a failed write still counts. Past a cap the digest is still
// built, from plain headlines, as when the writer is unavailable. Counts only: no story, topic or account id is stored
// (the per-account row is keyed by a hash of the account id, like the per-account text count, and pruned after 2 days).
import { sha256 } from "../crypto.js";
import { takeCounter } from "../dailyCounters.js";
import { inTransaction, type Db } from "../db.js";
import { DEFAULT_NEW_ACCOUNT_HOURS, DEFAULT_NEW_ACCOUNT_POOL, takeServerSlots } from "../serverUsage.js";

export interface NewsWriterCaps {
  /** Digests the writer may write for one account per UTC day. */
  perAccount: number;
  /** For the whole server per UTC day, new and established accounts together. */
  perServer: number;
  /** What accounts still new may use together per UTC day, inside perServer. Absent: DEFAULT_NEW_ACCOUNT_POOL.news. */
  newAccountPool?: number;
  /** An account is established with a verified phone number or once it is this many hours old. Absent: 24. */
  newAccountHours?: number;
}

/** Conservative: one scheduled digest and a few more a day per account. Each can be set (`NEWS_WRITER_DAILY_*`). */
export const DEFAULT_NEWS_WRITER_CAPS: Required<NewsWriterCaps> = {
  perAccount: 5, perServer: 500, newAccountPool: DEFAULT_NEW_ACCOUNT_POOL.news, newAccountHours: DEFAULT_NEW_ACCOUNT_HOURS,
};

export type WriterReservation = "ok" | "account_cap" | "server_cap" | "new_account_cap";

/** The UTC day of `now` (YYYY-MM-DD): a scheduled digest counts on the day it is built for. */
const utcDay = (now: Date) => now.toISOString().slice(0, 10);

/**
 * Reserves one digest by the writer for the account on `now`'s UTC day, or says which cap stopped it. The server's
 * counts live in server_daily_usage and the account's in daily_counters, neither tied to the account, so deleting it
 * gives nothing back (ADR-673). Both rows stay locked until the transaction ends, so every cap is exact.
 */
export async function reserveWriter(db: Db, accountId: string, caps: NewsWriterCaps | undefined, now: Date): Promise<WriterReservation> {
  const limits = { ...DEFAULT_NEWS_WRITER_CAPS, ...caps };
  const day = utcDay(now);
  return inTransaction(db, async (c) => {
    const slots = await takeServerSlots(c, "news", accountId,
      { perServer: limits.perServer, newAccountPool: limits.newAccountPool, newAccountHours: limits.newAccountHours }, day);
    if (!slots.ok) return slots.reason;
    // An account id is a random uuid: a plain hash is enough (as for the per-account text count).
    if (await takeCounter(c, "news_account", sha256(accountId).toString("hex"), limits.perAccount, day)) return "ok";
    await slots.giveBack();
    return "account_cap";
  });
}
