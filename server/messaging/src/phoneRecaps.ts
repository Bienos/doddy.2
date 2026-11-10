// Recaps of calls to and from Doddy's phone line (decision 2026-11-09-conversation-recaps, step 5).
//
// After a call, ElevenLabs' post-call webhook (the workspace webhook the task calls also use) brings the
// call's transcript. For a call that has a `calls` row of an account that turned recaps on, Claude writes three
// short lists from it (the same instructions the iPhone uses), and ONLY those lists are stored, encrypted,
// until the iPhone saves them as a note and says so, or for 30 days. The transcript lives in memory for this
// one call: it is never stored, and the log carries ids, counts and outcomes, never words.
//
// A missing recap is never shown as anything else: a call that wasn't matched, belongs to an account with
// recaps off, said too little, hit a cap or failed in the model just has none.
import type { Db } from "./db.js";
import { inTransaction } from "./db.js";
import type { TextCipher } from "./crypto.js";
import { reserve, addTokens } from "./assistant/usage.js";
import { RECAP_LIMITS, type RecapWriter } from "./assistant/recap.js";
import type { AssistantSettings } from "./config.js";

export const PHONE_RECAP_KEEP_DAYS = 30;
/** As `RecapRules.minimumWordsFromPerson` in the app: less than this from the caller is nothing to recap. */
export const MIN_WORDS_FROM_CALLER = 30;

export interface PhoneRecapDeps {
  /** The phone agent whose post-call payloads get a recap; payloads of any other agent are not read. */
  phoneAgentId?: string;
  /** HMAC secret of the workspace post-call webhook (ELEVENLABS_WEBHOOK_SECRET). */
  webhookSecret?: string;
  /** The same Claude writer as `POST /v1/recaps`; without it (no key, Messages off) there are no recaps. */
  writer?: RecapWriter;
  /** Messages' daily caps: a recap counts as one Messages request. */
  settings: AssistantSettings;
  now?: () => Date;
  /** How long the model may take. Default 45 s. */
  timeoutMs?: number;
}

export interface PhoneRecapContext {
  db: Db;
  cipher: TextCipher;
  deps: PhoneRecapDeps;
  log: (msg: string, extra?: object) => void;
}

export const recapAad = (accountId: string, callId: string) => `${accountId}:phone-recap:${callId}`;

export type PhoneRecapOutcome =
  | "stored" | "duplicate" | "ignored" | "unreadable" | "unmatched" | "off" | "tooShort" | "cap" | "failed";

export interface StoredPhoneRecap {
  discussed: string[];
  agreed: string[];
  to_do: string[];
  endedAt: string;
  durationSecs: number | null;
  direction: "inbound" | "outbound";
}

interface Turn { role: "person" | "doddy"; text: string }

/** What the webhook carries that a recap needs; anything else in it is not read. */
function readPayload(json: unknown): { agentId: string; conversationId: string; callSid: string | null; durationSecs: number | null; turns: Turn[] } | null {
  const env = json as { type?: unknown; data?: Record<string, unknown> } | null;
  if (!env || env.type !== "post_call_transcription" || typeof env.data !== "object" || env.data === null) return null;
  const d = env.data;
  const metadata = (d.metadata ?? {}) as { call_duration_secs?: unknown; phone_call?: { call_sid?: unknown } | null };
  if (typeof d.agent_id !== "string" || typeof d.conversation_id !== "string" || !Array.isArray(d.transcript)) return null;
  const turns: Turn[] = [];
  for (const t of d.transcript as { role?: unknown; message?: unknown }[]) {
    if (typeof t?.message !== "string" || t.message.trim() === "") continue;
    if (t.role === "user") turns.push({ role: "person", text: t.message });
    else if (t.role === "agent") turns.push({ role: "doddy", text: t.message });
  }
  const sid = metadata.phone_call?.call_sid;
  return {
    agentId: d.agent_id, conversationId: d.conversation_id, callSid: typeof sid === "string" ? sid : null,
    durationSecs: typeof metadata.call_duration_secs === "number" ? metadata.call_duration_secs : null, turns,
  };
}

const wordCount = (text: string) => text.split(/[^\p{L}\p{N}]+/u).filter(Boolean).length;

/** Cuts a long call to the writer's limits: the start and the end are kept, as the iPhone's own writer does. */
function fitted(turns: Turn[]): Turn[] {
  const total = turns.reduce((n, t) => n + [...t.text].length + 1, 0);
  if (turns.length <= RECAP_LIMITS.lines && total <= RECAP_LIMITS.conversation) return turns;
  const half = Math.floor(RECAP_LIMITS.conversation / 2);
  const head: Turn[] = [];
  let used = 0;
  for (const t of turns) {
    const n = [...t.text].length + 1;
    if (used + n > half || head.length >= RECAP_LIMITS.lines / 2) break;
    head.push(t); used += n;
  }
  const tail: Turn[] = [];
  used = 0;
  for (const t of turns.slice(head.length).reverse()) {
    const n = [...t.text].length + 1;
    if (used + n > half - 8 || tail.length >= RECAP_LIMITS.lines / 2 - 1) break;
    tail.unshift(t); used += n;
  }
  return [...head, { role: "doddy" as const, text: "[…]" }, ...tail];
}

/**
 * The post-call payload of a phone-agent call. Awaited by tests; the route doesn't wait for it, so ElevenLabs
 * gets its answer at once (it switches a webhook off after repeated failures).
 */
export async function onPhonePostCall(ctx: PhoneRecapContext, json: unknown): Promise<PhoneRecapOutcome> {
  const { db, cipher, deps } = ctx;
  const payload = readPayload(json);
  if (!payload) return "unreadable";
  if (!deps.phoneAgentId || payload.agentId !== deps.phoneAgentId) return "ignored";
  const writer = deps.writer;
  if (!writer) return "off";
  const now = (deps.now ?? (() => new Date()))();

  const { rows } = await db.query<{ id: string; account_id: string; direction: "inbound" | "outbound"; enabled: boolean }>(
    `SELECT c.id, c.account_id, c.direction, s.recaps_enabled_at IS NOT NULL AS enabled
       FROM calls c LEFT JOIN call_settings s ON s.account_id = c.account_id
      WHERE (c.conversation_id = $1 OR ($2::text IS NOT NULL AND c.call_sid = $2))
        AND c.created_at > $3::timestamptz - interval '2 days'
      ORDER BY c.created_at DESC LIMIT 1`, [payload.conversationId, payload.callSid, now]);
  const call = rows[0];
  if (!call) return "unmatched";
  if (!call.enabled) return "off";
  const { rows: existing } = await db.query("SELECT 1 FROM phone_recaps WHERE call_id = $1", [call.id]);
  if (existing.length > 0) return "duplicate";
  if (wordCount(payload.turns.filter((t) => t.role === "person").map((t) => t.text).join(" ")) < MIN_WORDS_FROM_CALLER) return "tooShort";

  const s = deps.settings;
  const reservation = await reserve(db, call.account_id, {
    perAccount: s.dailyPerAccount, perServer: s.dailyPerServer, newAccountPool: s.dailyForNewAccounts, newAccountHours: s.newAccountHours,
  });
  if (reservation !== "ok") {
    ctx.log("phone recap cap reached", { callId: call.id, cap: reservation });
    return "cap";
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), deps.timeoutMs ?? 45_000);
  try {
    const outcome = await writer.write({
      kind: "phone_line", language: "pl", lines: fitted(payload.turns).map((t) => ({ speaker: t.role, text: t.text })),
    }, controller.signal);
    if (outcome.usage) await addTokens(db, call.account_id, outcome.usage).catch(() => {});
    if (outcome.kind !== "ok") {
      ctx.log("phone recap not written", { callId: call.id, outcome: outcome.kind });
      return "failed";
    }
    const stored: StoredPhoneRecap = {
      discussed: outcome.recap.discussed, agreed: outcome.recap.agreed, to_do: outcome.recap.to_do,
      endedAt: now.toISOString(), durationSecs: payload.durationSecs, direction: call.direction,
    };
    const inserted = await inTransaction(db, async (c) => {
      await c.query("UPDATE calls SET conversation_id = coalesce(conversation_id, $2) WHERE id = $1", [call.id, payload.conversationId]);
      const r = await c.query(
        `INSERT INTO phone_recaps (call_id, account_id, key_version, ciphertext, created_at)
         VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING`,
        [call.id, call.account_id, cipher.keyVersion, cipher.encrypt(JSON.stringify(stored), recapAad(call.account_id, call.id)), now]);
      return (r.rowCount ?? 0) > 0;
    });
    ctx.log("phone recap stored", {
      callId: call.id, turns: payload.turns.length,
      points: stored.discussed.length + stored.agreed.length + stored.to_do.length, duplicate: !inserted,
    });
    return inserted ? "stored" : "duplicate";
  } catch (err) {
    ctx.log("phone recap provider error", { callId: call.id, kind: String((err as { name?: unknown }).name) });
    return "failed";
  } finally {
    clearTimeout(timer);
  }
}

/** Recaps older than their keep time go; called when the app asks, so there is no separate job to run. */
export async function expirePhoneRecaps(db: Db, now: Date = new Date()): Promise<number> {
  const r = await db.query(
    "DELETE FROM phone_recaps WHERE created_at < $1::timestamptz - make_interval(days => $2)", [now, PHONE_RECAP_KEEP_DAYS]);
  return r.rowCount ?? 0;
}
