// Recaps of S2 calls (ADR-693): what happens with ElevenLabs' post-call payload for the phone agent, the
// worker pass that builds the recap, and what the app reads, acknowledges or deletes. Logs carry ids,
// states and counts only, never words from the call.
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { sameBytes, sha256, type TextCipher } from "../crypto.js";
import type { Db } from "../db.js";
import { inTransaction } from "../db.js";
import { canPush, enqueue } from "../outbox.js";
import type { PushSender } from "../providers/types.js";
import { takeServerSlot } from "../serverUsage.js";
import {
  buildRecap, callerSpoke, phoneConversationSchema, storedInputFrom, transcriptFrom,
  type CallRecap, type RecapNote, type RecapWriter, type RecapWriterOutput, type StoredInput, type SummaryNote,
} from "./recap.js";

export interface RecapSettings {
  /** Model-written recaps per account and UTC day; past it, the recap is built by the rules alone. */
  dailyPerAccount: number;
  /** The same for the whole server (server_daily_usage, so deleting an account doesn't give it back). */
  dailyPerServer: number;
}
export const DEFAULT_RECAP_SETTINGS: RecapSettings = { dailyPerAccount: 30, dailyPerServer: 300 };

/** What the server is configured with (providers/index.ts); tests pass their own. */
export interface CallRecapDeps {
  /** The S2 agent whose post-call payloads get a recap; payloads of other agents never reach this code. */
  phoneAgentId?: string;
  /** HMAC secret of the workspace post-call webhook (ELEVENLABS_WEBHOOK_SECRET). */
  webhookSecret?: string;
  /** Optional: writes the summary (Anthropic only). Without it every recap is built by the rules. */
  writer?: RecapWriter;
  settings?: RecapSettings;
  now?: () => Date;
}

export interface RecapContext {
  db: Db;
  cipher: TextCipher;
  phoneAgentId?: string;
  webhookSecret?: string;
  writer?: RecapWriter;
  settings: RecapSettings;
  push?: PushSender;
  now: () => Date;
  log: (msg: string, extra?: object) => void;
}

export function recapContext(
  db: Db, deps: CallRecapDeps | undefined, cipher: TextCipher | undefined, push: PushSender | undefined,
  log: (msg: string, extra?: object) => void,
): RecapContext | undefined {
  // Without the text key nothing about a call can be stored, so there is no recap.
  if (!cipher) return undefined;
  return {
    db, cipher, phoneAgentId: deps?.phoneAgentId, webhookSecret: deps?.webhookSecret, writer: deps?.writer,
    settings: deps?.settings ?? DEFAULT_RECAP_SETTINGS, push, now: deps?.now ?? (() => new Date()), log,
  };
}

export const RECAP_KEEP_DAYS = 30;
const LEASE_MINUTES = 5;
const MAX_WRITER_TRIES = 2;
const BATCH = 5;

const inputAad = (accountId: string, callId: string) => `${accountId}:call-recap-input:${callId}`;
const recapAad = (accountId: string, callId: string) => `${accountId}:call-recap:${callId}`;
const noteAad = (accountId: string, noteId: string) => `${accountId}:note:${noteId}`;

type Q = Pick<pg.PoolClient, "query">;

// ---------- the post-call payload ----------

export type PostCallOutcome = "stored" | "duplicate" | "unmatched" | "ignored" | "unreadable";

/**
 * Stores the transcript of a finished phone-agent call, encrypted, for the worker. Only a call that has a
 * `calls` row (a verified number with calls on, matched by conversation id or Twilio call SID) gets one;
 * anything else is dropped without being stored or logged beyond its outcome.
 */
export async function onPhonePostCall(ctx: RecapContext, json: unknown): Promise<PostCallOutcome> {
  const env = json as { type?: unknown; data?: unknown } | null;
  if (!env || env.type !== "post_call_transcription") return "ignored";
  const parsed = phoneConversationSchema.safeParse(env.data);
  if (!parsed.success) return "unreadable";
  const conv = parsed.data;
  const sid = conv.metadata.phone_call?.call_sid ?? null;
  const now = ctx.now();
  const { rows } = await ctx.db.query<{ id: string; account_id: string }>(
    `SELECT id, account_id FROM calls
     WHERE (conversation_id = $1 OR ($2::text IS NOT NULL AND call_sid = $2))
       AND created_at > $3::timestamptz - interval '2 days'
     ORDER BY created_at DESC LIMIT 1`, [conv.conversation_id, sid, now]);
  const call = rows[0];
  if (!call) return "unmatched";
  const input = storedInputFrom(conv);
  const stored = await inTransaction(ctx.db, async (c) => {
    await c.query("UPDATE calls SET conversation_id = coalesce(conversation_id, $2) WHERE id = $1", [call.id, conv.conversation_id]);
    const { rowCount } = await c.query(
      `INSERT INTO call_recaps (call_id, account_id, conversation_id, state, key_version, input_ciphertext, process_after, created_at)
       VALUES ($1, $2, $3, 'waiting', $4, $5, $6, $6) ON CONFLICT DO NOTHING`,
      [call.id, call.account_id, conv.conversation_id, ctx.cipher.keyVersion,
        ctx.cipher.encrypt(JSON.stringify(input), inputAad(call.account_id, call.id)), now]);
    return (rowCount ?? 0) > 0;
  });
  ctx.log("call recap input", { callId: call.id, outcome: stored ? "stored" : "duplicate", turns: input.turns.length });
  return stored ? "stored" : "duplicate";
}

// ---------- the worker ----------

interface Claimed { call_id: string; account_id: string; input_ciphertext: Buffer; attempts: number; direction: "inbound" | "outbound" }

/** Builds due recaps, then wipes recaps past their 30 days. Returns counts for the log. */
export async function runRecapPasses(ctx: RecapContext): Promise<Record<string, number>> {
  const counts: Record<string, number> = {};
  const add = (k: string) => { counts[k] = (counts[k] ?? 0) + 1; };
  const now = ctx.now();
  const { rows } = await ctx.db.query<Claimed>(
    `UPDATE call_recaps r SET state = 'building', lease_until = $1::timestamptz + make_interval(mins => $2), attempts = r.attempts + 1
     FROM calls c
     WHERE c.id = r.call_id AND r.call_id IN (
       SELECT call_id FROM call_recaps
       WHERE (state = 'waiting' AND process_after <= $1) OR (state = 'building' AND lease_until < $1)
       ORDER BY process_after LIMIT $3 FOR UPDATE SKIP LOCKED)
     RETURNING r.call_id, r.account_id, r.input_ciphertext, r.attempts, c.direction`, [now, LEASE_MINUTES, BATCH]);
  for (const row of rows) add(await buildOne(ctx, row));
  const expired = await expireRecaps(ctx);
  if (expired) counts.expired = expired;
  return counts;
}

async function buildOne(ctx: RecapContext, row: Claimed): Promise<string> {
  const now = ctx.now();
  let input: StoredInput | null = null;
  try {
    input = JSON.parse(ctx.cipher.decrypt(row.input_ciphertext, inputAad(row.account_id, row.call_id))) as StoredInput;
  } catch {
    input = null;
  }
  const notes = await notesOf(ctx, row.account_id, row.call_id);
  const facts = { callId: row.call_id, direction: row.direction, input, notes, now };

  let written: RecapWriterOutput | null = null;
  let reason: SummaryNote | null = null;
  let modelUsed = false;
  if (!input) reason = "transcript_unreadable";
  else if (!callerSpoke(input)) reason = "empty_call";
  else if (!ctx.writer) reason = "no_writer";
  else if (!(await takeWriterSlot(ctx, row.account_id, now))) reason = "daily_limit";
  else {
    modelUsed = true;
    const { lines, tools } = transcriptFrom(input);
    try {
      written = await ctx.writer.write({
        direction: row.direction,
        lines: lines.map((l, line) => ({ line, speaker: l.speaker, text: l.text })),
        tools,
      });
    } catch (err) {
      const code = (err as Error).message?.slice(0, 40) ?? "error";
      if (row.attempts < MAX_WRITER_TRIES) {
        // Try once more in a few minutes; until then the transcript stays encrypted here.
        await ctx.db.query(
          `UPDATE call_recaps SET state = 'waiting', lease_until = NULL, process_after = $2::timestamptz + interval '3 minutes', model_used_at = $2
           WHERE call_id = $1 AND state = 'building'`, [row.call_id, now]);
        ctx.log("call recap writer failed, will retry", { callId: row.call_id, code });
        return "retry";
      }
      ctx.log("call recap writer failed", { callId: row.call_id, code });
      reason = "writer_failed";
    }
  }
  const recap = buildRecap(facts, written, reason);
  const json = JSON.stringify(recap);
  const digest = sha256(json);
  const done = await inTransaction(ctx.db, async (c) => {
    const { rowCount } = await c.query(
      `UPDATE call_recaps SET state = 'ready', recap_ciphertext = $2, recap_digest = $3, summary_by = $4, key_version = $5,
         input_ciphertext = NULL, lease_until = NULL, ready_at = $6,
         model_used_at = CASE WHEN $7 THEN coalesce(model_used_at, $6) ELSE model_used_at END
       WHERE call_id = $1 AND state = 'building'`,
      [row.call_id, ctx.cipher.encrypt(json, recapAad(row.account_id, row.call_id)), digest, recap.summaryBy,
        ctx.cipher.keyVersion, now, modelUsed]);
    if (!rowCount) return false;
    await receipt(c, row.account_id, row.call_id, "input", "recap_built", now);
    return true;
  });
  if (!done) return "lost_lease";
  ctx.log("call recap ready", {
    callId: row.call_id, summaryBy: recap.summaryBy, note: recap.summaryNote, agreed: recap.agreed.length,
    couldNotDo: recap.couldNotDo.length, notes: recap.notes.length, dropped: recap.droppedPointers,
    ...(written?.usage ?? {}),
  });
  // No words from the call in the notification.
  if (ctx.push && await canPush(ctx.db, row.account_id)) {
    await enqueue(ctx.db, row.account_id, ["push"], "Doddy's recap of your call is ready. Open Doddy to read it.", now,
      `call-recap:${row.call_id}`, { cipher: ctx.cipher });
  }
  return recap.summaryBy === "doddy_model" ? "built_model" : "built_rules";
}

/** Notes this call left in the inbox, readable ones only. Each one waits for the user's confirmation. */
async function notesOf(ctx: RecapContext, accountId: string, callId: string): Promise<RecapNote[]> {
  const { rows } = await ctx.db.query<{ id: string; ciphertext: Buffer; created_at: Date }>(
    "SELECT id, ciphertext, created_at FROM call_notes WHERE account_id = $1 AND call_id = $2 ORDER BY created_at", [accountId, callId]);
  return rows.flatMap((r) => {
    try {
      return [{ id: r.id, text: ctx.cipher.decrypt(r.ciphertext, noteAad(accountId, r.id)), createdAt: r.created_at.toISOString() }];
    } catch {
      return [];
    }
  });
}

/** One of the day's model-written recaps, for the account and for the server; false when either is used up. */
async function takeWriterSlot(ctx: RecapContext, accountId: string, now: Date): Promise<boolean> {
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM call_recaps WHERE account_id = $1
       AND model_used_at >= date_trunc('day', $2::timestamptz AT TIME ZONE 'utc') AT TIME ZONE 'utc'`, [accountId, now]);
    if ((rows[0]?.n ?? 0) >= ctx.settings.dailyPerAccount) return false;
    const day = now.toISOString().slice(0, 10);
    return takeServerSlot(c, "call_recaps", ctx.settings.dailyPerServer, day);
  });
}

async function receipt(c: Q, accountId: string, callId: string, item: "input" | "recap", reason: "recap_built" | "acked" | "deleted" | "expired", now: Date) {
  await c.query(
    "INSERT INTO call_recap_deletions (id, account_id, call_id, item, reason, deleted_at) VALUES ($1, $2, $3, $4, $5, $6)",
    [randomUUID(), accountId, callId, item, reason, now]);
}

async function receiptsFor(c: Q, callId: string) {
  const { rows } = await c.query<{ item: string; reason: string; deleted_at: Date }>(
    "SELECT item, reason, deleted_at FROM call_recap_deletions WHERE call_id = $1 ORDER BY deleted_at, item", [callId]);
  return rows.map((r) => ({ what: r.item, reason: r.reason, deletedAt: r.deleted_at.toISOString() }));
}

/** Wipes the content of one locked recap row and writes the receipts. */
async function wipe(c: Q, accountId: string, callId: string, had: { input: boolean; recap: boolean },
  state: "acked" | "deleted" | "expired", now: Date) {
  await c.query(
    `UPDATE call_recaps SET state = $2, input_ciphertext = NULL, recap_ciphertext = NULL, recap_digest = NULL,
       lease_until = NULL, finished_at = $3 WHERE call_id = $1`, [callId, state, now]);
  if (had.input) await receipt(c, accountId, callId, "input", state, now);
  if (had.recap) await receipt(c, accountId, callId, "recap", state, now);
}

/** Recaps (or waiting transcripts) older than 30 days are wiped whether or not the app saved them. */
export async function expireRecaps(ctx: RecapContext): Promise<number> {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ call_id: string; account_id: string; has_input: boolean; has_recap: boolean }>(
      `SELECT call_id, account_id, input_ciphertext IS NOT NULL AS has_input, recap_ciphertext IS NOT NULL AS has_recap
       FROM call_recaps WHERE created_at < $1::timestamptz - make_interval(days => $2)
         AND (input_ciphertext IS NOT NULL OR recap_ciphertext IS NOT NULL)
       LIMIT 100 FOR UPDATE SKIP LOCKED`, [now, RECAP_KEEP_DAYS]);
    for (const r of rows) await wipe(c, r.account_id, r.call_id, { input: r.has_input, recap: r.has_recap }, "expired", now);
    return rows.length;
  });
}

// ---------- what the app asks ----------

export type RecapState = "none" | "waiting" | "ready" | "acked" | "deleted" | "expired";
export const publicState = (s: string | null): RecapState =>
  s === null ? "none" : s === "building" ? "waiting" : (s as RecapState);

type Refusal = { status: 404 | 409 | 500; error: string; state?: RecapState };
const refuse = (r: Refusal) => ({ refusal: r });

/** The recap of one of the account's calls, when it is ready; otherwise its state. */
export async function getRecap(ctx: RecapContext, accountId: string, callId: string) {
  const { rows } = await ctx.db.query<{ state: string | null; recap_ciphertext: Buffer | null; recap_digest: Buffer | null }>(
    `SELECT r.state, r.recap_ciphertext, r.recap_digest FROM calls c LEFT JOIN call_recaps r ON r.call_id = c.id
     WHERE c.id = $1 AND c.account_id = $2`, [callId, accountId]);
  const row = rows[0];
  if (!row) return refuse({ status: 404, error: "not_found" });
  const state = publicState(row.state);
  if (state !== "ready" || !row.recap_ciphertext || !row.recap_digest) return { callId, state };
  let recap: CallRecap;
  try {
    recap = JSON.parse(ctx.cipher.decrypt(row.recap_ciphertext, recapAad(accountId, callId))) as CallRecap;
  } catch {
    return refuse({ status: 500, error: "recap_unreadable", state });
  }
  return { callId, state, recap, digest: row.recap_digest.toString("hex") };
}

/** The app saved the recap on the iPhone: the server deletes its copy and says what it deleted. */
export async function ackRecap(ctx: RecapContext, accountId: string, callId: string, digestHex: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ state: string; recap_digest: Buffer | null; recap_ciphertext: Buffer | null }>(
      "SELECT state, recap_digest, recap_ciphertext FROM call_recaps WHERE call_id = $1 AND account_id = $2 FOR UPDATE", [callId, accountId]);
    const r = rows[0];
    if (!r) return refuse({ status: 404, error: "not_found" });
    // Acknowledged before: the same answer again, so a lost reply can be retried.
    if (r.state === "acked") return { deletions: await receiptsFor(c, callId) };
    if (r.state !== "ready" || !r.recap_digest) return refuse({ status: 409, error: "no_recap", state: publicState(r.state) });
    if (!/^[0-9a-f]{64}$/.test(digestHex) || !sameBytes(r.recap_digest, Buffer.from(digestHex, "hex"))) {
      return refuse({ status: 409, error: "recap_mismatch" });
    }
    await wipe(c, accountId, callId, { input: false, recap: !!r.recap_ciphertext }, "acked", now);
    return { deletions: await receiptsFor(c, callId) };
  });
}

/** Deletes the server's copy without the app saving it (the user chose Delete). */
export async function deleteRecap(ctx: RecapContext, accountId: string, callId: string) {
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<{ has_input: boolean; has_recap: boolean }>(
      `SELECT input_ciphertext IS NOT NULL AS has_input, recap_ciphertext IS NOT NULL AS has_recap
       FROM call_recaps WHERE call_id = $1 AND account_id = $2 FOR UPDATE`, [callId, accountId]);
    const r = rows[0];
    if (!r) return refuse({ status: 404, error: "not_found" });
    if (r.has_input || r.has_recap) await wipe(c, accountId, callId, { input: r.has_input, recap: r.has_recap }, "deleted", now);
    return { deletions: await receiptsFor(c, callId) };
  });
}
