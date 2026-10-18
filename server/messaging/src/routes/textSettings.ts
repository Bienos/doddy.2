import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { memoryCopyOn } from "../inbox.js";
import { smsNumber } from "../outbox.js";
import { TEXTS_IN_CONSENT_VERSIONS } from "../textReplies.js";

// Settings for texts the user sends to Doddy's number, and the export of their phone and text
// history (ADR-490 unit U3, ADR-494). Every switch starts off.

const settingsBody = z.object({
  inboundEnabled: z.boolean().optional(),
  repliesEnabled: z.boolean().optional(),
  repliesUseMemories: z.boolean().optional(),
  language: z.enum(["en", "pl"]).optional(),
  consentTextVersion: z.string().max(32).optional(),
});

/** Rows of each kind in the export, newest first. */
const HISTORY_LIMIT = 1000;

export const textSettingsRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  // Texts reach the server only through Twilio's signed webhook, and are stored encrypted.
  const notesAvailable = () => !!deps.twilioAuthToken && !!deps.publicBaseUrl && !!deps.cipher;

  async function current(accountId: string) {
    const { rows: [r] } = await db.query<{
      inbound: boolean | null; replies: boolean | null; memories: boolean | null; language: string | null;
      consent: string | null; phone: boolean; opted_out: boolean;
    }>(
      `SELECT t.inbound_enabled AS inbound, t.replies_enabled AS replies, t.replies_use_memories AS memories, t.language,
              t.consent_text_version AS consent, p.account_id IS NOT NULL AS phone, p.sms_opted_out_at IS NOT NULL AS opted_out
       FROM (SELECT $1::uuid AS account_id) a
       LEFT JOIN text_settings t ON t.account_id = a.account_id
       LEFT JOIN phone_numbers p ON p.account_id = a.account_id`, [accountId]);
    return {
      inbound: r?.inbound ?? false, replies: r?.replies ?? false, memories: r?.memories ?? false,
      language: r?.language === "pl" ? "pl" as const : "en" as const, consent: r?.consent ?? null,
      phone: r?.phone ?? false, optedOut: r?.opted_out ?? false,
    };
  }

  app.get("/v1/texts/settings", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const s = await current(accountId);
    return {
      available: { notes: notesAvailable(), replies: notesAvailable() && !!deps.replyWriter },
      doddyNumber: deps.doddyPhoneNumber ?? null,
      phoneVerified: s.phone,
      // Replies are texts from Doddy, so they need the user's consent to those and no STOP since.
      textsFromDoddy: !!await smsNumber(db, accountId),
      optedOut: s.optedOut,
      inboundEnabled: s.inbound,
      repliesEnabled: s.replies,
      repliesUseMemories: s.memories,
      memoryCopy: await memoryCopyOn(db, accountId),
      language: s.language,
      consentTextVersion: s.consent,
    };
  });

  app.put("/v1/texts/settings", { preHandler: auth }, async (req, reply) => {
    const body = parse(settingsBody, req.body, reply);
    if (!body) return;
    // Turning something off is always accepted, even after the server lost its setup.
    const turnsOn = body.inboundEnabled === true || body.repliesEnabled === true || body.repliesUseMemories === true;
    if (turnsOn && !notesAvailable()) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    const cur = await current(accountId);
    // Each switch needs the one before it; turning one off turns off the ones after it.
    const inbound = body.inboundEnabled ?? cur.inbound;
    const replies = inbound && (body.repliesEnabled ?? cur.replies);
    const memories = replies && (body.repliesUseMemories ?? cur.memories);
    let consent = cur.consent;
    if (inbound && !cur.inbound) {
      if (!cur.phone) return reply.code(409).send({ error: "no_verified_phone" });
      if (!TEXTS_IN_CONSENT_VERSIONS.has(body.consentTextVersion ?? "")) {
        return reply.code(400).send({ error: "invalid_request", fields: ["consentTextVersion"] });
      }
      consent = body.consentTextVersion!;
    }
    if (replies && !cur.replies) {
      if (!deps.replyWriter) return reply.code(503).send({ error: "replies_not_configured" });
      if (!await smsNumber(db, accountId)) return reply.code(409).send({ error: "sms_not_enabled" });
    }
    if (memories && !cur.memories && !await memoryCopyOn(db, accountId)) {
      return reply.code(409).send({ error: "memory_copy_off" });
    }
    await db.query(
      `INSERT INTO text_settings (account_id, inbound_enabled, replies_enabled, replies_use_memories, language,
         consent_text_version, consent_at)
       VALUES ($1, $2, $3, $4, $5, $6, CASE WHEN $6::text IS NULL THEN NULL ELSE now() END)
       ON CONFLICT (account_id) DO UPDATE SET inbound_enabled = $2, replies_enabled = $3, replies_use_memories = $4,
         language = $5, updated_at = now(),
         consent_text_version = CASE WHEN $7 THEN $6 ELSE text_settings.consent_text_version END,
         consent_at = CASE WHEN $7 THEN now() ELSE text_settings.consent_at END`,
      [accountId, inbound, replies, memories, body.language ?? cur.language, consent, inbound && !cur.inbound]);
    return reply.code(204).send();
  });

  // "Export phone and text history": status rows and the notes waiting in the inbox. Message
  // text is erased once sent, so only the waiting notes have text in them.
  app.get("/v1/phone/history", { preHandler: auth, config: { rateLimit: { max: 10, timeWindow: "1 hour" } } }, async (req) => {
    const { accountId } = principal(req);
    const one = async (sql: string) => (await db.query(sql, [accountId])).rows[0] ?? null;
    const q = <T extends object>(sql: string) => db.query<T>(sql, [accountId, HISTORY_LIMIT]).then((r) => r.rows);
    const phone = await one(
      `SELECT e164 AS number, verified_at AS "verifiedAt", sms_consent_at AS "textsFromDoddyConsentAt",
              sms_consent_text_version AS "textsFromDoddyConsentVersion", sms_opted_out_at AS "stopAt"
       FROM phone_numbers WHERE account_id = $1`);
    const texts = await one(
      `SELECT inbound_enabled AS "textsToDoddy", replies_enabled AS "replies", replies_use_memories AS "repliesUseMemories",
              consent_text_version AS "consentVersion", consent_at AS "consentAt"
       FROM text_settings WHERE account_id = $1`);
    const notes = await q<{ id: string; source: string; ciphertext: Buffer; created_at: Date }>(
      "SELECT id, source, ciphertext, created_at FROM call_notes WHERE account_id = $1 ORDER BY created_at DESC LIMIT $2");
    return {
      exportedAt: new Date().toISOString(),
      phone,
      textSettings: texts,
      calls: await q<object>(
        `SELECT id, direction, status, error_code AS "errorCode", created_at AS "createdAt" FROM calls
         WHERE account_id = $1 ORDER BY created_at DESC LIMIT $2`),
      textsFromDoddy: await q<object>(
        `SELECT id, state, delivery_status AS "deliveryStatus", error_code AS "errorCode", approved_text AS "approvedByYou",
                created_at AS "createdAt" FROM outbound_messages
         WHERE account_id = $1 AND channel = 'sms' ORDER BY created_at DESC LIMIT $2`),
      textsToDoddy: await q<object>(
        `SELECT id, state, error_code AS "errorCode", received_at AS "receivedAt" FROM inbound_texts
         WHERE account_id = $1 ORDER BY received_at DESC LIMIT $2`),
      notesWaiting: notes.map((n) => {
        let text: string | null = null;
        try {
          text = deps.cipher?.decrypt(n.ciphertext, `${accountId}:note:${n.id}`) ?? null;
        } catch { /* unreadable after a key change: listed without text */ }
        return { id: n.id, source: n.source, text, createdAt: n.created_at };
      }),
    };
  });
};
