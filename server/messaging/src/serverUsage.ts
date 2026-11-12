// Server-wide daily counts (ADR-673, migration 015): per feature and UTC day, with no account in them,
// so deleting an account can't give the server's day back. The per-account rows (assistant_usage,
// deals_usage, errand_usage) still go with the account.
import type pg from "pg";

/** Features with a server-wide cap. `accounts`, `sms` and `outbound_calls` are the abuse caps of ADR-702 and ADR-704;
 * `news` counts digests the AI writer is asked to write (migration 030). */
export type CappedFeature = "assistant" | "deals" | "errands" | "studio" | "news" | "accounts" | "sms" | "outbound_calls";
/** The part of a paid feature's cap that accounts still "new" share (ADR-702). Counted inside the feature's own total. */
export type NewAccountPool = "assistant_new" | "deals_new" | "errands_new" | "studio_new" | "news_new";
type Q = Pick<pg.PoolClient, "query"> | pg.Pool;

/** Today in UTC as the database counts it, or the day in parameter `n` (YYYY-MM-DD, for a fixed clock). */
const day = (n: number) => `COALESCE($${n}::date, (now() AT TIME ZONE 'utc')::date)`;

/**
 * Takes one of the day's server-wide slots for `feature`, or answers false when the cap is reached.
 * Call it inside the reservation's transaction: the row stays locked until that ends, so two requests
 * can't both take the last slot.
 */
export async function takeServerSlot(c: Q, feature: CappedFeature | NewAccountPool, cap: number, onDay?: string): Promise<boolean> {
  // The insert below always succeeds for the day's first slot, so a cap of 0 (a pool closed on purpose) is answered here.
  if (cap < 1) return false;
  const { rowCount } = await c.query(
    `INSERT INTO server_daily_usage (feature, day, requests) VALUES ($1, ${day(3)}, 1)
     ON CONFLICT (feature, day) DO UPDATE SET requests = server_daily_usage.requests + 1
       WHERE server_daily_usage.requests < $2`,
    [feature, cap, onDay ?? null]);
  return rowCount === 1;
}

/** Gives back a slot taken earlier in the same transaction (a per-account cap refused afterwards). */
export async function returnServerSlot(c: Q, feature: CappedFeature | NewAccountPool, onDay?: string): Promise<void> {
  await c.query(
    `UPDATE server_daily_usage SET requests = requests - 1
     WHERE feature = $1 AND day = ${day(2)} AND requests > 0`,
    [feature, onDay ?? null]);
}

// ---------- new accounts and established ones (ADR-702) ----------

/** Accounts cost nothing to make, so mass-made ones must not be able to use up a paid feature's whole day. */
export const DEFAULT_NEW_ACCOUNT_HOURS = 24;
/** Per UTC day, for all new accounts together, inside the feature's server-wide cap. */
// Studio (ADR-740) pays for a model, web searches and a code container for every job, so its pool is closed: 0.
// News: digests written by the AI writer (manual, scheduled and radar summaries); past a cap they are plain headlines.
export const DEFAULT_NEW_ACCOUNT_POOL = { assistant: 200, deals: 200, errands: 10, studio: 0, news: 50 } as const;

type PoolFeature = keyof typeof DEFAULT_NEW_ACCOUNT_POOL;

export interface ServerCaps {
  /** Everything the whole server may do per UTC day, new and established accounts together. */
  perServer: number;
  /** The most the new accounts together may use of that. Default DEFAULT_NEW_ACCOUNT_POOL. */
  newAccountPool?: number;
  /** An account is established with a verified phone number, or once it is this many hours old. Default 24. */
  newAccountHours?: number;
}

/** Established: a verified phone number, or older than `hours` (database clock). An account that isn't there is new. */
export async function isEstablished(c: Q, accountId: string, hours: number): Promise<boolean> {
  const { rows } = await c.query<{ established: boolean }>(
    `SELECT (EXISTS (SELECT 1 FROM phone_numbers p WHERE p.account_id = a.id)
             OR a.created_at <= now() - make_interval(hours => $2::int)) AS established
     FROM accounts a WHERE a.id = $1`, [accountId, hours]);
  return rows[0]?.established ?? false;
}

export type ServerSlots = { ok: true; giveBack(): Promise<void> } | { ok: false; reason: "server_cap" | "new_account_cap" };

/**
 * Takes the day's server-wide slot for a paid feature on behalf of one account. An established account draws from
 * the server's whole cap. A new account must first fit in the new-account pool (a slice of that same cap), so a
 * flood of freshly made accounts can use at most the pool and never the rest, which stays for everyone else.
 * Call it inside the reservation's transaction; if a later per-account cap refuses, call `giveBack()`.
 */
export async function takeServerSlots(c: Q, feature: PoolFeature, accountId: string, caps: ServerCaps, onDay?: string): Promise<ServerSlots> {
  const pool: NewAccountPool = `${feature}_new`;
  const isNew = !(await isEstablished(c, accountId, caps.newAccountHours ?? DEFAULT_NEW_ACCOUNT_HOURS));
  if (isNew && !(await takeServerSlot(c, pool, caps.newAccountPool ?? DEFAULT_NEW_ACCOUNT_POOL[feature], onDay))) {
    return { ok: false, reason: "new_account_cap" };
  }
  if (!(await takeServerSlot(c, feature, caps.perServer, onDay))) {
    if (isNew) await returnServerSlot(c, pool, onDay);
    return { ok: false, reason: "server_cap" };
  }
  return {
    ok: true,
    giveBack: async () => {
      await returnServerSlot(c, feature, onDay);
      if (isNew) await returnServerSlot(c, pool, onDay);
    },
  };
}
