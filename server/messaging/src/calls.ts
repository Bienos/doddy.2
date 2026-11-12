import { randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { sha256 } from "./crypto.js";
import type { Db } from "./db.js";
import type { TaskVoice } from "./providers/taskCalls.js";
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
/** Doddy's calls to the user; mirrored in docs/trust/config/doddy_rules.yaml (contact_policy). */
export const OUTBOUND_HOURLY_LIMIT = 3;
export const OUTBOUND_DAILY_LIMIT = 10;
export const MAX_PENDING_NOTES = 20;

/**
 * Variables handed to the phone agent at the start of every call it takes (through ElevenLabs
 * register-call, ADR-750). The agent defines all of them, so every call must carry all of them.
 * Only verified callers reach the agent now; the other caller values stay for the prompt's sake.
 * `secret__doddy_session` is only ever placed in tool request headers by ElevenLabs and is
 * never sent to the language model.
 */
export interface CallVariables {
  secret__doddy_session: string;
  doddy_caller: "known" | "unknown" | "calls_off" | "unavailable";
  doddy_memory: "on" | "off";
  doddy_pin: "set" | "not_set";
  doddy_direction: "inbound" | "outbound";
  /** A scheduled call's reason as the user approved it on the card, or "none" (ADR-754). */
  doddy_call_reason: string;
  /** The agent's first sentence, written by the server (callOpening below). */
  doddy_call_opening: string;
}

export type Language = "en" | "pl";
export const lang = (v: string | null | undefined): Language => (v === "pl" ? "pl" : "en");

/**
 * The phone agent's first sentence (its first message is exactly this variable). Written here, not
 * by the model, and it always says Doddy is an AI (DOD-03). On a scheduled call it says the
 * reason the user approved, word for word.
 */
export function callOpening(reason: string | undefined, language: Language): string {
  if (reason === undefined) return "Hi, this is Doddy, an AI assistant. How can I help?";
  return language === "pl"
    ? `Cześć, tu Doddy, asystent AI. Dzwonię zgodnie z Twoją prośbą w sprawie: ${reason}`
    : `Hi, this is Doddy, an AI assistant. You asked me to call you about this: ${reason}`;
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
  purpose?: { reason: string; language: Language },
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
    doddy_call_reason: purpose?.reason ?? "none",
    doddy_call_opening: callOpening(purpose?.reason, purpose?.language ?? "en"),
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

/** The phone agent's conversations are swept once they are this old: the post-call webhook has long been and gone. */
export const PHONE_SWEEP_MIN_AGE_HOURS = 24;
/** Pages of 100 conversations read per sweep, newest first (ElevenLabs keeps the phone agent's for 30 days). */
export const PHONE_SWEEP_MAX_PAGES = 10;

type SweepContext = { db: Db; voice: Pick<TaskVoice, "listConversations" | "getConversation">; now: () => Date; log: (msg: string, extra?: object) => void };

/**
 * The phone agent's conversations at ElevenLabs that no live `calls` row owns are queued for deletion (reason
 * `orphan`), like the task agents' (`sweepOrphans`): a call whose account was deleted before its post-call webhook
 * came, a webhook that never came for a deleted account, or a conversation started anywhere but through this server.
 * A conversation whose webhook never arrived but whose Twilio call is still a `calls` row gets its id stored there
 * instead, and goes with that account. The worker deletes the queued ones and counts one gone only once a read says
 * so (`runDeletions`). Only conversations started a day ago or earlier are looked at. Logs counts only.
 */
export async function sweepPhoneAgentOrphans(ctx: SweepContext, agentId: string): Promise<number> {
  const now = ctx.now();
  let before = Math.floor(now.getTime() / 1000) - PHONE_SWEEP_MIN_AGE_HOURS * 3600;
  const seen = new Set<string>();
  let queued = 0;
  let linked = 0;
  for (let page = 0; page < PHONE_SWEEP_MAX_PAGES; page++) {
    const list = await ctx.voice.listConversations(agentId, before);
    if (list === "error") break;
    const fresh = list.filter((c) => !seen.has(c.id));
    for (const conv of fresh) {
      seen.add(conv.id);
      if (conv.id.length > 128) continue;
      const { rows: owned } = await ctx.db.query(
        `SELECT 1 FROM calls WHERE conversation_id = $1
         UNION ALL SELECT 1 FROM server_data_deletions
           WHERE location = 'elevenlabs' AND item = 'elevenlabs_conversation' AND provider_ref = $1 LIMIT 1`, [conv.id]);
      if (owned.length) continue;
      const got = await ctx.voice.getConversation(conv.id);
      if (got.kind === "not_found") continue;
      if (got.kind === "error") continue; // looked at again next time
      const sid = (got.conversation.metadata as { phone_call?: { call_sid?: unknown } | null }).phone_call?.call_sid;
      if (typeof sid === "string" && sid) {
        const { rowCount } = await ctx.db.query(
          "UPDATE calls SET conversation_id = $2 WHERE call_sid = $1 AND (conversation_id IS NULL OR conversation_id = $2)", [sid, conv.id]);
        if (rowCount) { linked++; continue; }
      }
      const r = await ctx.db.query(
        `INSERT INTO server_data_deletions (id, account_id, item, location, reason, result, provider_ref, next_try_at, requested_at)
         VALUES (gen_random_uuid(), NULL, 'elevenlabs_conversation', 'elevenlabs', 'orphan', 'pending', $1, $2, $2)
         ON CONFLICT (location, item, provider_ref) WHERE location <> 'doddy_server' DO NOTHING`, [conv.id, now]);
      queued += r.rowCount ?? 0;
    }
    // One page of 100 at most comes back; the next one starts at the oldest start time seen (same-second ones are
    // read again and skipped).
    if (list.length < 100 || fresh.length === 0) break;
    before = Math.min(...list.map((c) => c.startUnix)) + 1;
  }
  if (queued || linked) ctx.log("phone agent conversations swept", { queued, linked });
  return queued;
}
