import { randomUUID } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import type pg from "pg";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { hasDoddyAccount, principal, requireDevice, requireDeviceBeforeBody } from "../auth.js";
import { OUTBOUND_CONSENT_VERSIONS, OUTBOUND_DAILY_LIMIT, OUTBOUND_HOURLY_LIMIT } from "../calls.js";
import { abuseLimits } from "../config.js";
import { hashPin, isAcceptablePin } from "../crypto.js";
import { inTransaction } from "../db.js";
import type { NoteSource } from "../inbox.js";
import { log } from "../log.js";
import { isAllowedNumber } from "../phoneCountries.js";
import { formatClock, isValidTimeZone, QUIET_HOURS_DEFAULT } from "../quietHours.js";
import { cancelScheduledCalls } from "../scheduledCalls.js";
import { returnServerSlot, takeServerSlot } from "../serverUsage.js";
import { callsAvailable } from "./twilioVoice.js";

const settingsBody = z.object({
  inboundEnabled: z.boolean().optional(),
  outboundConsent: z.boolean().optional(),
  outboundConsentTextVersion: z.string().max(32).optional(),
  /** The iPhone's current time zone, for quiet hours on scheduled calls (ADR-754). */
  timeZone: z.string().refine(isValidTimeZone, "unknown time zone").optional(),
}).refine((b) => b.outboundConsent !== true || OUTBOUND_CONSENT_VERSIONS.has(b.outboundConsentTextVersion ?? ""),
  { path: ["outboundConsentTextVersion"] });
const pinBody = z.object({ pin: z.string() });
const MAX_SNAPSHOT_ITEMS = 5000;
const snapshotBody = z.object({
  items: z.array(z.object({
    // Postgres returns uuids in lowercase; the encryption binding must use the same spelling
    // (iOS sends uppercase).
    id: z.uuid().transform((id) => id.toLowerCase()),
    text: z.string().min(1).max(5000),
    capturedAt: z.iso.datetime({ offset: true }).nullable().optional(),
  })).max(MAX_SNAPSHOT_ITEMS),
}).refine((b) => new Set(b.items.map((i) => i.id)).size === b.items.length, "duplicate ids");
const idParam = z.object({ id: z.uuid() });

/**
 * A changed or removed PIN also ends the access that calls in progress got with the old one, and their right to a
 * recap (src/phoneRecaps.ts). A finished call has no session left, so it keeps its own.
 */
async function forgetPinOnCalls(c: pg.PoolClient, accountId: string): Promise<void> {
  await c.query(
    `UPDATE calls SET pin_verified_at = NULL
     WHERE account_id = $1 AND id IN (SELECT call_id FROM call_sessions WHERE account_id = $1 AND call_id IS NOT NULL)`, [accountId]);
  await c.query("UPDATE call_sessions SET pin_verified_at = NULL WHERE account_id = $1", [accountId]);
}

export const callRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const authBeforeBody = requireDeviceBeforeBody(db);
  const limits = abuseLimits(deps.limits);
  const ensureRow = (accountId: string) =>
    db.query("INSERT INTO call_settings (account_id) VALUES ($1) ON CONFLICT DO NOTHING", [accountId]);

  const quiet = deps.quietHours ?? QUIET_HOURS_DEFAULT;

  app.get("/v1/calls/settings", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    // One round trip; the settings row may not exist yet.
    const { rows } = await db.query<{
      inbound_enabled: boolean | null; pin_set: boolean | null; pin_locked: boolean | null; outbound: boolean | null;
      memory_on: boolean | null; copies: number; phone: boolean; time_zone: string | null;
    }>(
      `SELECT s.inbound_enabled, s.time_zone, s.pin_hash IS NOT NULL AS pin_set, coalesce(s.pin_locked_until > now(), false) AS pin_locked,
              s.outbound_consent_at IS NOT NULL AS outbound, s.memory_copy_enabled_at IS NOT NULL AS memory_on,
              (SELECT count(*)::int FROM memory_copies WHERE account_id = $1) AS copies,
              EXISTS (SELECT 1 FROM phone_numbers WHERE account_id = $1) AS phone
       FROM (SELECT $1::uuid AS account_id) a LEFT JOIN call_settings s ON s.account_id = a.account_id`, [accountId]);
    const r = rows[0]!;
    const s = r.inbound_enabled === null ? undefined : r;
    return {
      // What the server can actually do; the app shows "needs setup" otherwise.
      available: callsAvailable(deps),
      doddyNumber: deps.doddyPhoneNumber ?? null,
      phoneVerified: r.phone,
      inboundEnabled: s?.inbound_enabled ?? false,
      pinSet: s?.pin_set ?? false,
      pinLocked: s?.pin_locked ?? false,
      outboundConsent: s?.outbound ?? false,
      memoryCopy: { enabled: s?.memory_on ?? false, count: r.copies },
      // No scheduled call rings inside these, where the user is, unless its card allowed it.
      quietHours: { start: formatClock(quiet.start), end: formatClock(quiet.end) },
      timeZone: r.time_zone,
    };
  });

  app.put("/v1/calls/settings", { preHandler: auth }, async (req, reply) => {
    const body = parse(settingsBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    if (body.inboundEnabled || body.outboundConsent) {
      const phone = await db.query("SELECT 1 FROM phone_numbers WHERE account_id = $1", [accountId]);
      if (!phone.rowCount) return reply.code(409).send({ error: "no_verified_phone" });
    }
    await ensureRow(accountId);
    await inTransaction(db, async (c) => {
      await c.query(
        `UPDATE call_settings SET updated_at = now(),
           inbound_enabled = coalesce($2, inbound_enabled),
           outbound_consent_at = CASE WHEN $3::boolean IS NULL THEN outbound_consent_at WHEN $3 THEN now() END,
           outbound_consent_text_version = CASE WHEN $3::boolean IS NULL THEN outbound_consent_text_version WHEN $3 THEN $4 END,
           time_zone = coalesce($5, time_zone)
         WHERE account_id = $1`,
        [accountId, body.inboundEnabled ?? null, body.outboundConsent ?? null, body.outboundConsentTextVersion ?? null,
          body.timeZone ?? null]);
      // Turning calls from Doddy off also cancels the calls booked for later (ADR-754).
      if (body.outboundConsent === false) await cancelScheduledCalls(c, accountId, "consent_off");
    });
    return reply.code(204).send();
  });

  app.put("/v1/calls/pin", { preHandler: auth, config: { rateLimit: { max: 10, timeWindow: "1 hour" } } }, async (req, reply) => {
    const body = parse(pinBody, req.body, reply);
    if (!body) return;
    if (!isAcceptablePin(body.pin)) return reply.code(400).send({ error: "weak_pin" });
    const { accountId } = principal(req);
    await ensureRow(accountId);
    const hash = await hashPin(body.pin);
    await inTransaction(db, async (c) => {
      await c.query(
        `UPDATE call_settings SET pin_hash = $2, pin_failed_attempts = 0, pin_lock_count = 0, pin_locked_until = NULL, updated_at = now()
         WHERE account_id = $1`, [accountId, hash]);
      await forgetPinOnCalls(c, accountId);
    });
    return reply.code(204).send();
  });

  app.delete("/v1/calls/pin", { preHandler: auth }, async (req, reply) => {
    const { accountId } = principal(req);
    await inTransaction(db, async (c) => {
      await c.query("UPDATE call_settings SET pin_hash = NULL, updated_at = now() WHERE account_id = $1", [accountId]);
      await forgetPinOnCalls(c, accountId);
    });
    return reply.code(204).send();
  });

  // "Call me now". Doddy only calls the verified number, only after explicit consent. Twilio rings
  // it from Doddy's number; the phone agent and the call's session start only when it is answered
  // (routes/twilioVoice.ts, ADR-750).
  app.post("/v1/calls/outbound", {
    preHandler: auth, config: { rateLimit: { max: OUTBOUND_HOURLY_LIMIT, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    if (!callsAvailable(deps).outbound) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    const { rows } = await db.query<{ e164: string; consent: boolean }>(
      `SELECT p.e164, s.outbound_consent_at IS NOT NULL AS consent FROM phone_numbers p
       LEFT JOIN call_settings s ON s.account_id = p.account_id WHERE p.account_id = $1`, [accountId]);
    const target = rows[0];
    if (!target) return reply.code(409).send({ error: "no_verified_phone" });
    if (!target.consent) return reply.code(409).send({ error: "outbound_not_enabled" });
    // A number verified before the country list existed (or before it changed) is not called either (ADR-704).
    if (!isAllowedNumber(target.e164, limits.allowedCountryCodes)) return reply.code(409).send({ error: "phone_not_allowed" });
    const callId = randomUUID();
    const underLimit = await inTransaction(db, async (c) => {
      // Count and insert under one per-account lock, so parallel taps can't pass the limit together.
      await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [accountId]);
      const today = await c.query<{ n: number }>(
        `SELECT count(*)::int AS n FROM calls WHERE account_id = $1 AND direction = 'outbound'
         AND created_at > now() - interval '1 day'`, [accountId]);
      if ((today.rows[0]?.n ?? 0) >= OUTBOUND_DAILY_LIMIT) return false;
      // And a cap for the whole server per UTC day, taken in the same transaction as the call row (ADR-704): the
      // account's ten a day are free to make, so on their own they would not bound what a flood of accounts costs.
      if (!(await takeServerSlot(c, "outbound_calls", limits.outboundCallsPerServerDay))) return false;
      await c.query(
        "INSERT INTO calls (id, account_id, direction, status) VALUES ($1, $2, 'outbound', 'requested')", [callId, accountId]);
      return true;
    });
    if (!underLimit) return reply.code(429).send({ error: "daily_limit" });
    const outcome = await deps.outbound!.placeCall({
      to: target.e164, from: deps.doddyPhoneNumber!,
      answerUrl: `${deps.publicBaseUrl}/webhooks/twilio/voice/outbound/${callId}`,
      statusCallbackUrl: `${deps.publicBaseUrl}/webhooks/twilio/call-status`,
    });
    const status = outcome.kind === "accepted" ? "requested" : outcome.kind === "unknown" ? "unknown" : "failed";
    // Only from "requested": Twilio's callbacks may already have moved the call on.
    await db.query(
      `UPDATE calls SET status = CASE WHEN status = 'requested' THEN $2 ELSE status END,
         call_sid = coalesce(call_sid, $3), error_code = $4 WHERE id = $1`,
      [callId, status,
        outcome.kind === "accepted" ? outcome.callSid : null,
        outcome.kind === "accepted" ? null : outcome.code]);
    // The provider's code (e.g. twilio_21215) is the only way to tell why "Call me now" failed; ids and codes only.
    if (outcome.kind !== "accepted") log("outbound call", { id: callId, state: status, code: outcome.code });
    // Refused by the provider: no call was placed, so it doesn't use up the server's day. (An unknown outcome might be
    // ringing, so that one stays counted.) The account's own count stays, as before.
    if (status === "failed") {
      await returnServerSlot(db, "outbound_calls").catch(() => {});
      return reply.code(502).send({ error: "provider_unavailable", callId });
    }
    return reply.code(202).send({ callId, status });
  });

  // `recapNotCreated`: why a call has no recap while recaps are on ("pin_not_verified", src/phoneRecaps.ts), else null.
  app.get("/v1/calls", { preHandler: auth }, async (req) => {
    const { rows } = await db.query(
      `SELECT id, direction, status, created_at AS "createdAt", recap_not_created AS "recapNotCreated" FROM calls
       WHERE account_id = $1 ORDER BY created_at DESC LIMIT 20`, [principal(req).accountId]);
    return { calls: rows };
  });

  // Notes from calls wait here until the user confirms (saves locally) or discards them.
  app.get("/v1/call-notes", { preHandler: auth }, async (req, reply) => {
    if (!deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    const { rows } = await db.query<{ id: string; ciphertext: Buffer; created_at: Date; source: NoteSource }>(
      "SELECT id, ciphertext, created_at, source FROM call_notes WHERE account_id = $1 ORDER BY created_at", [accountId]);
    const cipher = deps.cipher;
    // A note that won't decrypt (e.g. after a key change) must not hide the others; it is listed
    // separately (older apps ignore the field) so it can still be discarded.
    // `source`: taken on a call, the user's text word for word, or written by Doddy from a text (ADR-753).
    const notes: { id: string; text: string; createdAt: Date; source: NoteSource }[] = [];
    const unreadable: { id: string; createdAt: Date }[] = [];
    for (const r of rows) {
      try {
        notes.push({ id: r.id, text: cipher.decrypt(r.ciphertext, `${accountId}:note:${r.id}`), createdAt: r.created_at, source: r.source });
      } catch {
        unreadable.push({ id: r.id, createdAt: r.created_at });
      }
    }
    return { notes, unreadable };
  });

  app.delete("/v1/call-notes/:id", { preHandler: auth }, async (req, reply) => {
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    const r = await db.query("DELETE FROM call_notes WHERE id = $1 AND account_id = $2", [p.id, principal(req).accountId]);
    return r.rowCount ? reply.code(204).send() : reply.code(404).send({ error: "not_found" });
  });

  // Opt-in copy of memories so calls can answer from them. Off deletes every copy at once.
  // Turning it on needs a Doddy account (signed in with Apple, Google or email); turning it off never does, so an
  // anonymous account from before can always delete what it stored.
  app.put("/v1/memory-copy", { preHandler: auth }, async (req, reply) => {
    if (!deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const body = parse(z.object({ enabled: z.boolean() }), req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    if (body.enabled && !(await hasDoddyAccount(db, accountId))) return reply.code(403).send({ error: "sign_in_required" });
    await ensureRow(accountId);
    await inTransaction(db, async (c) => {
      // The settings row first, as the snapshot below locks it, so the two never wait on each other in turn.
      await c.query(
        `UPDATE call_settings SET updated_at = now(),
           memory_copy_enabled_at = CASE WHEN $2 THEN coalesce(memory_copy_enabled_at, now()) END,
           memory_copy_bytes = CASE WHEN $2 THEN memory_copy_bytes ELSE 0 END
         WHERE account_id = $1`, [accountId, body.enabled]);
      if (!body.enabled) await c.query("DELETE FROM memory_copies WHERE account_id = $1", [accountId]);
    });
    return reply.code(204).send();
  });

  // Replaces the whole copy with what the phone holds now (deletions included).
  // The app sends one snapshot per burst of edits; 60 an hour is plenty and caps the encrypt work.
  // Only for a Doddy account, and within two quotas on the stored ciphertext (migration 030): the account's
  // (MEMORY_COPY_MB_PER_ACCOUNT, 413 memory_copy_too_large) and all accounts' together (MEMORY_COPY_MB_PER_SERVER,
  // 507 memory_copy_server_full). Both are counted by the database in the transaction that writes the copy.
  app.put("/v1/memory-copy/snapshot", {
    preParsing: authBeforeBody, bodyLimit: 8 * 1024 * 1024, config: { rateLimit: { max: 60, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    if (!deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    if (!(await hasDoddyAccount(db, accountId))) return reply.code(403).send({ error: "sign_in_required" });
    // Checked before parsing, so an over-long list is refused without validating each element.
    const rawItems = (req.body as { items?: unknown } | null)?.items;
    if (!Array.isArray(rawItems) || rawItems.length > MAX_SNAPSHOT_ITEMS) {
      return reply.code(400).send({ error: "invalid_request", fields: ["items"] });
    }
    const body = parse(snapshotBody, req.body, reply);
    if (!body) return;
    const tooLarge = () => reply.code(413).send({ error: "memory_copy_too_large", limitBytes: limits.memoryCopyBytesPerAccount });
    // Encrypted text is never shorter than the text itself: a copy over the quota already is refused unencrypted.
    if (body.items.reduce((n, i) => n + Buffer.byteLength(i.text, "utf8"), 0) > limits.memoryCopyBytesPerAccount) return tooLarge();
    const cipher = deps.cipher;
    // Encrypted before the transaction, so the server-wide lock below is held only for the database work.
    const sealed = body.items.map((i) => cipher.encrypt(i.text, `${accountId}:memory:${i.id}`));
    let outcome: "stored" | "off";
    try {
      outcome = await inTransaction(db, async (c) => {
        const { rows } = await c.query<{ on: boolean; bytes: string }>(
          "SELECT memory_copy_enabled_at IS NOT NULL AS on, memory_copy_bytes AS bytes FROM call_settings WHERE account_id = $1 FOR UPDATE",
          [accountId]);
        if (!rows[0]?.on) return "off";
        const before = Number(rows[0].bytes);
        // One snapshot at a time across the server, so two can't both fit under the server's quota.
        await c.query("SELECT pg_advisory_xact_lock(hashtext('memory_copy_quota'))");
        await c.query("DELETE FROM memory_copies WHERE account_id = $1", [accountId]);
        if (body.items.length) {
          await c.query(
            `INSERT INTO memory_copies (account_id, memory_id, key_version, ciphertext, captured_at)
             SELECT $1, * FROM unnest($2::uuid[], $3::smallint[], $4::bytea[], $5::timestamptz[])`,
            [accountId,
              body.items.map((i) => i.id),
              body.items.map(() => cipher.keyVersion),
              sealed,
              body.items.map((i) => i.capturedAt ?? null)]);
        }
        // What the account stores now, as the database counts it, kept beside its settings for the server's sum.
        const { rows: [mine] } = await c.query<{ bytes: string }>(
          `UPDATE call_settings SET memory_copy_bytes =
             (SELECT coalesce(sum(octet_length(ciphertext)), 0) FROM memory_copies WHERE account_id = $1)
           WHERE account_id = $1 RETURNING memory_copy_bytes AS bytes`, [accountId]);
        const bytes = Number(mine!.bytes);
        if (bytes > limits.memoryCopyBytesPerAccount) throw new MemoryCopyQuota("account");
        // A copy that doesn't grow is always kept, so a smaller one still goes through on a full server.
        if (bytes > before) {
          const { rows: [all] } = await c.query<{ bytes: string }>(
            "SELECT coalesce(sum(memory_copy_bytes), 0) AS bytes FROM call_settings");
          if (Number(all!.bytes) > limits.memoryCopyBytesPerServer) throw new MemoryCopyQuota("server");
        }
        return "stored";
      });
    } catch (err) {
      // Thrown inside the transaction, so nothing of this snapshot was kept: the earlier copy stays as it was.
      if (!(err instanceof MemoryCopyQuota)) throw err;
      log("memory copy refused, quota", { scope: err.scope });
      return err.scope === "account" ? tooLarge() : reply.code(507).send({ error: "memory_copy_server_full" });
    }
    if (outcome === "off") return reply.code(409).send({ error: "memory_copy_off" });
    return { count: body.items.length };
  });
};

/** A snapshot over a memory-copy quota; thrown inside its transaction so the write is rolled back. */
class MemoryCopyQuota extends Error {
  constructor(readonly scope: "account" | "server") { super(`memory_copy_quota_${scope}`); }
}
