import { randomUUID } from "node:crypto";
import type { FastifyBaseLogger, FastifyPluginAsync } from "fastify";
import { z } from "zod";
import type { Deps } from "../app.js";
import { openSession } from "../calls.js";
import type { Db } from "../db.js";
import { sayAndHangUp } from "../voiceTwiml.js";
import { formValue, verifiedTwilioForm } from "./twilioAuth.js";

// Calls reach Doddy's server before any AI (ADR-490). Twilio posts here; the server decides who
// is handed to the phone agent, through ElevenLabs register-call. Everyone else hears one fixed
// sentence and the call ends.

/** What the calls feature needs before it answers with the phone agent instead of a fixed line. */
export function callsAvailable(deps: Deps): { inbound: boolean; outbound: boolean } {
  const inbound = !!(deps.toolSecret && deps.cipher && deps.registrar && deps.twilioAuthToken && deps.publicBaseUrl);
  return { inbound, outbound: inbound && !!(deps.outbound && deps.doddyPhoneNumber) };
}

/** Twilio's CallStatus values mapped to ours. Queued and initiated add nothing to "requested". */
const TWILIO_CALL_STATUS: Record<string, string> = {
  ringing: "ringing", "in-progress": "answered", completed: "completed",
  busy: "busy", "no-answer": "no_answer", failed: "failed", canceled: "canceled",
};
/** A status only moves forward: requested → ringing → answered (or started) → a final one. */
const RANK_SQL = "CASE status WHEN 'requested' THEN 0 WHEN 'ringing' THEN 1 WHEN 'started' THEN 2 WHEN 'answered' THEN 2 ELSE 3 END";
const rank = (status: string) => (status === "ringing" ? 1 : status === "answered" ? 2 : 3);

const callIdParam = z.object({ callId: z.uuid() });

/** A finished call's session ends with it, so its key can't be used afterwards. */
export const endCallSessions = (db: Db, callId: string) =>
  db.query("DELETE FROM call_sessions WHERE call_id = $1", [callId]);

export const twilioVoiceRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const verified = verifiedTwilioForm.bind(undefined, deps);

  /** Opens the call's session and asks ElevenLabs for the TwiML that connects the phone agent. */
  async function connect(log: FastifyBaseLogger, call: {
    callId: string; accountId: string; direction: "inbound" | "outbound"; from: string; to: string;
  }): Promise<string> {
    try {
      const variables = await openSession(db, call.accountId, call.callId, call.direction);
      const outcome = await deps.registrar!.register({
        from: call.from, to: call.to, direction: call.direction, variables: { ...variables },
      });
      if (outcome.kind === "twiml") return outcome.twiml;
      log.warn({ event: "call_not_connected", code: outcome.code }, "phone agent not reached");
      await db.query("UPDATE calls SET status = 'failed', error_code = $2 WHERE id = $1", [call.callId, outcome.code]);
      await endCallSessions(db, call.callId);
      return sayAndHangUp("cant_talk");
    } catch (err) {
      log.error({ err: { message: (err as Error).message } }, "connecting a call failed");
      await db.query("UPDATE calls SET status = 'failed', error_code = 'server_error' WHERE id = $1", [call.callId])
        .catch(() => {});
      return sayAndHangUp("unavailable");
    }
  }

  // Someone calls Doddy's number.
  app.post("/webhooks/twilio/voice", async (req, reply) => {
    const form = verified(req, reply);
    if (!form) return;
    const twiml = (xml: string) => reply.type("text/xml").send(xml);
    if (!callsAvailable(deps).inbound) return twiml(sayAndHangUp("not_set_up"));
    const from = formValue(form.From);
    const callSid = formValue(form.CallSid);
    let row: { account_id: string; inbound_enabled: boolean | null } | undefined;
    try {
      // A withheld number ("anonymous" and the like) matches no verified number.
      ({ rows: [row] } = await db.query<{ account_id: string; inbound_enabled: boolean | null }>(
        `SELECT p.account_id, s.inbound_enabled FROM phone_numbers p
         LEFT JOIN call_settings s ON s.account_id = p.account_id WHERE p.e164 = $1`, [from]));
    } catch (err) {
      req.log.error({ err: { message: (err as Error).message } }, "caller lookup failed");
      return twiml(sayAndHangUp("unavailable"));
    }
    // Logged with the reason only: never the caller's number.
    if (!row) {
      req.log.info({ event: "call_refused", reason: "unknown_caller" }, "call refused");
      return twiml(sayAndHangUp("unknown_caller"));
    }
    if (!row.inbound_enabled) {
      req.log.info({ event: "call_refused", reason: "calls_off" }, "call refused");
      return twiml(sayAndHangUp("calls_off"));
    }
    const callId = randomUUID();
    try {
      await db.query(
        "INSERT INTO calls (id, account_id, direction, status, call_sid) VALUES ($1, $2, 'inbound', 'started', $3)",
        [callId, row.account_id, callSid || null]);
    } catch (err) {
      req.log.error({ err: { message: (err as Error).message } }, "recording the call failed");
      return twiml(sayAndHangUp("unavailable"));
    }
    return twiml(await connect(req.log, {
      callId, accountId: row.account_id, direction: "inbound", from, to: formValue(form.To),
    }));
  });

  // The user picked up a call Doddy placed ("Call me now"). The session opens only now, and only
  // once per call: the first answer moves the call from requested or ringing to answered.
  app.post("/webhooks/twilio/voice/outbound/:callId", async (req, reply) => {
    const form = verified(req, reply);
    if (!form) return;
    const twiml = (xml: string) => reply.type("text/xml").send(xml);
    const params = callIdParam.safeParse(req.params);
    if (!params.success) return twiml(sayAndHangUp("cant_talk"));
    if (!callsAvailable(deps).outbound) return twiml(sayAndHangUp("not_set_up"));
    const callSid = formValue(form.CallSid);
    // Consent and the verified number are checked again: either may have gone since the tap.
    const { rows: [row] } = await db.query<{ account_id: string; e164: string }>(
      `UPDATE calls c SET status = 'answered', call_sid = $2
       FROM phone_numbers p, call_settings s
       WHERE c.id = $1 AND c.direction = 'outbound' AND c.status IN ('requested', 'ringing')
         AND (c.call_sid IS NULL OR c.call_sid = $2)
         AND p.account_id = c.account_id AND s.account_id = c.account_id AND s.outbound_consent_at IS NOT NULL
       RETURNING c.account_id, p.e164`, [params.data.callId, callSid]);
    if (!row) {
      req.log.warn({ event: "call_not_connected", code: "not_answerable" }, "answered call not found or already used");
      return twiml(sayAndHangUp("cant_talk"));
    }
    return twiml(await connect(req.log, {
      callId: params.data.callId, accountId: row.account_id, direction: "outbound",
      from: deps.doddyPhoneNumber!, to: row.e164,
    }));
  });

  // How a call went, from Twilio: ringing, answered, completed, busy, no answer, failed, canceled.
  app.post("/webhooks/twilio/call-status", async (req, reply) => {
    const form = verified(req, reply);
    if (!form) return;
    const callSid = formValue(form.CallSid);
    const next = TWILIO_CALL_STATUS[formValue(form.CallStatus)];
    if (!callSid || !next) return reply.code(204).send();
    const { rows: [row] } = await db.query<{ id: string }>(
      `UPDATE calls SET status = $2 WHERE call_sid = $1 AND ${RANK_SQL} < $3 RETURNING id`,
      [callSid, next, rank(next)]);
    if (row && rank(next) === 3) await endCallSessions(db, row.id);
    return reply.code(204).send();
  });
};
