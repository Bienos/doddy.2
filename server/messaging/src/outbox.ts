import { randomUUID, timingSafeEqual } from "node:crypto";
import { textApprovalHash } from "./approval.js";
import type pg from "pg";
import { DEFAULT_ABUSE_LIMITS } from "./config.js";
import { returnCounter, takeCounter } from "./dailyCounters.js";
import { sha256, type TextCipher } from "./crypto.js";
import { log } from "./log.js";
import type { Db } from "./db.js";
import { scheduleDeletion } from "./providerRecords.js";
import { isAllowedNumber } from "./phoneCountries.js";
import type { PushData, PushSender, SendOutcome, SmsSender } from "./providers/types.js";
import { returnServerSlot, takeServerSlot } from "./serverUsage.js";

export type Channel = "push" | "sms";

export const MAX_ATTEMPTS = 5;
export const STALE_SENDING = "5 minutes";
/** How long after an unknown outcome Twilio's message list is checked (DOD-09), and how often. */
export const LOOKUP_AFTER = "2 minutes";
export const MAX_LOOKUPS = 3;

type Queryable = pg.Pool | pg.PoolClient;

export async function canPush(db: Queryable, accountId: string): Promise<boolean> {
  const { rowCount } = await db.query(
    `SELECT 1 FROM devices
     WHERE account_id = $1 AND apns_token IS NOT NULL AND apns_token_invalid_at IS NULL LIMIT 1`,
    [accountId]);
  return (rowCount ?? 0) > 0;
}

/** SMS needs a verified number, explicit in-app consent, and no STOP since. */
export async function smsNumber(db: Queryable, accountId: string): Promise<string | undefined> {
  const { rows } = await db.query<{ e164: string }>(
    `SELECT e164 FROM phone_numbers
     WHERE account_id = $1 AND sms_consent_at IS NOT NULL AND sms_opted_out_at IS NULL`,
    [accountId]);
  return rows[0]?.e164;
}

/** The wanted channels that can reach this account right now (set up and consented), in order. */
export async function usableChannels(db: Queryable, accountId: string, wanted: readonly Channel[]): Promise<Channel[]> {
  const out: Channel[] = [];
  for (const ch of wanted) {
    if (ch === "push" ? await canPush(db, accountId) : await smsNumber(db, accountId)) out.push(ch);
  }
  return out;
}

export interface QueuedMessage { id: string; channel: Channel; state: string }

/** The same idempotency key was used before with a different payload (DOD-07). */
export class IdempotencyConflict extends Error {
  constructor() { super("idempotency_mismatch"); }
}

/** Associated data binding an encrypted message body to its account and row. */
export const bodyAad = (accountId: string, messageId: string) => `${accountId}:outbound:${messageId}`;

/** Production without MEMORY_ENCRYPTION_KEY: a text would be stored in plain text, so nothing is queued (ADR-706). */
export class EncryptionNotConfigured extends Error {
  constructor() { super("not_configured"); }
}

/** A daily cap on queued texts is reached (ADR-704): the account's own or the server's. Nothing was queued. */
export class SmsDailyLimit extends Error {
  constructor(readonly scope: "account" | "server") { super("daily_limit"); }
}

/** Render sets NODE_ENV=production for a Node service. Read at the time of the call so a test can switch it. */
export const isProduction = () => process.env.NODE_ENV === "production";

export interface EnqueueOptions {
  /** What the idempotency key is bound to (defaults to the body). */
  fingerprint?: string;
  /** When set, the body is stored encrypted instead of in plain text. In production it is required (ADR-706). */
  cipher?: TextCipher;
  /**
   * A text the user approved on a card (ADR-750): the hash of the number and the exact text they
   * saw. The worker checks it again right before sending.
   */
  approvalHash?: Buffer;
  /** Texts queued per UTC day: per account and for the server (ADR-704). Default DEFAULT_ABUSE_LIMITS. */
  smsCaps?: { perAccount: number; perServer: number };
}

/**
 * Inserts one row per channel. Re-sending the same idempotency key with the same payload returns
 * the existing rows; with a different payload it throws IdempotencyConflict and queues nothing.
 * Throws EncryptionNotConfigured in production without a cipher, and SmsDailyLimit when a text would pass
 * a daily cap; in both cases nothing is queued (the slots taken for earlier texts of this call are given back).
 */
export async function enqueue(
  db: Queryable, accountId: string, channels: Channel[], body: string, sendAt: Date, idempotencyKey: string,
  opts: EnqueueOptions = {},
): Promise<QueuedMessage[]> {
  // Fail closed (ADR-706): outside production a missing key still stores plain text, so tests and local runs work.
  if (!opts.cipher && isProduction()) throw new EncryptionNotConfigured();
  const payloadHash = sha256(opts.fingerprint ?? body);
  const out: QueuedMessage[] = [];
  for (const channel of channels) {
    const id = randomUUID();
    const sealed = opts.cipher?.encrypt(body, bodyAad(accountId, id));
    // An SMS keeps a hash of its exact text until its outcome is known, so an unknown one can be
    // found in Twilio's message list (reconcileUnknownSms).
    const bodyHash = channel === "sms" ? sha256(body) : null;
    const approval = channel === "sms" ? opts.approvalHash ?? null : null;
    const slots = channel === "sms" ? await takeSmsSlots(db, accountId, idempotencyKey, opts.smsCaps) : undefined;
    let inserted: number | null;
    try {
      ({ rowCount: inserted } = await db.query(
        `INSERT INTO outbound_messages
           (id, account_id, channel, idempotency_key, body, body_ciphertext, body_key_version, send_at, state, payload_hash,
            body_hash, approved_text, approval_hash)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'queued', $9, $10, $11, $12)
         ON CONFLICT (account_id, channel, idempotency_key) DO NOTHING`,
        [id, accountId, channel, idempotencyKey, sealed ? null : body, sealed ?? null,
          sealed ? opts.cipher!.keyVersion : null, sendAt, payloadHash, bodyHash, approval !== null, approval]));
    } catch (err) {
      // Inside a transaction the rollback undoes the count anyway; outside one it must be given back here.
      await slots?.giveBack().catch(() => {});
      throw err;
    }
    // A replay of an earlier request queued nothing new, so it doesn't use up a text.
    if (!inserted) await slots?.giveBack();
    const { rows } = await db.query<QueuedMessage & { payload_hash: Buffer | null }>(
      `SELECT id, channel, state, payload_hash FROM outbound_messages
       WHERE account_id = $1 AND channel = $2 AND idempotency_key = $3`,
      [accountId, channel, idempotencyKey]);
    const row = rows[0]!;
    if (row.payload_hash && !row.payload_hash.equals(payloadHash)) throw new IdempotencyConflict();
    out.push({ id: row.id, channel: row.channel, state: row.state });
  }
  return out;
}

/**
 * Takes a slot of each daily cap on queued texts (ADR-704): the account's and the server's, both atomic. A replay of a
 * text already queued under the same idempotency key takes nothing, so a client that retries at the cap still gets its
 * answer. Throws SmsDailyLimit when a cap is reached.
 */
async function takeSmsSlots(
  db: Queryable, accountId: string, idempotencyKey: string, caps?: { perAccount: number; perServer: number },
): Promise<{ giveBack(): Promise<void> } | undefined> {
  const seen = await db.query(
    "SELECT 1 FROM outbound_messages WHERE account_id = $1 AND channel = 'sms' AND idempotency_key = $2", [accountId, idempotencyKey]);
  if (seen.rowCount) return undefined;
  const perAccount = caps?.perAccount ?? DEFAULT_ABUSE_LIMITS.smsPerAccountDay;
  const perServer = caps?.perServer ?? DEFAULT_ABUSE_LIMITS.smsPerServerDay;
  const key = sha256(accountId).toString("hex"); // an account id is a random uuid: a plain hash is enough
  if (!(await takeCounter(db, "sms_account", key, perAccount))) throw new SmsDailyLimit("account");
  if (!(await takeServerSlot(db, "sms", perServer))) {
    await returnCounter(db, "sms_account", key);
    throw new SmsDailyLimit("server");
  }
  return { giveBack: async () => { await returnServerSlot(db, "sms"); await returnCounter(db, "sms_account", key); } };
}

export async function cancelQueuedSms(db: Queryable, accountId: string): Promise<void> {
  await db.query(
    `UPDATE outbound_messages SET state = 'cancelled', error_code = 'sms_not_enabled', ${ERASE}, updated_at = now()
     WHERE account_id = $1 AND channel = 'sms' AND state = 'queued'`,
    [accountId]);
}

/** Erases a message's text and its hashes: for a final state whose outcome is known. */
export const ERASE = "body = NULL, body_ciphertext = NULL, body_key_version = NULL, approval_hash = NULL, body_hash = NULL";

interface Claimed { id: string; account_id: string; channel: Channel; body: string; attempts: number; approval_hash: Buffer | null; idempotency_key?: string }
interface ClaimedRow extends Omit<Claimed, "body"> { body: string | null; body_ciphertext: Buffer | null }

export interface Senders {
  push?: PushSender; sms?: SmsSender; cipher?: TextCipher;
  /** Calling codes a text may go to, checked again at send time (ADR-704). Default DEFAULT_ABUSE_LIMITS. */
  allowedCountryCodes?: readonly string[];
}

export interface DispatchResult { reaped: number; processed: number }

/**
 * One worker pass: mark messages stuck in `sending` as `unknown` (never resent), then claim due
 * messages with SKIP LOCKED so several workers can run, and hand each to its provider.
 */
export async function dispatchDue(db: Db, senders: Senders, batch = 20): Promise<DispatchResult> {
  const reaped = await db.query(
    `UPDATE outbound_messages
     SET state = 'unknown', error_code = 'worker_interrupted', body = NULL, body_ciphertext = NULL, body_key_version = NULL, updated_at = now()
     WHERE state = 'sending' AND updated_at < now() - $1::interval`,
    [STALE_SENDING]);
  const { rows } = await db.query<ClaimedRow>(
    `WITH due AS (
       SELECT id FROM outbound_messages
       WHERE state = 'queued' AND send_at <= now()
       ORDER BY send_at LIMIT $1 FOR UPDATE SKIP LOCKED)
     UPDATE outbound_messages m
     SET state = 'sending', attempts = m.attempts + 1, updated_at = now()
     FROM due WHERE m.id = due.id
     RETURNING m.id, m.account_id, m.channel, m.body, m.body_ciphertext, m.attempts, m.approval_hash, m.idempotency_key`,
    [batch]);
  for (const row of rows) {
    // Claimed rows wait their turn in this batch. Refresh the claim just before sending so the
    // stale-`sending` reaper times each message, not the whole batch; if another worker already
    // reaped it as unknown, it must not be sent now.
    const fresh = await db.query(
      "UPDATE outbound_messages SET updated_at = now() WHERE id = $1 AND state = 'sending'", [row.id]);
    if (!fresh.rowCount) continue;
    const body = row.body ?? openBody(senders.cipher, row);
    const msg: Claimed = { ...row, body: body ?? "" };
    if (body === undefined) {
      // Encrypted with a key this server doesn't have: never sent, so a definite failure.
      await finalize(db, msg, { kind: "rejected", code: "body_unreadable" });
      continue;
    }
    let outcome: SendOutcome | { kind: "cancelled"; code: string };
    try {
      outcome = msg.channel === "push" ? await sendPush(db, senders.push, msg)
        : await sendSms(db, senders.sms, msg, senders.allowedCountryCodes ?? DEFAULT_ABUSE_LIMITS.allowedCountryCodes);
    } catch {
      outcome = { kind: "unknown", code: "dispatch_error" };
    }
    await finalize(db, msg, outcome);
  }
  return { reaped: reaped.rowCount ?? 0, processed: rows.length };
}

function openBody(cipher: TextCipher | undefined, row: ClaimedRow): string | undefined {
  if (!cipher || !row.body_ciphertext) return undefined;
  try {
    return cipher.decrypt(row.body_ciphertext, bodyAad(row.account_id, row.id));
  } catch {
    return undefined;
  }
}

/**
 * What a tap on this push should open, from the key it was queued under (the call worker queues
 * `call-result:<attempt>`, the errand worker `errand-result:<id>`, the file watch `file-watch:<id>`). A kind
 * only: the attempt, the task, the file and the words stay on the server and in the app. A finished task or
 * file opens Messages, where Doddy's message about it is (owner, 10 Nov 2026).
 */
export function pushData(idempotencyKey: string | undefined): PushData | undefined {
  if (idempotencyKey?.startsWith("call-result:")) return { kind: "call-result" };
  if (idempotencyKey?.startsWith("errand-result:")) return { kind: "errand-result" };
  if (idempotencyKey?.startsWith("file-watch:")) return { kind: "file-ready" };
  return undefined;
}

async function sendPush(db: Db, sender: PushSender | undefined, msg: Claimed): Promise<SendOutcome | { kind: "cancelled"; code: string }> {
  if (!sender) return { kind: "transient", code: "push_not_configured" };
  const { rows: devices } = await db.query<{ id: string; apns_token: string; apns_environment: "sandbox" | "production" }>(
    `SELECT id, apns_token, apns_environment FROM devices
     WHERE account_id = $1 AND apns_token IS NOT NULL AND apns_token_invalid_at IS NULL`,
    [msg.account_id]);
  if (devices.length === 0) return { kind: "cancelled", code: "push_not_enabled" };

  const results: SendOutcome[] = [];
  for (const d of devices) {
    const r = await sender.send(
      { deviceToken: d.apns_token, environment: d.apns_environment },
      { title: "Doddy", body: msg.body }, msg.id, pushData(msg.idempotency_key));
    if (r.kind === "rejected" && r.deviceGone) {
      await db.query("UPDATE devices SET apns_token_invalid_at = now() WHERE id = $1", [d.id]);
    }
    results.push(r);
  }
  // Delivered to at least one phone counts as sent; otherwise report the most cautious outcome.
  return results.find((r) => r.kind === "accepted")
    ?? results.find((r) => r.kind === "unknown")
    ?? results.find((r) => r.kind === "transient")
    ?? results[0]!;
}

async function sendSms(
  db: Db, sender: SmsSender | undefined, msg: Claimed, allowedCountryCodes: readonly string[],
): Promise<SendOutcome | { kind: "cancelled"; code: string }> {
  if (!sender) return { kind: "transient", code: "sms_not_configured" };
  // Re-checked at send time: consent may have been withdrawn after the message was queued.
  const to = await smsNumber(db, msg.account_id);
  if (!to) return { kind: "cancelled", code: "sms_not_enabled" };
  // An approved text goes out only if the number and the text are still exactly what the user
  // approved (ADR-750, DOD-07): a changed number, or a stored text that changed, sends nothing.
  if (msg.approval_hash && !timingSafeEqual(textApprovalHash(to, msg.body), msg.approval_hash)) {
    return { kind: "rejected", code: "approval_mismatch" };
  }
  // A number verified before the country list existed (or before it changed) is not texted either (ADR-704).
  if (!isAllowedNumber(to, allowedCountryCodes)) return { kind: "cancelled", code: "sms_country_not_allowed" };
  const r = await sender.send(to, msg.body);
  if (r.kind === "rejected" && r.unsubscribed) {
    await db.query("UPDATE phone_numbers SET sms_opted_out_at = now(), updated_at = now() WHERE account_id = $1",
      [msg.account_id]);
  }
  return r;
}

async function finalize(db: Db, msg: Claimed, o: SendOutcome | { kind: "cancelled"; code: string }): Promise<void> {
  const final = async (state: string, code: string | null, providerId: string | null = null) => {
    const r = await db.query(
      // An unknown outcome keeps its hashes until Twilio's message list has been checked.
      `UPDATE outbound_messages
       SET state = $2, error_code = $3, provider_message_id = $4, body = NULL, body_ciphertext = NULL, body_key_version = NULL,
         approval_hash = CASE WHEN $2 = 'unknown' THEN approval_hash END,
         body_hash = CASE WHEN $2 = 'unknown' THEN body_hash END, updated_at = now()
       WHERE id = $1 AND state = 'sending'`,
      [msg.id, state, code, providerId]);
    // The row was reaped meanwhile: the real outcome would otherwise vanish without a trace.
    if (!r.rowCount) log("outcome after reap", { id: msg.id, outcome: state, code });
  };
  switch (o.kind) {
    case "accepted":
      await final("sent", null, o.providerId);
      // Twilio's record of the text is deleted later (ADR-753), receipt or not.
      if (msg.channel === "sms") await scheduleDeletion(db, "message", o.providerId);
      break;
    case "rejected": await final("failed", o.code); break;
    case "unknown": await final("unknown", o.code); break;
    case "cancelled": await final("cancelled", o.code); break;
    case "transient":
      if (msg.attempts >= MAX_ATTEMPTS) { await final("failed", o.code); break; }
      // Exponential backoff: 30 s, 60 s, 120 s, 240 s.
      await db.query(
        `UPDATE outbound_messages
         SET state = 'queued', error_code = $2, send_at = now() + make_interval(secs => $3), updated_at = now()
         WHERE id = $1 AND state = 'sending'`,
        [msg.id, o.code, 30 * 2 ** (msg.attempts - 1)]);
  }
}

/** One message in Twilio's message list, as the lookup needs it. */
export interface SentRecord { sid: string; body: string; createdAt: Date; status: string }

/**
 * Reconciliation first (DOD-09): a text whose outcome is unknown is looked up in Twilio's message
 * list a little later, by its recipient and the hash of its exact text. Found, it becomes `sent`
 * with Twilio's id and status; not found, it stays unknown and says so. Never resent here.
 */
export async function reconcileUnknownSms(db: Db, sms: SmsSender | undefined, batch = 5): Promise<number> {
  if (!sms?.recentMessagesTo) return 0;
  const { rows } = await db.query<{ id: string; body_hash: Buffer; created_at: Date; e164: string; lookup_attempts: number }>(
    `SELECT m.id, m.body_hash, m.created_at, p.e164, m.lookup_attempts FROM outbound_messages m
     JOIN phone_numbers p ON p.account_id = m.account_id
     WHERE m.state = 'unknown' AND m.channel = 'sms' AND m.lookup IS NULL AND m.body_hash IS NOT NULL
       AND m.updated_at < now() - $1::interval
     ORDER BY m.updated_at LIMIT $2`, [LOOKUP_AFTER, batch]);
  for (const row of rows) {
    const records = await sms.recentMessagesTo(row.e164).catch(() => undefined);
    if (!records) {
      // Couldn't ask Twilio: try again after the same wait, then give up and say so.
      await db.query(
        `UPDATE outbound_messages SET lookup_attempts = lookup_attempts + 1, updated_at = now(),
           lookup = CASE WHEN lookup_attempts + 1 >= $2 THEN 'failed' END,
           approval_hash = CASE WHEN lookup_attempts + 1 >= $2 THEN NULL ELSE approval_hash END,
           body_hash = CASE WHEN lookup_attempts + 1 >= $2 THEN NULL ELSE body_hash END
         WHERE id = $1 AND state = 'unknown'`, [row.id, MAX_LOOKUPS]);
      continue;
    }
    const earliest = row.created_at.getTime() - 5 * 60_000;
    const match = records.find((r) => r.createdAt.getTime() >= earliest && sha256(r.body).equals(row.body_hash));
    if (match) {
      try {
        await db.query(
          `UPDATE outbound_messages SET state = 'sent', provider_message_id = $2, delivery_status = $3, lookup = 'found',
             error_code = NULL, approval_hash = NULL, body_hash = NULL, updated_at = now()
           WHERE id = $1 AND state = 'unknown'`, [row.id, match.sid, match.status]);
        await scheduleDeletion(db, "message", match.sid);
      } catch {
        // That Twilio message already belongs to another row: don't guess, and don't look again.
        await db.query(
          `UPDATE outbound_messages SET lookup = 'failed', approval_hash = NULL, body_hash = NULL, updated_at = now()
           WHERE id = $1 AND state = 'unknown'`, [row.id]);
      }
    } else {
      await db.query(
        `UPDATE outbound_messages SET lookup = 'not_found', approval_hash = NULL, body_hash = NULL, updated_at = now()
         WHERE id = $1 AND state = 'unknown'`, [row.id]);
    }
    log("unknown text looked up", { id: row.id, found: !!match });
  }
  return rows.length;
}
