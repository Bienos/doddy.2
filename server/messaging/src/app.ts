import { createHash } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyReply } from "fastify";
import formbody from "@fastify/formbody";
import rateLimit from "@fastify/rate-limit";
import type { z } from "zod";
import type { Db } from "./db.js";
import type { TextCipher } from "./crypto.js";
import type {
  CallRegistrar, OutboundCaller, PhoneVerifier, PushSender, SmsSender, TextReplyWriter,
} from "./providers/types.js";
import { callRoutes } from "./routes/calls.js";
import { elevenLabsRoutes } from "./routes/elevenlabs.js";
import { newsRoutes } from "./routes/news.js";
import type { NewsDeps } from "./news/digest.js";
import type { QuietHours } from "./quietHours.js";
import { accountRoutes } from "./routes/account.js";
import { phoneRoutes } from "./routes/phone.js";
import { updateRoutes } from "./routes/updates.js";
import { textRoutes } from "./routes/texts.js";
import { textSettingsRoutes } from "./routes/textSettings.js";
import { twilioWebhookRoutes } from "./routes/twilioWebhooks.js";
import { twilioVoiceRoutes } from "./routes/twilioVoice.js";
import { scheduledCallRoutes } from "./routes/scheduledCalls.js";

export interface Deps {
  db: Db;
  push?: PushSender;
  sms?: SmsSender;
  verifier?: PhoneVerifier;
  /** Needed (with publicBaseUrl) to verify Twilio webhook signatures. */
  twilioAuthToken?: string;
  publicBaseUrl?: string;
  /** Phone calls (S2, routed through this server since ADR-490): Twilio rings the user's number... */
  outbound?: OutboundCaller;
  /** ...and ElevenLabs register-call connects an answered call to the phone agent. */
  registrar?: CallRegistrar;
  cipher?: TextCipher;
  /** Shared with ElevenLabs; authenticates the phone agent's tool requests. */
  toolSecret?: string;
  doddyPhoneNumber?: string;
  /** Writes replies to the user's texts when they turn replies on (Claude, ADR-494). */
  replyWriter?: TextReplyWriter;
  /** No scheduled call rings inside these hours unless its card allowed it (ADR-495). Default 21:00–08:00. */
  quietHours?: QuietHours;
  /** News digests: feeds always; keyword search and AI writer when configured. */
  news?: NewsDeps;
  logger?: boolean;
  /** Proxies in front that append to X-Forwarded-For (Render: 1). Default 1. */
  trustProxyHops?: number;
  /** Verify codes the whole server may start per UTC day. Default 200. */
  verifyDailyCap?: number;
}

export async function buildApp(deps: Deps): Promise<FastifyInstance> {
  const app = Fastify({
    // Render terminates TLS and appends to X-Forwarded-For. Trusting a fixed number of hops reads
    // the client IP from the right, so a client-supplied X-Forwarded-For can't change it (ADR-175).
    trustProxy: (_address: string, hop: number) => hop < (deps.trustProxyHops ?? 1),
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
    // Signed-in routes count per bearer token (requests with a made-up token get their own bucket
    // but are refused by auth before they do anything). Routes without auth must set
    // keyGenerator: byIp, or a made-up Authorization header would buy a fresh bucket.
    keyGenerator: (req) => {
      const auth = req.headers.authorization;
      return auth ? "auth:" + createHash("sha256").update(auth).digest("hex") : "ip:" + req.ip;
    },
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
  await app.register(textRoutes(deps));
  await app.register(textSettingsRoutes(deps));
  await app.register(twilioWebhookRoutes(deps));
  await app.register(twilioVoiceRoutes(deps));
  await app.register(callRoutes(deps));
  await app.register(scheduledCallRoutes(deps));
  await app.register(elevenLabsRoutes(deps));
  await app.register(newsRoutes(deps));
  return app;
}

/** Parses with zod; on failure sends 400 with the failing field paths (never the values). */
export function parse<T extends z.ZodType>(schema: T, data: unknown, reply: FastifyReply): z.infer<T> | undefined {
  const r = schema.safeParse(data);
  if (r.success) return r.data;
  void reply.code(400).send({ error: "invalid_request", fields: r.error.issues.map((i) => i.path.join(".")) });
  return undefined;
}
