// Call tasks (decision docs/decisions/2026-11-09-restaurant-calls-one-tap.md): up to three places,
// approved with one tap, called one after another until one says yes.
//
// What keeps a task inside its approval:
//   - each place is an ordinary call case, checked and compiled by the same code as a single case
//     (compileCase), with its own encrypted payload and digest;
//   - the task digest covers every case digest in order and the "text me the result" choice, so one
//     approval is bound to exactly those calls and that text; a place's attempt still references its
//     own case digest by foreign key;
//   - a place is called only after the previous one ended without a yes, within `chain_until`, inside
//     calling hours, with the kill switch off; every dial gate runs again in dialAttempt;
//   - a yes needs the model's yes and a quote cut from the transcript; anything less stops the task as
//     "unclear" for the person to read, so Doddy never guesses and moves on.
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { z } from "zod";
import { hmacSha256, sameBytes } from "../crypto.js";
import { inTransaction, type Db } from "../db.js";
import { canPush, enqueue, SmsDailyLimit, smsNumber } from "../outbox.js";
import { purgePayload } from "./cases.js";
import type { TaskCallContext } from "./context.js";
import { callFits } from "./hours.js";
import { canonicalJson, previewOf, type CallPayload } from "./payload.js";
import type { CallResult, WriterOutput } from "./result.js";
import {
  compileCase, decryptPayload, DIAL_WINDOW_MINUTES, dialAttempt, insertCase, MAX_OPEN_CASES, openCaseCount, type CompiledCase, type Refusal,
} from "./service.js";

type Q = pg.PoolClient | Db;

export const MAX_PLACES = 3;
export const TASK_PREVIEW_MINUTES = 30;
/** How long one approval keeps calling the next place. The table caps it at 4 hours. */
export const CHAIN_HOURS = 3;
/** A task still active this long after chain_until (a result that never came) is closed as stopped. */
export const STUCK_AFTER_CHAIN_MS = 2 * 3600_000;

const ms = (minutes: number) => minutes * 60_000;
const plus = (d: Date, millis: number) => new Date(d.getTime() + millis);

/** Strict. The shared parts are checked again per place by the brief schema (compileCase). */
export const taskSchema = z.strictObject({
  kind: z.literal("ask"),
  places: z.array(z.unknown()).min(1).max(MAX_PLACES),
  principal: z.unknown(),
  goal: z.unknown(),
  question: z.unknown(),
  facts: z.array(z.unknown()).max(5).optional(),
  maxDurationSecs: z.number().int().optional(),
  /** "Text me the result": a text to the person's own verified number when the task ends. */
  textResult: z.boolean(),
});

export type TaskOutcome = "yes" | "none" | "unclear" | "stopped";
type Answer = "yes" | "no" | "unclear" | "none";

/** HMAC (derived key) of what the one tap approves: the case digests in order and the text choice. */
export function taskDigest(ctx: TaskCallContext, textResult: boolean, caseDigests: Buffer[]): Buffer {
  return hmacSha256(ctx.cipher.derivedKey("call-task-digest"),
    canonicalJson({ format: 1, kind: "ask", textResult, cases: caseDigests.map((d) => d.toString("hex")) }));
}

function refuse(status: Refusal["status"], error: string): { refusal: Refusal } {
  return { refusal: { status, error } as Refusal };
}

// ---------- create ----------

export async function createTask(ctx: TaskCallContext, accountId: string, body: unknown) {
  if (ctx.settings.killSwitch) return refuse(503, "calls_disabled");
  const parsed = taskSchema.safeParse(body);
  if (!parsed.success) return { refusal: { status: 400, error: "invalid_request", fields: parsed.error.issues.map((i) => i.path.join(".")) } as Refusal };
  const t = parsed.data;
  const compiled: CompiledCase[] = [];
  for (const [i, callee] of t.places.entries()) {
    const brief = { kind: t.kind, callee, principal: t.principal, goal: t.goal, question: t.question, facts: t.facts ?? [],
      ...(t.maxDurationSecs === undefined ? {} : { maxDurationSecs: t.maxDurationSecs }) };
    const r = await compileCase(ctx, accountId, brief, `places.${i}.`);
    if ("refusal" in r) return r;
    compiled.push(r.compiled);
  }
  if (new Set(compiled.map((c) => c.e164)).size !== compiled.length) return refuse(400, "duplicate_place");

  const now = ctx.now();
  const taskId = randomUUID();
  const digest = taskDigest(ctx, t.textResult, compiled.map((c) => c.digest));
  const approvableUntil = plus(now, ms(TASK_PREVIEW_MINUTES));
  const created = await inTransaction(ctx.db, async (c) => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('call_cases:' || $1))", [accountId]);
    if (await openCaseCount(c, accountId) + compiled.length > MAX_OPEN_CASES) return false;
    await c.query(
      `INSERT INTO call_tasks (id, account_id, kind, state, places, task_digest, text_result, approvable_until, created_at, updated_at)
       VALUES ($1, $2, 'ask', 'awaiting_approval', $3, $4, $5, $6, $7, $7)`,
      [taskId, accountId, compiled.length, digest, t.textResult, approvableUntil, now]);
    for (const [i, cc] of compiled.entries()) await insertCase(ctx, c, accountId, cc, approvableUntil, now, { id: taskId, position: i + 1 });
    return true;
  });
  if (!created) return refuse(409, "too_many_open_cases");
  const first = compiled[0]!;
  return {
    preview: {
      taskId, digest: digest.toString("hex"), approvableUntil: approvableUntil.toISOString(), kind: "ask" as const, textResult: t.textResult,
      places: compiled.map((cc) => previewOf(cc.payload, cc.digest, approvableUntil)),
      callableNow: callFits(now, first.brief.maxDurationSecs),
    },
  };
}

// ---------- approve ----------

interface TaskRow {
  id: string; account_id: string; state: string; places: number; task_digest: Buffer; text_result: boolean; approvable_until: Date;
  approved_device_id: string | null; chain_until: Date | null; created_at: Date;
}
interface TaskCaseRow { id: string; task_position: number; payload_digest: Buffer; max_duration_secs: number; state: string; created_at: Date }

async function taskCases(c: Q, taskId: string): Promise<TaskCaseRow[]> {
  const { rows } = await c.query<TaskCaseRow>(
    "SELECT id, task_position, payload_digest, max_duration_secs, state, created_at FROM call_cases WHERE task_id = $1 ORDER BY task_position",
    [taskId]);
  return rows;
}

/** One tap: the task starts, and its first place is called now. */
export async function approveTask(ctx: TaskCallContext, accountId: string, deviceId: string, taskId: string, digestHex: string) {
  if (ctx.settings.killSwitch) return refuse(503, "calls_disabled");
  const now = ctx.now();
  const given = Buffer.from(digestHex, "hex");
  const result = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<TaskRow>("SELECT * FROM call_tasks WHERE id = $1 AND account_id = $2 FOR UPDATE", [taskId, accountId]);
    const task = rows[0];
    if (!task) return refuse(404, "not_found");
    if (task.state !== "awaiting_approval" || task.approvable_until <= now) return refuse(409, "not_approvable");
    if (!sameBytes(task.task_digest, given)) return refuse(409, "digest_mismatch");
    const cases = await taskCases(c, taskId);
    // The stored cases must still be exactly what the digest covers.
    if (cases.length !== task.places || !sameBytes(taskDigest(ctx, task.text_result, cases.map((k) => k.payload_digest)), given)) {
      return refuse(409, "digest_mismatch");
    }
    const first = cases[0]!;
    if (!callFits(now, first.max_duration_secs)) return refuse(409, "outside_hours");
    const chainUntil = plus(now, CHAIN_HOURS * 3600_000);
    await c.query(
      `UPDATE call_tasks SET state = 'active', approved_at = $2, approved_device_id = $3, chain_until = $4, updated_at = $2 WHERE id = $1`,
      [taskId, now, deviceId, chainUntil]);
    // The places' payloads must outlive the chain (and a dial window), within the table's 2-day bound.
    await c.query(
      `UPDATE call_cases SET approvable_until = LEAST($2::timestamptz, created_at + interval '2 days'), updated_at = $3 WHERE task_id = $1`,
      [taskId, plus(chainUntil, ms(DIAL_WINDOW_MINUTES + 60)), now]);
    return { attemptId: await startPlace(c, accountId, first, deviceId, now) };
  });
  if ("refusal" in result) return result;
  return { attemptId: result.attemptId, dial: await dialAttempt(ctx, result.attemptId) };
}

/** An attempt for one place, bound to that case's own digest; dialAttempt runs every gate before dialing. */
async function startPlace(c: Q, accountId: string, kase: TaskCaseRow, deviceId: string | null, now: Date): Promise<string> {
  const attemptId = randomUUID();
  await c.query(
    `INSERT INTO call_attempts (id, case_id, account_id, attempt_no, approved_digest, approved_at, approved_device_id,
       dial_not_before, dial_deadline, state, time_limit_secs, created_at, updated_at)
     VALUES ($1, $2, $3, 1, $4, $5, $6, $5, $7, 'scheduled', $8, $5, $5)`,
    [attemptId, kase.id, accountId, kase.payload_digest, now, deviceId, plus(now, ms(DIAL_WINDOW_MINUTES)), kase.max_duration_secs + 20]);
  await c.query("UPDATE call_cases SET state = 'active', updated_at = $2 WHERE id = $1", [kase.id, now]);
  return attemptId;
}

// ---------- after each place ----------

/** The place was rung but nobody there answered the question: the next place is called. */
const NOT_REACHED = new Set(["no_answer", "busy", "failed", "voicemail", "ivr", "wrong_number", "no_conversation"]);
/**
 * Ends the task: the person took over or ended it, or Doddy couldn't place the call or doesn't know
 * whether it happened (a gate, the voice being down, an unknown outcome). Moving on would repeat the
 * same failure on the next place, or report "nobody said yes" when nobody was asked.
 */
const STOPS = new Set(["taken_over", "stopped", "not_placed", "voice_unavailable", "unknown"]);

/** What the place's call means for the task. A yes needs the model's yes and a quote from the transcript. */
export function answerOf(result: CallResult, writer: WriterOutput | undefined): Answer | "stop" {
  if (STOPS.has(result.outcome)) return "stop";
  if (NOT_REACHED.has(result.outcome)) return "none";
  if (result.outcome !== "answered") return "unclear";
  if (writer?.answer === "yes" && result.quote && result.confidence !== "low" && result.warnings.length === 0) return "yes";
  if (writer?.answer === "no") return "no";
  return "unclear";
}

/**
 * Called in the same transaction that stores a task place's result. Moves the task on: the next
 * place, or the end with a push and, if chosen, a text to the person's own number.
 * Returns true when it handled the notifications (the caller then sends no per-call push).
 */
export async function advanceTask(c: Q, ctx: TaskCallContext, x: {
  accountId: string; caseId: string; attemptId: string; result: CallResult; writer: WriterOutput | undefined;
}): Promise<boolean> {
  const { rows: caseRows } = await c.query<{ task_id: string | null; task_position: number | null }>(
    "SELECT task_id, task_position FROM call_cases WHERE id = $1", [x.caseId]);
  const taskId = caseRows[0]?.task_id;
  const position = caseRows[0]?.task_position;
  if (!taskId || !position) return false;
  const now = ctx.now();
  const answer = answerOf(x.result, x.writer);
  await c.query("UPDATE call_cases SET task_answer = $2, state = 'finished', updated_at = $3 WHERE id = $1 AND state = 'active'",
    [x.caseId, answer === "stop" ? "none" : answer, now]);
  const { rows } = await c.query<TaskRow>("SELECT * FROM call_tasks WHERE id = $1 FOR UPDATE", [taskId]);
  const task = rows[0];
  if (!task || task.state !== "active") return true; // cancelled mid-way: nothing more, no message
  if (answer === "yes") return finishTask(c, ctx, task, "yes", position, x, now);
  if (answer === "unclear") return finishTask(c, ctx, task, "unclear", position, x, now);
  if (answer === "stop") return finishTask(c, ctx, task, "stopped", position, x, now);
  const next = (await taskCases(c, taskId)).find((k) => k.task_position === position + 1);
  if (!next) return finishTask(c, ctx, task, "none", null, x, now);
  const mayGoOn = !ctx.settings.killSwitch && task.chain_until !== null && now < task.chain_until && callFits(now, next.max_duration_secs)
    && next.state === "awaiting_approval";
  if (!mayGoOn) return finishTask(c, ctx, task, "stopped", position, x, now);
  await startPlace(c, task.account_id, next, task.approved_device_id, now);
  ctx.log("call task: next place", { taskId, position: position + 1 });
  return true;
}

async function finishTask(c: Q, ctx: TaskCallContext, task: TaskRow, outcome: TaskOutcome, position: number | null,
  x: { accountId: string; caseId: string; attemptId: string; result: CallResult }, now: Date): Promise<true> {
  await c.query(
    `UPDATE call_tasks SET state = 'finished', outcome = $2, outcome_position = $3, finished_at = $4, updated_at = $4 WHERE id = $1`,
    [task.id, outcome, position, now]);
  // The places never reached keep nothing: their briefs go now, with receipts.
  const { rows: waiting } = await c.query<{ id: string }>(
    "SELECT id FROM call_cases WHERE task_id = $1 AND state = 'awaiting_approval'", [task.id]);
  for (const w of waiting) await purgePayload(c, task.account_id, w.id, "cancelled", "cancelled", now);
  if (ctx.push && await canPush(c, task.account_id)) {
    // Never the answer itself on the Lock Screen: only that one is waiting (same kind as a single call's, so the app opens the recap).
    await enqueue(c, task.account_id, ["push"], "Doddy skończył dzwonić. Wynik czeka w aplikacji.", now, `call-result:${x.attemptId}`, { cipher: ctx.cipher });
  }
  if (task.text_result && await smsNumber(c, task.account_id)) {
    const text = await resultText(c, ctx, task, outcome, x);
    try {
      await enqueue(c, task.account_id, ["sms"], text, now, `call-task:${task.id}`, { cipher: ctx.cipher, smsCaps: ctx.smsCaps });
    } catch (err) {
      // At the daily cap the push and the app still carry the result; the task itself is done.
      if (!(err instanceof SmsDailyLimit)) throw err;
      ctx.log("call task: result text over the daily cap", { taskId: task.id });
    }
  }
  ctx.log("call task finished", { taskId: task.id, outcome });
  return true;
}

/** The result text, in Polish, built from the approved card and the quote cut from the transcript. At most 640 characters. */
async function resultText(c: Q, ctx: TaskCallContext, task: TaskRow, outcome: TaskOutcome,
  x: { accountId: string; caseId: string; result: CallResult }): Promise<string> {
  const placeName = await calleeName(c, ctx, task.account_id, x.caseId);
  const clip = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s);
  let text: string;
  switch (outcome) {
    case "yes":
      text = `Doddy: ${placeName} odpowiada: „${clip(x.result.quote?.text ?? "", 300)}”. Szczegóły w aplikacji Doddy.`;
      break;
    case "unclear":
      text = `Doddy: rozmowa z ${placeName} się odbyła, ale odpowiedź nie jest jasna. Sprawdź ją w aplikacji Doddy.`;
      break;
    case "none":
      text = task.places === 1
        ? `Doddy: ${placeName}: brak potwierdzenia. Szczegóły w aplikacji Doddy.`
        : `Doddy: żadne z ${task.places} miejsc nie potwierdziło. Szczegóły w aplikacji Doddy.`;
      break;
    case "stopped":
      text = "Doddy: zatrzymałem dzwonienie przed końcem listy. Szczegóły w aplikacji Doddy.";
      break;
  }
  return clip(text, 640);
}

/** The place's name as the approved card showed it; "miejsce" when its brief is already gone. */
async function calleeName(c: Q, ctx: TaskCallContext, accountId: string, caseId: string): Promise<string> {
  const { rows } = await c.query<{ payload_ciphertext: Buffer | null }>("SELECT payload_ciphertext FROM call_cases WHERE id = $1", [caseId]);
  const blob = rows[0]?.payload_ciphertext;
  if (!blob) return "miejsce";
  const payload: CallPayload = decryptPayload(ctx, accountId, caseId, blob);
  return payload.display.callee.name.slice(0, 80);
}

// ---------- read, cancel, expire ----------

export async function getTask(ctx: TaskCallContext, accountId: string, taskId: string) {
  const { rows } = await ctx.db.query<TaskRow & { outcome: string | null; outcome_position: number | null; finished_at: Date | null; approved_at: Date | null }>(
    "SELECT * FROM call_tasks WHERE id = $1 AND account_id = $2", [taskId, accountId]);
  const task = rows[0];
  if (!task) return undefined;
  const { rows: cases } = await ctx.db.query<{ id: string; task_position: number; state: string; task_answer: string | null; payload_ciphertext: Buffer | null; payload_digest: Buffer; approvable_until: Date }>(
    `SELECT id, task_position, state, task_answer, payload_ciphertext, payload_digest, approvable_until FROM call_cases
     WHERE task_id = $1 ORDER BY task_position`, [taskId]);
  return {
    taskId: task.id, kind: "ask", state: task.state, textResult: task.text_result,
    digest: task.state === "awaiting_approval" ? task.task_digest.toString("hex") : null,
    approvableUntil: task.approvable_until, approvedAt: task.approved_at, chainUntil: task.chain_until,
    outcome: task.outcome, outcomePosition: task.outcome_position, finishedAt: task.finished_at,
    places: cases.map((k) => ({
      position: k.task_position, caseId: k.id, state: k.state, answer: k.task_answer,
      preview: k.payload_ciphertext ? previewOf(decryptPayload(ctx, accountId, k.id, k.payload_ciphertext), k.payload_digest, k.approvable_until) : null,
    })),
  };
}

/** No more places are called; a call already ringing is ended with Zakończ on that place, as for any call. */
export async function cancelTask(ctx: TaskCallContext, accountId: string, taskId: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string }>("SELECT state FROM call_tasks WHERE id = $1 AND account_id = $2 FOR UPDATE", [taskId, accountId]);
    if (!rows[0]) return "not_found" as const;
    if (!["awaiting_approval", "active"].includes(rows[0].state)) return "ok" as const;
    await c.query("UPDATE call_tasks SET state = 'cancelled', updated_at = $2 WHERE id = $1", [taskId, now]);
    const { rows: cases } = await c.query<{ id: string }>(
      "SELECT id FROM call_cases WHERE task_id = $1 AND state = 'awaiting_approval'", [taskId]);
    for (const k of cases) await purgePayload(c, accountId, k.id, "cancelled", "cancelled", now);
    // A place scheduled but not dialed yet is cancelled too.
    await c.query(
      `UPDATE call_attempts a SET state = 'cancelled', end_reason = 'canceled', settled_at = $2, updated_at = $2
       FROM call_cases k WHERE a.case_id = k.id AND k.task_id = $1 AND a.state = 'scheduled'`, [taskId, now]);
    return "ok" as const;
  });
}

/** Unapproved tasks lapse; a task whose last result never came is closed as stopped. */
export async function expireTasks(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  const lapsed = await ctx.db.query(
    "UPDATE call_tasks SET state = 'expired', updated_at = $1 WHERE state = 'awaiting_approval' AND approvable_until <= $1", [now]);
  const stuck = await ctx.db.query(
    `UPDATE call_tasks SET state = 'finished', outcome = 'stopped', finished_at = $1, updated_at = $1
     WHERE state = 'active' AND chain_until < $2`, [now, new Date(now.getTime() - STUCK_AFTER_CHAIN_MS)]);
  return (lapsed.rowCount ?? 0) + (stuck.rowCount ?? 0);
}
