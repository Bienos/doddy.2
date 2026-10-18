import { randomUUID, timingSafeEqual } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { callApprovalHash } from "../approval.js";
import { principal, requireDevice } from "../auth.js";
import { OUTBOUND_DAILY_LIMIT, OUTBOUND_HOURLY_LIMIT } from "../calls.js";
import { inTransaction, type Db } from "../db.js";
import { inQuietHours, isValidTimeZone, QUIET_HOURS_DEFAULT } from "../quietHours.js";
import {
  CALL_REASON_MAX_LENGTH, capExceeded, SCHEDULED_CALL_MAX_DAYS, SCHEDULED_CALLS_PENDING_MAX, sealReason,
} from "../scheduledCalls.js";
import { callsAvailable } from "./twilioVoice.js";

// "Call me later" (ADR-490 unit U4, ADR-495): a call approved on a card with its time, the exact
// reason Doddy will say, and whether it may ring inside quiet hours. The worker places it
// (scheduledCalls.ts placeDueCall), after checking it all again.

const scheduleBody = z.object({
  // Exactly as the app hashed it.
  at: z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/),
  // Exactly what the card showed: never trimmed or rewritten.
  // One line, no lone surrogates, and no {{ or }}: the reason is handed to the phone agent as a
  // variable inside its instructions.
  reason: z.string().min(1).max(CALL_REASON_MAX_LENGTH)
    .refine((s) => s.trim().length > 0 && !/\p{Cs}/u.test(s) && !/\{\{|\}\}/.test(s) && !/[\r\n]/.test(s),
      "empty or not valid text"),
  timeZone: z.string().refine(isValidTimeZone, "unknown time zone"),
  allowQuietHours: z.boolean(),
  language: z.enum(["en", "pl"]).default("en"),
  approvalHash: z.string().regex(/^[0-9a-f]{64}$/),
  idempotencyKey: z.string().min(1).max(128),
});
const idParam = z.object({ id: z.uuid() });

type Queryable = { query: Db["query"] };

/** The verified number and whether calls from Doddy are on. */
async function caller(db: Queryable, accountId: string): Promise<{ e164: string | null; consent: boolean }> {
  const { rows: [who] } = await db.query<{ e164: string | null; consent: boolean }>(
    `SELECT p.e164, s.outbound_consent_at IS NOT NULL AS consent FROM (SELECT $1::uuid AS account_id) a
     LEFT JOIN phone_numbers p ON p.account_id = a.account_id LEFT JOIN call_settings s ON s.account_id = a.account_id`,
    [accountId]);
  return { e164: who?.e164 ?? null, consent: who?.consent ?? false };
}

/**
 * The answer to a repeat of an earlier request (the same idempotency key), or undefined for a new
 * one. A call still waiting or being placed is the same call again; one that is over is not
 * "booked" any more, so the repeat says so instead of repeating 202.
 */
async function repeatOf(db: Queryable, accountId: string, key: string, expected: Buffer):
    Promise<{ status: number; body: object } | undefined> {
  const { rows: [again] } = await db.query<{ id: string; call_at_text: string; state: string; approval_hash: Buffer }>(
    "SELECT id, call_at_text, state, approval_hash FROM scheduled_calls WHERE account_id = $1 AND idempotency_key = $2",
    [accountId, key]);
  if (!again) return undefined;
  if (!again.approval_hash.equals(expected)) return { status: 409, body: { error: "idempotency_mismatch" } };
  if (again.state !== "scheduled" && again.state !== "placing") {
    return { status: 409, body: { error: "already_done", id: again.id, state: again.state } };
  }
  return { status: 202, body: { id: again.id, at: again.call_at_text, state: again.state } };
}

class Refused extends Error {
  constructor(readonly status: number, readonly code: string) { super(code); }
}

export const scheduledCallRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);

  // 30 requests an hour, as for texts; the caps on calls themselves are checked below.
  app.post("/v1/calls/scheduled", { preHandler: auth, config: { rateLimit: { max: 30, timeWindow: "1 hour" } } }, async (req, reply) => {
    if (!callsAvailable(deps).outbound || !deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const body = parse(scheduleBody, req.body, reply);
    if (!body) return;
    const at = new Date(body.at);
    if (Number.isNaN(at.getTime())) return reply.code(400).send({ error: "invalid_request", fields: ["at"] });
    const { accountId } = principal(req);
    const who = await caller(db, accountId);
    if (!who.e164) return reply.code(409).send({ error: "no_verified_phone" });
    if (!who.consent) return reply.code(409).send({ error: "outbound_not_enabled" });
    // The number, time, reason and quiet-hours choice the card showed; any difference is refused.
    const expected = callApprovalHash(who.e164, body.at, body.reason, body.allowQuietHours);
    if (!timingSafeEqual(expected, Buffer.from(body.approvalHash, "hex"))) {
      return reply.code(409).send({ error: "approval_mismatch" });
    }
    // A repeat of the same tap is answered before anything else, so a try-again after an unclear
    // answer hears what happened to the first, not a refusal that would read as "not booked".
    const earlier = await repeatOf(db, accountId, body.idempotencyKey, expected);
    if (earlier) return reply.code(earlier.status).send(earlier.body);
    const now = Date.now();
    if (at.getTime() < now + 60_000) return reply.code(409).send({ error: "too_soon" });
    if (at.getTime() > now + SCHEDULED_CALL_MAX_DAYS * 86_400_000 + 5 * 60_000) return reply.code(409).send({ error: "too_far" });
    if (!body.allowQuietHours && inQuietHours(at, body.timeZone, deps.quietHours ?? QUIET_HOURS_DEFAULT)) {
      return reply.code(409).send({ error: "quiet_hours" });
    }
    const cipher = deps.cipher;
    // The same call with the other quiet-hours choice, as a second card could approve it.
    const sameCall = [callApprovalHash(who.e164, body.at, body.reason, false), callApprovalHash(who.e164, body.at, body.reason, true)];
    try {
      const call = await inTransaction(db, async (c) => {
        // The same lock as Call me now, turning calls off and changing the number (cancelScheduledCalls).
        await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [accountId]);
        const again = await repeatOf(c, accountId, body.idempotencyKey, expected);
        if (again) return again;
        // Checked again under the lock: consent or the number may have changed since.
        const now = await caller(c, accountId);
        if (!now.consent) throw new Refused(409, "outbound_not_enabled");
        if (now.e164 !== who.e164) throw new Refused(409, "approval_mismatch");
        // The same time and reason already waiting (another card, or after Doddy was reopened):
        // never a second call.
        const { rowCount: duplicate } = await c.query(
          `SELECT 1 FROM scheduled_calls WHERE account_id = $1 AND state IN ('scheduled', 'placing') AND approval_hash = ANY($2::bytea[])`,
          [accountId, sameCall]);
        if (duplicate) throw new Refused(409, "already_booked");
        const { rows: [{ pending } = { pending: 0 }] } = await c.query<{ pending: number }>(
          "SELECT count(*)::int AS pending FROM scheduled_calls WHERE account_id = $1 AND state = 'scheduled'", [accountId]);
        if (pending >= SCHEDULED_CALLS_PENDING_MAX) throw new Refused(429, "too_many_scheduled");
        // Every hour and every day that would hold this call, counting calls already made and
        // calls booked before and after it. Checked again when the call is due.
        const { rows: times } = await c.query<{ t: Date }>(
          `SELECT created_at AS t FROM calls WHERE account_id = $1 AND direction = 'outbound'
             AND created_at > $2::timestamptz - interval '1 day'
           UNION ALL
           SELECT call_at AS t FROM scheduled_calls WHERE account_id = $1 AND state IN ('scheduled', 'placing')
             AND call_at > $2::timestamptz - interval '1 day' AND call_at < $2::timestamptz + interval '1 day'`, [accountId, at]);
        const others = times.map((r) => r.t);
        if (capExceeded(others, at, 86_400_000, OUTBOUND_DAILY_LIMIT)) throw new Refused(429, "daily_limit");
        if (capExceeded(others, at, 3_600_000, OUTBOUND_HOURLY_LIMIT)) throw new Refused(429, "hourly_limit");
        const id = randomUUID();
        await c.query(
          `INSERT INTO scheduled_calls (id, account_id, call_at, call_at_text, reason_ciphertext, reason_key_version, time_zone,
             allow_quiet_hours, language, approval_hash, idempotency_key, state)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'scheduled')`,
          [id, accountId, at, body.at, sealReason(cipher, accountId, id, body.reason), cipher.keyVersion, body.timeZone,
            body.allowQuietHours, body.language, expected, body.idempotencyKey]);
        // The zone the iPhone is in now, for quiet hours when the call is due.
        await c.query(
          `INSERT INTO call_settings (account_id, time_zone) VALUES ($1, $2)
           ON CONFLICT (account_id) DO UPDATE SET time_zone = $2, updated_at = now()`, [accountId, body.timeZone]);
        return { status: 202, body: { id, at: body.at, state: "scheduled" } };
      });
      return reply.code(call.status).send(call.body);
    } catch (err) {
      if (err instanceof Refused) return reply.code(err.status).send({ error: err.code });
      throw err;
    }
  });

  app.get("/v1/calls/scheduled", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const { rows } = await db.query<{
      id: string; at: string; state: string; error_code: string | null; allow_quiet_hours: boolean;
      reason_ciphertext: Buffer | null; created_at: Date;
    }>(
      `SELECT id, call_at_text AS at, state, error_code, allow_quiet_hours, reason_ciphertext, created_at FROM scheduled_calls
       WHERE account_id = $1 ORDER BY call_at DESC LIMIT 20`, [accountId]);
    return {
      calls: rows.map((r) => {
        let reason: string | null = null;
        try {
          reason = r.reason_ciphertext && deps.cipher ? deps.cipher.decrypt(r.reason_ciphertext, `${accountId}:call_reason:${r.id}`) : null;
        } catch { /* unreadable after a key change: shown without its reason */ }
        return { id: r.id, at: r.at, state: r.state, errorCode: r.error_code, allowQuietHours: r.allow_quiet_hours, reason, createdAt: r.created_at };
      }),
    };
  });

  app.delete("/v1/calls/scheduled/:id", { preHandler: auth }, async (req, reply) => {
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    const { accountId } = principal(req);
    const r = await db.query(
      `UPDATE scheduled_calls SET state = 'cancelled', error_code = 'cancelled_by_user', reason_ciphertext = NULL,
         reason_key_version = NULL, updated_at = now() WHERE id = $1 AND account_id = $2 AND state = 'scheduled'`, [p.id, accountId]);
    if (r.rowCount) return reply.code(204).send();
    const exists = await db.query("SELECT 1 FROM scheduled_calls WHERE id = $1 AND account_id = $2", [p.id, accountId]);
    return exists.rowCount ? reply.code(409).send({ error: "already_placed_or_done" }) : reply.code(404).send({ error: "not_found" });
  });
};
