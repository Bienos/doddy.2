import { randomUUID, timingSafeEqual } from "node:crypto";
import { callApprovalHash } from "./approval.js";
import { lang, OUTBOUND_DAILY_LIMIT, OUTBOUND_HOURLY_LIMIT, type Language } from "./calls.js";
import type { TextCipher } from "./crypto.js";
import type pg from "pg";
import { inTransaction, type Db } from "./db.js";
import { log } from "./log.js";
import { canPush, enqueue } from "./outbox.js";
import type { OutboundCaller } from "./providers/types.js";
import { DEFAULT_TIME_ZONE, inQuietHours, localClock, QUIET_HOURS_DEFAULT, type QuietHours } from "./quietHours.js";

// Calls the user asked Doddy to make later (ADR-490 unit U4, ADR-495). The card showed the time,
// the exact reason Doddy will say, and whether quiet hours apply; the tap approved exactly that
// (callApprovalHash). When the time comes the worker checks everything again: the number and
// consent, quiet hours where the user is now, the daily cap, and whether it is too late. A call
// whose outcome is unknown is never placed again.

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
const NOTICE: Record<Language, { missed: Notice; quiet: Notice; limit: Notice; cancelled: Notice; failed: Notice; notSetUp: Notice }> = {
  en: {
    missed: (t) => `Doddy couldn't call you at ${t}: its server wasn't running then. Ask again if you still want the call.`,
    quiet: (t) => `Doddy didn't call you at ${t}: it's quiet hours where you are now. Ask again for another time.`,
    limit: (t) => `Doddy didn't call you at ${t}: it had already called you as many times as it may in an hour or a day.`,
    cancelled: (t) => `Doddy didn't call you at ${t}: your number or your consent to calls changed since you asked.`,
    failed: (t) => `Doddy couldn't place your call at ${t}: the phone service turned it down. Ask again if you still want it.`,
    notSetUp: (t) => `Doddy couldn't call you at ${t}: its phone line isn't set up on its server right now.`,
  },
  pl: {
    missed: (t) => `Doddy nie mógł zadzwonić o ${t}: jego serwer wtedy nie działał. Poproś ponownie, jeśli nadal chcesz tę rozmowę.`,
    quiet: (t) => `Doddy nie zadzwonił o ${t}: tam, gdzie teraz jesteś, trwają godziny ciszy. Poproś o inną godzinę.`,
    limit: (t) => `Doddy nie zadzwonił o ${t}: wykonał już tyle połączeń, ile może w ciągu godziny lub dnia.`,
    cancelled: (t) => `Doddy nie zadzwonił o ${t}: od Twojej prośby zmienił się numer albo zgoda na rozmowy.`,
    failed: (t) => `Doddy nie mógł zadzwonić o ${t}: usługa telefoniczna odrzuciła połączenie. Poproś ponownie, jeśli nadal chcesz tę rozmowę.`,
    notSetUp: (t) => `Doddy nie mógł zadzwonić o ${t}: jego linia telefoniczna nie jest teraz skonfigurowana na serwerze.`,
  },
};

const reasonAad = (accountId: string, id: string) => `${accountId}:call_reason:${id}`;

export interface ScheduledCallDeps {
  db: Db;
  cipher?: TextCipher;
  outbound?: OutboundCaller;
  doddyPhoneNumber?: string;
  publicBaseUrl?: string;
  quietHours?: QuietHours;
  now?: () => Date;
}

interface DueCall {
  id: string; account_id: string; call_at: Date; call_at_text: string; reason_ciphertext: Buffer; time_zone: string;
  allow_quiet_hours: boolean; language: string; approval_hash: Buffer;
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
     RETURNING id, account_id, call_at, call_at_text, reason_ciphertext, time_zone, allow_quiet_hours, language, approval_hash`, [now]);
  if (!due) return false;
  const language = lang(due.language);
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

  // Too late: Doddy's server wasn't running at the time. A call long after it was asked for is
  // not what the user approved.
  if (now.getTime() - due.call_at.getTime() > SCHEDULED_CALL_LATE_MINUTES * 60_000) {
    return end("missed", "server_late", NOTICE[language].missed);
  }
  if (!deps.outbound || !deps.doddyPhoneNumber || !deps.publicBaseUrl) return end("failed", "not_configured", NOTICE[language].notSetUp);

  const { rows: [who] } = await db.query<{ e164: string | null; consent: boolean; zone: string | null }>(
    `SELECT p.e164, s.outbound_consent_at IS NOT NULL AS consent, s.time_zone AS zone
     FROM (SELECT $1::uuid AS account_id) a
     LEFT JOIN phone_numbers p ON p.account_id = a.account_id
     LEFT JOIN call_settings s ON s.account_id = a.account_id`, [due.account_id]);
  const zone = who?.zone ?? due.time_zone ?? DEFAULT_TIME_ZONE;
  if (!who?.e164 || !who.consent) return end("cancelled", who?.e164 ? "consent_off" : "no_verified_phone", NOTICE[language].cancelled, zone);

  let reason: string;
  try {
    reason = cipher.decrypt(due.reason_ciphertext, reasonAad(due.account_id, due.id));
  } catch {
    return end("failed", "reason_unreadable", NOTICE[language].notSetUp, zone);
  }
  // The approval covers the number it was shown for: a different number now is not approved.
  const expected = callApprovalHash(who.e164, due.call_at_text, reason, due.allow_quiet_hours);
  if (!timingSafeEqual(expected, due.approval_hash)) return end("cancelled", "number_changed", NOTICE[language].cancelled, zone);
  // Quiet hours where the user is now (the zone may have changed since the card).
  if (!due.allow_quiet_hours && inQuietHours(now, zone, deps.quietHours ?? QUIET_HOURS_DEFAULT)) {
    return end("skipped_quiet_hours", "quiet_hours", NOTICE[language].quiet, zone);
  }

  const callId = randomUUID();
  const underCap = await inTransaction(db, async (c) => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [due.account_id]);
    const { rows: [made] } = await c.query<{ day: number; hour: number }>(
      `SELECT count(*)::int AS day, count(*) FILTER (WHERE created_at > $2::timestamptz - interval '1 hour')::int AS hour
       FROM calls WHERE account_id = $1 AND direction = 'outbound' AND created_at > $2::timestamptz - interval '1 day'`,
      [due.account_id, now]);
    if ((made?.day ?? 0) >= OUTBOUND_DAILY_LIMIT || (made?.hour ?? 0) >= OUTBOUND_HOURLY_LIMIT) return false;
    await c.query("INSERT INTO calls (id, account_id, direction, status) VALUES ($1, $2, 'outbound', 'requested')", [callId, due.account_id]);
    await c.query("UPDATE scheduled_calls SET call_id = $2, updated_at = now() WHERE id = $1", [due.id, callId]);
    return true;
  });
  if (!underCap) return end("limit", "daily_limit", NOTICE[language].limit, zone);

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
  if (outcome.kind === "rejected") return end("failed", outcome.code, NOTICE[language].failed, zone);
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

/** A call left in "placing" (the worker stopped mid-way) is unknown: it is never placed again. */
async function reapStuckCalls(db: Db): Promise<void> {
  await db.query(
    `UPDATE scheduled_calls SET state = 'unknown', error_code = 'worker_interrupted', reason_ciphertext = NULL,
       reason_key_version = NULL, updated_at = now()
     WHERE state = 'placing' AND updated_at < now() - make_interval(mins => $1)`, [PLACING_STUCK_MINUTES]);
}

/** The reason for an answered scheduled call, for the phone agent; undefined for any other call. */
export async function scheduledPurpose(db: Db, cipher: TextCipher | undefined, callId: string):
    Promise<{ reason: string; language: Language } | undefined> {
  if (!cipher) return undefined;
  const { rows: [row] } = await db.query<{ id: string; account_id: string; reason_ciphertext: Buffer | null; language: string }>(
    "SELECT id, account_id, reason_ciphertext, language FROM scheduled_calls WHERE call_id = $1", [callId]);
  if (!row?.reason_ciphertext) return undefined;
  try {
    return { reason: cipher.decrypt(row.reason_ciphertext, reasonAad(row.account_id, row.id)), language: lang(row.language) };
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
 * their reasons are erased now. The worker would refuse them anyway (the approval is bound to the
 * number); this keeps the list honest and the reasons no longer than needed.
 */
export async function cancelScheduledCalls(db: pg.Pool | pg.PoolClient, accountId: string, code: "number_changed" | "consent_off"): Promise<number> {
  const r = await db.query(
    `UPDATE scheduled_calls SET state = 'cancelled', error_code = $2, reason_ciphertext = NULL, reason_key_version = NULL,
       updated_at = now() WHERE account_id = $1 AND state = 'scheduled'`, [accountId, code]);
  return r.rowCount ?? 0;
}

export const sealReason = (cipher: TextCipher, accountId: string, id: string, reason: string) =>
  cipher.encrypt(reason, reasonAad(accountId, id));
