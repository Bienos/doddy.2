// The daily caps behind the leaflet search (SHOPPING.md §2). Counts per account and UTC day, nothing else:
// no item, page or offer is stored. A request is reserved before anything is fetched, so a flood can't spend
// more than the caps, and an attempt that fails still counts (the caps bound spend, not success).
import { inTransaction, type Db } from "../db.js";
import { returnServerSlot, takeServerSlot } from "../serverUsage.js";

export type Reservation = "ok" | "account_cap" | "server_cap";

/**
 * Reserves one request for the account today against both caps, or says which cap stopped it. The
 * server's count lives in server_daily_usage (ADR-673), so deleting an account doesn't give it back;
 * its row stays locked until the transaction ends, so both caps are exact.
 */
export async function reserve(db: Db, accountId: string, caps: { perAccount: number; perServer: number }): Promise<Reservation> {
  return inTransaction(db, async (c) => {
    if (!(await takeServerSlot(c, "deals", caps.perServer))) return "server_cap";
    const { rowCount } = await c.query(
      `INSERT INTO deals_usage (account_id, day, requests) VALUES ($1, (now() AT TIME ZONE 'utc')::date, 1)
       ON CONFLICT (account_id, day) DO UPDATE SET requests = deals_usage.requests + 1
         WHERE deals_usage.requests < $2`, [accountId, caps.perAccount]);
    if (rowCount === 1) return "ok";
    await returnServerSlot(c, "deals");
    return "account_cap";
  });
}

/** Adds what a search spent (pages sent to the reader, tokens the model reported) to today's row. */
export async function addUsage(db: Db, accountId: string, spent: { pagesRead: number; inputTokens: number; outputTokens: number }): Promise<void> {
  const n = (v: number) => Math.max(0, Math.trunc(v));
  await db.query(
    `UPDATE deals_usage SET pages_read = pages_read + $2, input_tokens = input_tokens + $3, output_tokens = output_tokens + $4
     WHERE account_id = $1 AND day = (now() AT TIME ZONE 'utc')::date`,
    [accountId, n(spent.pagesRead), n(spent.inputTokens), n(spent.outputTokens)]);
}
