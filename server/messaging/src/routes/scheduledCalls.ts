import { randomUUID, timingSafeEqual } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { callApprovalHash } from "../approval.js";
import { principal, requireDevice } from "../auth.js";
import { OUTBOUND_DAILY_LIMIT, OUTBOUND_HOURLY_LIMIT } from "../calls.js";
import { inTransaction } from "../db.js";
import { inQuietHours, isValidTimeZone, QUIET_HOURS_DEFAULT } from "../quietHours.js";
import {
  CALL_REASON_MAX_LENGTH, SCHEDULED_CALL_MAX_DAYS, SCHEDULED_CALLS_PENDING_MAX, sealReason,
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
    const now = Date.now();
    if (at.getTime() < now + 60_000) return reply.code(409).send({ error: "too_soon" });
    if (at.getTime() > now + SCHEDULED_CALL_MAX_DAYS * 86_400_000 + 5 * 60_000) return reply.code(409).send({ error: "too_far" });
    const { accountId } = principal(req);
    const { rows: [who] } = await db.query<{ e164: string | null; consent: boolean }>(
      `SELECT p.e164, s.outbound_consent_at IS NOT NULL AS consent FROM (SELECT $1::uuid AS account_id) a
       LEFT JOIN phone_numbers p ON p.account_id = a.account_id LEFT JOIN call_settings s ON s.account_id = a.account_id`,
      [accountId]);
    if (!who?.e164) return reply.code(409).send({ error: "no_verified_phone" });
    if (!who.consent) return reply.code(409).send({ error: "outbound_not_enabled" });
    // The number, time, reason and quiet-hours choice the card showed; any difference is refused.
    const expected = callApprovalHash(who.e164, body.at, body.reason, body.allowQuietHours);
    if (!timingSafeEqual(expected, Buffer.from(body.approvalHash, "hex"))) {
      return reply.code(409).send({ error: "approval_mismatch" });
    }
    if (!body.allowQuietHours && inQuietHours(at, body.timeZone, deps.quietHours ?? QUIET_HOURS_DEFAULT)) {
      return reply.code(409).send({ error: "quiet_hours" });
    }
    const cipher = deps.cipher;
    try {
      const call = await inTransaction(db, async (c) => {
        await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [accountId]);
        const { rows: [again] } = await c.query<{ id: string; call_at_text: string; state: string; approval_hash: Buffer }>(
          "SELECT id, call_at_text, state, approval_hash FROM scheduled_calls WHERE account_id = $1 AND idempotency_key = $2",
          [accountId, body.idempotencyKey]);
        if (again) {
          // A retry of the same tap: the same call again, never a second one.
          if (!again.approval_hash.equals(expected)) throw new Refused(409, "idempotency_mismatch");
          return { id: again.id, at: again.call_at_text, state: again.state };
        }
        const { rows: [counts] } = await c.query<{ pending: number; day: number; hour: number }>(
          `SELECT count(*) FILTER (WHERE state = 'scheduled')::int AS pending,
                  count(*) FILTER (WHERE state = 'scheduled' AND call_at > $2::timestamptz - interval '1 day' AND call_at <= $2)::int AS day,
                  count(*) FILTER (WHERE state = 'scheduled' AND call_at > $2::timestamptz - interval '1 hour' AND call_at <= $2)::int AS hour
           FROM scheduled_calls WHERE account_id = $1`, [accountId, at]);
        if ((counts?.pending ?? 0) >= SCHEDULED_CALLS_PENDING_MAX) throw new Refused(429, "too_many_scheduled");
        const { rows: [made] } = await c.query<{ day: number; hour: number }>(
          `SELECT count(*)::int AS day, count(*) FILTER (WHERE created_at > $2::timestamptz - interval '1 hour')::int AS hour
           FROM calls WHERE account_id = $1 AND direction = 'outbound'
           AND created_at > $2::timestamptz - interval '1 day' AND created_at <= $2`, [accountId, at]);
        // The caps are checked now, for the calls already made or booked before this one, and
        // again when the call is due.
        if ((counts?.day ?? 0) + (made?.day ?? 0) >= OUTBOUND_DAILY_LIMIT) throw new Refused(429, "daily_limit");
        if ((counts?.hour ?? 0) + (made?.hour ?? 0) >= OUTBOUND_HOURLY_LIMIT) throw new Refused(429, "hourly_limit");
        const id = randomUUID();
        await c.query(
          `INSERT INTO scheduled_calls (id, account_id, call_at, call_at_text, reason_ciphertext, reason_key_version, time_zone,
             allow_quiet_hours, language, approval_hash, idempotency_key, state)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'scheduled')`,
          [id, accountId, at, body.at, sealReason(cipher, accountId, id, body.reason), cipher.keyVersion, body.timeZone,
            body.allowQuietHours, body.language, expected, body.idempotencyKey]);
        // Where the user is now, for quiet hours when the call is due.
        await c.query(
          `INSERT INTO call_settings (account_id, time_zone) VALUES ($1, $2)
           ON CONFLICT (account_id) DO UPDATE SET time_zone = $2, updated_at = now()`, [accountId, body.timeZone]);
        return { id, at: body.at, state: "scheduled" };
      });
      return reply.code(202).send(call);
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
