import type { FastifyPluginAsync } from "fastify";
import type { Deps } from "../app.js";
import { abuseLimits, smsCapsOf } from "../config.js";
import { inTransaction } from "../db.js";
import { cancelQueuedSms } from "../outbox.js";
import { scheduleDeletion } from "../providerRecords.js";
import { classifySms } from "../sms.js";
import { handleSmsChat, type SmsChatOutcome } from "../smsChat.js";
import { receiveText } from "../textsIn.js";
import { formValue as str, verifiedTwilioForm } from "./twilioAuth.js";

const EMPTY_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response/>';

/** Twilio's message statuses in the order they happen; the last group is final. Others are ignored. */
const DELIVERY_RANK: Record<string, number> = {
  accepted: 0, scheduled: 0, queued: 0, sending: 1, sent: 2,
  delivered: 3, undelivered: 3, failed: 3, read: 3, canceled: 3,
};
const DELIVERY_RANK_SQL = `CASE WHEN delivery_status IS NULL THEN -1
  WHEN delivery_status IN ('accepted', 'scheduled', 'queued') THEN 0 WHEN delivery_status = 'sending' THEN 1
  WHEN delivery_status = 'sent' THEN 2 ELSE 3 END`;

/** Twilio's segment count as a number 1 to 255, or undefined for anything else (absent, "0", text, a negative). */
export function reportedSegments(raw: string): number | undefined {
  if (!/^\d{1,3}$/.test(raw)) return undefined;
  const n = Number(raw);
  return n >= 1 && n <= 255 ? n : undefined;
}

export const twilioWebhookRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const verified = verifiedTwilioForm.bind(undefined, deps);
  const limits = abuseLimits(deps.limits);
  const smsChatLog = deps.smsChatLog ?? ((msg: string, extra: object = {}) => app.log.info(extra, msg));

  // Inbound SMS. STOP / START / HELP change state only; Twilio's Advanced Opt-Out sends the confirmation replies.
  // Any other text goes to exactly one handler, never both, and only for the user's own verified number:
  //  1. "Texts to Doddy" (ADR-753, off by default): the text becomes a note in the inbox, with no reply.
  //  2. Otherwise "Text with Doddy" (ADR-656, off by default, smsChat.ts): one answer by text, queued for the worker.
  // From anyone else the text is dropped: no reply, nothing stored. The answer to Twilio is always empty TwiML.
  app.post("/webhooks/twilio/sms", async (req, reply) => {
    const form = verified(req, reply);
    if (!form) return;
    const from = str(form.From);
    const sid = str(form.MessageSid);
    const body = str(form.Body);
    // Every inbound record is deleted at Twilio later, a stranger's too (ADR-753).
    await scheduleDeletion(db, "message", sid);
    const kind = classifySms(body);
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
      const kept = await receiveText(deps, { from, sid, body });
      if (kept === "dropped") {
        // Texts to Doddy are off for this sender (or it is nobody's number): Text with Doddy decides. Twilio waits at
        // most 15 s for this answer and a model call can take longer, so the answer is made after it.
        const done = handleSmsChat({ db, cipher: deps.cipher, assistant: deps.assistant, log: smsChatLog, smsCaps: smsCapsOf(limits) }, from, body, sid)
          .catch((err: unknown): SmsChatOutcome => {
            smsChatLog("sms chat failed", { kind: String((err as { name?: unknown }).name) });
            return "unavailable";
          });
        deps.onSmsChat?.(done);
      }
    }
    return reply.type("text/xml").send(EMPTY_TWIML);
  });

  // Delivery receipts for messages we sent (queued → sending → sent → delivered / undelivered /
  // failed). They can arrive out of order, so a status only moves forward (ADR-750): a late "sent"
  // never hides "delivered".
  app.post("/webhooks/twilio/status", async (req, reply) => {
    const form = verified(req, reply);
    if (!form) return;
    const sid = str(form.MessageSid);
    const status = str(form.MessageStatus);
    const rank = DELIVERY_RANK[status];
    if (sid && rank !== undefined) {
      await db.query(
        `UPDATE outbound_messages SET delivery_status = $2, updated_at = now()
         WHERE provider_message_id = $1 AND channel = 'sms' AND ${DELIVERY_RANK_SQL} < $3`, [sid, status, rank]);
      // Segments Twilio counted, to reconcile with the estimate made when the text was queued (smsSegments.ts). Twilio's
      // status-callback page does not list NumSegments (checked 9 Nov 2026), so this is read only when it is sent, only
      // from a status where the count is final (sent or later), and only as a whole number within the column's range.
      const reported = reportedSegments(str(form.NumSegments));
      if (sid && reported !== undefined && rank !== undefined && rank >= 2) {
        await db.query(
          `UPDATE outbound_messages SET reported_segments = $2 WHERE provider_message_id = $1 AND channel = 'sms'`, [sid, reported]);
      }
    }
    return reply.code(204).send();
  });
};
