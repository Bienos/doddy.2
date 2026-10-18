import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { inTransaction } from "../db.js";
import { enqueue, ERASE, IdempotencyConflict, usableChannels, type Channel } from "../outbox.js";

const MAX_DAYS_AHEAD = 30;

const updateBody = z.object({
  // 640 chars ≈ 4 GSM SMS segments; enough for an update, small enough to keep cost visible.
  text: z.string().trim().min(1).max(640),
  channels: z.array(z.enum(["push", "sms"])).min(1).max(2).refine((c) => new Set(c).size === c.length),
  sendAt: z.iso.datetime({ offset: true }).optional(),
  idempotencyKey: z.string().min(1).max(128),
});
const idParam = z.object({ id: z.uuid() });

export const updateRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);

  app.post("/v1/updates", { preHandler: auth, config: { rateLimit: { max: 60, timeWindow: "1 hour" } } }, async (req, reply) => {
    const body = parse(updateBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    const sendAt = body.sendAt ? new Date(body.sendAt) : new Date();
    if (sendAt.getTime() > Date.now() + MAX_DAYS_AHEAD * 86_400_000) {
      return reply.code(400).send({ error: "invalid_request", fields: ["sendAt"] });
    }
    const channels = body.channels as Channel[];
    for (const ch of channels) {
      if (!deps[ch]) return reply.code(503).send({ error: `${ch}_not_configured` });
    }
    const usable = await usableChannels(db, accountId, channels);
    const missing = channels.find((ch) => !usable.includes(ch));
    if (missing) return reply.code(409).send({ error: `${missing}_not_enabled` });
    try {
      // One transaction: a conflict on the second channel must not leave the first one queued.
      // The key is bound to the text and, when given, the requested time (a retry without
      // sendAt is still the same request).
      const messages = await inTransaction(db, (c) =>
        enqueue(c, accountId, channels, body.text, sendAt, body.idempotencyKey, {
          fingerprint: JSON.stringify([body.text, body.sendAt ?? null]), cipher: deps.cipher,
        }));
      return reply.code(202).send({ messages });
    } catch (err) {
      if (err instanceof IdempotencyConflict) return reply.code(409).send({ error: "idempotency_mismatch" });
      throw err;
    }
  });

  app.get("/v1/updates/:id", { preHandler: auth }, async (req, reply) => {
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    // Scoped by account: another account's id is indistinguishable from a missing one.
    const { rows } = await db.query(
      `SELECT id, channel, state, send_at AS "sendAt", delivery_status AS "deliveryStatus", error_code AS "errorCode",
         lookup FROM outbound_messages WHERE id = $1 AND account_id = $2`,
      [p.id, principal(req).accountId]);
    if (!rows[0]) return reply.code(404).send({ error: "not_found" });
    return rows[0];
  });

  app.delete("/v1/updates/:id", { preHandler: auth }, async (req, reply) => {
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    const r = await db.query(
      // ERASE clears the encrypted text too (before U2 only the plain one was cleared, which an
      // encrypted queued message refused).
      `UPDATE outbound_messages SET state = 'cancelled', error_code = 'cancelled_by_user', ${ERASE}, updated_at = now()
       WHERE id = $1 AND account_id = $2 AND state = 'queued'`,
      [p.id, principal(req).accountId]);
    if (r.rowCount) return reply.code(204).send();
    const exists = await db.query("SELECT 1 FROM outbound_messages WHERE id = $1 AND account_id = $2",
      [p.id, principal(req).accountId]);
    return exists.rowCount
      ? reply.code(409).send({ error: "already_sending_or_done" })
      : reply.code(404).send({ error: "not_found" });
  });
};
