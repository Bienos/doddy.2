import { randomUUID } from "node:crypto";
import type pg from "pg";
import type { TextCipher } from "./crypto.js";
import { inTransaction, type Db } from "./db.js";
import { memoryCopyOn, quotedMemory, saveNoteIn, searchMemoryCopy } from "./inbox.js";
import { log } from "./log.js";
import { canPush, enqueue, smsNumber } from "./outbox.js";
import type { TextReplyOutcome, TextReplyTools, TextReplyWriter } from "./providers/types.js";

// Texts the user sends to Doddy's number (ADR-490 unit U3, ADR-494). Only the user's own verified
// number gets through, and only with "Texts to Doddy" on; everyone else is dropped without a reply
// and nothing about them is stored. A text becomes a note in the inbox, or, with replies on, a
// reply job: Claude answers with two tools (search the memory copy, if allowed; leave a note), and
// the answer goes to the user's number only, once per text. The text is data: no tool can text
// anyone or change anything outside the inbox.

/** Mirrored in docs/trust/config/doddy_rules.yaml (contact_policy); a test keeps them equal. */
export const INBOUND_TEXTS_PER_HOUR = 30;
export const AI_REPLIES_PER_DAY = 30;
export const AI_REPLY_BUDGET_USD_PER_DAY = 1.0;
export const AI_REPLY_WINDOW_MINUTES = 10;
export const AI_REPLY_MAX_SEGMENTS = 3;
/** Twilio delivers up to 1600 characters; nothing longer is kept. */
export const INBOUND_TEXT_MAX = 1600;
/** A reply job left in "replying" this long was cut off (the worker stopped). */
const STUCK_MINUTES = 5;

/** The wordings the app may record consent to (DoddyCore TextsToDoddyConsent). */
export const TEXTS_IN_CONSENT_VERSIONS = new Set(["texts-in-v1"]);

export type Language = "en" | "pl";

/** Doddy's fixed texts and notifications, in the language of the user's settings. */
export const FIXED: Record<Language, {
  failedNoted: string; failed: string; tooLong: string; dailyLimit: string; paused: string; inboxFull: string;
}> = {
  en: {
    failedNoted: "Doddy couldn't answer that just now. Your text is waiting as a note in the Doddy app.",
    failed: "Doddy couldn't answer that just now.",
    tooLong: "That answer is too long for a text. Ask me in the Doddy app.",
    dailyLimit: "Doddy can't answer more texts today. Your texts are waiting as notes in the Doddy app.",
    paused: `More than ${INBOUND_TEXTS_PER_HOUR} texts arrived in an hour, so Doddy is ignoring texts for the rest of the hour.`,
    inboxFull: "Doddy's note inbox is full, so your text wasn't kept. Open Doddy to confirm or clear notes.",
  },
  pl: {
    failedNoted: "Doddy nie mógł teraz odpowiedzieć. Twój SMS czeka jako notatka w aplikacji Doddy.",
    failed: "Doddy nie mógł teraz odpowiedzieć.",
    tooLong: "Ta odpowiedź jest za długa na SMS. Zapytaj mnie w aplikacji Doddy.",
    dailyLimit: "Doddy nie odpowie już dziś na więcej SMS-ów. Twoje SMS-y czekają jako notatki w aplikacji Doddy.",
    paused: `W ciągu godziny przyszło ponad ${INBOUND_TEXTS_PER_HOUR} SMS-ów, więc do końca godziny Doddy je pomija.`,
    inboxFull: "Skrzynka notatek Doddy’ego jest pełna, więc Twój SMS nie został zachowany. Otwórz Doddy’ego, żeby potwierdzić lub usunąć notatki.",
  },
};

const lang = (value: string | null | undefined): Language => (value === "pl" ? "pl" : "en");
const bodyAad = (accountId: string, id: string) => `${accountId}:text:${id}`;

export interface TextDeps {
  db: Db;
  cipher?: TextCipher;
  replyWriter?: TextReplyWriter;
}

export type ReceiveResult = "noted" | "inbox_full" | "limited" | "reply_queued" | "duplicate" | "dropped";

/**
 * A text from Twilio's webhook (after its signature was checked, and after STOP/START/HELP were
 * handled). Answers quickly: a reply is written later by the worker (processTextReplies).
 */
export async function receiveText(deps: TextDeps, msg: { from: string; sid: string; body: string }): Promise<ReceiveResult> {
  const { db, cipher } = deps;
  const { rows: [who] } = await db.query<{ account_id: string; replies: boolean; language: string }>(
    `SELECT p.account_id, t.replies_enabled AS replies, t.language FROM phone_numbers p
     JOIN text_settings t ON t.account_id = p.account_id WHERE p.e164 = $1 AND t.inbound_enabled`, [msg.from]);
  // Not the user's number, or texts to Doddy are off: no reply, nothing stored, no number logged.
  if (!who) return dropped("not_allowed");
  if (!cipher) return dropped("not_configured");
  if (!msg.sid) return dropped("no_message_id");
  const text = msg.body.slice(0, INBOUND_TEXT_MAX);
  if (!text.trim()) return dropped("empty");
  const accountId = who.account_id;
  const language = lang(who.language);
  // Replies need the writer, and Doddy's texts to the user allowed (consent given, no STOP since).
  const replies = who.replies && !!deps.replyWriter && !!await smsNumber(db, accountId);
  const id = randomUUID();

  const result = await inTransaction(db, async (c): Promise<{ state: ReceiveResult; firstOverLimit?: boolean }> => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('inbound_texts:' || $1))", [accountId]);
    const dup = await c.query("SELECT 1 FROM inbound_texts WHERE message_sid = $1", [msg.sid]);
    if (dup.rowCount) return { state: "duplicate" };
    const { rows: [hour] } = await c.query<{ n: number }>(
      "SELECT count(*)::int AS n FROM inbound_texts WHERE account_id = $1 AND received_at > now() - interval '1 hour'", [accountId]);
    const recent = hour?.n ?? 0;
    const insert = (state: ReceiveResult, sealed?: Buffer) => c.query(
      `INSERT INTO inbound_texts (id, account_id, message_sid, state, body_ciphertext, body_key_version) VALUES ($1, $2, $3, $4, $5, $6)`,
      [id, accountId, msg.sid, state, sealed ?? null, sealed ? cipher.keyVersion : null]);
    if (recent >= INBOUND_TEXTS_PER_HOUR) {
      await insert("limited");
      return { state: "limited", firstOverLimit: recent === INBOUND_TEXTS_PER_HOUR };
    }
    if (replies) {
      await insert("reply_queued", cipher.encrypt(text, bodyAad(accountId, id)));
      return { state: "reply_queued" };
    }
    const noted = await saveNoteIn(c, cipher, accountId, text, "text");
    await insert(noted ? "noted" : "inbox_full");
    return { state: noted ? "noted" : "inbox_full" };
  });

  // Push only, never a text: the user is told about texts that were not kept, nothing else.
  if (result.firstOverLimit) await notify(db, cipher, accountId, FIXED[language].paused, `texts-paused:${accountId}:${hourBucket()}`);
  if (result.state === "inbox_full") await notify(db, cipher, accountId, FIXED[language].inboxFull, `text-inbox-full:${id}`);
  if (result.state !== "duplicate") log("text received", { id, state: result.state });
  return result.state;
}

/**
 * Texts to Doddy were agreed to for one number: when it is removed, replaced or proved by another
 * account, they are switched off and need the user's consent again.
 */
export async function textsOff(c: pg.PoolClient, accountId: string): Promise<void> {
  await c.query(
    `UPDATE text_settings SET inbound_enabled = false, replies_enabled = false, replies_use_memories = false, updated_at = now()
     WHERE account_id = $1`, [accountId]);
}

function dropped(reason: string): ReceiveResult {
  log("text dropped", { reason });
  return "dropped";
}

const hourBucket = () => new Date().toISOString().slice(0, 13);

async function notify(db: Db, cipher: TextCipher, accountId: string, body: string, key: string) {
  if (await canPush(db, accountId)) await enqueue(db, accountId, ["push"], body, new Date(), key, { cipher });
}

interface Claimed { id: string; account_id: string; body_ciphertext: Buffer; received_at: Date }

/**
 * One reply job per call: claims the oldest queued text, writes and queues the reply, and erases
 * the text. Every path ends in a final state, with the text kept as a note whenever no answer was
 * sent, so a text is never silently lost. Returns whether a job was handled.
 */
export async function processTextReply(deps: TextDeps & { now?: () => Date }): Promise<boolean> {
  const { db, cipher } = deps;
  if (!cipher) return false;
  await reapStuck(db, cipher);
  const { rows: [job] } = await db.query<Claimed>(
    `UPDATE inbound_texts SET state = 'replying', updated_at = now()
     WHERE id = (SELECT id FROM inbound_texts WHERE state = 'reply_queued' ORDER BY received_at FOR UPDATE SKIP LOCKED LIMIT 1)
     RETURNING id, account_id, body_ciphertext, received_at`);
  if (!job) return false;
  const now = deps.now?.() ?? new Date();

  let text: string;
  try {
    text = cipher.decrypt(job.body_ciphertext, bodyAad(job.account_id, job.id));
  } catch {
    await finish(db, cipher, job, "reply_failed", "body_unreadable");
    return true;
  }
  const { rows: [settings] } = await db.query<{ replies: boolean; memories: boolean; language: string }>(
    `SELECT replies_enabled AS replies, replies_use_memories AS memories, language FROM text_settings WHERE account_id = $1`,
    [job.account_id]);
  const language = lang(settings?.language);
  const to = await smsNumber(db, job.account_id);

  // Replies were turned off, STOP was sent, or the server lost its writer meanwhile: a note instead.
  if (!settings?.replies || !to || !deps.replyWriter) {
    await asNote(db, cipher, job, text, language, null);
    return true;
  }
  // Too late to answer: a reply long after the text would be confusing.
  if (now.getTime() - job.received_at.getTime() > AI_REPLY_WINDOW_MINUTES * 60_000) {
    await asNote(db, cipher, job, text, language, "late");
    return true;
  }
  const { rows: [usage] } = await db.query<{ mine: number; cost: string }>(
    `SELECT count(*) FILTER (WHERE account_id = $1 AND state IN ('replied', 'reply_failed'))::int AS mine,
            coalesce(sum(cost_microusd), 0)::text AS cost
     FROM inbound_texts WHERE received_at > now() - interval '1 day'`, [job.account_id]);
  const overCount = (usage?.mine ?? 0) >= AI_REPLIES_PER_DAY;
  const overBudget = Number(usage?.cost ?? 0) >= AI_REPLY_BUDGET_USD_PER_DAY * 1_000_000;
  if (overCount || overBudget) {
    await asNote(db, cipher, job, text, language, overCount ? "daily_limit" : "budget", {
      body: FIXED[language].dailyLimit, key: `text-limit:${job.account_id}:${now.toISOString().slice(0, 10)}`,
    });
    return true;
  }

  const tools: TextReplyTools = {
    // Claude's words, not the user's: labelled as Doddy's note so the app never calls it "your text".
    saveNote: async (note) => (await inTransaction(db, (c) =>
      saveNoteIn(c, cipher, job.account_id, note.slice(0, INBOUND_TEXT_MAX), "doddy"))) ? "saved" : "inbox_full",
  };
  if (settings.memories && await memoryCopyOn(db, job.account_id)) {
    tools.searchMemories = async (query) => (await searchMemoryCopy(db, cipher, job.account_id, query)).map(quotedMemory);
  }
  let outcome: TextReplyOutcome;
  try {
    outcome = await deps.replyWriter.reply(
      { text, language, receivedAt: job.received_at, maxSegments: AI_REPLY_MAX_SEGMENTS }, tools);
  } catch {
    outcome = { kind: "failed", code: "writer_error", costMicroUsd: 0 };
  }
  const cost = Math.max(0, Math.round(outcome.costMicroUsd));
  const key = `text-reply:${job.id}`;
  if (outcome.kind === "reply") {
    await finish(db, cipher, job, "replied", null, cost, { body: outcome.text, key });
  } else if (outcome.kind === "too_long") {
    await finish(db, cipher, job, "reply_failed", "too_long", cost, { body: FIXED[language].tooLong, key });
  } else {
    // No answer: keep the text as a note, and say so in one fixed text.
    const code = outcome.code;
    await inTransaction(db, async (c) => {
      const noted = await saveNoteIn(c, cipher, job.account_id, text, "text");
      await finishIn(c, cipher, job, "reply_failed", code, cost,
        { body: noted ? FIXED[language].failedNoted : FIXED[language].failed, key });
    });
  }
  log("text reply", { id: job.id, outcome: outcome.kind, costMicroUsd: cost });
  return true;
}

type Reply = { body: string; key: string };

/**
 * Final state, text erased, and the reply (if any) queued in the same transaction; nothing is
 * queued if the job was already closed (reapStuck). The reply waits in the outbox encrypted, as
 * it may quote memories, and the outbox checks again that texts to the user are allowed.
 */
async function finishIn(
  c: pg.PoolClient, cipher: TextCipher, job: Claimed, state: string, code: string | null, cost = 0, reply?: Reply,
): Promise<boolean> {
  const r = await c.query(
    `UPDATE inbound_texts SET state = $2, error_code = $3, cost_microusd = cost_microusd + $4,
       body_ciphertext = NULL, body_key_version = NULL, updated_at = now() WHERE id = $1 AND state = 'replying'`,
    [job.id, state, code, cost]);
  if (!r.rowCount) return false;
  if (reply) await enqueue(c, job.account_id, ["sms"], reply.body, new Date(), reply.key, { cipher });
  return true;
}

const finish = (db: Db, cipher: TextCipher, job: Claimed, state: string, code: string | null, cost = 0, reply?: Reply) =>
  inTransaction(db, (c) => finishIn(c, cipher, job, state, code, cost, reply));

async function asNote(
  db: Db, cipher: TextCipher, job: Claimed, text: string, language: Language, code: string | null, reply?: Reply,
) {
  const noted = await inTransaction(db, async (c) => {
    const id = await saveNoteIn(c, cipher, job.account_id, text, "text");
    await finishIn(c, cipher, job, id ? "noted" : "inbox_full", code, 0, reply);
    return !!id;
  });
  if (!noted) await notify(db, cipher, job.account_id, FIXED[language].inboxFull, `text-inbox-full:${job.id}`);
}

/** A job the worker never finished: its text becomes a note; no reply was queued for it. */
async function reapStuck(db: Db, cipher: TextCipher): Promise<void> {
  const { rows } = await db.query<Claimed>(
    `SELECT id, account_id, body_ciphertext, received_at FROM inbound_texts
     WHERE state = 'replying' AND updated_at < now() - make_interval(mins => $1) LIMIT 5`, [STUCK_MINUTES]);
  for (const job of rows) {
    let text: string | undefined;
    try {
      text = cipher.decrypt(job.body_ciphertext, bodyAad(job.account_id, job.id));
    } catch { /* unreadable: closed without a note */ }
    await inTransaction(db, async (c) => {
      if (text !== undefined) await saveNoteIn(c, cipher, job.account_id, text, "text");
      await finishIn(c, cipher, job, "reply_failed", "worker_interrupted");
    });
    log("text reply interrupted", { id: job.id });
  }
}
