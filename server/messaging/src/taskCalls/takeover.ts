// "Przejmij" (ADR-505): the user's verified phone rings from Doddy's number. Only after they press 1
// is the callee moved, with a short spoken handover, into a private conference the user then joins.
// Until then Doddy keeps talking, so a missed or voicemail-answered takeover loses nothing. Live
// transcription stops at the handover: Doddy doesn't listen to the user's own conversation.
import { randomBytes, randomUUID } from "node:crypto";
import { inTransaction } from "../db.js";
import type { TaskCallContext } from "./context.js";
import { handoverLine, TAKEOVER_NOT_TAKEN, TAKEOVER_TOO_LATE, takeoverPrompt } from "./opening.js";
import { classifyDestination } from "./phone.js";
import { caseOwnedBy, decryptPayload, latestAttempt, takeoverUrls } from "./service.js";
import { calleeHandoverTwiml, hangUp, sayAndHangUp, takeoverPromptTwiml, userJoinTwiml } from "./twiml.js";
import { field, isUuid, type Form } from "./webhooks.js";

export const MIN_SECONDS_LEFT = 30;
export const USER_LEG_TIME_LIMIT = 1860;
export const JOIN_WATCHDOG_MS = 20_000;

export type TakeoverStart =
  | { kind: "started" | "already"; takeoverId: string; state: string }
  | { kind: "refused"; error: "not_found" | "calls_disabled" | "not_takeoverable" | "no_verified_phone" | "phone_not_supported" | "no_more_tries" };

export async function startTakeover(ctx: TaskCallContext, accountId: string, caseId: string): Promise<TakeoverStart> {
  if (ctx.settings.killSwitch) return { kind: "refused", error: "calls_disabled" };
  const kase = await caseOwnedBy(ctx.db, caseId, accountId);
  if (!kase) return { kind: "refused", error: "not_found" };
  const a = await latestAttempt(ctx.db, caseId);
  const now = ctx.now();
  if (!a || a.state !== "in_progress" || !a.voice_connected_at || a.ending_at || !a.twilio_call_sid
    || !a.hangup_due_at || a.hangup_due_at.getTime() - now.getTime() < MIN_SECONDS_LEFT * 1000 || !kase.payload_ciphertext) {
    return { kind: "refused", error: "not_takeoverable" };
  }
  const { rows: open } = await ctx.db.query<{ id: string; state: string }>(
    "SELECT id, state FROM call_takeovers WHERE attempt_id = $1 AND state IN ('dialing', 'ringing', 'prompted', 'joining')", [a.id]);
  if (open[0]) return { kind: "already", takeoverId: open[0].id, state: open[0].state };
  const { rows: phone } = await ctx.db.query<{ e164: string }>("SELECT e164 FROM phone_numbers WHERE account_id = $1", [accountId]);
  if (!phone[0]) return { kind: "refused", error: "no_verified_phone" };
  const userPhone = classifyDestination(phone[0].e164);
  const payload = decryptPayload(ctx, accountId, caseId, kase.payload_ciphertext);
  // v1 rings Polish numbers only, never the callee's own number.
  if (!userPhone.ok || userPhone.e164 === payload.twilio.to) return { kind: "refused", error: "phone_not_supported" };

  const takeoverId = randomUUID();
  const inserted = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ n: number }>("SELECT count(*)::int AS n FROM call_takeovers WHERE attempt_id = $1", [a.id]);
    const tries = rows[0]?.n ?? 0;
    if (tries >= 2) return false;
    await c.query(
      `INSERT INTO call_takeovers (id, attempt_id, account_id, try_no, state, conference_name, requested_at)
       VALUES ($1, $2, $3, $4, 'dialing', $5, $6)`,
      [takeoverId, a.id, accountId, tries + 1, `doddy-${randomBytes(18).toString("base64url")}`, now]);
    return true;
  }).catch((err: { code?: string }) => {
    if (err.code === "23505") return "race" as const; // another tap won: one open takeover per attempt
    throw err;
  });
  if (inserted === "race") {
    const { rows } = await ctx.db.query<{ id: string; state: string }>(
      "SELECT id, state FROM call_takeovers WHERE attempt_id = $1 AND state IN ('dialing', 'ringing', 'prompted', 'joining')", [a.id]);
    return rows[0] ? { kind: "already", takeoverId: rows[0].id, state: rows[0].state } : { kind: "refused", error: "not_takeoverable" };
  }
  if (!inserted) return { kind: "refused", error: "no_more_tries" };

  const u = takeoverUrls(ctx, takeoverId);
  const outcome = await ctx.telephony.createCall({
    to: userPhone.e164, from: ctx.config.fromNumber, url: u.answer, fallbackUrl: u.fallback, statusCallback: u.status,
    timeLimitSecs: USER_LEG_TIME_LIMIT, timeoutSecs: 25,
  });
  const at = ctx.now();
  if (outcome.kind === "accepted") {
    await inTransaction(ctx.db, async (c) => {
      await c.query("UPDATE call_takeovers SET state = 'ringing', twilio_call_sid = $2 WHERE id = $1 AND state = 'dialing'", [takeoverId, outcome.sid]);
      await c.query(
        `INSERT INTO call_cost_items (attempt_id, account_id, component, ref, status, due_by, next_try_at)
         VALUES ($1, $2, 'twilio_takeover', $3, 'pending', $4, $5), ($1, $2, 'twilio_conference', $3, 'pending', $4, $5)
         ON CONFLICT DO NOTHING`,
        [a.id, accountId, takeoverId, new Date(at.getTime() + 24 * 3600_000), new Date(at.getTime() + 120_000)]);
    });
    ctx.log("takeover leg dialled", { attemptId: a.id, takeoverId });
    return { kind: "started", takeoverId, state: "ringing" };
  }
  await ctx.db.query(
    "UPDATE call_takeovers SET state = $2, settled_at = CASE WHEN $2 = 'failed' THEN $3::timestamptz END WHERE id = $1",
    [takeoverId, outcome.kind === "rejected" ? "failed" : "unknown", at]);
  return { kind: "started", takeoverId, state: outcome.kind === "rejected" ? "failed" : "unknown" };
}

interface TakeoverRow {
  id: string; attempt_id: string; account_id: string; state: string; twilio_call_sid: string | null; conference_name: string;
  callee_joined_at: Date | null; user_joined_at: Date | null;
}

async function takeover(ctx: TaskCallContext, id: string): Promise<TakeoverRow | undefined> {
  if (!isUuid(id)) return undefined;
  const { rows } = await ctx.db.query<TakeoverRow>("SELECT * FROM call_takeovers WHERE id = $1", [id]);
  return rows[0];
}

const ownsLeg = (ctx: TaskCallContext, t: TakeoverRow, f: Form) =>
  field(f, "AccountSid") === ctx.telephony.accountSid && t.twilio_call_sid !== null && field(f, "CallSid") === t.twilio_call_sid;

/** The user picked up their phone: ask for 1, unless the call is already over. */
export async function onTakeoverAnswer(ctx: TaskCallContext, takeoverId: string, f: Form): Promise<string> {
  const t = await takeover(ctx, takeoverId);
  if (!t || field(f, "AccountSid") !== ctx.telephony.accountSid) return hangUp();
  // The SID may not be stored yet if Twilio answers faster than our own write.
  if (!t.twilio_call_sid) {
    await ctx.db.query("UPDATE call_takeovers SET twilio_call_sid = $2 WHERE id = $1 AND twilio_call_sid IS NULL", [t.id, field(f, "CallSid")]);
    t.twilio_call_sid = field(f, "CallSid");
  }
  if (!ownsLeg(ctx, t, f)) return hangUp();
  const { rows } = await ctx.db.query<{ state: string; account_id: string; case_id: string; payload_ciphertext: Buffer | null }>(
    `SELECT a.state, a.account_id, a.case_id, c.payload_ciphertext FROM call_attempts a JOIN call_cases c ON c.id = a.case_id WHERE a.id = $1`,
    [t.attempt_id]);
  const a = rows[0];
  if (!a || a.state !== "in_progress" || !a.payload_ciphertext || !["dialing", "ringing"].includes(t.state)) {
    await ctx.db.query("UPDATE call_takeovers SET state = 'failed', settled_at = $2 WHERE id = $1 AND settled_at IS NULL", [t.id, ctx.now()]);
    return sayAndHangUp(TAKEOVER_TOO_LATE, ctx.say);
  }
  await ctx.db.query("UPDATE call_takeovers SET state = 'prompted' WHERE id = $1 AND state IN ('dialing', 'ringing')", [t.id]);
  const payload = decryptPayload(ctx, a.account_id, a.case_id, a.payload_ciphertext);
  return takeoverPromptTwiml(takeoverPrompt(payload.display.callee.name), ctx.say, takeoverUrls(ctx, t.id).digits);
}

/** Pressed 1: hand the callee over first, then let the user join. Anything else: Doddy carries on. */
export async function onTakeoverDigits(ctx: TaskCallContext, takeoverId: string, f: Form): Promise<string> {
  const t = await takeover(ctx, takeoverId);
  if (!t || !ownsLeg(ctx, t, f)) return hangUp();
  const now = ctx.now();
  if (field(f, "Digits") !== "1") {
    await ctx.db.query("UPDATE call_takeovers SET state = 'declined', settled_at = $2 WHERE id = $1 AND state = 'prompted'", [t.id, now]);
    return sayAndHangUp(TAKEOVER_NOT_TAKEN, ctx.say);
  }
  const claimed = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; twilio_call_sid: string | null; ending_at: Date | null; account_id: string; case_id: string; payload_ciphertext: Buffer | null }>(
      `SELECT a.state, a.twilio_call_sid, a.ending_at, a.account_id, a.case_id, c.payload_ciphertext
       FROM call_attempts a JOIN call_cases c ON c.id = a.case_id WHERE a.id = $1 FOR UPDATE OF a`, [t.attempt_id]);
    const a = rows[0];
    const { rowCount } = await c.query("UPDATE call_takeovers SET state = 'joining' WHERE id = $1 AND state = 'prompted'", [t.id]);
    if (!rowCount || !a || a.state !== "in_progress" || a.ending_at || !a.twilio_call_sid || !a.payload_ciphertext) return undefined;
    // From here the AI part is over: no goodbye timer, no more transcript.
    await c.query("UPDATE call_attempts SET state = 'taken_over', taken_over_at = $2, hangup_due_at = NULL, updated_at = $2 WHERE id = $1", [t.attempt_id, now]);
    return { sid: a.twilio_call_sid, payload: decryptPayload(ctx, a.account_id, a.case_id, a.payload_ciphertext) };
  });
  if (!claimed) {
    await ctx.db.query("UPDATE call_takeovers SET state = 'failed', settled_at = $2 WHERE id = $1 AND settled_at IS NULL", [t.id, now]);
    return sayAndHangUp(TAKEOVER_TOO_LATE, ctx.say);
  }
  const u = takeoverUrls(ctx, t.id);
  const redirect = await ctx.telephony.updateCall(claimed.sid, {
    twiml: calleeHandoverTwiml(handoverLine(claimed.payload.display.principal.genitive), ctx.say, t.conference_name, u.conference),
  });
  if (redirect.kind === "not_in_progress" || redirect.kind === "rejected") {
    await ctx.db.query("UPDATE call_takeovers SET state = 'failed', settled_at = $2 WHERE id = $1", [t.id, ctx.now()]);
    return sayAndHangUp(TAKEOVER_TOO_LATE, ctx.say);
  }
  if (redirect.kind === "unknown") await ctx.db.query("UPDATE call_takeovers SET state = 'unknown' WHERE id = $1", [t.id]);
  ctx.log("takeover joining", { attemptId: t.attempt_id, takeoverId: t.id });
  // If the redirect didn't happen, the watchdog ends a conference with only the user in it.
  return userJoinTwiml(t.conference_name, u.conference);
}

/** Conference events: once both are in, the callee's time limit is raised to the user's. */
export async function onConference(ctx: TaskCallContext, takeoverId: string, f: Form): Promise<void> {
  const t = await takeover(ctx, takeoverId);
  if (!t || field(f, "AccountSid") !== ctx.telephony.accountSid) return;
  const event = field(f, "StatusCallbackEvent");
  const sid = field(f, "CallSid");
  const now = ctx.now();
  if (event === "conference-end") {
    await ctx.db.query("UPDATE call_takeovers SET state = 'ended', settled_at = $2 WHERE id = $1 AND settled_at IS NULL", [t.id, now]);
    return;
  }
  if (event !== "participant-join") return;
  const { rows: att } = await ctx.db.query<{ twilio_call_sid: string | null }>("SELECT twilio_call_sid FROM call_attempts WHERE id = $1", [t.attempt_id]);
  const calleeSid = att[0]?.twilio_call_sid;
  const column = sid === calleeSid ? "callee_joined_at" : sid === t.twilio_call_sid ? "user_joined_at" : undefined;
  if (!column) return;
  const { rows } = await ctx.db.query<{ both: boolean }>(
    `UPDATE call_takeovers SET ${column} = coalesce(${column}, $2) WHERE id = $1
     RETURNING (callee_joined_at IS NOT NULL AND user_joined_at IS NOT NULL) AS both`, [t.id, now]);
  if (rows[0]?.both) {
    const { rowCount } = await ctx.db.query(
      "UPDATE call_takeovers SET state = 'joined', joined_at = $2 WHERE id = $1 AND state IN ('joining', 'unknown')", [t.id, now]);
    if (rowCount && calleeSid) await ctx.telephony.updateCall(calleeSid, { timeLimitSecs: USER_LEG_TIME_LIMIT });
  }
}

/** The user's leg ended or never connected. */
export async function onTakeoverStatus(ctx: TaskCallContext, takeoverId: string, f: Form): Promise<void> {
  const t = await takeover(ctx, takeoverId);
  if (!t || field(f, "AccountSid") !== ctx.telephony.accountSid) return;
  if (t.twilio_call_sid && field(f, "CallSid") !== t.twilio_call_sid) return;
  const status = field(f, "CallStatus");
  if (!["completed", "busy", "no-answer", "failed", "canceled"].includes(status)) return;
  const now = ctx.now();
  await ctx.db.query(
    `UPDATE call_takeovers SET state = CASE WHEN state = 'joined' THEN 'ended' WHEN state = 'prompted' THEN 'declined' ELSE 'failed' END,
       settled_at = $2 WHERE id = $1 AND settled_at IS NULL`, [t.id, now]);
  await ctx.db.query("UPDATE call_cost_items SET next_try_at = $2 WHERE attempt_id = $1 AND ref = $3 AND status = 'pending'",
    [t.attempt_id, new Date(now.getTime() + 60_000), t.id]);
}

/** Watchdog: a takeover stuck half-joined for 20 s ends both legs, with no one left on hold. */
export async function endHalfJoined(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  const { rows } = await ctx.db.query<{ id: string; twilio_call_sid: string | null; callee_sid: string | null }>(
    `SELECT t.id, t.twilio_call_sid, a.twilio_call_sid AS callee_sid FROM call_takeovers t JOIN call_attempts a ON a.id = t.attempt_id
     WHERE t.state IN ('joining', 'unknown') AND t.joined_at IS NULL AND a.taken_over_at < $1`, [new Date(now.getTime() - JOIN_WATCHDOG_MS)]);
  for (const r of rows) {
    for (const sid of [r.twilio_call_sid, r.callee_sid]) if (sid) await ctx.telephony.updateCall(sid, { status: "completed" });
    await ctx.db.query("UPDATE call_takeovers SET state = 'failed', settled_at = $2 WHERE id = $1 AND settled_at IS NULL", [r.id, now]);
  }
  return rows.length;
}
