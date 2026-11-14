// Webhooks of task calls: Twilio (signed with the task account's auth token) and ElevenLabs'
// post-call webhook (HMAC over the raw body). Twilio handlers always answer with TwiML that ends
// safely; anything unexpected gets the short spoken AI apology, never silence.
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify";
import type { Deps } from "../app.js";
import { byIp } from "../auth.js";
import { onPhonePostCall, type PhoneRecapContext } from "../phoneRecaps.js";
import { isValidTwilioSignature } from "../providers/twilio.js";
import type { TaskCallContext } from "../taskCalls/context.js";
import { freshElevenLabsSignature, isValidElevenLabsSignature } from "../taskCalls/elevenLabsSignature.js";
import { TECHNICAL_APOLOGY } from "../taskCalls/opening.js";
import { onConference, onTakeoverAnswer, onTakeoverDigits, onTakeoverStatus } from "../taskCalls/takeover.js";
import { sayAndHangUp } from "../taskCalls/twiml.js";
import { onAnswer, onConnectEnded, onPostCall, onStatus, onTranscription, type Form } from "../taskCalls/webhooks.js";

export const POST_CALL_BODY_LIMIT = 2 * 1024 * 1024;
/** Requests to the post-call webhook per client address. */
export const POST_CALL_RATE_LIMIT = { max: 120, timeWindow: "1 minute" } as const;

export const taskCallWebhookRoutes = (deps: Deps, ctx: TaskCallContext | undefined): FastifyPluginAsync => async (app) => {
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

  // The same workspace webhook serves the task-call agent and the phone agent: every phone-agent call keeps its
  // conversation id (so deleting the account deletes the conversation), and gets a recap when they are on (step 5).
  const webhookSecret = () => ctx?.config.webhookSecret ?? (deps.phoneRecaps?.phoneAgentId ? deps.phoneRecaps.webhookSecret : undefined);

  // ElevenLabs post-call: raw bytes for the HMAC, and room for a long transcript.
  await app.register(async (scope) => {
    scope.removeContentTypeParser("application/json");
    scope.addContentTypeParser("application/json", { parseAs: "buffer", bodyLimit: POST_CALL_BODY_LIMIT },
      (_req, body, done) => done(null, body));
    scope.post("/webhooks/elevenlabs/post-call", {
      bodyLimit: POST_CALL_BODY_LIMIT,
      // Per address: ElevenLabs sends one request per finished conversation, far below this.
      config: { rateLimit: { ...POST_CALL_RATE_LIMIT, keyGenerator: byIp } },
      // Before the body is read: no secret here, or no well-formed, current signature header, is refused without
      // buffering up to 2 MB. The digest itself needs the bytes and is checked in the handler, before any JSON parsing.
      preParsing: async (req, reply, payload) => {
        const sig = req.headers["elevenlabs-signature"];
        if (!webhookSecret()) void reply.code(503).send({ error: "not_configured" });
        else if (!freshElevenLabsSignature(typeof sig === "string" ? sig : undefined)) void reply.code(401).send({ error: "bad_signature" });
        return payload;
      },
    }, async (req, reply) => {
      const phone: PhoneRecapContext | undefined = deps.phoneRecaps?.phoneAgentId
        ? { db: deps.db, cipher: deps.cipher, deps: deps.phoneRecaps, log: (msg, extra) => req.log.info(extra ?? {}, msg) }
        : undefined;
      const secret = webhookSecret();
      if (!secret) return reply.code(503).send({ error: "not_configured" });
      const raw = req.body;
      const sig = req.headers["elevenlabs-signature"];
      if (!Buffer.isBuffer(raw) || !isValidElevenLabsSignature(secret, typeof sig === "string" ? sig : undefined, raw)) {
        return reply.code(401).send({ error: "bad_signature" });
      }
      let json: unknown;
      try {
        json = JSON.parse(raw.toString("utf8"));
      } catch {
        return reply.code(400).send({ error: "invalid_json" });
      }
      const agentId = (json as { data?: { agent_id?: unknown } } | null)?.data?.agent_id;
      if (phone && typeof agentId === "string" && agentId === phone.deps.phoneAgentId) {
        // Not awaited: the model takes seconds, and ElevenLabs switches a webhook off after repeated failures. The
        // conversation id is stored on the call first, before any model is asked.
        void onPhonePostCall(phone, json).catch((err) => req.log.error({ kind: String((err as { name?: unknown }).name) }, "phone recap failed"));
      } else if (ctx) {
        await onPostCall(ctx, json);
      }
      // Always 200 once verified: ElevenLabs switches a webhook off after repeated failures.
      return reply.code(200).send({ ok: true });
    });
  });
};
