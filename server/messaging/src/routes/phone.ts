import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { sha256 } from "../crypto.js";
import { inTransaction } from "../db.js";
import { cancelQueuedSms } from "../outbox.js";
import { textsOff } from "../textReplies.js";
import { cancelScheduledCalls } from "../scheduledCalls.js";
import { ProviderError } from "../providers/types.js";

/** Verify codes one phone number may receive, across all accounts. */
const VERIFY_PER_NUMBER_HOUR = 3;
const VERIFY_PER_NUMBER_DAY = 6;

const e164 = z.string().regex(/^\+[1-9][0-9]{6,14}$/);
const startBody = z.object({ phone: e164 });
const checkBody = z.object({ phone: e164, code: z.string().regex(/^[0-9]{4,10}$/) });
const consentBody = z.object({ consent: z.boolean(), textVersion: z.string().min(1).max(64).optional() })
  .refine((b) => !b.consent || b.textVersion !== undefined, { path: ["textVersion"] });

function providerFailure(err: unknown, reply: FastifyReply) {
  if (!(err instanceof ProviderError)) throw err;
  if (err.status === 429) return reply.code(429).send({ error: "too_many_attempts" });
  if (err.status === 400) return reply.code(400).send({ error: "phone_rejected" });
  return reply.code(502).send({ error: "provider_unavailable" });
}

export const phoneRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db, verifier } = deps;
  const auth = requireDevice(db);
  const limited = { max: 5, timeWindow: "1 hour" };

  app.post("/v1/phone/verification", { preHandler: auth, config: { rateLimit: limited } }, async (req, reply) => {
    if (!verifier) return reply.code(503).send({ error: "not_configured" });
    const body = parse(startBody, req.body, reply);
    if (!body) return;
    // Per destination number and per server, whatever account asks: new accounts can't be used
    // to text one number over and over, and a flood can't run up the SMS bill (ADR-175).
    const phoneHash = sha256(body.phone);
    const allowed = await inTransaction(db, async (c) => {
      // The caps include a server-wide one, so count and insert under one lock.
      await c.query("SELECT pg_advisory_xact_lock(4242002)");
      const { rows: [counts] } = await c.query<{ hour: number; day: number; server: number }>(
        `SELECT count(*) FILTER (WHERE phone_hash = $1 AND started_at > now() - interval '1 hour')::int AS hour,
                count(*) FILTER (WHERE phone_hash = $1 AND started_at > now() - interval '1 day')::int AS day,
                count(*) FILTER (WHERE started_at > date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')::int AS server
         FROM phone_verification_starts WHERE started_at > now() - interval '1 day'`, [phoneHash]);
      if (counts!.hour >= VERIFY_PER_NUMBER_HOUR || counts!.day >= VERIFY_PER_NUMBER_DAY || counts!.server >= (deps.verifyDailyCap ?? 200)) {
        return false;
      }
      await c.query("INSERT INTO phone_verification_starts (phone_hash) VALUES ($1)", [phoneHash]);
      await c.query("DELETE FROM phone_verification_starts WHERE started_at < now() - interval '2 days'");
      return true;
    });
    if (!allowed) return reply.code(429).send({ error: "too_many_attempts" });
    try {
      await verifier.start(body.phone);
    } catch (err) {
      return providerFailure(err, reply);
    }
    return reply.code(202).send({ status: "code_sent" });
  });

  app.post("/v1/phone/verification/check", { preHandler: auth, config: { rateLimit: { max: 10, timeWindow: "1 hour" } } }, async (req, reply) => {
    if (!verifier) return reply.code(503).send({ error: "not_configured" });
    const body = parse(checkBody, req.body, reply);
    if (!body) return;
    let result;
    try {
      result = await verifier.check(body.phone, body.code);
    } catch (err) {
      return providerFailure(err, reply);
    }
    if (result === "wrong_code") return reply.code(400).send({ error: "wrong_code" });
    if (result === "expired_or_missing") return reply.code(400).send({ error: "code_expired" });

    const { accountId } = principal(req);
    await inTransaction(db, async (c) => {
      // Proving ownership moves the number from any older account (e.g. after a reinstall).
      const moved = await c.query<{ account_id: string }>(
        "DELETE FROM phone_numbers WHERE e164 = $1 AND account_id <> $2 RETURNING account_id", [body.phone, accountId]);
      for (const row of moved.rows) {
        await cancelQueuedSms(c, row.account_id);
        await textsOff(c, row.account_id);
        await cancelScheduledCalls(c, row.account_id, "number_changed");
      }
      const previous = await c.query<{ e164: string }>(
        "SELECT e164 FROM phone_numbers WHERE account_id = $1 FOR UPDATE", [accountId]);
      // Texts queued for an older number must not go to the new one.
      if (previous.rows[0] && previous.rows[0].e164 !== body.phone) {
        await cancelQueuedSms(c, accountId);
        // A new number needs new consent for texts to Doddy (ADR-494).
        await textsOff(c, accountId);
        // Calls booked for the old number were approved for it only (ADR-495).
        await cancelScheduledCalls(c, accountId, "number_changed");
      }
      // A different number starts without SMS consent; the same number keeps its state.
      await c.query(
        `INSERT INTO phone_numbers (account_id, e164, verified_at) VALUES ($1, $2, now())
         ON CONFLICT (account_id) DO UPDATE SET
           verified_at = now(), updated_at = now(),
           sms_consent_at = CASE WHEN phone_numbers.e164 = EXCLUDED.e164 THEN phone_numbers.sms_consent_at END,
           sms_consent_text_version = CASE WHEN phone_numbers.e164 = EXCLUDED.e164 THEN phone_numbers.sms_consent_text_version END,
           sms_opted_out_at = CASE WHEN phone_numbers.e164 = EXCLUDED.e164 THEN phone_numbers.sms_opted_out_at END,
           e164 = EXCLUDED.e164`,
        [accountId, body.phone]);
    });
    return { verified: true };
  });

  app.get("/v1/phone", { preHandler: auth }, async (req) => {
    const { rows } = await db.query<{ e164: string; sms_consent_at: Date | null; sms_opted_out_at: Date | null }>(
      "SELECT e164, sms_consent_at, sms_opted_out_at FROM phone_numbers WHERE account_id = $1", [principal(req).accountId]);
    const p = rows[0];
    if (!p) return { phone: null, smsEnabled: false, optedOut: false };
    return {
      phone: p.e164,
      smsEnabled: p.sms_consent_at !== null && p.sms_opted_out_at === null,
      // After a STOP the carrier blocks us until the user texts START.
      optedOut: p.sms_opted_out_at !== null,
    };
  });

  app.put("/v1/phone/sms-consent", { preHandler: auth }, async (req, reply) => {
    const body = parse(consentBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    const r = await inTransaction(db, async (c) => {
      const u = await c.query(
        `UPDATE phone_numbers SET updated_at = now(),
           sms_consent_at = CASE WHEN $2 THEN now() END,
           sms_consent_text_version = CASE WHEN $2 THEN $3 END
         WHERE account_id = $1`,
        [accountId, body.consent, body.textVersion ?? null]);
      if (!body.consent) await cancelQueuedSms(c, accountId);
      return u.rowCount ?? 0;
    });
    if (r === 0) return reply.code(404).send({ error: "no_verified_phone" });
    return reply.code(204).send();
  });

  app.delete("/v1/phone", { preHandler: auth }, async (req, reply) => {
    const { accountId } = principal(req);
    await inTransaction(db, async (c) => {
      await cancelQueuedSms(c, accountId);
      await textsOff(c, accountId);
      await cancelScheduledCalls(c, accountId, "number_changed");
      await c.query("DELETE FROM phone_numbers WHERE account_id = $1", [accountId]);
    });
    return reply.code(204).send();
  });
};
