// Server-wide daily counts (ADR-673, migration 015): per feature and UTC day, with no account in them,
// so deleting an account can't give the server's day back. The per-account rows (assistant_usage,
// deals_usage, errand_usage) still go with the account.
import type pg from "pg";

export type CappedFeature = "assistant" | "deals" | "errands" | "call_recaps";
type Q = Pick<pg.PoolClient, "query">;

/** Today in UTC as the database counts it, or the day in parameter `n` (YYYY-MM-DD, for a fixed clock). */
const day = (n: number) => `COALESCE($${n}::date, (now() AT TIME ZONE 'utc')::date)`;

/**
 * Takes one of the day's server-wide slots for `feature`, or answers false when the cap is reached.
 * Call it inside the reservation's transaction: the row stays locked until that ends, so two requests
 * can't both take the last slot.
 */
export async function takeServerSlot(c: Q, feature: CappedFeature, cap: number, onDay?: string): Promise<boolean> {
  const { rowCount } = await c.query(
    `INSERT INTO server_daily_usage (feature, day, requests) VALUES ($1, ${day(3)}, 1)
     ON CONFLICT (feature, day) DO UPDATE SET requests = server_daily_usage.requests + 1
       WHERE server_daily_usage.requests < $2`,
    [feature, cap, onDay ?? null]);
  return rowCount === 1;
}

/** Gives back a slot taken earlier in the same transaction (a per-account cap refused afterwards). */
export async function returnServerSlot(c: Q, feature: CappedFeature, onDay?: string): Promise<void> {
  await c.query(
    `UPDATE server_daily_usage SET requests = requests - 1
     WHERE feature = $1 AND day = ${day(2)} AND requests > 0`,
    [feature, onDay ?? null]);
}
