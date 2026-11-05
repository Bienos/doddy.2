// The daily caps behind Messages (ADR-586). Counts per account and UTC day, nothing else: no question,
// answer or note is stored. A request is counted before the model is called, so a flood cannot spend
// more than the cap, and an attempt that fails still counts (the cap bounds spend, not success).
import { inTransaction, type Db } from "../db.js";
import { takeServerSlots, type ServerCaps } from "../serverUsage.js";

export type Reservation = "ok" | "account_cap" | "server_cap" | "new_account_cap";

/**
 * Reserves one request for the account today, or says which cap stopped it. The server's count lives
 * in server_daily_usage (ADR-673), so deleting an account doesn't give it back; its row stays locked
 * until the transaction ends, so both caps are exact. An account that is still new (no verified phone
 * number, not a day old) draws from the new-account pool too and so can't use more than the pool (ADR-702).
 */
export async function reserve(db: Db, accountId: string, caps: ServerCaps & { perAccount: number }): Promise<Reservation> {
  return inTransaction(db, async (c) => {
    const slots = await takeServerSlots(c, "assistant", accountId, caps);
    if (!slots.ok) return slots.reason;
    const { rowCount } = await c.query(
      `INSERT INTO assistant_usage (account_id, day, requests) VALUES ($1, (now() AT TIME ZONE 'utc')::date, 1)
       ON CONFLICT (account_id, day) DO UPDATE SET requests = assistant_usage.requests + 1
         WHERE assistant_usage.requests < $2`,
      [accountId, caps.perAccount]);
    if (rowCount === 1) return "ok";
    await slots.giveBack();
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
