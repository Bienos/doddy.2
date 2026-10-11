import { randomUUID } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import type pg from "pg";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { OUTBOUND_CONSENT_VERSIONS, OUTBOUND_DAILY_LIMIT, openSession } from "../calls.js";
import { hashPin, isAcceptablePin } from "../crypto.js";
import { inTransaction } from "../db.js";

const settingsBody = z.object({
  inboundEnabled: z.boolean().optional(),
  outboundConsent: z.boolean().optional(),
  outboundConsentTextVersion: z.string().max(32).optional(),
}).refine((b) => b.outboundConsent !== true || OUTBOUND_CONSENT_VERSIONS.has(b.outboundConsentTextVersion ?? ""),
  { path: ["outboundConsentTextVersion"] });
const pinBody = z.object({ pin: z.string() });
const snapshotBody = z.object({
  items: z.array(z.object({
    // Postgres returns uuids in lowercase; the encryption binding must use the same spelling
    // (iOS sends uppercase).
    id: z.uuid().transform((id) => id.toLowerCase()),
    text: z.string().min(1).max(5000),
    capturedAt: z.iso.datetime({ offset: true }).nullable().optional(),
  })).max(5000),
}).refine((b) => new Set(b.items.map((i) => i.id)).size === b.items.length, "duplicate ids");
const idParam = z.object({ id: z.uuid() });

/** A changed or removed PIN also ends the access that calls in progress got with the old one. */
const forgetPinOnCalls = (c: pg.PoolClient, accountId: string) =>
  c.query("UPDATE call_sessions SET pin_verified_at = NULL WHERE account_id = $1", [accountId]);

export const callRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const ensureRow = (accountId: string) =>
    db.query("INSERT INTO call_settings (account_id) VALUES ($1) ON CONFLICT DO NOTHING", [accountId]);

  app.get("/v1/calls/settings", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const { rows } = await db.query<{
      inbound_enabled: boolean; pin_set: boolean; pin_locked: boolean; outbound: boolean; memory_on: boolean;
    }>(
      `SELECT inbound_enabled, pin_hash IS NOT NULL AS pin_set, coalesce(pin_locked_until > now(), false) AS pin_locked,
              outbound_consent_at IS NOT NULL AS outbound, memory_copy_enabled_at IS NOT NULL AS memory_on
       FROM call_settings WHERE account_id = $1`, [accountId]);
    const s = rows[0];
    const count = await db.query<{ n: number }>("SELECT count(*)::int AS n FROM memory_copies WHERE account_id = $1", [accountId]);
    const phone = await db.query("SELECT 1 FROM phone_numbers WHERE account_id = $1", [accountId]);
    return {
      // What the server can actually do; the app shows "needs setup" otherwise.
      available: { inbound: !!(deps.toolSecret && deps.cipher), outbound: !!(deps.outbound && deps.toolSecret && deps.cipher) },
      doddyNumber: deps.doddyPhoneNumber ?? null,
      phoneVerified: (phone.rowCount ?? 0) > 0,
      inboundEnabled: s?.inbound_enabled ?? false,
      pinSet: s?.pin_set ?? false,
      pinLocked: s?.pin_locked ?? false,
      outboundConsent: s?.outbound ?? false,
      memoryCopy: { enabled: s?.memory_on ?? false, count: count.rows[0]?.n ?? 0 },
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
    await db.query(
      `UPDATE call_settings SET updated_at = now(),
         inbound_enabled = coalesce($2, inbound_enabled),
         outbound_consent_at = CASE WHEN $3::boolean IS NULL THEN outbound_consent_at WHEN $3 THEN now() END,
         outbound_consent_text_version = CASE WHEN $3::boolean IS NULL THEN outbound_consent_text_version WHEN $3 THEN $4 END
       WHERE account_id = $1`,
      [accountId, body.inboundEnabled ?? null, body.outboundConsent ?? null, body.outboundConsentTextVersion ?? null]);
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

  // "Call me now". Doddy only calls the verified number, only after explicit consent.
  app.post("/v1/calls/outbound", { preHandler: auth, config: { rateLimit: { max: 3, timeWindow: "1 hour" } } }, async (req, reply) => {
    if (!deps.outbound || !deps.toolSecret || !deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    const { rows } = await db.query<{ e164: string; consent: boolean }>(
      `SELECT p.e164, s.outbound_consent_at IS NOT NULL AS consent FROM phone_numbers p
       LEFT JOIN call_settings s ON s.account_id = p.account_id WHERE p.account_id = $1`, [accountId]);
    const target = rows[0];
    if (!target) return reply.code(409).send({ error: "no_verified_phone" });
    if (!target.consent) return reply.code(409).send({ error: "outbound_not_enabled" });
    const callId = randomUUID();
    const underLimit = await inTransaction(db, async (c) => {
      // Count and insert under one per-account lock, so parallel taps can't pass the limit together.
      await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [accountId]);
      const today = await c.query<{ n: number }>(
        `SELECT count(*)::int AS n FROM calls WHERE account_id = $1 AND direction = 'outbound'
         AND created_at > now() - interval '1 day'`, [accountId]);
      if ((today.rows[0]?.n ?? 0) >= OUTBOUND_DAILY_LIMIT) return false;
      await c.query(
        "INSERT INTO calls (id, account_id, direction, status) VALUES ($1, $2, 'outbound', 'requested')", [callId, accountId]);
      return true;
    });
    if (!underLimit) return reply.code(429).send({ error: "daily_limit" });
    const variables = await openSession(db, accountId, callId, "outbound");
    const outcome = await deps.outbound.placeCall(target.e164, { ...variables });
    const status = outcome.kind === "accepted" ? "requested" : outcome.kind === "unknown" ? "unknown" : "failed";
    await db.query(
      "UPDATE calls SET status = $2, conversation_id = $3, call_sid = $4, error_code = $5 WHERE id = $1",
      [callId, status,
        outcome.kind === "accepted" ? outcome.conversationId ?? null : null,
        outcome.kind === "accepted" ? outcome.callSid ?? null : null,
        outcome.kind === "accepted" ? null : outcome.code]);
    if (status === "failed") return reply.code(502).send({ error: "provider_unavailable", callId });
    return reply.code(202).send({ callId, status });
  });

  app.get("/v1/calls", { preHandler: auth }, async (req) => {
    const { rows } = await db.query(
      `SELECT id, direction, status, created_at AS "createdAt" FROM calls
       WHERE account_id = $1 ORDER BY created_at DESC LIMIT 20`, [principal(req).accountId]);
    return { calls: rows };
  });

  // Notes from calls wait here until the user confirms (saves locally) or discards them.
  app.get("/v1/call-notes", { preHandler: auth }, async (req, reply) => {
    if (!deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    const { rows } = await db.query<{ id: string; ciphertext: Buffer; created_at: Date }>(
      "SELECT id, ciphertext, created_at FROM call_notes WHERE account_id = $1 ORDER BY created_at", [accountId]);
    const cipher = deps.cipher;
    // A note that won't decrypt (e.g. after a key change) must not hide the others; it is listed
    // separately (older apps ignore the field) so it can still be discarded.
    const notes: { id: string; text: string; createdAt: Date }[] = [];
    const unreadable: { id: string; createdAt: Date }[] = [];
    for (const r of rows) {
      try {
        notes.push({ id: r.id, text: cipher.decrypt(r.ciphertext, `${accountId}:note:${r.id}`), createdAt: r.created_at });
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
  app.put("/v1/memory-copy", { preHandler: auth }, async (req, reply) => {
    if (!deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const body = parse(z.object({ enabled: z.boolean() }), req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    await ensureRow(accountId);
    await inTransaction(db, async (c) => {
      if (!body.enabled) await c.query("DELETE FROM memory_copies WHERE account_id = $1", [accountId]);
      await c.query(
        `UPDATE call_settings SET updated_at = now(),
           memory_copy_enabled_at = CASE WHEN $2 THEN coalesce(memory_copy_enabled_at, now()) END
         WHERE account_id = $1`, [accountId, body.enabled]);
    });
    return reply.code(204).send();
  });

  // Replaces the whole copy with what the phone holds now (deletions included).
  // The app sends one snapshot per burst of edits; 60 an hour is plenty and caps the encrypt work.
  app.put("/v1/memory-copy/snapshot", {
    preHandler: auth, bodyLimit: 8 * 1024 * 1024, config: { rateLimit: { max: 60, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    if (!deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const body = parse(snapshotBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    const cipher = deps.cipher;
    const done = await inTransaction(db, async (c) => {
      const { rows } = await c.query<{ on: boolean }>(
        "SELECT memory_copy_enabled_at IS NOT NULL AS on FROM call_settings WHERE account_id = $1 FOR UPDATE", [accountId]);
      if (!rows[0]?.on) return false;
      await c.query("DELETE FROM memory_copies WHERE account_id = $1", [accountId]);
      if (body.items.length) {
        await c.query(
          `INSERT INTO memory_copies (account_id, memory_id, key_version, ciphertext, captured_at)
           SELECT $1, * FROM unnest($2::uuid[], $3::smallint[], $4::bytea[], $5::timestamptz[])`,
          [accountId,
            body.items.map((i) => i.id),
            body.items.map(() => cipher.keyVersion),
            body.items.map((i) => cipher.encrypt(i.text, `${accountId}:memory:${i.id}`)),
            body.items.map((i) => i.capturedAt ?? null)]);
      }
      return true;
    });
    if (!done) return reply.code(409).send({ error: "memory_copy_off" });
    return { count: body.items.length };
  });
};
