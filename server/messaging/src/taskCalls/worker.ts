// Background passes for call cases (run by the worker loop every couple of seconds). Each pass is
// safe to run in several processes at once: rows are claimed with SKIP LOCKED, leases or guarded updates.
import { canonicalJson } from "./payload.js";
import { inTransaction } from "../db.js";
import { canPush, enqueue } from "../outbox.js";
import { hmacSha256 } from "../crypto.js";
import type { TaskCallContext } from "./context.js";
import { purgePayload, receipt } from "./cases.js";
import { buildCallResult, type CallResult, type Line, type WriterOutput } from "./result.js";
import { decryptPayload, dialAttempt, endCall, inputAad, liveAad, resultAad, STALE_DIALING_MS } from "./service.js";
import { endHalfJoined } from "./takeover.js";
import { onStatus, queueConversationDeletion } from "./webhooks.js";
import type { CallPayload } from "./payload.js";

const LIVE = "state IN ('dialing','ringing','connecting','in_progress') OR (state = 'unknown' AND settled_at IS NULL)";
const RESULT_LEASE_MS = 5 * 60_000;
const NON_RETRYABLE = new Set(["answered", "taken_over", "wrong_number", "ivr", "no_conversation", "stopped"]);

export interface PassCounts { [pass: string]: number }

export async function runTaskCallPasses(ctx: TaskCallContext, state: { lastSweep: number }): Promise<PassCounts> {
  const counts: PassCounts = {};
  const run = async (name: string, fn: () => Promise<number>) => {
    try {
      const n = await fn();
      if (n) counts[name] = n;
    } catch (err) {
      ctx.log("task-call pass failed", { pass: name, error: (err as Error).message.slice(0, 200) });
    }
  };
  if (ctx.settings.killSwitch) await run("killSwitch", () => killSweep(ctx));
  await run("dialDue", () => dialDue(ctx));
  await run("goodbyeDue", () => goodbyeDue(ctx));
  await run("reendStuck", () => reendStuck(ctx));
  await run("reap", () => reapStale(ctx));
  await run("takeoverWatchdog", () => endHalfJoined(ctx));
  await run("results", () => processResults(ctx));
  await run("costs", () => settleCosts(ctx));
  await run("deletions", () => runDeletions(ctx));
  await run("expire", () => expire(ctx));
  if (Date.now() - state.lastSweep > 3 * 3600_000) {
    state.lastSweep = Date.now();
    await run("orphans", () => sweepOrphans(ctx));
    await run("drift", async () => (await ctx.drift.refresh()).length);
  }
  return counts;
}

/** Kill switch on: nothing scheduled dials, and every call still in its AI part ends now. */
export async function killSweep(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  const cancelled = await ctx.db.query(
    `UPDATE call_attempts SET state = 'cancelled', end_reason = 'gate_refused', error_code = 'kill_switch', settled_at = $1, updated_at = $1
     WHERE state = 'scheduled' RETURNING id, account_id`, [now]);
  for (const r of cancelled.rows as { id: string; account_id: string }[]) {
    await ctx.db.query("INSERT INTO call_results (attempt_id, account_id, state, process_after) VALUES ($1, $2, 'waiting', $3) ON CONFLICT DO NOTHING",
      [r.id, r.account_id, now]);
  }
  const { rows } = await ctx.db.query<{ id: string }>(`SELECT id FROM call_attempts WHERE (${LIVE}) AND ending_at IS NULL`);
  for (const r of rows) await endCall(ctx, r.id, "kill_switch");
  return (cancelled.rowCount ?? 0) + rows.length;
}

async function dialDue(ctx: TaskCallContext): Promise<number> {
  const { rows } = await ctx.db.query<{ id: string }>(
    "SELECT id FROM call_attempts WHERE state = 'scheduled' AND dial_not_before <= $1 ORDER BY dial_not_before LIMIT 5", [ctx.now()]);
  for (const r of rows) await dialAttempt(ctx, r.id);
  return rows.length;
}

/** The approved maximum is reached: Doddy says goodbye and the call ends. */
async function goodbyeDue(ctx: TaskCallContext): Promise<number> {
  const { rows } = await ctx.db.query<{ id: string }>(
    "SELECT id FROM call_attempts WHERE state = 'in_progress' AND ending_at IS NULL AND hangup_due_at <= $1 LIMIT 20", [ctx.now()]);
  for (const r of rows) await endCall(ctx, r.id, "time_limit");
  return rows.length;
}

/** A goodbye that didn't end the call within 30 s: hang up without it. */
async function reendStuck(ctx: TaskCallContext): Promise<number> {
  const { rows } = await ctx.db.query<{ id: string; twilio_call_sid: string }>(
    `SELECT id, twilio_call_sid FROM call_attempts WHERE (${LIVE}) AND ending_at < $1 AND twilio_call_sid IS NOT NULL LIMIT 20`,
    [new Date(ctx.now().getTime() - 30_000)]);
  for (const r of rows) await ctx.telephony.updateCall(r.twilio_call_sid, { status: "completed" });
  return rows.length;
}

/** Attempts no callback has settled: ask Twilio, or settle as unknown. Never redials. */
async function reapStale(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  const stale = await ctx.db.query(
    "UPDATE call_attempts SET state = 'unknown', error_code = coalesce(error_code, 'no_answer_from_server'), updated_at = $1 WHERE state = 'dialing' AND dial_started_at < $2",
    [now, new Date(now.getTime() - STALE_DIALING_MS)]);
  const { rows } = await ctx.db.query<{ id: string; account_id: string; twilio_call_sid: string | null }>(
    `SELECT id, account_id, twilio_call_sid FROM call_attempts
     WHERE ((${LIVE}) AND updated_at < $1::timestamptz - make_interval(secs => time_limit_secs + 900))
        OR (state = 'taken_over' AND settled_at IS NULL AND updated_at < $1::timestamptz - interval '45 minutes')
     LIMIT 10`, [now]);
  for (const r of rows) {
    if (r.twilio_call_sid) {
      const call = await ctx.telephony.fetchCall(r.twilio_call_sid);
      if (call.kind === "ok" && ["completed", "busy", "no-answer", "failed", "canceled"].includes(call.call.status)) {
        await onStatus(ctx, r.id, { AccountSid: ctx.telephony.accountSid, CallSid: r.twilio_call_sid, CallStatus: call.call.status,
          CallDuration: call.call.durationSecs === null ? "" : String(call.call.durationSecs) });
        continue;
      }
      if (call.kind === "ok") continue; // still running: look again later
    }
    await inTransaction(ctx.db, async (c) => {
      await c.query("UPDATE call_attempts SET settled_at = $2, updated_at = $2 WHERE id = $1 AND state = 'unknown' AND settled_at IS NULL", [r.id, now]);
      await c.query("INSERT INTO call_results (attempt_id, account_id, state, process_after) VALUES ($1, $2, 'waiting', $3) ON CONFLICT DO NOTHING",
        [r.id, r.account_id, now]);
    });
  }
  return (stale.rowCount ?? 0) + rows.length;
}

// ---------- results ----------

interface ResultRow {
  attempt_id: string; account_id: string; case_id: string; input_ciphertext: Buffer | null; end_reason: string | null;
  answered_at: Date | null; voice_connected_at: Date | null; taken_over_at: Date | null; duration_secs: number | null;
  payload_ciphertext: Buffer | null; attempt_no: number;
}

export async function processResults(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  // Lease a few rows, so a slow model call never blocks other workers and a crash retries later.
  const { rows } = await ctx.db.query<ResultRow>(
    `UPDATE call_results r SET process_after = $2
     FROM call_attempts a JOIN call_cases c ON c.id = a.case_id
     WHERE r.attempt_id = a.id AND r.attempt_id IN (
       SELECT r2.attempt_id FROM call_results r2 JOIN call_attempts a2 ON a2.id = r2.attempt_id
       WHERE r2.state = 'waiting' AND r2.process_after <= $1 AND a2.settled_at IS NOT NULL
       ORDER BY r2.process_after LIMIT 5 FOR UPDATE OF r2 SKIP LOCKED)
     RETURNING r.attempt_id, r.account_id, a.case_id, r.input_ciphertext, a.end_reason, a.answered_at, a.voice_connected_at,
       a.taken_over_at, a.duration_secs, c.payload_ciphertext, a.attempt_no`,
    [now, new Date(now.getTime() + RESULT_LEASE_MS)]);
  for (const r of rows) await buildAndStore(ctx, r);
  return rows.length;
}

async function buildAndStore(ctx: TaskCallContext, r: ResultRow) {
  const now = ctx.now();
  const payload: CallPayload | undefined = r.payload_ciphertext ? decryptPayload(ctx, r.account_id, r.case_id, r.payload_ciphertext) : undefined;
  let transcript: Line[] = [];
  let source: CallResult["source"] = "none";
  let voicemailToolUsed = false;
  if (r.input_ciphertext) {
    const input = JSON.parse(ctx.cipher.decrypt(r.input_ciphertext, inputAad(r.account_id, r.attempt_id))) as
      { turns: { role: "doddy" | "callee"; text: string; atSecs: number | null; tools: string[] }[] };
    transcript = input.turns.map((t) => ({ speaker: t.role, text: t.text, atSecs: t.atSecs }));
    voicemailToolUsed = input.turns.some((t) => t.tools.includes("voicemail_detection"));
    source = "elevenlabs";
  } else {
    const { rows } = await ctx.db.query<{ transcription_sid: string; seq: number; speaker: "doddy" | "callee"; ciphertext: Buffer }>(
      "SELECT transcription_sid, seq, speaker, ciphertext FROM call_live_lines WHERE attempt_id = $1 ORDER BY received_at, transcription_sid, seq",
      [r.attempt_id]);
    transcript = rows.flatMap((l) => {
      try { return [{ speaker: l.speaker, text: ctx.cipher.decrypt(l.ciphertext, liveAad(r.account_id, r.attempt_id, l.transcription_sid, l.seq)), atSecs: null }]; }
      catch { return []; }
    });
    if (transcript.length) source = "twilio_live";
  }
  const takenOverAtSecs = r.taken_over_at && r.answered_at ? Math.round((r.taken_over_at.getTime() - r.answered_at.getTime()) / 1000) : null;
  let writer: WriterOutput | undefined;
  if (ctx.writer && payload && transcript.some((l) => l.speaker === "callee") && r.voice_connected_at) {
    try {
      writer = await ctx.writer.write({ question: payload.display.question, goal: payload.display.goal, transcript });
    } catch (err) {
      ctx.log("call result writer failed; using rules", { attemptId: r.attempt_id, error: (err as Error).message.slice(0, 80) });
    }
  }
  const result = buildCallResult({
    endReason: (r.end_reason as never) ?? null,
    answered: r.answered_at !== null,
    voiceConnected: r.voice_connected_at !== null,
    takenOverAtSecs,
    durationSecs: r.duration_secs,
    question: payload?.display.question ?? "",
    callbackLine: payload?.agent.variables.doddy_callback_line ?? "Sprawdzę to u",
    allowedTexts: payload ? [payload.agent.variables.doddy_opening_line, payload.display.question, ...payload.display.facts.map((x) => x.text)] : [],
    transcript, source, voicemailToolUsed, writer,
  });
  const json = canonicalJson(result);
  const digest = hmacSha256(ctx.cipher.derivedKey("call-result-digest"), json);
  await inTransaction(ctx.db, async (c) => {
    const { rowCount } = await c.query(
      `UPDATE call_results SET state = 'ready', outcome = $2, source = $3, confidence = $4, warning_count = $5, key_version = $6,
         ciphertext = $7, result_digest = $8, input_source = NULL, input_key_version = NULL, input_ciphertext = NULL,
         ready_at = $9, expires_at = $9::timestamptz + interval '7 days'
       WHERE attempt_id = $1 AND state = 'waiting'`,
      [r.attempt_id, result.outcome, result.source, result.confidence, result.warnings.length, ctx.cipher.keyVersion,
        ctx.cipher.encrypt(json, resultAad(r.account_id, r.attempt_id)), digest, now]);
    if (!rowCount) return;
    if (r.input_ciphertext) await receipt(c, r.account_id, r.case_id, r.attempt_id, "call_input", "processed", 1, now);
    const lines = await c.query("DELETE FROM call_live_lines WHERE attempt_id = $1", [r.attempt_id]);
    if (lines.rowCount) await receipt(c, r.account_id, r.case_id, r.attempt_id, "live_lines", "processed", lines.rowCount, now);
    // The conversation at ElevenLabs goes now that its cost and transcript are captured.
    await c.query(
      "UPDATE server_data_deletions SET next_try_at = $2 WHERE attempt_id = $1 AND item = 'elevenlabs_conversation' AND result = 'pending'",
      [r.attempt_id, now]);
    if (writer?.usage) {
      await c.query(
        `INSERT INTO call_cost_items (attempt_id, account_id, component, status, amount_micros, currency, quantity, unit, due_by, settled_at)
         VALUES ($1, $2, 'model', $3, $4, $5, $6, 'token', $7, $7) ON CONFLICT DO NOTHING`,
        [r.attempt_id, r.account_id, ...modelCost(writer.usage), now]);
    }
    if (NON_RETRYABLE.has(result.outcome) || r.attempt_no >= 3) {
      await c.query("UPDATE call_cases SET state = 'finished', updated_at = $2 WHERE id = $1 AND state = 'active'", [r.case_id, now]);
    }
    if (ctx.push && await canPush(c, r.account_id)) {
      // Never the answer itself: only that one is waiting.
      await enqueue(c, r.account_id, ["push"], "Doddy skończył rozmowę. Odpowiedź czeka w aplikacji.", now, `call-result:${r.attempt_id}`, { cipher: ctx.cipher });
    }
  });
  ctx.log("call result ready", { attemptId: r.attempt_id, outcome: result.outcome, confidence: result.confidence, source: result.source });
}

/**
 * Claude Haiku 5.5 list prices (USD per million tokens, prompts up to 100K): input 0.10, output 0.50
 * (Anthropic model table, checked 2026-10-18). Marked "estimated": the provider bills, we only multiply.
 * Tokens × USD-per-million = micro-dollars.
 */
export const MODEL_PRICE_PER_MTOK = { input: 0.1, output: 0.5 };
function modelCost(u: { inputTokens: number; outputTokens: number }): [string, number, string, number] {
  const micros = Math.round(u.inputTokens * MODEL_PRICE_PER_MTOK.input + u.outputTokens * MODEL_PRICE_PER_MTOK.output);
  return ["estimated", micros, "USD", u.inputTokens + u.outputTokens];
}

// ---------- costs ----------

interface CostRow {
  attempt_id: string; component: string; ref: string; tries: number; due_by: Date; twilio_call_sid: string | null;
  takeover_sid: string | null; voice_connected_at: Date | null; ended_at: Date | null; taken_over_at: Date | null; settled_at: Date | null;
  el_conversation_id: string | null; joined_at: Date | null; takeover_settled_at: Date | null;
}

export async function settleCosts(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  const { rows } = await ctx.db.query<CostRow>(
    `SELECT i.attempt_id, i.component, i.ref, i.tries, i.due_by, a.twilio_call_sid, t.twilio_call_sid AS takeover_sid,
            a.voice_connected_at, a.ended_at, a.taken_over_at, a.settled_at, a.el_conversation_id, t.joined_at, t.settled_at AS takeover_settled_at
     FROM call_cost_items i JOIN call_attempts a ON a.id = i.attempt_id
     LEFT JOIN call_takeovers t ON t.id::text = i.ref
     WHERE i.status = 'pending' AND i.next_try_at <= $1 ORDER BY i.next_try_at LIMIT 20`, [now]);
  for (const r of rows) {
    const settle = (status: "reported" | "estimated" | "zero" | "unknown", amount: number | null, currency: string | null, quantity: number | null, unit: string | null) =>
      ctx.db.query(
        `UPDATE call_cost_items SET status = $4, amount_micros = $5, currency = $6, quantity = $7, unit = $8, settled_at = $9, next_try_at = NULL
         WHERE attempt_id = $1 AND component = $2 AND ref = $3 AND status = 'pending'`,
        [r.attempt_id, r.component, r.ref, status, amount, currency, quantity, unit, now]);
    const later = () => ctx.db.query(
      `UPDATE call_cost_items SET tries = tries + 1, next_try_at = $4 WHERE attempt_id = $1 AND component = $2 AND ref = $3 AND status = 'pending'`,
      [r.attempt_id, r.component, r.ref, new Date(now.getTime() + Math.min(2 ** r.tries * 60_000, 4 * 3600_000))]);
    const overdue = now > r.due_by;
    const prices = ctx.settings.prices;

    if (r.component === "twilio_call" || r.component === "twilio_takeover") {
      const sid = r.component === "twilio_call" ? r.twilio_call_sid : r.takeover_sid;
      if (!sid) { if (overdue) await settle("unknown", null, null, null, null); else await later(); continue; }
      const call = await ctx.telephony.fetchCall(sid);
      if (call.kind === "ok" && call.call.price !== null && call.call.priceUnit && /^-?\d+(\.\d+)?$/.test(call.call.price)) {
        const micros = Math.round(Math.abs(Number(call.call.price)) * 1e6);
        await settle(micros === 0 ? "zero" : "reported", micros, call.call.priceUnit.toUpperCase(), call.call.durationSecs === null ? null : call.call.durationSecs / 60, "minute");
      } else if (call.kind === "not_found" || overdue) {
        await settle("unknown", null, null, null, null);
      } else {
        await later(); // Twilio fills the price a while after the call
      }
      continue;
    }
    if (r.component === "twilio_transcription") {
      if (!r.settled_at) { await later(); continue; }
      if (!r.voice_connected_at) { await settle("zero", 0, "USD", 0, "minute"); continue; }
      const end = r.taken_over_at ?? r.ended_at ?? now;
      const minutes = Math.ceil(Math.max(0, end.getTime() - r.voice_connected_at.getTime()) / 60_000);
      if (prices.transcriptionUsdPerMin === undefined) await settle("unknown", null, null, minutes, "minute");
      else await settle("estimated", Math.round(minutes * prices.transcriptionUsdPerMin * 1e6), "USD", minutes, "minute");
      continue;
    }
    if (r.component === "twilio_conference") {
      if (!r.takeover_settled_at) { if (overdue) await settle("unknown", null, null, null, null); else await later(); continue; }
      if (!r.joined_at) { await settle("zero", 0, "USD", 0, "participant_minute"); continue; }
      const minutes = 2 * Math.ceil(Math.max(0, r.takeover_settled_at.getTime() - r.joined_at.getTime()) / 60_000);
      if (prices.conferenceUsdPerParticipantMin === undefined) await settle("unknown", null, null, minutes, "participant_minute");
      else await settle("estimated", Math.round(minutes * prices.conferenceUsdPerParticipantMin * 1e6), "USD", minutes, "participant_minute");
      continue;
    }
    if (r.component === "elevenlabs_voice") {
      // Normally set by the post-call webhook. Otherwise read it from the conversation, if known.
      if (r.el_conversation_id) {
        const conv = await ctx.voice.getConversation(r.el_conversation_id);
        const credits = conv.kind === "ok" ? conv.conversation.metadata.cost : undefined;
        if (typeof credits === "number") {
          const p = prices.elevenLabsUsdPerCredit;
          await settle(p === undefined ? "unknown" : "estimated", p === undefined ? null : Math.round(credits * p * 1e6), p === undefined ? null : "USD", credits, "credit");
          continue;
        }
      }
      if (overdue) await settle("unknown", null, null, null, null); else await later();
      continue;
    }
    if (overdue) await settle("unknown", null, null, null, null); else await later();
  }
  return rows.length;
}

// ---------- deletions ----------

/** Deletes conversations at ElevenLabs; "deleted" only once a read confirms it is gone. */
export async function runDeletions(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  const { rows } = await ctx.db.query<{ id: string; provider_ref: string; tries: number; attempt_id: string | null }>(
    `SELECT id, provider_ref, tries, attempt_id FROM server_data_deletions
     WHERE result = 'pending' AND location = 'elevenlabs' AND next_try_at <= $1 ORDER BY next_try_at LIMIT 10`, [now]);
  for (const r of rows) {
    // Capture the voice cost first if it is still missing.
    if (r.attempt_id) {
      const { rows: pending } = await ctx.db.query("SELECT 1 FROM call_cost_items WHERE attempt_id = $1 AND component = 'elevenlabs_voice' AND status = 'pending'", [r.attempt_id]);
      if (pending.length) {
        await ctx.db.query("UPDATE call_cost_items SET next_try_at = $2 WHERE attempt_id = $1 AND component = 'elevenlabs_voice' AND status = 'pending'", [r.attempt_id, now]);
        await ctx.db.query("UPDATE call_attempts SET el_conversation_id = coalesce(el_conversation_id, $2) WHERE id = $1", [r.attempt_id, r.provider_ref]);
        await settleCosts(ctx);
      }
    }
    const del = await ctx.voice.deleteConversation(r.provider_ref);
    let result: "deleted" | "not_found" | "failed" | undefined;
    if (del === "not_found") result = "not_found";
    else if (del === "deleted") {
      const check = await ctx.voice.getConversation(r.provider_ref);
      if (check.kind === "not_found") result = "deleted";
    }
    if (!result && r.tries + 1 >= 10) result = "failed";
    if (result) {
      await ctx.db.query("UPDATE server_data_deletions SET result = $2, tries = tries + 1, settled_at = $3, next_try_at = NULL WHERE id = $1", [r.id, result, now]);
      if (result === "failed") ctx.log("ElevenLabs conversation could not be deleted", { deletionId: r.id });
    } else {
      await ctx.db.query("UPDATE server_data_deletions SET tries = tries + 1, next_try_at = $2 WHERE id = $1",
        [r.id, new Date(now.getTime() + Math.min(2 ** r.tries * 60_000, 6 * 3600_000))]);
    }
  }
  return rows.length;
}

/** Any conversation of the task agent older than a day that no waiting result needs is deleted. */
export async function sweepOrphans(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  const list = await ctx.voice.listConversations(ctx.config.agentId, Math.floor(now.getTime() / 1000) - 24 * 3600);
  if (list === "error") return 0;
  let queued = 0;
  for (const conv of list) {
    const { rows } = await ctx.db.query(
      `SELECT 1 FROM call_attempts a JOIN call_results r ON r.attempt_id = a.id WHERE a.el_conversation_id = $1 AND r.state = 'waiting'`, [conv.id]);
    if (rows.length) continue;
    await queueConversationDeletion(ctx, conv.id, null, null, null, "orphan", now);
    queued++;
  }
  return queued;
}

// ---------- expiry ----------

export async function expire(ctx: TaskCallContext): Promise<number> {
  const now = ctx.now();
  let n = 0;
  const { rows: results } = await ctx.db.query<{ attempt_id: string; account_id: string; case_id: string }>(
    `UPDATE call_results r SET state = 'expired', ciphertext = NULL, key_version = NULL, settled_at = $1
     FROM call_attempts a WHERE a.id = r.attempt_id AND r.state = 'ready' AND r.expires_at <= $1
     RETURNING r.attempt_id, r.account_id, a.case_id`, [now]);
  for (const r of results) await receipt(ctx.db, r.account_id, r.case_id, r.attempt_id, "call_result", "expired", 1, now);
  n += results.length;
  const { rows: lines } = await ctx.db.query<{ attempt_id: string; account_id: string; case_id: string; n: number }>(
    `WITH gone AS (DELETE FROM call_live_lines WHERE received_at < $1 RETURNING attempt_id, account_id)
     SELECT g.attempt_id, g.account_id, a.case_id, count(*)::int AS n FROM gone g JOIN call_attempts a ON a.id = g.attempt_id
     GROUP BY g.attempt_id, g.account_id, a.case_id`, [new Date(now.getTime() - 24 * 3600_000)]);
  for (const l of lines) await receipt(ctx.db, l.account_id, l.case_id, l.attempt_id, "live_lines", "expired", l.n, now);
  n += lines.length;
  const { rows: cases } = await ctx.db.query<{ id: string; account_id: string; state: string }>(
    `SELECT c.id, c.account_id, c.state FROM call_cases c WHERE c.payload_ciphertext IS NOT NULL AND c.approvable_until <= $1
       AND NOT EXISTS (SELECT 1 FROM call_attempts a WHERE a.case_id = c.id
         AND (a.state IN ('scheduled','dialing','ringing','connecting','in_progress','taken_over') OR (a.state = 'unknown' AND a.settled_at IS NULL)))
       AND NOT EXISTS (SELECT 1 FROM call_attempts a JOIN call_results r ON r.attempt_id = a.id WHERE a.case_id = c.id AND r.state = 'waiting')
     LIMIT 20`, [now]);
  for (const c of cases) {
    await inTransaction(ctx.db, (tx) => purgePayload(tx, c.account_id, c.id, c.state === "awaiting_approval" ? "expired" : "finished", "expired", now));
  }
  return n + cases.length;
}

/** Before an account is deleted: end its calls and make sure ElevenLabs copies are deleted promptly. */
export async function beforeAccountDeleted(ctx: TaskCallContext, accountId: string): Promise<void> {
  const { rows } = await ctx.db.query<{ id: string; el_conversation_id: string | null }>(
    "SELECT id, el_conversation_id FROM call_attempts WHERE account_id = $1", [accountId]);
  const now = ctx.now();
  for (const r of rows) {
    await endCall(ctx, r.id, "account_deleted");
    if (r.el_conversation_id) await queueConversationDeletion(ctx, r.el_conversation_id, accountId, null, r.id, "account_deleted", now);
  }
  await ctx.db.query(
    "UPDATE server_data_deletions SET next_try_at = $2 WHERE account_id = $1 AND result = 'pending'", [accountId, now]);
}
