import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import type { Deps } from "../app.js";
import { inTransaction } from "../db.js";
import { cancelQueuedSms } from "../outbox.js";
import { isValidTwilioSignature } from "../providers/twilio.js";
import { classifySms } from "../sms.js";
import { handleSmsChat, type SmsChatOutcome } from "../smsChat.js";

type Form = Record<string, string | string[] | undefined>;
const EMPTY_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response/>';

const str = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";

export const twilioWebhookRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const smsChatLog = deps.smsChatLog ?? ((msg: string, extra: object = {}) => app.log.info(extra, msg));

  /** Rejects anything not signed by Twilio. Returns the form fields when valid. */
  function verified(req: FastifyRequest, reply: FastifyReply): Form | undefined {
    if (!deps.twilioAuthToken || !deps.publicBaseUrl) {
      void reply.code(503).send({ error: "not_configured" });
      return undefined;
    }
    const form = (req.body ?? {}) as Form;
    const sig = req.headers["x-twilio-signature"];
    if (!isValidTwilioSignature(deps.twilioAuthToken, deps.publicBaseUrl + req.url, form,
      typeof sig === "string" ? sig : undefined)) {
      void reply.code(403).send({ error: "bad_signature" });
      return undefined;
    }
    return form;
  }

  // Inbound SMS. Opt-out / opt-in keywords change state; any other text goes to Doddy when its sender
  // turned texting on (smsChat.ts), answered after this webhook returns, as a queued text. The message
  // text is not stored. Twilio's Advanced Opt-Out sends the keyword replies, so we answer with empty TwiML.
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
    } else if (kind === "other") {
      // Twilio waits at most 15 s for this answer and a model call can take longer, so it runs after.
      const done = handleSmsChat({ db, cipher: deps.cipher, assistant: deps.assistant, log: smsChatLog }, from, str(form.Body), str(form.MessageSid))
        .catch((err: unknown): SmsChatOutcome => {
          smsChatLog("sms chat failed", { kind: String((err as { name?: unknown }).name) });
          return "unavailable";
        });
      deps.onSmsChat?.(done);
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
