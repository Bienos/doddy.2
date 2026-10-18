import type { FastifyPluginAsync } from "fastify";
import type { Deps } from "../app.js";
import { inTransaction } from "../db.js";
import { cancelQueuedSms } from "../outbox.js";
import { classifySms } from "../sms.js";
import { formValue as str, verifiedTwilioForm } from "./twilioAuth.js";

const EMPTY_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response/>';

export const twilioWebhookRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const verified = verifiedTwilioForm.bind(undefined, deps);

  // Inbound SMS. Only opt-out / opt-in keywords change state; message text is not stored.
  // Twilio's Advanced Opt-Out sends the confirmation replies, so we answer with empty TwiML.
  app.post("/webhooks/twilio/sms", async (req, reply) => {
    const form = verified(req, reply);
    if (!form) return;
    const from = str(form.From);
    const kind = classifySms(str(form.Body));
    if (kind === "opt_out") {
      await inTransaction(db, async (c) => {
        const { rows } = await c.query<{ account_id: string }>(
          `UPDATE phone_numbers SET sms_opted_out_at = now(), updated_at = now()
           WHERE e164 = $1 RETURNING account_id`, [from]);
        for (const r of rows) await cancelQueuedSms(c, r.account_id);
      });
    } else if (kind === "opt_in") {
      await db.query(
        "UPDATE phone_numbers SET sms_opted_out_at = NULL, updated_at = now() WHERE e164 = $1", [from]);
    }
    return reply.type("text/xml").send(EMPTY_TWIML);
  });

  // Delivery receipts for messages we sent (queued → sent → delivered / undelivered / failed).
  app.post("/webhooks/twilio/status", async (req, reply) => {
    const form = verified(req, reply);
    if (!form) return;
    const sid = str(form.MessageSid);
    const status = str(form.MessageStatus);
    if (sid && /^[a-z_]{1,32}$/.test(status)) {
      await db.query(
        `UPDATE outbound_messages SET delivery_status = $2, updated_at = now()
         WHERE provider_message_id = $1 AND channel = 'sms'`, [sid, status]);
    }
    return reply.code(204).send();
  });
};
