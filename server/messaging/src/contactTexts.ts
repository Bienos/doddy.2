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

const OPT_OUT = "contact-text-opt-out";

/**
 * How a number that opted out is found: a keyed hash (ADR-705) under the current key. Its number is kept beside it only
 * encrypted (`number_ciphertext`, associated data `optOutAad`), so a key rotation can re-hash it: the keyed hashes of
 * everything else start afresh after a rotation, but a STOP must never be forgotten (scripts/reencrypt.mjs).
 */
export const optOutHash = (cipher: TextCipher | undefined, e164: string) => keyedDigest(cipher?.derivedKey(OPT_OUT), e164);

/** The associated data of an opted-out number's ciphertext. Not the hash, which changes when the key does. */
export const optOutAad = OPT_OUT;

/** The number's hash under every key the server holds, the current one first (both during a rotation). */
const optOutHashes = (cipher: TextCipher | undefined, e164: string): Buffer[] =>
  cipher ? cipher.derivedKeys(OPT_OUT).map((k) => keyedDigest(k, e164)) : [keyedDigest(undefined, e164)];

export async function contactOptedOut(db: Q, cipher: TextCipher | undefined, e164: string): Promise<boolean> {
  const { rowCount } = await db.query("SELECT 1 FROM contact_text_opt_outs WHERE number_hash = ANY($1::bytea[])", [optOutHashes(cipher, e164)]);
  return (rowCount ?? 0) > 0;
}

/** STOP from this number (or Twilio said it unsubscribed): no text to it as a contact, and its queued ones are cancelled. */
export async function recordContactOptOut(db: Q, cipher: TextCipher | undefined, e164: string): Promise<void> {
  await db.query(
    `INSERT INTO contact_text_opt_outs (number_hash, number_ciphertext, key_version) VALUES ($1, $2, $3)
     ON CONFLICT (number_hash) DO NOTHING`,
    [optOutHash(cipher, e164), cipher ? cipher.encrypt(e164, optOutAad) : null, cipher ? cipher.keyVersion : null]);
  await db.query(
    `UPDATE outbound_messages SET state = 'cancelled', error_code = 'contact_opted_out',
       body = NULL, body_ciphertext = NULL, body_key_version = NULL, approval_hash = NULL, body_hash = NULL, to_e164 = NULL,
       updated_at = now()
     WHERE channel = 'sms' AND state = 'queued' AND to_e164 = $1`, [e164]);
}

/** START from this number: it may be texted as a contact again. */
export async function clearContactOptOut(db: Q, cipher: TextCipher | undefined, e164: string): Promise<void> {
  await db.query("DELETE FROM contact_text_opt_outs WHERE number_hash = ANY($1::bytea[])", [optOutHashes(cipher, e164)]);
}
