import { timingSafeEqual } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { textApprovalHash } from "../approval.js";
import { principal, requireDevice } from "../auth.js";
import { abuseLimits } from "../config.js";
import { sha256 } from "../crypto.js";
import { inTransaction } from "../db.js";
import { enqueue, IdempotencyConflict, smsNumber, SmsDailyLimit } from "../outbox.js";
import { isAllowedNumber } from "../phoneCountries.js";
import { CONTACT_NUMBER, CONTACT_TEXTS_PER_DAY, contactOptedOut } from "../contactTexts.js";

// Texts the user approved on a card (ADR-750, unit U2), from Doddy's number to their own verified
// number and nobody else. The card showed the exact text; the app hashed the number and that text
// when the user tapped Send. The server checks the same hash with the number it holds, and the
// worker checks it once more right before sending, so an approval covers exactly one text.
// The daily caps and the allowed countries are the default branch's abuse limits (ADR-704, config.ts
// DEFAULT_ABUSE_LIMITS), applied by enqueue and checked again by the worker; this route adds no caps of its own.

/** UTF-16 code units, as JavaScript and Swift's `utf16.count` both count them. */
export const TEXT_MAX_LENGTH = 640;

const textBody = z.object({
  // Exactly what the card showed: never trimmed or normalised here.
  body: z.string().min(1).max(TEXT_MAX_LENGTH)
    // A lone surrogate (\p{Cs}) can't be hashed the same way on the iPhone, so it isn't text.
    .refine((s) => s.trim().length > 0 && !/\p{Cs}/u.test(s), "empty or not valid text"),
  approvalHash: z.string().regex(/^[0-9a-f]{64}$/),
  idempotencyKey: z.string().min(1).max(128),
});

// A text to one of the user's contacts (decision 2026-11-09-texts-to-contacts): the contact's number too. The app read
// it from the contact card; the approval hash binds that number and the exact text.
const contactTextBody = textBody.extend({ to: z.string().regex(CONTACT_NUMBER) });

export const textRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const limits = abuseLimits(deps.limits);

  app.post("/v1/texts", { preHandler: auth, config: { rateLimit: { max: 30, timeWindow: "1 hour" } } }, async (req, reply) => {
    // The card tells the user the text is kept encrypted until it is sent, so without the key
    // nothing is stored at all.
    if (!deps.sms || !deps.cipher) return reply.code(503).send({ error: "sms_not_configured" });
    const body = parse(textBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    // Verified, consented, no STOP since: the only number a text may go to.
    const to = await smsNumber(db, accountId);
    if (!to) return reply.code(409).send({ error: "sms_not_enabled" });
    // A number verified before the country list existed (or before it changed) is not texted either (ADR-704).
    if (!isAllowedNumber(to, limits.allowedCountryCodes)) return reply.code(409).send({ error: "phone_not_allowed" });
    const expected = textApprovalHash(to, body.body);
    if (!timingSafeEqual(expected, Buffer.from(body.approvalHash, "hex"))) {
      // The number or the text isn't what the card showed: nothing is queued.
      return reply.code(409).send({ error: "approval_mismatch" });
    }
    try {
      const messages = await inTransaction(db, async (c) => {
        const { rows: [again] } = await c.query<{ id: string; channel: "sms"; state: string; payload_hash: Buffer | null }>(
          `SELECT id, channel, state, payload_hash FROM outbound_messages
           WHERE account_id = $1 AND channel = 'sms' AND idempotency_key = $2`, [accountId, body.idempotencyKey]);
        if (again) {
          // A retry of the same tap: the same text again, never a second one.
          // enqueue binds the key to sha256 of the fingerprint, which here is the approval hash.
          if (!again.payload_hash?.equals(sha256(expected.toString("hex")))) throw new IdempotencyConflict();
          return [{ id: again.id, channel: again.channel, state: again.state }];
        }
        return enqueue(c, accountId, ["sms"], body.body, new Date(), body.idempotencyKey, {
          fingerprint: expected.toString("hex"), cipher: deps.cipher, approvalHash: expected,
          // The account's and the server's texts per UTC day, taken atomically with the row (ADR-704).
          smsCaps: { perAccount: limits.smsPerAccountDay, perServer: limits.smsPerServerDay },
        });
      });
      return reply.code(202).send({ messages });
    } catch (err) {
      if (err instanceof IdempotencyConflict) return reply.code(409).send({ error: "idempotency_mismatch" });
      if (err instanceof SmsDailyLimit) {
        return reply.code(429).send({ error: err.scope === "account" ? "daily_limit" : "server_daily_limit" });
      }
      throw err;
    }
  });
  app.post("/v1/texts/contact", { preHandler: auth, config: { rateLimit: { max: 60, timeWindow: "1 hour" } } }, async (req, reply) => {
    if (!deps.contactTexts) return reply.code(503).send({ error: "contact_texts_off" });
    if (!deps.sms || !deps.cipher) return reply.code(503).send({ error: "sms_not_configured" });
    const body = parse(contactTextBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    // Only an account with a verified number of its own texts other people: a real phone behind every sender.
    const own = await db.query("SELECT 1 FROM phone_numbers WHERE account_id = $1", [accountId]);
    if (!own.rowCount) return reply.code(409).send({ error: "phone_not_verified" });
    // Never Doddy's own number (a text to itself would come back as an inbound text).
    if (body.to === deps.doddyPhoneNumber) return reply.code(409).send({ error: "phone_not_allowed" });
    if (!isAllowedNumber(body.to, limits.allowedCountryCodes)) return reply.code(409).send({ error: "phone_not_allowed" });
    if (await contactOptedOut(db, deps.cipher, body.to)) return reply.code(409).send({ error: "contact_opted_out" });
    const expected = textApprovalHash(body.to, body.body);
    if (!timingSafeEqual(expected, Buffer.from(body.approvalHash, "hex"))) {
      // The number or the text isn't what the card showed: nothing is queued.
      return reply.code(409).send({ error: "approval_mismatch" });
    }
    try {
      const messages = await inTransaction(db, async (c) => {
        const { rows: [again] } = await c.query<{ id: string; channel: "sms"; state: string; payload_hash: Buffer | null }>(
          `SELECT id, channel, state, payload_hash FROM outbound_messages
           WHERE account_id = $1 AND channel = 'sms' AND idempotency_key = $2`, [accountId, body.idempotencyKey]);
        if (again) {
          // A retry of the same tap: the same text to the same number, never a second one.
          if (!again.payload_hash?.equals(sha256(expected.toString("hex")))) throw new IdempotencyConflict();
          return [{ id: again.id, channel: again.channel, state: again.state }];
        }
        return enqueue(c, accountId, ["sms"], body.body, new Date(), body.idempotencyKey, {
          fingerprint: expected.toString("hex"), cipher: deps.cipher, approvalHash: expected, to: body.to,
          contactTextsPerDay: CONTACT_TEXTS_PER_DAY,
          smsCaps: { perAccount: limits.smsPerAccountDay, perServer: limits.smsPerServerDay },
        });
      });
      return reply.code(202).send({ messages });
    } catch (err) {
      if (err instanceof IdempotencyConflict) return reply.code(409).send({ error: "idempotency_mismatch" });
      if (err instanceof SmsDailyLimit) {
        return reply.code(429).send({ error: err.scope === "account" ? "daily_limit" : "server_daily_limit" });
      }
      throw err;
    }
  });
};
