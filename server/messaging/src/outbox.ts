import { createHash, randomUUID } from "node:crypto";
import type pg from "pg";
import type { Db } from "./db.js";
import type { PushSender, SendOutcome, SmsSender } from "./providers/types.js";

export type Channel = "push" | "sms";

export const MAX_ATTEMPTS = 5;
export const STALE_SENDING = "5 minutes";

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

export interface QueuedMessage { id: string; channel: Channel; state: string }

/** The same idempotency key was used before with a different payload (DOD-07). */
export class IdempotencyConflict extends Error {
  constructor() { super("idempotency_mismatch"); }
}

/**
 * Inserts one row per channel. Re-sending the same idempotency key with the same payload returns
 * the existing rows; with a different payload it throws IdempotencyConflict and queues nothing.
 * `fingerprint` is what the key is bound to (defaults to the body).
 */
export async function enqueue(
  db: Queryable, accountId: string, channels: Channel[], body: string, sendAt: Date, idempotencyKey: string,
  fingerprint: string = body,
): Promise<QueuedMessage[]> {
  const payloadHash = createHash("sha256").update(fingerprint).digest();
  const out: QueuedMessage[] = [];
  for (const channel of channels) {
    await db.query(
      `INSERT INTO outbound_messages (id, account_id, channel, idempotency_key, body, send_at, state, payload_hash)
       VALUES ($1, $2, $3, $4, $5, $6, 'queued', $7)
       ON CONFLICT (account_id, channel, idempotency_key) DO NOTHING`,
      [randomUUID(), accountId, channel, idempotencyKey, body, sendAt, payloadHash]);
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

export async function cancelQueuedSms(db: Queryable, accountId: string): Promise<void> {
  await db.query(
    `UPDATE outbound_messages SET state = 'cancelled', error_code = 'sms_not_enabled', body = NULL, updated_at = now()
     WHERE account_id = $1 AND channel = 'sms' AND state = 'queued'`,
    [accountId]);
}

interface Claimed { id: string; account_id: string; channel: Channel; body: string; attempts: number }

export interface Senders { push?: PushSender; sms?: SmsSender }

export interface DispatchResult { reaped: number; processed: number }

/**
 * One worker pass: mark messages stuck in `sending` as `unknown` (never resent), then claim due
 * messages with SKIP LOCKED so several workers can run, and hand each to its provider.
 */
export async function dispatchDue(db: Db, senders: Senders, batch = 20): Promise<DispatchResult> {
  const reaped = await db.query(
    `UPDATE outbound_messages
     SET state = 'unknown', error_code = 'worker_interrupted', body = NULL, updated_at = now()
     WHERE state = 'sending' AND updated_at < now() - $1::interval`,
    [STALE_SENDING]);
  const { rows } = await db.query<Claimed>(
    `WITH due AS (
       SELECT id FROM outbound_messages
       WHERE state = 'queued' AND send_at <= now()
       ORDER BY send_at LIMIT $1 FOR UPDATE SKIP LOCKED)
     UPDATE outbound_messages m
     SET state = 'sending', attempts = m.attempts + 1, updated_at = now()
     FROM due WHERE m.id = due.id
     RETURNING m.id, m.account_id, m.channel, m.body, m.attempts`,
    [batch]);
  for (const msg of rows) {
    // Claimed rows wait their turn in this batch. Refresh the claim just before sending so the
    // stale-`sending` reaper times each message, not the whole batch; if another worker already
    // reaped it as unknown, it must not be sent now.
    const fresh = await db.query(
      "UPDATE outbound_messages SET updated_at = now() WHERE id = $1 AND state = 'sending'", [msg.id]);
    if (!fresh.rowCount) continue;
    let outcome: SendOutcome | { kind: "cancelled"; code: string };
    try {
      outcome = msg.channel === "push" ? await sendPush(db, senders.push, msg) : await sendSms(db, senders.sms, msg);
    } catch {
      outcome = { kind: "unknown", code: "dispatch_error" };
    }
    await finalize(db, msg, outcome);
  }
  return { reaped: reaped.rowCount ?? 0, processed: rows.length };
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
      { title: "Doddy", body: msg.body }, msg.id);
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

async function sendSms(db: Db, sender: SmsSender | undefined, msg: Claimed): Promise<SendOutcome | { kind: "cancelled"; code: string }> {
  if (!sender) return { kind: "transient", code: "sms_not_configured" };
  // Re-checked at send time: consent may have been withdrawn after the message was queued.
  const to = await smsNumber(db, msg.account_id);
  if (!to) return { kind: "cancelled", code: "sms_not_enabled" };
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
      `UPDATE outbound_messages
       SET state = $2, error_code = $3, provider_message_id = $4, body = NULL, updated_at = now()
       WHERE id = $1 AND state = 'sending'`,
      [msg.id, state, code, providerId]);
    // The row was reaped meanwhile: the real outcome would otherwise vanish without a trace.
    if (!r.rowCount) console.log(JSON.stringify({ time: new Date().toISOString(), msg: "outcome after reap", id: msg.id, outcome: state, code }));
  };
  switch (o.kind) {
    case "accepted": await final("sent", null, o.providerId); break;
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
