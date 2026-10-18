// What happens when Twilio or ElevenLabs calls us during and after a task call. Each handler checks
// that the request belongs to an attempt we created, in a state where it makes sense, and changes
// state only forward, so late or replayed callbacks change nothing.
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { inTransaction } from "../db.js";
import { conversationSchema } from "../providers/taskCalls.js";
import type { TaskCallContext } from "./context.js";
import { callFits } from "./hours.js";
import { TECHNICAL_APOLOGY } from "./opening.js";
import { ATTEMPT_VARIABLE, payloadDigest } from "./payload.js";
import { decryptPayload, inputAad, liveAad, urlsFor } from "./service.js";
import { agentAnswerTwiml, hangUp, parseAgentTwiml, sayAndHangUp } from "./twiml.js";

export type Form = Record<string, string | string[] | undefined>;
export const field = (f: Form, k: string) => { const v = f[k]; return (Array.isArray(v) ? v[0] : v) ?? ""; };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const isUuid = (s: unknown): s is string => typeof s === "string" && UUID.test(s);

interface AttemptRow {
  id: string; case_id: string; account_id: string; state: string; approved_digest: Buffer; twilio_call_sid: string | null;
  twilio_seq: number | null; answered_at: Date | null; voice_connected_at: Date | null; ending_at: Date | null; end_reason: string | null;
  taken_over_at: Date | null; settled_at: Date | null; max_duration_secs: number; payload_ciphertext: Buffer | null;
  live_activity_token: string | null; live_activity_env: "sandbox" | "production" | null; dial_started_at: Date | null;
}

async function attempt(ctx: TaskCallContext, id: string): Promise<AttemptRow | undefined> {
  if (!isUuid(id)) return undefined;
  const { rows } = await ctx.db.query<AttemptRow>(
    `SELECT a.*, c.max_duration_secs, c.payload_ciphertext, c.live_activity_token, c.live_activity_env
     FROM call_attempts a JOIN call_cases c ON c.id = a.case_id WHERE a.id = $1`, [id]);
  return rows[0];
}

/** The callback is about this attempt's call: same account, and the call SID it has (or links now). */
function ownsCall(ctx: TaskCallContext, a: AttemptRow, f: Form): boolean {
  if (field(f, "AccountSid") !== ctx.telephony.accountSid) return false;
  const sid = field(f, "CallSid");
  return /^CA[0-9a-f]{32}$/.test(sid) && (a.twilio_call_sid === null || a.twilio_call_sid === sid);
}

async function linkSid(ctx: TaskCallContext, a: AttemptRow, sid: string) {
  if (a.twilio_call_sid) return;
  await ctx.db.query("UPDATE call_attempts SET twilio_call_sid = $2, updated_at = $3 WHERE id = $1 AND twilio_call_sid IS NULL",
    [a.id, sid, ctx.now()]);
  a.twilio_call_sid = sid;
}

const apology = (ctx: TaskCallContext) => sayAndHangUp(TECHNICAL_APOLOGY, ctx.say);

// ---------- answer ----------

/**
 * Twilio asks what to do now that the callee picked up. Last gate before any voice: then the call is
 * registered with ElevenLabs (once) and live transcription starts. Any problem: the AI apology.
 */
export async function onAnswer(ctx: TaskCallContext, attemptId: string, f: Form): Promise<string> {
  const started = Date.now();
  const a = await attempt(ctx, attemptId);
  if (!a || !ownsCall(ctx, a, f)) return apology(ctx);
  await linkSid(ctx, a, field(f, "CallSid"));
  const now = ctx.now();
  // Claim the answer once: a replayed request never registers a second conversation.
  const { rowCount } = await ctx.db.query(
    `UPDATE call_attempts SET state = 'connecting', answered_at = coalesce(answered_at, $2), updated_at = $2
     WHERE id = $1 AND state IN ('dialing', 'ringing', 'unknown') AND ending_at IS NULL AND settled_at IS NULL`, [a.id, now]);
  if (!rowCount) return apology(ctx);
  const refuse = async (reason: "kill_switch" | "voice_unavailable" | "gate_refused", code: string) => {
    await ctx.db.query("UPDATE call_attempts SET end_reason = coalesce(end_reason, $2), error_code = coalesce(error_code, $3), updated_at = $4 WHERE id = $1",
      [a.id, reason, code, now]);
    ctx.log("task call answer refused", { attemptId: a.id, code });
    return apology(ctx);
  };
  if (ctx.settings.killSwitch) return refuse("kill_switch", "kill_switch");
  if (!callFits(now, a.max_duration_secs, 0)) return refuse("gate_refused", "outside_hours");
  if (ctx.drift.cached().length) return refuse("gate_refused", "agent_drift");
  if (!a.payload_ciphertext) return refuse("gate_refused", "case_closed");
  const payload = decryptPayload(ctx, a.account_id, a.case_id, a.payload_ciphertext);
  if (!payloadDigest(ctx.keys, payload).equals(a.approved_digest)) return refuse("gate_refused", "payload_mismatch");
  if (field(f, "To") !== payload.twilio.to || field(f, "From") !== payload.twilio.from) return refuse("gate_refused", "number_mismatch");

  const registerStarted = Date.now();
  const reg = await ctx.voice.registerCall({
    agentId: ctx.config.agentId, from: payload.twilio.from, to: payload.twilio.to,
    variables: { ...payload.agent.variables, [ATTEMPT_VARIABLE]: a.id },
  });
  const registerMs = Date.now() - registerStarted;
  if (reg.kind !== "ok") return refuse("voice_unavailable", reg.code);
  const stream = parseAgentTwiml(reg.twiml);
  if (!stream) return refuse("voice_unavailable", "elevenlabs_twiml_shape");
  await ctx.db.query(
    `UPDATE call_attempts SET state = 'in_progress', voice_connected_at = $2, hangup_due_at = $2::timestamptz + make_interval(secs => $3), updated_at = $2
     WHERE id = $1 AND state = 'connecting'`, [a.id, now, a.max_duration_secs]);
  const u = urlsFor(ctx, a.id);
  ctx.log("task call answered", { attemptId: a.id, answerMs: Date.now() - started, registerMs });
  await pushLiveActivity(ctx, a, { phase: "talking", answeredAtUnix: Math.floor(now.getTime() / 1000) }, false);
  return agentAnswerTwiml(stream, { transcription: u.transcription, connectEnded: u.connectEnded });
}

/** The agent's stream ended. A very quick end with no Doddy line means the voice failed: apologise. */
export async function onConnectEnded(ctx: TaskCallContext, attemptId: string, f: Form): Promise<string> {
  const a = await attempt(ctx, attemptId);
  if (!a || !ownsCall(ctx, a, f)) return hangUp();
  const quick = a.voice_connected_at && ctx.now().getTime() - a.voice_connected_at.getTime() < 3_000;
  if (quick) {
    const { rows } = await ctx.db.query<{ n: number }>("SELECT count(*)::int AS n FROM call_live_lines WHERE attempt_id = $1 AND speaker = 'doddy'", [a.id]);
    if ((rows[0]?.n ?? 0) === 0) {
      await ctx.db.query("UPDATE call_attempts SET end_reason = coalesce(end_reason, 'voice_unavailable') WHERE id = $1", [a.id]);
      return apology(ctx);
    }
  }
  return hangUp();
}

// ---------- status ----------

const FINAL: Record<string, "completed" | "busy" | "no_answer" | "failed" | "canceled"> = {
  completed: "completed", busy: "busy", "no-answer": "no_answer", failed: "failed", canceled: "canceled",
};

/** Twilio's call progress. Only moves forward; the SequenceNumber drops late or replayed callbacks. */
export async function onStatus(ctx: TaskCallContext, attemptId: string, f: Form): Promise<void> {
  const a = await attempt(ctx, attemptId);
  if (!a || !ownsCall(ctx, a, f)) {
    // A call we can't match (or one past its attempt) must not keep running.
    if (field(f, "AccountSid") === ctx.telephony.accountSid && /^CA[0-9a-f]{32}$/.test(field(f, "CallSid"))
      && field(f, "CallStatus") === "in-progress") {
      await ctx.telephony.updateCall(field(f, "CallSid"), { status: "completed" });
    }
    return;
  }
  await linkSid(ctx, a, field(f, "CallSid"));
  const seq = Number(field(f, "SequenceNumber"));
  if (Number.isInteger(seq) && a.twilio_seq !== null && seq <= a.twilio_seq) return;
  const status = field(f, "CallStatus");
  const now = ctx.now();
  const setSeq = Number.isInteger(seq) ? seq : null;
  if (status === "ringing") {
    await ctx.db.query(
      `UPDATE call_attempts SET state = CASE WHEN state IN ('dialing', 'unknown') THEN 'ringing' ELSE state END,
         twilio_seq = coalesce($2, twilio_seq), updated_at = $3 WHERE id = $1 AND settled_at IS NULL`, [a.id, setSeq, now]);
    await pushLiveActivity(ctx, a, { phase: "ringing" }, false);
    return;
  }
  if (status === "in-progress") {
    // The answer webhook moves the state; here only the time is recorded.
    await ctx.db.query("UPDATE call_attempts SET answered_at = coalesce(answered_at, $2), twilio_seq = coalesce($3, twilio_seq), updated_at = $2 WHERE id = $1",
      [a.id, now, setSeq]);
    return;
  }
  const final = FINAL[status];
  if (!final) return;
  const duration = /^\d+$/.test(field(f, "CallDuration")) ? Number(field(f, "CallDuration")) : null;
  const ended = await inTransaction(ctx.db, async (c) => {
    const answered = a.answered_at !== null || a.voice_connected_at !== null;
    const reason = final === "completed" ? (answered ? "completed" : "no_answer") : final;
    const { rows } = await c.query<{ voice_connected_at: Date | null }>(
      `UPDATE call_attempts SET state = 'ended', ended_at = $2, settled_at = $2, duration_secs = coalesce($3, duration_secs),
         end_reason = coalesce(end_reason, $4), twilio_seq = coalesce($5, twilio_seq), hangup_due_at = NULL, updated_at = $2
       WHERE id = $1 AND settled_at IS NULL RETURNING voice_connected_at`, [a.id, now, duration, reason, setSeq]);
    if (!rows[0]) return false;
    // Wait a little for the ElevenLabs transcript when there was a conversation.
    const wait = rows[0].voice_connected_at ? 3 * 60_000 : 0;
    await c.query(
      `INSERT INTO call_results (attempt_id, account_id, state, process_after) VALUES ($1, $2, 'waiting', $3)
       ON CONFLICT (attempt_id) DO UPDATE SET process_after = LEAST(call_results.process_after, EXCLUDED.process_after)
       WHERE call_results.state = 'waiting' AND call_results.input_ciphertext IS NULL`,
      [a.id, a.account_id, new Date(now.getTime() + wait)]);
    // Never answered: no transcription or voice was used.
    if (!rows[0].voice_connected_at) {
      await c.query(
        `UPDATE call_cost_items SET status = 'zero', amount_micros = 0, currency = 'USD', settled_at = $2, next_try_at = NULL
         WHERE attempt_id = $1 AND status = 'pending' AND component IN ('twilio_transcription', 'elevenlabs_voice')`, [a.id, now]);
    }
    // The cost of the call itself can be read soon after it ends.
    await c.query("UPDATE call_cost_items SET next_try_at = $2 WHERE attempt_id = $1 AND status = 'pending'", [a.id, new Date(now.getTime() + 60_000)]);
    // A case with a failed attempt stays retryable for a day.
    if (!rows[0].voice_connected_at) {
      await c.query(
        `UPDATE call_cases SET approvable_until = LEAST(GREATEST(approvable_until, $2::timestamptz + interval '1 day'), created_at + interval '2 days'), updated_at = $2
         WHERE id = $1`, [a.case_id, now]);
    }
    return true;
  });
  if (!ended) return;
  // A takeover leg still ringing is pointless now.
  const { rows: legs } = await ctx.db.query<{ id: string; twilio_call_sid: string | null }>(
    `SELECT id, twilio_call_sid FROM call_takeovers WHERE attempt_id = $1 AND state IN ('dialing', 'ringing', 'prompted')`, [a.id]);
  for (const leg of legs) {
    if (leg.twilio_call_sid) await ctx.telephony.updateCall(leg.twilio_call_sid, { status: "completed" });
    await ctx.db.query("UPDATE call_takeovers SET state = 'failed', settled_at = $2 WHERE id = $1 AND settled_at IS NULL", [leg.id, now]);
  }
  ctx.log("task call ended", { attemptId: a.id, status: final });
  await pushLiveActivity(ctx, a, { phase: "ended", endedAtUnix: Math.floor(now.getTime() / 1000) }, true);
}

// ---------- live transcription ----------

const transcriptionData = z.object({ transcript: z.string().max(4000) }).passthrough();

/** One final line of live transcript. Nothing is kept once the user took over or the call ended. */
export async function onTranscription(ctx: TaskCallContext, attemptId: string, f: Form): Promise<void> {
  if (field(f, "TranscriptionEvent") !== "transcription-content" || field(f, "Final") !== "true") return;
  const a = await attempt(ctx, attemptId);
  if (!a || !ownsCall(ctx, a, f) || a.twilio_call_sid === null) return;
  if (a.state !== "in_progress" || a.taken_over_at || a.settled_at) return;
  const sid = field(f, "TranscriptionSid");
  const seq = Number(field(f, "SequenceId"));
  if (!/^[A-Za-z0-9]{1,64}$/.test(sid) || !Number.isInteger(seq) || seq < 0) return;
  let text: string;
  try {
    const d = transcriptionData.safeParse(JSON.parse(field(f, "TranscriptionData")));
    if (!d.success) return;
    text = d.data.transcript.replace(/\s+/g, " ").trim();
  } catch {
    return;
  }
  if (!text) return;
  const speaker = field(f, "Track") === "inbound_track" ? "callee" : "doddy";
  await ctx.db.query(
    `INSERT INTO call_live_lines (attempt_id, account_id, transcription_sid, seq, speaker, key_version, ciphertext)
     VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT DO NOTHING`,
    [a.id, a.account_id, sid, seq, speaker, ctx.cipher.keyVersion, ctx.cipher.encrypt(text, liveAad(a.account_id, a.id, sid, seq))]);
}

// ---------- ElevenLabs post-call ----------

const envelope = z.object({ type: z.string(), data: z.object({ agent_id: z.string() }).passthrough() }).passthrough();

/**
 * The transcript and voice cost of a finished conversation. Payloads of any other agent (the S2
 * memory agent shares the workspace webhook) are dropped before anything else is read or logged.
 */
export async function onPostCall(ctx: TaskCallContext, json: unknown): Promise<void> {
  const env = envelope.safeParse(json);
  if (!env.success || env.data.data.agent_id !== ctx.config.agentId) return;
  if (env.data.type !== "post_call_transcription") return;
  const parsed = conversationSchema.safeParse(env.data.data);
  if (!parsed.success) { ctx.log("post-call payload unreadable", {}); return; }
  const conv = parsed.data;
  const attemptId = conv.conversation_initiation_client_data?.dynamic_variables?.[ATTEMPT_VARIABLE];
  const now = ctx.now();
  const a = isUuid(attemptId) ? await attempt(ctx, attemptId) : undefined;
  if (!a) {
    await queueConversationDeletion(ctx, conv.conversation_id, null, null, null, "orphan", now);
    return;
  }
  const turns = conv.transcript.map((t) => ({
    role: t.role === "agent" ? "doddy" : "callee",
    text: typeof t.message === "string" ? t.message : "",
    atSecs: typeof t.time_in_call_secs === "number" ? t.time_in_call_secs : null,
    tools: (t.tool_calls ?? []).map((x) => x.tool_name ?? "").filter(Boolean),
  }));
  const input = JSON.stringify({ turns, terminationReason: conv.metadata.termination_reason ?? null, durationSecs: conv.metadata.call_duration_secs ?? null });
  const stored = await inTransaction(ctx.db, async (c) => {
    await c.query("UPDATE call_attempts SET el_conversation_id = coalesce(el_conversation_id, $2) WHERE id = $1", [a.id, conv.conversation_id]);
    const { rowCount } = await c.query(
      `INSERT INTO call_results (attempt_id, account_id, state, input_source, input_key_version, input_ciphertext, process_after)
       VALUES ($1, $2, 'waiting', 'elevenlabs', $3, $4, $5)
       ON CONFLICT (attempt_id) DO UPDATE SET input_source = EXCLUDED.input_source, input_key_version = EXCLUDED.input_key_version,
         input_ciphertext = EXCLUDED.input_ciphertext, process_after = LEAST(call_results.process_after, EXCLUDED.process_after)
       WHERE call_results.state = 'waiting'`,
      [a.id, a.account_id, ctx.cipher.keyVersion, ctx.cipher.encrypt(input, inputAad(a.account_id, a.id)), now]);
    // Voice cost, read from the conversation before it is deleted.
    const credits = conv.metadata.cost;
    const price = ctx.settings.prices.elevenLabsUsdPerCredit;
    if (typeof credits === "number" && credits >= 0) {
      await c.query(
        `UPDATE call_cost_items SET status = $3, amount_micros = $4, currency = $5, quantity = $6, unit = 'credit', settled_at = $2, next_try_at = NULL
         WHERE attempt_id = $1 AND component = 'elevenlabs_voice' AND status IN ('pending', 'unknown')`,
        [a.id, now, price !== undefined ? "estimated" : "unknown", price !== undefined ? Math.round(credits * price * 1e6) : null,
          price !== undefined ? "USD" : null, credits]);
    }
    return (rowCount ?? 0) > 0;
  });
  // Deleted at ElevenLabs once the result is built; if it arrived after that, it isn't kept and goes now.
  await queueConversationDeletion(ctx, conv.conversation_id, a.account_id, a.case_id, a.id, "processed", now, stored);
}

/**
 * A deletion of the conversation at ElevenLabs. When `afterProcessing` is set, it runs once the
 * result is built (the worker sets next_try_at then); otherwise it runs right away.
 */
export async function queueConversationDeletion(
  ctx: TaskCallContext, conversationId: string, accountId: string | null, caseId: string | null, attemptId: string | null,
  reason: "processed" | "acked" | "orphan" | "account_deleted" | "expired", now: Date, afterProcessing = false,
): Promise<void> {
  await ctx.db.query(
    `INSERT INTO server_data_deletions (id, account_id, case_id, attempt_id, item, location, reason, result, provider_ref, next_try_at, requested_at)
     VALUES ($1, $2, $3, $4, 'elevenlabs_conversation', 'elevenlabs', $5, 'pending', $6, $7, $8)
     ON CONFLICT (location, item, provider_ref) WHERE location <> 'doddy_server' DO NOTHING`,
    [randomUUID(), accountId, caseId, attemptId, reason, conversationId,
      afterProcessing ? new Date(now.getTime() + 24 * 3600_000) : now, now]);
}

// ---------- Live Activity ----------

export async function pushLiveActivity(
  ctx: TaskCallContext, a: { live_activity_token: string | null; live_activity_env: "sandbox" | "production" | null },
  state: Record<string, unknown>, end: boolean,
): Promise<void> {
  if (!ctx.liveActivity || !a.live_activity_token || !a.live_activity_env) return;
  try {
    await ctx.liveActivity.update(a.live_activity_token, a.live_activity_env, state, end);
  } catch {
    // Best effort: the app also polls while it is open.
  }
}
