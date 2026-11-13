import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { memoryCopyOn } from "../inbox.js";
import { smsNumber } from "../outbox.js";
import { TEXTS_IN_CONSENT_VERSIONS } from "../textsIn.js";

// Settings for texts the user sends to Doddy's number, and the export of their phone and text
// history (ADR-750 unit U3, ADR-753). Every switch starts off.

const settingsBody = z.object({
  inboundEnabled: z.boolean().optional(),
  language: z.enum(["en", "pl"]).optional(),
  consentTextVersion: z.string().max(32).optional(),
  // Strict: an app that still sends repliesEnabled or repliesUseMemories (ADR-755) is refused, never silently ignored.
}).strict();

/** Rows of each kind in the export, newest first. */
const HISTORY_LIMIT = 1000;

export const textSettingsRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  // Texts reach the server only through Twilio's signed webhook, and are stored encrypted.
  const notesAvailable = () => !!deps.twilioAuthToken && !!deps.publicBaseUrl && !!deps.cipher;

  async function current(accountId: string) {
    const { rows: [r] } = await db.query<{
      inbound: boolean | null; language: string | null;
      consent: string | null; phone: boolean; opted_out: boolean;
    }>(
      `SELECT t.inbound_enabled AS inbound, t.language,
              t.consent_text_version AS consent, p.account_id IS NOT NULL AS phone, p.sms_opted_out_at IS NOT NULL AS opted_out
       FROM (SELECT $1::uuid AS account_id) a
       LEFT JOIN text_settings t ON t.account_id = a.account_id
       LEFT JOIN phone_numbers p ON p.account_id = a.account_id`, [accountId]);
    return {
      inbound: r?.inbound ?? false,
      language: r?.language === "pl" ? "pl" as const : "en" as const, consent: r?.consent ?? null,
      phone: r?.phone ?? false, optedOut: r?.opted_out ?? false,
    };
  }

  app.get("/v1/texts/settings", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const s = await current(accountId);
    return {
      available: { notes: notesAvailable() },
      doddyNumber: deps.doddyPhoneNumber ?? null,
      phoneVerified: s.phone,
      textsFromDoddy: !!await smsNumber(db, accountId),
      optedOut: s.optedOut,
      inboundEnabled: s.inbound,
      memoryCopy: await memoryCopyOn(db, accountId),
      language: s.language,
      consentTextVersion: s.consent,
    };
  });

  app.put("/v1/texts/settings", { preHandler: auth }, async (req, reply) => {
    const body = parse(settingsBody, req.body, reply);
    if (!body) return;
    // Turning something off is always accepted, even after the server lost its setup.
    if (body.inboundEnabled === true && !notesAvailable()) return reply.code(503).send({ error: "not_configured" });
    const { accountId } = principal(req);
    const cur = await current(accountId);
    const inbound = body.inboundEnabled ?? cur.inbound;
    let consent = cur.consent;
    if (inbound && !cur.inbound) {
      if (!cur.phone) return reply.code(409).send({ error: "no_verified_phone" });
      if (!TEXTS_IN_CONSENT_VERSIONS.has(body.consentTextVersion ?? "")) {
        return reply.code(400).send({ error: "invalid_request", fields: ["consentTextVersion"] });
      }
      consent = body.consentTextVersion!;
    }
    await db.query(
      `INSERT INTO text_settings (account_id, inbound_enabled, language, consent_text_version, consent_at)
       VALUES ($1, $2, $3, $4, CASE WHEN $4::text IS NULL THEN NULL ELSE now() END)
       ON CONFLICT (account_id) DO UPDATE SET inbound_enabled = $2, language = $3, updated_at = now(),
         consent_text_version = CASE WHEN $5 THEN $4 ELSE text_settings.consent_text_version END,
         consent_at = CASE WHEN $5 THEN now() ELSE text_settings.consent_at END`,
      [accountId, inbound, body.language ?? cur.language, consent, inbound && !cur.inbound]);
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
      `SELECT inbound_enabled AS "textsToDoddy", consent_text_version AS "consentVersion", consent_at AS "consentAt"
       FROM text_settings WHERE account_id = $1`);
    const notes = await q<{ id: string; source: string; ciphertext: Buffer; created_at: Date }>(
      "SELECT id, source, ciphertext, created_at FROM call_notes WHERE account_id = $1 ORDER BY created_at DESC LIMIT $2");
    return {
      exportedAt: new Date().toISOString(),
      phone,
      textSettings: texts,
      calls: await q<object>(
        `SELECT id, direction, status, error_code AS "errorCode", created_at AS "createdAt",
                recap_not_created AS "recapNotCreated" FROM calls
         WHERE account_id = $1 ORDER BY created_at DESC LIMIT $2`),
      textsFromDoddy: await q<object>(
        `SELECT id, state, delivery_status AS "deliveryStatus", error_code AS "errorCode", approved_text AS "approvedByYou",
                created_at AS "createdAt" FROM outbound_messages
         WHERE account_id = $1 AND channel = 'sms' ORDER BY created_at DESC LIMIT $2`),
      textsToDoddy: await q<object>(
        `SELECT id, state, received_at AS "receivedAt" FROM inbound_texts
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
