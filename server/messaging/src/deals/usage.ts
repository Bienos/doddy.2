// The daily caps behind the leaflet search (SHOPPING.md §2). Counts per account and UTC day, nothing else:
// no item, page or offer is stored. A request is reserved before anything is fetched, so a flood can't spend
// more than the caps, and an attempt that fails still counts (the caps bound spend, not success).
import { inTransaction, type Db } from "../db.js";

export type Reservation = "ok" | "account_cap" | "server_cap";

/** One lock for every reservation: the check and the count happen together, so both caps are exact. */
const RESERVE_LOCK = 4242012;

/** Reserves one request for the account today against both caps, or says which cap stopped it. */
export async function reserve(db: Db, accountId: string, caps: { perAccount: number; perServer: number }): Promise<Reservation> {
  return inTransaction(db, async (c) => {
    await c.query("SELECT pg_advisory_xact_lock($1)", [RESERVE_LOCK]);
    const { rows } = await c.query<{ total: string; mine: string }>(
      `SELECT COALESCE(SUM(requests), 0) AS total,
              COALESCE(SUM(requests) FILTER (WHERE account_id = $1), 0) AS mine
       FROM deals_usage WHERE day = (now() AT TIME ZONE 'utc')::date`, [accountId]);
    if (Number(rows[0]!.total) >= caps.perServer) return "server_cap";
    if (Number(rows[0]!.mine) >= caps.perAccount) return "account_cap";
    await c.query(
      `INSERT INTO deals_usage (account_id, day, requests) VALUES ($1, (now() AT TIME ZONE 'utc')::date, 1)
       ON CONFLICT (account_id, day) DO UPDATE SET requests = deals_usage.requests + 1`, [accountId]);
    return "ok";
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
