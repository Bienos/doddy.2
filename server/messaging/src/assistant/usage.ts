// The daily caps behind Messages (ADR-586). Counts per account and UTC day, nothing else: no question,
// answer or note is stored. A request is counted before the model is called, so a flood cannot spend
// more than the cap, and an attempt that fails still counts (the cap bounds spend, not success).
import { inTransaction, type Db } from "../db.js";
import { returnServerSlot, takeServerSlot } from "../serverUsage.js";

export type Reservation = "ok" | "account_cap" | "server_cap";

/**
 * Reserves one request for the account today, or says which cap stopped it. The server's count lives
 * in server_daily_usage (ADR-673), so deleting an account doesn't give it back; its row stays locked
 * until the transaction ends, so both caps are exact.
 */
export async function reserve(db: Db, accountId: string, caps: { perAccount: number; perServer: number }): Promise<Reservation> {
  return inTransaction(db, async (c) => {
    if (!(await takeServerSlot(c, "assistant", caps.perServer))) return "server_cap";
    const { rowCount } = await c.query(
      `INSERT INTO assistant_usage (account_id, day, requests) VALUES ($1, (now() AT TIME ZONE 'utc')::date, 1)
       ON CONFLICT (account_id, day) DO UPDATE SET requests = assistant_usage.requests + 1
         WHERE assistant_usage.requests < $2`,
      [accountId, caps.perAccount]);
    if (rowCount === 1) return "ok";
    await returnServerSlot(c, "assistant");
    return "account_cap";
  });
}

/** Adds what the model reported to today's row. */
export async function addTokens(db: Db, accountId: string, usage: { inputTokens: number; outputTokens: number }): Promise<void> {
  await db.query(
    `UPDATE assistant_usage SET input_tokens = input_tokens + $2, output_tokens = output_tokens + $3
     WHERE account_id = $1 AND day = (now() AT TIME ZONE 'utc')::date`,
    [accountId, Math.max(0, Math.trunc(usage.inputTokens)), Math.max(0, Math.trunc(usage.outputTokens))]);
}
