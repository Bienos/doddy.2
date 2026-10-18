import { timingSafeEqual } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { textApprovalHash } from "../approval.js";
import { principal, requireDevice } from "../auth.js";
import { sha256 } from "../crypto.js";
import { inTransaction } from "../db.js";
import { enqueue, IdempotencyConflict, smsNumber } from "../outbox.js";

// Texts the user approved on a card (ADR-490, unit U2), from Doddy's number to their own verified
// number and nobody else. The card showed the exact text; the app hashed the number and that text
// when the user tapped Send. The server checks the same hash with the number it holds, and the
// worker checks it once more right before sending, so an approval covers exactly one text.

/** Mirrored in docs/trust/config/doddy_rules.yaml (contact_policy); a test keeps them equal. */
export const APPROVED_TEXTS_PER_DAY = 20;
export const APPROVED_TEXTS_SERVER_PER_DAY = 300;
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

class DailyLimit extends Error {
  constructor(readonly scope: "account" | "server") { super("daily_limit"); }
}

export const textRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);

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
    const expected = textApprovalHash(to, body.body);
    if (!timingSafeEqual(expected, Buffer.from(body.approvalHash, "hex"))) {
      // The number or the text isn't what the card showed: nothing is queued.
      return reply.code(409).send({ error: "approval_mismatch" });
    }
    try {
      const messages = await inTransaction(db, async (c) => {
        // One at a time across the server, so parallel taps can't pass a limit together.
        await c.query("SELECT pg_advisory_xact_lock(hashtext('approved_texts'))");
        const { rows: [again] } = await c.query<{ id: string; channel: "sms"; state: string; payload_hash: Buffer | null }>(
          `SELECT id, channel, state, payload_hash FROM outbound_messages
           WHERE account_id = $1 AND channel = 'sms' AND idempotency_key = $2`, [accountId, body.idempotencyKey]);
        if (again) {
          // A retry of the same tap: the same text again, never a second one.
          // enqueue binds the key to sha256 of the fingerprint, which here is the approval hash.
          if (!again.payload_hash?.equals(sha256(expected.toString("hex")))) throw new IdempotencyConflict();
          return [{ id: again.id, channel: again.channel, state: again.state }];
        }
        const { rows: [counts] } = await c.query<{ mine: number; all: number }>(
          `SELECT count(*) FILTER (WHERE account_id = $1)::int AS mine, count(*)::int AS all FROM outbound_messages
           WHERE approved_text AND created_at > now() - interval '1 day'`, [accountId]);
        if ((counts?.mine ?? 0) >= APPROVED_TEXTS_PER_DAY) throw new DailyLimit("account");
        if ((counts?.all ?? 0) >= APPROVED_TEXTS_SERVER_PER_DAY) throw new DailyLimit("server");
        return enqueue(c, accountId, ["sms"], body.body, new Date(), body.idempotencyKey, {
          fingerprint: expected.toString("hex"), cipher: deps.cipher, approvalHash: expected,
        });
      });
      return reply.code(202).send({ messages });
    } catch (err) {
      if (err instanceof IdempotencyConflict) return reply.code(409).send({ error: "idempotency_mismatch" });
      if (err instanceof DailyLimit) {
        return reply.code(429).send({ error: err.scope === "account" ? "daily_limit" : "server_daily_limit" });
      }
      throw err;
    }
  });
};
