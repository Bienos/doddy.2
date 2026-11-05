// Webhooks of task calls: Twilio (signed with the task account's auth token) and ElevenLabs'
// post-call webhook (HMAC over the raw body). Twilio handlers always answer with TwiML that ends
// safely; anything unexpected gets the short spoken AI apology, never silence.
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import type { Deps } from "../app.js";
import { isValidTwilioSignature } from "../providers/twilio.js";
import type { TaskCallContext } from "../taskCalls/context.js";
import { isValidElevenLabsSignature } from "../taskCalls/elevenLabsSignature.js";
import { TECHNICAL_APOLOGY } from "../taskCalls/opening.js";
import { onConference, onTakeoverAnswer, onTakeoverDigits, onTakeoverStatus } from "../taskCalls/takeover.js";
import { sayAndHangUp } from "../taskCalls/twiml.js";
import { onAnswer, onConnectEnded, onPostCall, onStatus, onTranscription, type Form } from "../taskCalls/webhooks.js";

export const POST_CALL_BODY_LIMIT = 2 * 1024 * 1024;

export const taskCallWebhookRoutes = (_deps: Deps, ctx: TaskCallContext | undefined): FastifyPluginAsync => async (app) => {
  /** Signed by Twilio for the task-call account; returns the form fields. */
  function verified(req: FastifyRequest, reply: FastifyReply): Form | undefined {
    if (!ctx) {
      void reply.code(503).send({ error: "not_configured" });
      return undefined;
    }
    const form = (req.body ?? {}) as Form;
    const sig = req.headers["x-twilio-signature"];
    if (!isValidTwilioSignature(ctx.config.twilioAuthToken, ctx.publicBaseUrl + req.url, form, typeof sig === "string" ? sig : undefined)) {
      void reply.code(403).send({ error: "bad_signature" });
      return undefined;
    }
    return form;
  }
  const q = (req: FastifyRequest, key: string) => {
    const v = (req.query as Record<string, unknown>)[key];
    return typeof v === "string" ? v : "";
  };
  const twiml = (reply: FastifyReply, xml: string) => reply.type("text/xml").send(xml);

  app.post("/webhooks/twilio/task-call/answer", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    try {
      return twiml(reply, await onAnswer(ctx, q(req, "a"), f));
    } catch (err) {
      req.log.error({ err: { message: (err as Error).message } }, "task-call answer failed");
      return twiml(reply, sayAndHangUp(TECHNICAL_APOLOGY, ctx.say));
    }
  });

  // Twilio's fallback when our answer URL failed or timed out: the same apology.
  app.post("/webhooks/twilio/task-call/fallback", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    return twiml(reply, sayAndHangUp(TECHNICAL_APOLOGY, ctx.say));
  });

  app.post("/webhooks/twilio/task-call/connect-ended", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    return twiml(reply, await onConnectEnded(ctx, q(req, "a"), f));
  });

  app.post("/webhooks/twilio/task-call/status", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    await onStatus(ctx, q(req, "a"), f);
    return reply.code(204).send();
  });

  app.post("/webhooks/twilio/task-call/transcription", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    await onTranscription(ctx, q(req, "a"), f);
    return reply.code(204).send();
  });

  app.post("/webhooks/twilio/task-call/takeover-answer", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    return twiml(reply, await onTakeoverAnswer(ctx, q(req, "t"), f));
  });

  app.post("/webhooks/twilio/task-call/takeover-digits", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    return twiml(reply, await onTakeoverDigits(ctx, q(req, "t"), f));
  });

  app.post("/webhooks/twilio/task-call/takeover-status", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    await onTakeoverStatus(ctx, q(req, "t"), f);
    return reply.code(204).send();
  });

  app.post("/webhooks/twilio/task-call/conference", async (req, reply) => {
    const f = verified(req, reply);
    if (!f || !ctx) return;
    await onConference(ctx, q(req, "t"), f);
    return reply.code(204).send();
  });

  // ElevenLabs post-call: raw bytes for the HMAC, and room for a long transcript.
  await app.register(async (scope) => {
    scope.removeContentTypeParser("application/json");
    scope.addContentTypeParser("application/json", { parseAs: "buffer", bodyLimit: POST_CALL_BODY_LIMIT },
      (_req, body, done) => done(null, body));
    scope.post("/webhooks/elevenlabs/post-call", { bodyLimit: POST_CALL_BODY_LIMIT }, async (req, reply) => {
      if (!ctx) return reply.code(503).send({ error: "not_configured" });
      const raw = req.body;
      const sig = req.headers["elevenlabs-signature"];
      if (!Buffer.isBuffer(raw) || !isValidElevenLabsSignature(ctx.config.webhookSecret, typeof sig === "string" ? sig : undefined, raw)) {
        return reply.code(401).send({ error: "bad_signature" });
      }
      let json: unknown;
      try {
        json = JSON.parse(raw.toString("utf8"));
      } catch {
        return reply.code(400).send({ error: "invalid_json" });
      }
      await onPostCall(ctx, json);
      // Always 200 once verified: ElevenLabs switches a webhook off after repeated failures.
      return reply.code(200).send({ ok: true });
    });
  });
};
