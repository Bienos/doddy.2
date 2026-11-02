import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { sha256 } from "./crypto.js";
import type { Db } from "./db.js";
import type pg from "pg";

export const SESSION_HOURS = 2;
export const PIN_MAX_ATTEMPTS = 5;
export const PIN_LOCK_MINUTES = 15;

/**
 * Lockouts escalate and the count only resets after a correct PIN or a new PIN (ADR-175):
 * 15 min, 1 h, 4 h, 16 h, then 24 h each time. Five guesses per lockout, so a caller who keeps
 * guessing gets about 25 tries in the first day and 5 a day after that.
 */
export function pinLockMinutes(previousLocks: number): number {
  return Math.min(PIN_LOCK_MINUTES * 4 ** previousLocks, 24 * 60);
}
export const OUTBOUND_DAILY_LIMIT = 10;
export const MAX_PENDING_NOTES = 20;

/**
 * Variables handed to the phone agent at the start of every call. The agent defines all of
 * them, so every response must contain all of them (ElevenLabs requirement).
 * `secret__doddy_session` is only ever placed in tool request headers by ElevenLabs and is
 * never sent to the language model.
 */
export interface CallVariables {
  secret__doddy_session: string;
  doddy_caller: "known" | "unknown" | "calls_off" | "unavailable";
  doddy_memory: "on" | "off";
  doddy_pin: "set" | "not_set";
  doddy_direction: "inbound" | "outbound";
}

export function variablesFor(caller: CallVariables["doddy_caller"], direction: CallVariables["doddy_direction"]): CallVariables {
  return { secret__doddy_session: "none", doddy_caller: caller, doddy_memory: "off", doddy_pin: "not_set", doddy_direction: direction };
}

export function sameSecret(expected: string, given: string | undefined): boolean {
  if (!given) return false;
  const a = sha256(expected);
  const b = sha256(given);
  return timingSafeEqual(a, b);
}

/** Creates the per-call capability and returns the variables for a recognised caller. */
export async function openSession(
  db: Db, accountId: string, callId: string, direction: CallVariables["doddy_direction"],
): Promise<CallVariables> {
  const token = randomBytes(32).toString("base64url");
  await db.query(
    `INSERT INTO call_sessions (id, account_id, token_hash, call_id, expires_at)
     VALUES ($1, $2, $3, $4, now() + make_interval(hours => $5))`,
    [randomUUID(), accountId, sha256(token), callId, SESSION_HOURS]);
  const { rows } = await db.query<{ pin_set: boolean; memory_on: boolean }>(
    `SELECT pin_hash IS NOT NULL AS pin_set, memory_copy_enabled_at IS NOT NULL AS memory_on
     FROM call_settings WHERE account_id = $1`, [accountId]);
  return {
    secret__doddy_session: token,
    doddy_caller: "known",
    doddy_memory: rows[0]?.memory_on ? "on" : "off",
    doddy_pin: rows[0]?.pin_set ? "set" : "not_set",
    doddy_direction: direction,
  };
}

export interface Session { id: string; accountId: string; pinVerified: boolean }

export async function findSession(db: Db, token: string | undefined): Promise<Session | undefined> {
  if (!token || token === "none" || token.length > 100) return undefined;
  const { rows } = await db.query<{ id: string; account_id: string; pin_verified: boolean }>(
    `SELECT id, account_id, pin_verified_at IS NOT NULL AS pin_verified
     FROM call_sessions WHERE token_hash = $1 AND expires_at > now()`, [sha256(token)]);
  const r = rows[0];
  return r && { id: r.id, accountId: r.account_id, pinVerified: r.pin_verified };
}

export async function purgeExpiredSessions(db: Db): Promise<number> {
  const r = await db.query("DELETE FROM call_sessions WHERE expires_at < now()");
  return r.rowCount ?? 0;
}

/** Wording shown next to the "Doddy may call me" switch; stored with its version. */
export const OUTBOUND_CONSENT_VERSIONS = new Set(["calls-v1"]);

/**
 * Queues the deletion at ElevenLabs of every phone-agent conversation (incoming calls, "call me now")
 * recorded for the account. Run before the account is deleted: the cascade removes the `calls` rows
 * that hold the ids, the queued rows (account_id then cleared) outlive it.
 */
export async function queuePhoneAgentDeletions(db: Db | pg.PoolClient, accountId: string, now: Date): Promise<number> {
  const r = await db.query(
    `INSERT INTO server_data_deletions (id, account_id, item, location, reason, result, provider_ref, next_try_at, requested_at)
     SELECT gen_random_uuid(), account_id, 'elevenlabs_conversation', 'elevenlabs', 'account_deleted', 'pending', conversation_id, $2, $2
     FROM calls WHERE account_id = $1 AND conversation_id IS NOT NULL AND length(conversation_id) <= 128
     ON CONFLICT (location, item, provider_ref) WHERE location <> 'doddy_server' DO NOTHING`,
    [accountId, now]);
  return r.rowCount ?? 0;
}
