// Daily counts kept per key (a client address, an account), next to the server-wide ones in serverUsage.ts
// (security review 4 Nov 2026, ADR-702, ADR-704). Only a keyed hash of the address or account is stored, never the
// address, and the rows are pruned after three days. Nothing here holds content.
import type pg from "pg";
import { keyedDigest } from "./crypto.js";

type Q = Pick<pg.PoolClient, "query"> | pg.Pool;

/** `news_account`: digests the AI writer is asked to write per account (migration 030). `news_summary_account`: the
 * story summaries one account asks for in On my radar (migration 038). */
export type CounterScope = "signup_ip" | "sms_account" | "news_account" | "news_summary_account";

/** The day in parameter `n` (YYYY-MM-DD, for a fixed clock) or today in UTC as the database counts it. */
const day = (n: number) => `COALESCE($${n}::date, (now() AT TIME ZONE 'utc')::date)`;

/**
 * Takes one slot of the key's count for the UTC day, or answers false when `cap` is reached. One statement, so
 * parallel requests cannot both take the last slot; inside a transaction the row stays locked until it ends.
 */
export async function takeCounter(c: Q, scope: CounterScope, key: string, cap: number, onDay?: string): Promise<boolean> {
  if (cap < 1) return false; // the first insert of a day would otherwise pass a cap of 0
  const { rowCount } = await c.query(
    `INSERT INTO daily_counters (scope, key, day, n) VALUES ($1, $2, ${day(4)}, 1)
     ON CONFLICT (scope, key, day) DO UPDATE SET n = daily_counters.n + 1
       WHERE daily_counters.n < $3`,
    [scope, key, cap, onDay ?? null]);
  return rowCount === 1;
}

/** Gives back a slot taken earlier (a later cap refused, or nothing was queued after all). */
export async function returnCounter(c: Q, scope: CounterScope, key: string, onDay?: string): Promise<void> {
  await c.query(
    `UPDATE daily_counters SET n = n - 1 WHERE scope = $1 AND key = $2 AND day = ${day(3)} AND n > 0`,
    [scope, key, onDay ?? null]);
}

/** Drops counts older than two days. Cheap (indexed by day); called when accounts are made and by the worker. */
export async function pruneCounters(c: Q): Promise<void> {
  await c.query("DELETE FROM daily_counters WHERE day < (now() AT TIME ZONE 'utc')::date - 2");
}

/** The stored form of a key: hex of its keyed digest (see keyedDigest in crypto.ts). */
export const counterKey = (secret: Buffer | undefined, value: string): string => keyedDigest(secret, value).toString("hex");

/**
 * What counts as one client. IPv4 is the address. IPv6 is its /64: one household or phone holds a whole /64, so
 * counting single addresses would hand an attacker with one prefix as many fresh buckets as it likes. An IPv4
 * address written the IPv6 way (::ffff:1.2.3.4) is read as the IPv4 address.
 */
export function clientBucket(ip: string): string {
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(ip);
  if (mapped?.[1]) return mapped[1];
  if (!ip.includes(":")) return ip;
  const zone = ip.indexOf("%");
  const bare = zone >= 0 ? ip.slice(0, zone) : ip;
  const [head = "", tail = ""] = bare.split("::", 2);
  const left = head ? head.split(":") : [];
  const right = bare.includes("::") && tail ? tail.split(":") : [];
  // An IPv4 address in the last 32 bits (64:ff9b::192.0.2.1) takes two groups; it never reaches the /64.
  const last = (right.length ? right : left).at(-1);
  if (last?.includes(".")) (right.length ? right : left).splice(-1, 1, "0", "0");
  const fill = bare.includes("::") ? Array(Math.max(0, 8 - left.length - right.length)).fill("0") : [];
  const groups = [...left, ...fill, ...right];
  if (groups.length !== 8 || !groups.every((g) => /^[0-9a-f]{1,4}$/i.test(g))) return ip; // not an address we can read: its own bucket
  return `v6:${groups.slice(0, 4).map((g) => g.toLowerCase().padStart(4, "0")).join(":")}/64`;
}
