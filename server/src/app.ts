import Fastify, { type FastifyInstance, type FastifyReply } from "fastify";
import formbody from "@fastify/formbody";
import rateLimit from "@fastify/rate-limit";
import type { z } from "zod";
import type { Db } from "./db.js";
import type { TextCipher } from "./crypto.js";
import type { OutboundCaller, PhoneVerifier, PushSender, SmsSender, VoiceTokenIssuer } from "./providers/types.js";
import { callRoutes } from "./routes/calls.js";
import { elevenLabsRoutes } from "./routes/elevenlabs.js";
import { accountRoutes } from "./routes/account.js";
import { phoneRoutes } from "./routes/phone.js";
import { updateRoutes } from "./routes/updates.js";
import { voiceRoutes } from "./routes/voice.js";
import { twilioWebhookRoutes } from "./routes/twilioWebhooks.js";

export interface Deps {
  db: Db;
  push?: PushSender;
  sms?: SmsSender;
  verifier?: PhoneVerifier;
  voice?: VoiceTokenIssuer;
  /** Needed (with publicBaseUrl) to verify Twilio webhook signatures. */
  twilioAuthToken?: string;
  publicBaseUrl?: string;
  /** S2: phone calls. */
  outbound?: OutboundCaller;
  cipher?: TextCipher;
  /** Shared with ElevenLabs; authenticates the call-start webhook and tool requests. */
  toolSecret?: string;
  doddyPhoneNumber?: string;
  logger?: boolean;
}

export async function buildApp(deps: Deps): Promise<FastifyInstance> {
  const app = Fastify({
    // Render terminates TLS and sets X-Forwarded-For.
    trustProxy: true,
    bodyLimit: 16 * 1024,
    logger: deps.logger === false ? false : {
      level: "info",
      // Never log bearer tokens or signatures. Request bodies are not logged at all.
      redact: ["req.headers.authorization", 'req.headers["x-twilio-signature"]',
        'req.headers["x-doddy-tool-secret"]', 'req.headers["x-doddy-session"]'],
    },
  });
  await app.register(formbody);
  await app.register(rateLimit, {
    global: false,
    keyGenerator: (req) => req.headers.authorization ?? req.ip,
  });

  app.setErrorHandler((err: Error & { statusCode?: number }, req, reply) => {
    if (err.statusCode && err.statusCode < 500) {
      return reply.code(err.statusCode).send({ error: err.statusCode === 429 ? "rate_limited" : "bad_request" });
    }
    req.log.error({ err: { message: err.message, code: (err as { code?: string }).code } }, "request failed");
    return reply.code(500).send({ error: "internal" });
  });

  app.get("/healthz", async (_req, reply) => {
    try {
      await deps.db.query("SELECT 1");
      return { ok: true };
    } catch {
      return reply.code(503).send({ ok: false });
    }
  });

  await app.register(accountRoutes(deps));
  await app.register(phoneRoutes(deps));
  await app.register(updateRoutes(deps));
  await app.register(voiceRoutes(deps));
  await app.register(twilioWebhookRoutes(deps));
  await app.register(callRoutes(deps));
  await app.register(elevenLabsRoutes(deps));
  return app;
}

/** Parses with zod; on failure sends 400 with the failing field paths (never the values). */
export function parse<T extends z.ZodType>(schema: T, data: unknown, reply: FastifyReply): z.infer<T> | undefined {
  const r = schema.safeParse(data);
  if (r.success) return r.data;
  void reply.code(400).send({ error: "invalid_request", fields: r.error.issues.map((i) => i.path.join(".")) });
  return undefined;
}
