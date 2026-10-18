// Call cases: create a brief, approve it, dial, end, read live. Every route and webhook goes through
// here. The rules that make a call outside the approval impossible:
//   - the provider payload is compiled once at create, encrypted, and approved by its digest;
//   - an attempt references (case, digest) by foreign key, and may dial only inside its window;
//   - `dialAttempt` is the only code that creates a Twilio call, and it claims the attempt in a
//     committed transaction first, so nothing dials twice;
//   - every gate (kill switch, hours, destination, limits, agent drift) runs again at dial time.
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { sameBytes } from "../crypto.js";
import { inTransaction, type Db } from "../db.js";
import { briefSchema, checkBriefContent, type ContentRefusal } from "./brief.js";
import type { TaskCallContext } from "./context.js";
import { callFits } from "./hours.js";
import {
  ATTEMPT_VARIABLE, callerPhoneHash, canonicalJson, compilePayload, destinationHash, payloadAad, payloadDigest, previewOf,
  type CallPayload,
} from "./payload.js";
import { classifyDestination, type DestinationRefusal } from "./phone.js";
import { GOODBYE } from "./opening.js";
import { RETRYABLE_OUTCOMES } from "./result.js";
import { sayAndHangUp } from "./twiml.js";

export const PREVIEW_MINUTES = 30;
export const DIAL_WINDOW_MINUTES = 10;
export const RETRY_DAYS = 1;
export const MAX_ATTEMPTS = 3;
export const MAX_OPEN_CASES = 5;
export const STALE_DIALING_MS = 2 * 60_000;

type Q = Pick<pg.PoolClient, "query"> | Db;

export type Refusal =
  | { status: 400; error: "invalid_request"; fields: string[] }
  | { status: 400; error: "brief_refused"; field: string; reason: ContentRefusal | "too_long" }
  | { status: 400; error: "destination_refused"; reason: DestinationRefusal | "own_number" | "doddy_number" }
  | { status: 400; error: "bad_time" }
  | { status: 404; error: "not_found" }
  | { status: 409; error: "no_verified_phone" | "too_many_open_cases" | "not_approvable" | "digest_mismatch" | "outside_hours"
      | "attempt_open" | "already_answered" | "no_more_attempts" | "not_live" | "taken_over" | "not_takeoverable" | "result_mismatch" }
  | { status: 503; error: "calls_disabled" | "not_configured" };

const ms = (minutes: number) => minutes * 60_000;
const plus = (d: Date, millis: number) => new Date(d.getTime() + millis);

export function urlsFor(ctx: TaskCallContext, attemptId: string) {
  const base = `${ctx.publicBaseUrl}/webhooks/twilio/task-call`;
  const q = `?a=${attemptId}`;
  return {
    answer: `${base}/answer${q}`, fallback: `${base}/fallback${q}`, status: `${base}/status${q}`,
    transcription: `${base}/transcription${q}`, connectEnded: `${base}/connect-ended${q}`,
  };
}

export function takeoverUrls(ctx: TaskCallContext, takeoverId: string) {
  const base = `${ctx.publicBaseUrl}/webhooks/twilio/task-call`;
  const q = `?t=${takeoverId}`;
  return {
    answer: `${base}/takeover-answer${q}`, digits: `${base}/takeover-digits${q}`, status: `${base}/takeover-status${q}`,
    conference: `${base}/conference${q}`, fallback: `${base}/fallback${q}`,
  };
}

// ---------- payload storage ----------

export function decryptPayload(ctx: TaskCallContext, accountId: string, caseId: string, blob: Buffer): CallPayload {
  return JSON.parse(ctx.cipher.decrypt(blob, payloadAad(accountId, caseId))) as CallPayload;
}

/** The stored payload, checked against the digest the attempt was approved with. */
function verifiedPayload(ctx: TaskCallContext, accountId: string, caseId: string, blob: Buffer, approved: Buffer): CallPayload | undefined {
  const payload = decryptPayload(ctx, accountId, caseId, blob);
  return sameBytes(payloadDigest(ctx.keys, payload), approved) ? payload : undefined;
}

// ---------- create ----------

export async function createCase(ctx: TaskCallContext, accountId: string, body: unknown) {
  if (ctx.settings.killSwitch) return refuse(503, "calls_disabled");
  const parsed = briefSchema.safeParse(body);
  if (!parsed.success) return { refusal: { status: 400, error: "invalid_request", fields: parsed.error.issues.map((i) => i.path.join(".")) } as Refusal };
  const brief = parsed.data;
  const problem = checkBriefContent(brief);
  if (problem) return { refusal: { status: 400, error: "brief_refused", field: problem.field, reason: problem.reason } as Refusal };
  if (brief.maxDurationSecs > ctx.settings.limits.maxDurationSecs) {
    return { refusal: { status: 400, error: "brief_refused", field: "maxDurationSecs", reason: "too_long" } as Refusal };
  }
  const dest = classifyDestination(brief.callee.phone);
  if (!dest.ok) return { refusal: { status: 400, error: "destination_refused", reason: dest.reason } as Refusal };
  const own = await verifiedPhone(ctx.db, accountId);
  if (!own) return refuse(409, "no_verified_phone");
  if (dest.e164 === own) return { refusal: { status: 400, error: "destination_refused", reason: "own_number" } as Refusal };
  if (dest.e164 === ctx.config.fromNumber) return { refusal: { status: 400, error: "destination_refused", reason: "doddy_number" } as Refusal };

  const now = ctx.now();
  const caseId = randomUUID();
  const payload = compilePayload({ caseId, brief, destination: dest, fromNumber: ctx.config.fromNumber, notice: ctx.settings.notice });
  const digest = payloadDigest(ctx.keys, payload);
  const approvableUntil = plus(now, ms(PREVIEW_MINUTES));
  const created = await inTransaction(ctx.db, async (c) => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('call_cases:' || $1))", [accountId]);
    const { rows } = await c.query<{ n: number }>(
      "SELECT count(*)::int AS n FROM call_cases WHERE account_id = $1 AND state IN ('awaiting_approval', 'active')", [accountId]);
    if ((rows[0]?.n ?? 0) >= MAX_OPEN_CASES) return false;
    await c.query(
      `INSERT INTO call_cases (id, account_id, kind, language, state, payload_format, payload_key_version, payload_ciphertext,
         payload_digest, destination_hash, destination_kind, destination_source, max_duration_secs, approvable_until, created_at, updated_at)
       VALUES ($1, $2, 'ask', 'pl', 'awaiting_approval', 1, $3, $4, $5, $6, $7, $8, $9, $10, $11, $11)`,
      [caseId, accountId, ctx.cipher.keyVersion, ctx.cipher.encrypt(canonicalJson(payload), payloadAad(accountId, caseId)),
        digest, destinationHash(ctx.keys, dest.e164), dest.kind, brief.callee.source, brief.maxDurationSecs, approvableUntil, now]);
    return true;
  });
  if (!created) return refuse(409, "too_many_open_cases");
  return { preview: { ...previewOf(payload, digest, approvableUntil), callableNow: callFits(now, brief.maxDurationSecs) } };
}

async function verifiedPhone(db: Q, accountId: string): Promise<string | undefined> {
  const { rows } = await db.query<{ e164: string }>("SELECT e164 FROM phone_numbers WHERE account_id = $1", [accountId]);
  return rows[0]?.e164;
}

function refuse<S extends Refusal["status"]>(status: S, error: string): { refusal: Refusal } {
  return { refusal: { status, error } as Refusal };
}

// ---------- approve ----------

export async function approve(ctx: TaskCallContext, accountId: string, deviceId: string, caseId: string, digestHex: string, atIso?: string) {
  if (ctx.settings.killSwitch) return refuse(503, "calls_disabled");
  const now = ctx.now();
  const at = atIso ? new Date(atIso) : now;
  if (Number.isNaN(at.getTime()) || at.getTime() < now.getTime() - 60_000 || at.getTime() > now.getTime() + ms(24 * 60)) {
    return refuse(400, "bad_time");
  }
  const given = Buffer.from(digestHex, "hex");
  const result = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; payload_digest: Buffer; approvable_until: Date; max_duration_secs: number; created_at: Date }>(
      `SELECT state, payload_digest, approvable_until, max_duration_secs, created_at FROM call_cases
       WHERE id = $1 AND account_id = $2 FOR UPDATE`, [caseId, accountId]);
    const kase = rows[0];
    if (!kase) return refuse(404, "not_found");
    if (!["awaiting_approval", "active"].includes(kase.state) || kase.approvable_until <= now) return refuse(409, "not_approvable");
    if (!sameBytes(kase.payload_digest, given)) return refuse(409, "digest_mismatch");
    if (!callFits(at, kase.max_duration_secs)) return refuse(409, "outside_hours");
    const { rows: prior } = await c.query<{ n: number; open: number; reached: number }>(
      `SELECT count(*)::int AS n,
              count(*) FILTER (WHERE state IN ('scheduled','dialing','ringing','connecting','in_progress','taken_over')
                                  OR (state = 'unknown' AND settled_at IS NULL))::int AS open,
              count(*) FILTER (WHERE voice_connected_at IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM call_results r WHERE r.attempt_id = call_attempts.id AND r.outcome = ANY($2::text[])))::int AS reached
       FROM call_attempts WHERE case_id = $1`, [caseId, RETRYABLE_OUTCOMES]);
    const p = prior[0]!;
    if (p.open > 0) return refuse(409, "attempt_open");
    if (p.reached > 0) return refuse(409, "already_answered");
    if (p.n >= MAX_ATTEMPTS) return refuse(409, "no_more_attempts");
    const attemptId = randomUUID();
    await c.query(
      `INSERT INTO call_attempts (id, case_id, account_id, attempt_no, approved_digest, approved_at, approved_device_id,
         dial_not_before, dial_deadline, state, time_limit_secs, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'scheduled', $10, $6, $6)`,
      [attemptId, caseId, accountId, p.n + 1, given, now, deviceId, at, plus(at, ms(DIAL_WINDOW_MINUTES)), kase.max_duration_secs + 20]);
    // The payload must outlive the dial window (and a day for a retry), within the table's 2-day bound.
    const keepUntil = new Date(Math.min(Math.max(kase.approvable_until.getTime(), plus(at, ms(DIAL_WINDOW_MINUTES + 60)).getTime()),
      kase.created_at.getTime() + ms(2 * 24 * 60)));
    await c.query("UPDATE call_cases SET state = 'active', approvable_until = $2, updated_at = $3 WHERE id = $1", [caseId, keepUntil, now]);
    return { attemptId };
  });
  if ("refusal" in result) return result;
  const dialNow = at.getTime() <= now.getTime() + 60_000;
  const dial = dialNow ? await dialAttempt(ctx, result.attemptId) : { kind: "scheduled" as const };
  return { attemptId: result.attemptId, dial };
}

// ---------- dial ----------

export type DialOutcome =
  | { kind: "dialing" } | { kind: "scheduled" } | { kind: "not_scheduled"; state: string } | { kind: "not_yet" }
  | { kind: "expired" } | { kind: "refused"; gate: string } | { kind: "not_placed"; code: string } | { kind: "unknown"; code: string };

/** The only code that asks Twilio to place a task call. */
export async function dialAttempt(ctx: TaskCallContext, attemptId: string): Promise<DialOutcome> {
  // Network check before taking locks: the live agent must still match its spec.
  const drift = await ctx.drift.problems();
  const now = ctx.now();
  const claim = await inTransaction(ctx.db, async (c) => {
    // One dial claim at a time across the server: limits are counted and recorded atomically.
    await c.query("SELECT pg_advisory_xact_lock(hashtext('task_call_dial'))");
    const { rows } = await c.query<{
      state: string; case_id: string; account_id: string; approved_digest: Buffer; dial_not_before: Date; dial_deadline: Date;
      payload_ciphertext: Buffer | null; max_duration_secs: number; destination_hash: Buffer; case_state: string;
    }>(
      `SELECT a.state, a.case_id, a.account_id, a.approved_digest, a.dial_not_before, a.dial_deadline,
              c.payload_ciphertext, c.max_duration_secs, c.destination_hash, c.state AS case_state
       FROM call_attempts a JOIN call_cases c ON c.id = a.case_id WHERE a.id = $1 FOR UPDATE OF a, c`, [attemptId]);
    const a = rows[0];
    if (!a) return { kind: "not_scheduled" as const, state: "missing" };
    if (a.state !== "scheduled") return { kind: "not_scheduled" as const, state: a.state };
    if (now < a.dial_not_before) return { kind: "not_yet" as const };
    const stop = async (state: "expired" | "cancelled", reason: string, code: string | null) => {
      await c.query(
        `UPDATE call_attempts SET state = $2, end_reason = $3, error_code = $4, settled_at = $5, updated_at = $5 WHERE id = $1`,
        [attemptId, state, reason, code, now]);
      await c.query(
        `INSERT INTO call_results (attempt_id, account_id, state, process_after) VALUES ($1, $2, 'waiting', $3) ON CONFLICT DO NOTHING`,
        [attemptId, a.account_id, now]);
    };
    if (now > a.dial_deadline) { await stop("expired", "expired", null); return { kind: "expired" as const }; }
    const gate = async (code: string) => { await stop("cancelled", "gate_refused", code); return { kind: "refused" as const, gate: code }; };
    if (ctx.settings.killSwitch) return gate("kill_switch");
    if (a.case_state !== "active" || !a.payload_ciphertext) return gate("case_closed");
    if (drift.length) return gate("agent_drift");
    if (!callFits(now, a.max_duration_secs)) return gate("outside_hours");
    const payload = verifiedPayload(ctx, a.account_id, a.case_id, a.payload_ciphertext, a.approved_digest);
    if (!payload) return gate("payload_mismatch");
    const dest = classifyDestination(payload.twilio.to);
    const own = await verifiedPhone(c, a.account_id);
    if (!own) return gate("no_verified_phone");
    if (!dest.ok || dest.e164 !== payload.twilio.to || dest.e164 === own || dest.e164 === ctx.config.fromNumber
      || payload.twilio.from !== ctx.config.fromNumber) return gate("destination");
    const limit = await limitReached(ctx, c, callerPhoneHash(ctx.keys, own), a.destination_hash, now);
    if (limit) return gate(limit);
    // One call at a time per account (also a unique index; checked here so it is a clear refusal).
    const { rows: live } = await c.query(
      `SELECT 1 FROM call_attempts WHERE account_id = $1 AND id <> $2
       AND (state IN ('dialing','ringing','connecting','in_progress','taken_over') OR (state = 'unknown' AND settled_at IS NULL))`,
      [a.account_id, attemptId]);
    if (live.length) return gate("one_live_call");

    // Claim: committed before Twilio is asked, together with the cost rows and the dial log.
    await c.query("UPDATE call_attempts SET state = 'dialing', dial_started_at = $2, updated_at = $2 WHERE id = $1", [attemptId, now]);
    await c.query(
      `INSERT INTO call_cost_items (attempt_id, account_id, component, status, due_by, next_try_at)
       SELECT $1, $2, x, 'pending', $3, $4 FROM unnest($5::text[]) AS x`,
      [attemptId, a.account_id, plus(now, ms(24 * 60)), plus(now, ms(2)), ["twilio_call", "twilio_transcription", "elevenlabs_voice"]]);
    await c.query("INSERT INTO call_dial_log (destination_hash, caller_phone_hash, dialed_at) VALUES ($1, $2, $3)",
      [a.destination_hash, callerPhoneHash(ctx.keys, own), now]);
    return { kind: "claimed" as const, payload, accountId: a.account_id };
  });
  if (claim.kind !== "claimed") return claim;

  const u = urlsFor(ctx, attemptId);
  const t = claim.payload.twilio;
  const outcome = await ctx.telephony.createCall({
    to: t.to, from: t.from, url: u.answer, fallbackUrl: u.fallback, statusCallback: u.status,
    timeLimitSecs: t.timeLimitSecs, timeoutSecs: t.timeoutSecs,
  });
  const at = ctx.now();
  if (outcome.kind === "accepted") {
    await ctx.db.query(
      "UPDATE call_attempts SET twilio_call_sid = coalesce(twilio_call_sid, $2), updated_at = $3 WHERE id = $1", [attemptId, outcome.sid, at]);
    ctx.log("task call dialled", { attemptId });
    return { kind: "dialing" };
  }
  if (outcome.kind === "rejected") {
    await inTransaction(ctx.db, async (c) => {
      await c.query(
        `UPDATE call_attempts SET state = 'not_placed', end_reason = 'twilio_refused', error_code = $2, settled_at = $3, updated_at = $3
         WHERE id = $1 AND state = 'dialing'`, [attemptId, outcome.code, at]);
      // Nothing was placed, so nothing is charged.
      await c.query(
        `UPDATE call_cost_items SET status = 'zero', amount_micros = 0, currency = 'USD', settled_at = $2, next_try_at = NULL
         WHERE attempt_id = $1 AND status = 'pending'`, [attemptId, at]);
      await c.query(
        "INSERT INTO call_results (attempt_id, account_id, state, process_after) VALUES ($1, $2, 'waiting', $3) ON CONFLICT DO NOTHING",
        [attemptId, claim.accountId, at]);
    });
    ctx.log("task call refused by Twilio", { attemptId, code: outcome.code });
    return { kind: "not_placed", code: outcome.code };
  }
  // The call may be ringing: never redialled. A status callback (it carries the attempt id) links it.
  await ctx.db.query("UPDATE call_attempts SET state = 'unknown', error_code = $2, updated_at = $3 WHERE id = $1 AND state = 'dialing'",
    [attemptId, outcome.code, at]);
  ctx.log("task call outcome unknown", { attemptId, code: outcome.code });
  return { kind: "unknown", code: outcome.code };
}

/** Which limit a new dial would break, if any. Counted from the content-free dial log. */
async function limitReached(ctx: TaskCallContext, c: Q, caller: Buffer, destination: Buffer, now: Date): Promise<string | undefined> {
  const l = ctx.settings.limits;
  const { rows } = await c.query<{ caller_hour: number; caller_day: number; dest_caller_day: number; dest_day: number; dest_recent: number; global_day: number }>(
    `SELECT
       count(*) FILTER (WHERE caller_phone_hash = $1 AND dialed_at > $3::timestamptz - interval '1 hour')::int AS caller_hour,
       count(*) FILTER (WHERE caller_phone_hash = $1 AND dialed_at > $3::timestamptz - interval '1 day')::int AS caller_day,
       count(*) FILTER (WHERE caller_phone_hash = $1 AND destination_hash = $2 AND dialed_at > $3::timestamptz - interval '1 day')::int AS dest_caller_day,
       count(*) FILTER (WHERE destination_hash = $2 AND dialed_at > $3::timestamptz - interval '1 day')::int AS dest_day,
       count(*) FILTER (WHERE destination_hash = $2 AND dialed_at > $3::timestamptz - make_interval(mins => $4))::int AS dest_recent,
       count(*)::int AS global_day
     FROM call_dial_log WHERE dialed_at > $3::timestamptz - interval '1 day'`,
    [caller, destination, now, l.destinationGapMinutes]);
  const r = rows[0]!;
  if (r.global_day >= l.globalPerDay) return "limit_global_day";
  if (r.caller_hour >= l.userPerHour) return "limit_user_hour";
  if (r.caller_day >= l.userPerDay) return "limit_user_day";
  if (r.dest_caller_day >= l.destinationPerUserDay) return "limit_destination_user_day";
  if (r.dest_day >= l.destinationPerDay) return "limit_destination_day";
  if (r.dest_recent > 0) return "limit_destination_gap";
  return undefined;
}

// ---------- end ----------

export type EndReason = "user_ended" | "kill_switch" | "time_limit" | "account_deleted";

/**
 * Ends the AI part of a call: a fixed Polish goodbye, then hang up (or cancel while it rings).
 * Safe to call again; a call the user has joined is never ended by this.
 */
export async function endCall(ctx: TaskCallContext, attemptId: string, reason: EndReason): Promise<"ending" | "not_live" | "taken_over" | "unknown"> {
  const now = ctx.now();
  const { rows } = await ctx.db.query<{ state: string; twilio_call_sid: string | null }>(
    `UPDATE call_attempts SET ending_at = coalesce(ending_at, $2), end_reason = coalesce(end_reason, $3), updated_at = $2
     WHERE id = $1 AND state IN ('dialing', 'ringing', 'connecting', 'in_progress', 'unknown') AND settled_at IS NULL
     RETURNING state, twilio_call_sid`, [attemptId, now, reason]);
  const a = rows[0];
  if (!a) {
    const { rows: t } = await ctx.db.query<{ state: string }>("SELECT state FROM call_attempts WHERE id = $1", [attemptId]);
    return t[0]?.state === "taken_over" ? "taken_over" : "not_live";
  }
  if (!a.twilio_call_sid) return "unknown"; // not linked yet; the status callback or the sweep ends it
  const answered = a.state === "connecting" || a.state === "in_progress";
  const r = await ctx.telephony.updateCall(a.twilio_call_sid,
    answered ? { twiml: sayAndHangUp(GOODBYE, ctx.say) } : { status: a.state === "dialing" ? "canceled" : "completed" });
  if (r.kind === "unknown" || r.kind === "rejected") {
    // Second try without the goodbye: the call must end.
    const hard = await ctx.telephony.updateCall(a.twilio_call_sid, { status: "completed" });
    if (hard.kind === "unknown" || hard.kind === "rejected") return "unknown";
  }
  ctx.log("task call ending", { attemptId, reason });
  return "ending";
}

// ---------- reads ----------

export async function caseOwnedBy(db: Q, caseId: string, accountId: string) {
  const { rows } = await db.query<{ id: string; state: string; payload_ciphertext: Buffer | null; payload_digest: Buffer; approvable_until: Date }>(
    "SELECT id, state, payload_ciphertext, payload_digest, approvable_until FROM call_cases WHERE id = $1 AND account_id = $2",
    [caseId, accountId]);
  return rows[0];
}

/** The newest attempt of a case. */
export async function latestAttempt(db: Q, caseId: string) {
  const { rows } = await db.query<{
    id: string; state: string; attempt_no: number; answered_at: Date | null; voice_connected_at: Date | null; hangup_due_at: Date | null;
    ended_at: Date | null; end_reason: string | null; taken_over_at: Date | null; ending_at: Date | null; dial_not_before: Date;
    twilio_call_sid: string | null; account_id: string; settled_at: Date | null;
  }>("SELECT * FROM call_attempts WHERE case_id = $1 ORDER BY attempt_no DESC LIMIT 1", [caseId]);
  return rows[0];
}

export type Phase = "scheduled" | "ringing" | "connecting" | "talking" | "taken_over" | "ending" | "ended" | "unknown";

export function phaseOf(a: { state: string; ending_at: Date | null; settled_at: Date | null }): Phase {
  if (a.settled_at && a.state !== "unknown") return "ended";
  if (a.state === "taken_over") return "taken_over";
  if (a.ending_at) return "ending";
  switch (a.state) {
    case "scheduled": return "scheduled";
    case "dialing": case "ringing": return "ringing";
    case "connecting": return "connecting";
    case "in_progress": return "talking";
    case "unknown": return a.settled_at ? "ended" : "unknown";
    default: return "ended";
  }
}

export async function liveView(ctx: TaskCallContext, accountId: string, caseId: string, after?: string) {
  const kase = await caseOwnedBy(ctx.db, caseId, accountId);
  if (!kase) return undefined;
  const a = await latestAttempt(ctx.db, caseId);
  if (!a) return { attempt: null, lines: [], cursor: after ?? null };
  const { rows } = await ctx.db.query<{ transcription_sid: string; seq: number; speaker: string; ciphertext: Buffer; received: string }>(
    `SELECT transcription_sid, seq, speaker, ciphertext, received_at::text AS received FROM call_live_lines
     WHERE attempt_id = $1 AND ($2::timestamptz IS NULL OR received_at > $2::timestamptz)
     ORDER BY received_at, transcription_sid, seq LIMIT 200`, [a.id, after ?? null]);
  const lines = rows.flatMap((r) => {
    try {
      return [{ key: `${r.transcription_sid}:${r.seq}`, speaker: r.speaker, text: ctx.cipher.decrypt(r.ciphertext, liveAad(accountId, a.id, r.transcription_sid, r.seq)) }];
    } catch {
      return [];
    }
  });
  const { rows: t } = await ctx.db.query<{ state: string }>(
    "SELECT state FROM call_takeovers WHERE attempt_id = $1 ORDER BY try_no DESC LIMIT 1", [a.id]);
  return {
    attempt: {
      id: a.id, attemptNo: a.attempt_no, phase: phaseOf(a), dialNotBefore: a.dial_not_before, answeredAt: a.answered_at,
      hangupDueAt: a.hangup_due_at, endedAt: a.ended_at, endReason: a.end_reason, takenOverAt: a.taken_over_at,
      takeover: t[0] ? { state: t[0].state } : null,
    },
    lines,
    cursor: rows.length ? rows[rows.length - 1]!.received : after ?? null,
  };
}

export const liveAad = (accountId: string, attemptId: string, sid: string, seq: number) => `${accountId}:call-live:${attemptId}:${sid}:${seq}`;
export const inputAad = (accountId: string, attemptId: string) => `${accountId}:call-input:${attemptId}`;
export const resultAad = (accountId: string, attemptId: string) => `${accountId}:call-result:${attemptId}`;

export { ATTEMPT_VARIABLE };
