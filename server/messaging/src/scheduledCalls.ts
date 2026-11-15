import { randomUUID, timingSafeEqual } from "node:crypto";
import { callApprovalHash, morningCallApprovalHash } from "./approval.js";
import { lang, OUTBOUND_DAILY_LIMIT, OUTBOUND_HOURLY_LIMIT, type CallKind, type Language } from "./calls.js";
import { DEFAULT_ABUSE_LIMITS, type AbuseLimits } from "./config.js";
import type { TextCipher } from "./crypto.js";
import type pg from "pg";
import { inTransaction, type Db } from "./db.js";
import { log } from "./log.js";
import { canPush, enqueue } from "./outbox.js";
import { isAllowedNumber } from "./phoneCountries.js";
import type { OutboundCaller } from "./providers/types.js";
import { DEFAULT_TIME_ZONE, inQuietHours, localClock, QUIET_HOURS_DEFAULT, type QuietHours } from "./quietHours.js";
import { returnServerSlot, takeServerSlot } from "./serverUsage.js";

// Calls the user asked Doddy to make later (ADR-750 unit U4, ADR-754). The card showed the time,
// the exact reason Doddy will say, and whether quiet hours apply; the tap approved exactly that
// (callApprovalHash). When the time comes the worker checks everything again: the number and
// consent, quiet hours where the user is now, the daily cap, and whether it is too late. A call
// whose outcome is unknown is never placed again. A morning call's day (kind 'morning', decision
// 2026-11-14-morning-call, morningCalls.ts) goes through the same checks, with its schedule's approval
// instead of a card's and its schedule still active, checked again under the lock just before the call.

/** Mirrored in docs/trust/config/doddy_rules.yaml (contact_policy); a test keeps them equal. */
export const SCHEDULED_CALL_MAX_DAYS = 7;
export const SCHEDULED_CALL_LATE_MINUTES = 15;
export const SCHEDULED_CALLS_PENDING_MAX = 10;
/** UTF-16 code units, as JavaScript and Swift's `utf16.count` count them. */
export const CALL_REASON_MAX_LENGTH = 200;
/** A call that didn't get to "placed" in this time is unknown: never placed again. */
const PLACING_STUCK_MINUTES = 5;
/** A placed call's reason stays (encrypted) this long if Twilio never reports the call's end. */
const REASON_KEPT_HOURS = 2;

type Notice = (time: string) => string;
type Notices = { missed: Notice; quiet: Notice; limit: Notice; cancelled: Notice; failed: Notice; notSetUp: Notice; unreadable: Notice };
const NOTICE: Record<Language, Notices> = {
  en: {
    missed: (t) => `Doddy couldn't call you at ${t}: its server couldn't place the call in time. Ask again if you still want it.`,
    quiet: (t) => `Doddy didn't call you at ${t}: it was quiet hours in the time zone your iPhone last gave Doddy. Ask again for another time.`,
    limit: (t) => `Doddy didn't call you at ${t}: it had already tried to call you as many times as it may in an hour or a day.`,
    cancelled: (t) => `Doddy didn't call you at ${t}: your number or your consent to calls changed since you asked.`,
    failed: (t) => `Doddy couldn't place your call at ${t}: the phone service turned it down. Ask again if you still want it.`,
    notSetUp: (t) => `Doddy couldn't call you at ${t}: its phone line isn't set up on its server right now.`,
    unreadable: (t) => `Doddy couldn't call you at ${t}: its server couldn't read what the call was about. Ask again if you still want it.`,
  },
  pl: {
    missed: (t) => `Doddy nie mógł zadzwonić o ${t}: jego serwer nie zdążył wykonać połączenia. Poproś ponownie, jeśli nadal chcesz tę rozmowę.`,
    quiet: (t) => `Doddy nie zadzwonił o ${t}: w strefie czasowej, którą Twój iPhone ostatnio podał Doddy’emu, trwały godziny ciszy. Poproś o inną godzinę.`,
    limit: (t) => `Doddy nie zadzwonił o ${t}: próbował już dzwonić tyle razy, ile może w ciągu godziny lub dnia.`,
    cancelled: (t) => `Doddy nie zadzwonił o ${t}: od Twojej prośby zmienił się numer albo zgoda na rozmowy.`,
    failed: (t) => `Doddy nie mógł zadzwonić o ${t}: usługa telefoniczna odrzuciła połączenie. Poproś ponownie, jeśli nadal chcesz tę rozmowę.`,
    notSetUp: (t) => `Doddy nie mógł zadzwonić o ${t}: jego linia telefoniczna nie jest teraz skonfigurowana na serwerze.`,
    unreadable: (t) => `Doddy nie mógł zadzwonić o ${t}: jego serwer nie mógł odczytać, czego dotyczy rozmowa. Poproś ponownie, jeśli nadal jej chcesz.`,
  },
};

/** A morning call that didn't happen one day: the next days' calls stay as they were, except after "cancelled", which stops them. */
const MORNING_NOTICE: Record<Language, Notices> = {
  en: {
    missed: (t) => `Doddy couldn't make your morning call at ${t}: its server couldn't place it in time. Your morning calls go on as set.`,
    quiet: (t) => `Doddy didn't make your morning call at ${t}: it was quiet hours in the time zone your iPhone last gave Doddy. Your morning calls go on as set.`,
    limit: (t) => `Doddy didn't make your morning call at ${t}: it had already tried to call you as many times as it may in an hour or a day.`,
    cancelled: () => "Doddy stopped your morning calls: your number or your consent to calls changed. Ask again to set them up.",
    failed: (t) => `Doddy couldn't make your morning call at ${t}: the phone service turned it down.`,
    notSetUp: (t) => `Doddy couldn't make your morning call at ${t}: its phone line isn't set up on its server right now.`,
    unreadable: (t) => `Doddy couldn't make your morning call at ${t}: its server couldn't read the plan it wrote for the day.`,
  },
  pl: {
    missed: (t) => `Doddy nie zdążył z porannym telefonem o ${t}: jego serwer nie wykonał połączenia na czas. Kolejne poranne telefony bez zmian.`,
    quiet: (t) => `Doddy nie zadzwonił rano o ${t}: w strefie czasowej, którą Twój iPhone ostatnio podał Doddy’emu, trwały godziny ciszy. Kolejne poranne telefony bez zmian.`,
    limit: (t) => `Doddy nie zadzwonił rano o ${t}: próbował już dzwonić tyle razy, ile może w ciągu godziny lub dnia.`,
    cancelled: () => "Doddy przestał dzwonić rano: zmienił się Twój numer albo zgoda na rozmowy. Poproś ponownie, żeby to ustawić.",
    failed: (t) => `Doddy nie mógł zadzwonić rano o ${t}: usługa telefoniczna odrzuciła połączenie.`,
    notSetUp: (t) => `Doddy nie mógł zadzwonić rano o ${t}: jego linia telefoniczna nie jest teraz skonfigurowana na serwerze.`,
    unreadable: (t) => `Doddy nie mógł zadzwonić rano o ${t}: jego serwer nie mógł odczytać planu dnia, który napisał.`,
  },
};

export const reasonAad = (accountId: string, id: string) => `${accountId}:call_reason:${id}`;

export interface ScheduledCallDeps {
  db: Db;
  cipher?: TextCipher;
  outbound?: OutboundCaller;
  doddyPhoneNumber?: string;
  publicBaseUrl?: string;
  quietHours?: QuietHours;
  /** The countries a call may go to and the server's calls per UTC day (ADR-704): the same limits as "call me now". Default DEFAULT_ABUSE_LIMITS. */
  limits?: Pick<AbuseLimits, "allowedCountryCodes" | "outboundCallsPerServerDay">;
  now?: () => Date;
}

interface DueCall {
  id: string; account_id: string; call_at: Date; call_at_text: string; reason_ciphertext: Buffer; time_zone: string;
  allow_quiet_hours: boolean; language: string; approval_hash: Buffer; kind: CallKind; morning_call_id: string | null;
}

/** A morning call's schedule as the worker checks it when that day's call is due. */
interface Schedule {
  state: string; local_time: string; days: string; time_zone: string; allow_quiet_hours: boolean; language: string; approval_hash: Buffer;
}

/**
 * Places at most one due call. Returns whether one was handled. Every path ends in a final
 * state; a notice goes to the user (push only) whenever the call they asked for didn't happen.
 */
export async function placeDueCall(deps: ScheduledCallDeps): Promise<boolean> {
  const { db, cipher } = deps;
  if (!cipher) return false;
  await reapStuckCalls(db);
  const now = deps.now?.() ?? new Date();
  const { rows: [due] } = await db.query<DueCall>(
    `UPDATE scheduled_calls SET state = 'placing', updated_at = now()
     WHERE id = (SELECT id FROM scheduled_calls WHERE state = 'scheduled' AND call_at <= $1
                 ORDER BY call_at FOR UPDATE SKIP LOCKED LIMIT 1)
     RETURNING id, account_id, call_at, call_at_text, reason_ciphertext, time_zone, allow_quiet_hours, language, approval_hash,
       kind, morning_call_id`, [now]);
  if (!due) return false;
  const language = lang(due.language);
  const morning = due.kind === "morning";
  const notices = (morning ? MORNING_NOTICE : NOTICE)[language];
  const end = async (state: string, code: string, notice?: (t: string) => string, zone = due.time_zone) => {
    await db.query(
      `UPDATE scheduled_calls SET state = $2, error_code = $3, reason_ciphertext = NULL, reason_key_version = NULL, updated_at = now()
       WHERE id = $1 AND state = 'placing'`, [due.id, state, code]);
    if (notice && await canPush(db, due.account_id)) {
      await enqueue(db, due.account_id, ["push"], notice(localClock(due.call_at, zone)), new Date(), `scheduled-call:${due.id}`, { cipher });
    }
    log("scheduled call", { id: due.id, state, code });
    return true;
  };
  // A morning call whose number or consent changed: the schedule was bound to them, so it stops too (one notice).
  const cancel = async (code: string, zone: string) => {
    if (morning && due.morning_call_id) await stopSchedule(db, due.morning_call_id, code);
    return end("cancelled", code, notices.cancelled, zone);
  };

  // Too late (the worker wasn't running, or was held up): a call long after the time the user
  // approved is not what they approved.
  if (now.getTime() - due.call_at.getTime() > SCHEDULED_CALL_LATE_MINUTES * 60_000) {
    return end("missed", "server_late", notices.missed);
  }
  if (!deps.outbound || !deps.doddyPhoneNumber || !deps.publicBaseUrl) return end("failed", "not_configured", notices.notSetUp);

  const { rows: [who] } = await db.query<{ e164: string | null; consent: boolean; zone: string | null }>(
    `SELECT p.e164, s.outbound_consent_at IS NOT NULL AS consent, s.time_zone AS zone
     FROM (SELECT $1::uuid AS account_id) a
     LEFT JOIN phone_numbers p ON p.account_id = a.account_id
     LEFT JOIN call_settings s ON s.account_id = a.account_id`, [due.account_id]);
  const zone = who?.zone ?? due.time_zone ?? DEFAULT_TIME_ZONE;
  if (!who?.e164 || !who.consent) return cancel(who?.e164 ? "consent_off" : "no_verified_phone", zone);
  // A number verified before the country list existed (or before it changed) is not called either (ADR-704).
  const limits = { ...DEFAULT_ABUSE_LIMITS, ...deps.limits };
  if (!isAllowedNumber(who.e164, limits.allowedCountryCodes)) return cancel("country_not_allowed", zone);

  let reason: string;
  try {
    reason = cipher.decrypt(due.reason_ciphertext, reasonAad(due.account_id, due.id));
  } catch {
    return end("failed", "reason_unreadable", notices.unreadable, zone);
  }
  if (morning) {
    // The schedule must still be active (a stop cancels its waiting call, but this one may have been claimed just
    // before), and its approval must cover the number now; this day's call carries the same approval.
    const schedule = due.morning_call_id ? await scheduleOf(db, due.morning_call_id) : undefined;
    if (!schedule || schedule.state !== "active") return end("cancelled", "morning_calls_stopped");
    const expected = morningCallApprovalHash(who.e164, schedule.local_time, schedule.days, schedule.time_zone,
      schedule.allow_quiet_hours, schedule.language);
    if (!timingSafeEqual(expected, schedule.approval_hash) || !schedule.approval_hash.equals(due.approval_hash)) {
      return cancel("number_changed", zone);
    }
  } else {
    // The approval covers the number it was shown for: a different number now is not approved.
    const expected = callApprovalHash(who.e164, due.call_at_text, reason, due.allow_quiet_hours);
    if (!timingSafeEqual(expected, due.approval_hash)) return end("cancelled", "number_changed", notices.cancelled, zone);
  }
  // Quiet hours in the zone the iPhone last sent (it may have changed since the card).
  if (!due.allow_quiet_hours && inQuietHours(now, zone, deps.quietHours ?? QUIET_HOURS_DEFAULT)) {
    return end("skipped_quiet_hours", "quiet_hours", notices.quiet, zone);
  }

  const callId = randomUUID();
  const underCap = await inTransaction(db, async (c): Promise<boolean | "stopped"> => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [due.account_id]);
    // Stopped since the check above: under the lock a stop takes too, so nothing rings after "stop" was answered.
    if (morning) {
      const { rows: [still] } = await c.query<{ active: boolean }>(
        "SELECT state = 'active' AS active FROM morning_calls WHERE id = $1", [due.morning_call_id]);
      if (!still?.active) return "stopped";
    }
    const { rows: [made] } = await c.query<{ day: number; hour: number }>(
      `SELECT count(*)::int AS day, count(*) FILTER (WHERE created_at > $2::timestamptz - interval '1 hour')::int AS hour
       FROM calls WHERE account_id = $1 AND direction = 'outbound' AND created_at > $2::timestamptz - interval '1 day'`,
      [due.account_id, now]);
    if ((made?.day ?? 0) >= OUTBOUND_DAILY_LIMIT || (made?.hour ?? 0) >= OUTBOUND_HOURLY_LIMIT) return false;
    // And the cap for the whole server per UTC day, shared with "call me now" and taken in the same transaction as the
    // call row (ADR-704): the account's own caps alone do not bound what a flood of accounts costs.
    if (!(await takeServerSlot(c, "outbound_calls", limits.outboundCallsPerServerDay))) return false;
    await c.query("INSERT INTO calls (id, account_id, direction, status) VALUES ($1, $2, 'outbound', 'requested')", [callId, due.account_id]);
    await c.query("UPDATE scheduled_calls SET call_id = $2, updated_at = now() WHERE id = $1", [due.id, callId]);
    return true;
  });
  if (underCap === "stopped") return end("cancelled", "morning_calls_stopped");
  if (!underCap) return end("limit", "daily_limit", notices.limit, zone);

  const outcome = await deps.outbound.placeCall({
    to: who.e164, from: deps.doddyPhoneNumber,
    answerUrl: `${deps.publicBaseUrl}/webhooks/twilio/voice/outbound/${callId}`,
    statusCallbackUrl: `${deps.publicBaseUrl}/webhooks/twilio/call-status`,
  }).catch(() => ({ kind: "unknown" as const, code: "caller_error" }));
  const callStatus = outcome.kind === "accepted" ? "requested" : outcome.kind === "unknown" ? "unknown" : "failed";
  await db.query(
    `UPDATE calls SET status = CASE WHEN status = 'requested' THEN $2 ELSE status END,
       call_sid = coalesce(call_sid, $3), error_code = $4 WHERE id = $1`,
    [callId, callStatus, outcome.kind === "accepted" ? outcome.callSid : null, outcome.kind === "accepted" ? null : outcome.code]);
  // Refused by the provider: no call was placed, so it doesn't use up the server's day. (An unknown outcome might be
  // ringing, so that one stays counted.)
  if (outcome.kind === "rejected") {
    await returnServerSlot(db, "outbound_calls").catch(() => {});
    return end("failed", outcome.code, notices.failed, zone);
  }
  // Placed: the reason stays until the call ends, so Doddy can say it on answering. Unknown: it
  // is never placed again (DOD-09), and it can't be connected either (the answer webhook takes
  // only calls Twilio accepted), so its reason goes now.
  await db.query(
    `UPDATE scheduled_calls SET state = $2, error_code = $3, updated_at = now(),
       reason_ciphertext = CASE WHEN $2 = 'unknown' THEN NULL ELSE reason_ciphertext END,
       reason_key_version = CASE WHEN $2 = 'unknown' THEN NULL ELSE reason_key_version END
     WHERE id = $1 AND state = 'placing'`,
    [due.id, outcome.kind === "accepted" ? "placed" : "unknown", outcome.kind === "accepted" ? null : outcome.code]);
  log("scheduled call", { id: due.id, state: outcome.kind === "accepted" ? "placed" : "unknown" });
  return true;
}

async function scheduleOf(db: Db, id: string): Promise<Schedule | undefined> {
  const { rows: [row] } = await db.query<Schedule>(
    `SELECT state, local_time, days, time_zone, allow_quiet_hours, language, approval_hash FROM morning_calls WHERE id = $1`, [id]);
  return row;
}

/** Stops one morning call: no new day's call is made for it. */
async function stopSchedule(db: Db, id: string, code: string): Promise<void> {
  await db.query(
    `UPDATE morning_calls SET state = 'stopped', stop_code = $2, stopped_at = now(), next_call_at = NULL, updated_at = now()
     WHERE id = $1 AND state = 'active'`, [id, code]);
}

/** A call left in "placing" (the worker stopped mid-way) is unknown: it is never placed again. */
async function reapStuckCalls(db: Db): Promise<void> {
  await db.query(
    `UPDATE scheduled_calls SET state = 'unknown', error_code = 'worker_interrupted', reason_ciphertext = NULL,
       reason_key_version = NULL, updated_at = now()
     WHERE state = 'placing' AND updated_at < now() - make_interval(mins => $1)`, [PLACING_STUCK_MINUTES]);
}

/** The reason for an answered scheduled call, for the phone agent; undefined for any other call. */
export async function scheduledPurpose(db: Db, cipher: TextCipher | undefined, callId: string):
    Promise<{ reason: string; language: Language; kind: CallKind } | undefined> {
  if (!cipher) return undefined;
  const { rows: [row] } = await db.query<{ id: string; account_id: string; reason_ciphertext: Buffer | null; language: string; kind: CallKind }>(
    "SELECT id, account_id, reason_ciphertext, language, kind FROM scheduled_calls WHERE call_id = $1", [callId]);
  if (!row?.reason_ciphertext) return undefined;
  try {
    return {
      reason: cipher.decrypt(row.reason_ciphertext, reasonAad(row.account_id, row.id)), language: lang(row.language),
      kind: row.kind === "morning" ? "morning" : "once",
    };
  } catch {
    return undefined;
  }
}

/** Once the call is over (Twilio's final status), its reason is erased. */
export async function forgetCallReason(db: Db, callId: string): Promise<void> {
  await db.query(
    "UPDATE scheduled_calls SET reason_ciphertext = NULL, reason_key_version = NULL, updated_at = now() WHERE call_id = $1 AND reason_ciphertext IS NOT NULL",
    [callId]);
}

/** Reasons of placed calls whose end Twilio never reported are erased after a while (unknown ones too, though they lose theirs at once). */
export async function pruneCallReasons(db: Db): Promise<number> {
  const r = await db.query(
    `UPDATE scheduled_calls SET reason_ciphertext = NULL, reason_key_version = NULL
     WHERE state IN ('placed', 'unknown') AND reason_ciphertext IS NOT NULL AND updated_at < now() - make_interval(hours => $1)`,
    [REASON_KEPT_HOURS]);
  return r.rowCount ?? 0;
}

/**
 * The number changed or went, or calls were turned off: calls waiting for it won't happen, and
 * their reasons are erased now. Call it inside the transaction that makes the change. The worker would refuse them anyway (the approval is bound to the
 * number); this keeps the list honest and the reasons no longer than needed. A morning call stops too: its standing
 * permission was bound to that number and that consent (decision 2026-11-14-morning-call).
 */
export async function cancelScheduledCalls(db: pg.PoolClient, accountId: string, code: "number_changed" | "consent_off"): Promise<number> {
  // Inside the caller's transaction, under the lock a booking takes, so a booking can't slip in
  // between this and the change that caused it.
  await db.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [accountId]);
  await db.query(
    `UPDATE morning_calls SET state = 'stopped', stop_code = $2, stopped_at = now(), next_call_at = NULL, updated_at = now()
     WHERE account_id = $1 AND state = 'active'`, [accountId, code]);
  const r = await db.query(
    `UPDATE scheduled_calls SET state = 'cancelled', error_code = $2, reason_ciphertext = NULL, reason_key_version = NULL,
       updated_at = now() WHERE account_id = $1 AND state = 'scheduled'`, [accountId, code]);
  return r.rowCount ?? 0;
}

/**
 * Whether one more call at `at` would put more than `limit` calls into some window of `windowMs`
 * that holds it, with the calls at `others` (made or booked). Windows are half-open, like the
 * worker's "in the last hour" count, and it is enough to try those starting at a call.
 */
export function capExceeded(others: readonly Date[], at: Date, windowMs: number, limit: number): boolean {
  const points = [...others.map((d) => d.getTime()), at.getTime()];
  const t = at.getTime();
  return points.some((start) => start <= t && start > t - windowMs
    && points.filter((p) => p >= start && p < start + windowMs).length > limit);
}

export const sealReason = (cipher: TextCipher, accountId: string, id: string, reason: string) =>
  cipher.encrypt(reason, reasonAad(accountId, id));
