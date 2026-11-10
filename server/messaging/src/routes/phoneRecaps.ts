// What the iPhone reads, saves and deletes of phone-line recaps (decision 2026-11-09-conversation-recaps,
// step 5; the recaps are made by `phoneRecaps.ts` from the post-call webhook).
//   GET    /v1/calls/recaps           whether recaps are on, and the recaps waiting (decrypted for this account)
//   PUT    /v1/calls/recaps/settings  { enabled }: on records the time; off deletes every recap waiting
//   DELETE /v1/calls/recaps/:id       after the iPhone saved the note; :id is the call's id
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { inTransaction } from "../db.js";
import { expirePhoneRecaps, recapAad, type StoredPhoneRecap } from "../phoneRecaps.js";

const idParam = z.object({ id: z.uuid() });
const settingsBody = z.strictObject({ enabled: z.boolean() });

export const phoneRecapRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);

  app.get("/v1/calls/recaps", { preHandler: auth, config: { rateLimit: { max: 120, timeWindow: "1 hour" } } }, async (req, reply) => {
    if (!deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    await expirePhoneRecaps(db).catch(() => 0);
    const { rows: settings } = await db.query<{ enabled: boolean }>(
      "SELECT recaps_enabled_at IS NOT NULL AS enabled FROM call_settings WHERE account_id = $1", [accountId]);
    const { rows } = await db.query<{ call_id: string; ciphertext: Buffer }>(
      "SELECT call_id, ciphertext FROM phone_recaps WHERE account_id = $1 ORDER BY created_at LIMIT 50", [accountId]);
    const recaps: (StoredPhoneRecap & { callId: string })[] = [];
    const unreadable: string[] = [];
    for (const r of rows) {
      // One that won't decrypt (a key change) must not hide the others; it is listed so it can still be deleted.
      try {
        recaps.push({ callId: r.call_id, ...(JSON.parse(deps.cipher.decrypt(r.ciphertext, recapAad(accountId, r.call_id))) as StoredPhoneRecap) });
      } catch {
        unreadable.push(r.call_id);
      }
    }
    return { schemaVersion: 1, enabled: settings[0]?.enabled ?? false, recaps, unreadable };
  });

  app.put("/v1/calls/recaps/settings", { preHandler: auth, config: { rateLimit: { max: 30, timeWindow: "1 hour" } } }, async (req, reply) => {
    const body = parse(settingsBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    await inTransaction(db, async (c) => {
      await c.query("INSERT INTO call_settings (account_id) VALUES ($1) ON CONFLICT DO NOTHING", [accountId]);
      if (!body.enabled) await c.query("DELETE FROM phone_recaps WHERE account_id = $1", [accountId]);
      await c.query(
        `UPDATE call_settings SET updated_at = now(),
           recaps_enabled_at = CASE WHEN $2::boolean THEN coalesce(recaps_enabled_at, now()) ELSE NULL END
         WHERE account_id = $1`, [accountId, body.enabled]);
    });
    return { schemaVersion: 1, enabled: body.enabled };
  });

  app.delete("/v1/calls/recaps/:id", { preHandler: auth }, async (req, reply) => {
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    const r = await db.query("DELETE FROM phone_recaps WHERE call_id = $1 AND account_id = $2", [p.id, principal(req).accountId]);
    return r.rowCount ? reply.code(204).send() : reply.code(404).send({ error: "not_found" });
  });
};
