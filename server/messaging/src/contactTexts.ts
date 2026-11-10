// Texts from Doddy's number to one of the user's iPhone contacts (owner, 9 Nov 2026; decision
// docs/decisions/2026-11-09-texts-to-contacts.md). The app reads the number from the contact card; the user taps a
// card with the contact, the number and the exact text; the approval hash binds that number and text (DOD-07).
// No signature is added. At most CONTACT_TEXTS_PER_DAY a day per account, and a number that answered STOP is not
// texted again until it answers START.
import type pg from "pg";
import { keyedDigest, type TextCipher } from "./crypto.js";

type Q = Pick<pg.PoolClient, "query"> | pg.Pool;

/** Texts to contacts per account per UTC day. Mirrors contact_texts_per_account_day in doddy_rules.yaml and DoddyCore's ContactText.maxPerDay. */
export const CONTACT_TEXTS_PER_DAY = 50;

/** E.164 as DoddyCore's ContactText writes it: a plus, then 8 to 15 digits, not starting with 0. */
export const CONTACT_NUMBER = /^\+[1-9][0-9]{7,14}$/;

/** The stored form of a number that opted out: a keyed hash (ADR-705), never the number. */
export const optOutHash = (cipher: TextCipher | undefined, e164: string) =>
  keyedDigest(cipher?.derivedKey("contact-text-opt-out"), e164);

export async function contactOptedOut(db: Q, cipher: TextCipher | undefined, e164: string): Promise<boolean> {
  const { rowCount } = await db.query("SELECT 1 FROM contact_text_opt_outs WHERE number_hash = $1", [optOutHash(cipher, e164)]);
  return (rowCount ?? 0) > 0;
}

/** STOP from this number (or Twilio said it unsubscribed): no text to it as a contact, and its queued ones are cancelled. */
export async function recordContactOptOut(db: Q, cipher: TextCipher | undefined, e164: string): Promise<void> {
  await db.query("INSERT INTO contact_text_opt_outs (number_hash) VALUES ($1) ON CONFLICT DO NOTHING", [optOutHash(cipher, e164)]);
  await db.query(
    `UPDATE outbound_messages SET state = 'cancelled', error_code = 'contact_opted_out',
       body = NULL, body_ciphertext = NULL, body_key_version = NULL, approval_hash = NULL, body_hash = NULL, to_e164 = NULL,
       updated_at = now()
     WHERE channel = 'sms' AND state = 'queued' AND to_e164 = $1`, [e164]);
}

/** START from this number: it may be texted as a contact again. */
export async function clearContactOptOut(db: Q, cipher: TextCipher | undefined, e164: string): Promise<void> {
  await db.query("DELETE FROM contact_text_opt_outs WHERE number_hash = $1", [optOutHash(cipher, e164)]);
}
