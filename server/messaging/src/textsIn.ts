import { randomUUID } from "node:crypto";
import type pg from "pg";
import type { TextCipher } from "./crypto.js";
import { inTransaction, type Db } from "./db.js";
import { saveNoteIn } from "./inbox.js";
import { log } from "./log.js";
import { canPush, enqueue } from "./outbox.js";

// Texts the user sends to Doddy's number (ADR-750 unit U3, ADR-753). Only the user's own verified number gets
// through, and only with "Texts to Doddy" on (off by default, with its own consent wording); everyone else is
// dropped without a reply and nothing about them is stored. A text becomes a note in the inbox, encrypted, that
// waits for the user's confirmation. It gets NO reply: no model reads it, nothing from memory is put in a text,
// and the text is data, never an instruction. An answer by text is the separate "Text with Doddy" (ADR-656,
// smsChat.ts, its own consent). The webhook gives a text to exactly one of the two, never both: see
// routes/twilioWebhooks.ts. Doddy's old branch also had Claude write replies with a note and a memory tool; that
// was not brought forward (ADR-755), because ADR-656 already answers texts and sends no memory over a phone network.

/** Mirrored in docs/trust/config/doddy_rules.yaml (contact_policy); a test keeps them equal. */
export const INBOUND_TEXTS_PER_HOUR = 30;
/** Twilio delivers up to 1600 characters; nothing longer is kept. */
export const INBOUND_TEXT_MAX = 1600;

/** The wordings the app may record consent to (DoddyCore TextsToDoddyConsent). */
export const TEXTS_IN_CONSENT_VERSIONS = new Set(["texts-in-v1"]);

export type Language = "en" | "pl";

/** Doddy's fixed notifications (push only, never a text), in the language of the user's settings. */
export const FIXED: Record<Language, { paused: string; inboxFull: string }> = {
  en: {
    paused: `More than ${INBOUND_TEXTS_PER_HOUR} texts arrived in an hour, so Doddy is ignoring texts for the rest of the hour.`,
    inboxFull: "Doddy's note inbox is full, so your text wasn't kept. Open Doddy to confirm or clear notes.",
  },
  pl: {
    paused: `W ciągu godziny przyszło ponad ${INBOUND_TEXTS_PER_HOUR} SMS-ów, więc do końca godziny Doddy je pomija.`,
    inboxFull: "Skrzynka notatek Doddy’ego jest pełna, więc Twój SMS nie został zachowany. Otwórz Doddy’ego, żeby potwierdzić lub usunąć notatki.",
  },
};

const lang = (value: string | null | undefined): Language => (value === "pl" ? "pl" : "en");

export interface TextDeps {
  db: Db;
  cipher?: TextCipher;
}

/** "dropped" also means: not handled here, so the webhook may hand the text to Text with Doddy (ADR-656). */
export type ReceiveResult = "noted" | "inbox_full" | "limited" | "duplicate" | "dropped";

/**
 * A text from Twilio's webhook (after its signature was checked, and after STOP/START/HELP were handled). The text
 * is saved as an encrypted note in the same transaction as its row; nothing is sent back.
 */
export async function receiveText(deps: TextDeps, msg: { from: string; sid: string; body: string }): Promise<ReceiveResult> {
  const { db, cipher } = deps;
  const { rows: [who] } = await db.query<{ account_id: string; language: string }>(
    `SELECT p.account_id, t.language FROM phone_numbers p
     JOIN text_settings t ON t.account_id = p.account_id WHERE p.e164 = $1 AND t.inbound_enabled`, [msg.from]);
  // Not the user's number, or texts to Doddy are off: no reply, nothing stored, no number logged.
  if (!who) return dropped("not_allowed");
  if (!cipher) return dropped("not_configured");
  if (!msg.sid) return dropped("no_message_id");
  const text = msg.body.slice(0, INBOUND_TEXT_MAX);
  if (!text.trim()) return dropped("empty");
  const accountId = who.account_id;
  const language = lang(who.language);
  const id = randomUUID();

  const result = await inTransaction(db, async (c): Promise<{ state: ReceiveResult; firstOverLimit?: boolean }> => {
    await c.query("SELECT pg_advisory_xact_lock(hashtext('inbound_texts:' || $1))", [accountId]);
    const dup = await c.query("SELECT 1 FROM inbound_texts WHERE message_sid = $1", [msg.sid]);
    if (dup.rowCount) return { state: "duplicate" };
    const { rows: [hour] } = await c.query<{ n: number }>(
      "SELECT count(*)::int AS n FROM inbound_texts WHERE account_id = $1 AND received_at > now() - interval '1 hour'", [accountId]);
    const recent = hour?.n ?? 0;
    const insert = (state: "noted" | "inbox_full" | "limited") => c.query(
      "INSERT INTO inbound_texts (id, account_id, message_sid, state) VALUES ($1, $2, $3, $4)", [id, accountId, msg.sid, state]);
    if (recent >= INBOUND_TEXTS_PER_HOUR) {
      await insert("limited");
      return { state: "limited", firstOverLimit: recent === INBOUND_TEXTS_PER_HOUR };
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
  await c.query("UPDATE text_settings SET inbound_enabled = false, updated_at = now() WHERE account_id = $1", [accountId]);
}

function dropped(reason: string): ReceiveResult {
  log("text dropped", { reason });
  return "dropped";
}

const hourBucket = () => new Date().toISOString().slice(0, 13);

async function notify(db: Db, cipher: TextCipher, accountId: string, body: string, key: string) {
  if (await canPush(db, accountId)) await enqueue(db, accountId, ["push"], body, new Date(), key, { cipher });
}
