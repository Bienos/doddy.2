import { createHash } from "node:crypto";
import Fastify, { type FastifyInstance, type FastifyReply } from "fastify";
import formbody from "@fastify/formbody";
import rateLimit from "@fastify/rate-limit";
import type { z } from "zod";
import type { AccountVerifier } from "./doddyAccount.js";
import type { AbuseLimits } from "./config.js";
import type { Db } from "./db.js";
import type { TextCipher } from "./crypto.js";
import type { CallRegistrar, OutboundCaller, PhoneVerifier, PushSender, SmsSender } from "./providers/types.js";
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
import { callCaseRoutes } from "./routes/callCases.js";
import { taskCallWebhookRoutes } from "./routes/taskCallWebhooks.js";
import { taskCallContext, type TaskCallContext, type TaskCallDeps } from "./taskCalls/context.js";
import { errandRoutes } from "./routes/errands.js";
import { errandContext, type ErrandContext, type ErrandDeps } from "./errands/context.js";
import { fileWatchRoutes } from "./routes/fileWatches.js";
import { studioRoutes } from "./routes/studio.js";
import { fileWatchContext, type FileWatchContext, type FileWatchDeps } from "./fileWatches.js";
import { studioContext, type StudioContext, type StudioDeps } from "./studio/context.js";
import { assistantRoutes } from "./routes/assistant.js";
import { dealsRoutes } from "./routes/deals.js";
import { registryRoutes } from "./routes/registry.js";
import type { CeidgClient } from "./registry/ceidg.js";
import type { DealsDeps } from "./deals/service.js";
import type { AssistantDeps } from "./assistant/deps.js";
import type { PhoneRecapDeps } from "./phoneRecaps.js";
import { phoneRecapRoutes } from "./routes/phoneRecaps.js";
import { watchRoutes } from "./routes/watches.js";
import { watchContext, type WatchContext, type WatchDeps } from "./watches/context.js";

declare module "fastify" {
  interface FastifyInstance {
    /** The call-case context the routes use (null when the feature is off); tests run worker passes on it. */
    taskCallContext: TaskCallContext | null;
    /** The errand context the routes use (null without MEMORY_ENCRYPTION_KEY); tests run worker passes on it. */
    errandContext: ErrandContext | null;
    /** The Studio context the routes use (null without MEMORY_ENCRYPTION_KEY); tests run worker passes on it. */
    studioContext: StudioContext | null;
    /** The file-ready push context (null without MEMORY_ENCRYPTION_KEY or DOCUMENTS_ORIGIN); tests run worker passes on it. */
    fileWatchContext: FileWatchContext | null;
    /** The price-watch context the routes use (null without MEMORY_ENCRYPTION_KEY); tests run worker passes on it. */
    watchContext: WatchContext | null;
  }
}

export interface Deps {
  db: Db;
  /** Checks a Doddy account's token for `POST /v1/accounts/sign-in` (decision 2026-11-08-required-account). Absent: that route says "not set up". */
  accounts?: AccountVerifier | null;
  push?: PushSender;
  sms?: SmsSender;
  verifier?: PhoneVerifier;
  /** Needed (with publicBaseUrl) to verify Twilio webhook signatures. */
  twilioAuthToken?: string;
  publicBaseUrl?: string;
  /** Phone calls (S2, routed through this server since ADR-750): Twilio rings the user's number... */
  outbound?: OutboundCaller;
  /** ...and ElevenLabs register-call connects an answered call to the phone agent. */
  registrar?: CallRegistrar;
  cipher?: TextCipher;
  /** Shared with ElevenLabs; authenticates the phone agent's tool requests. */
  toolSecret?: string;
  doddyPhoneNumber?: string;
  /** No scheduled call rings inside these hours unless its card allowed it (ADR-754). Default 21:00–08:00. */
  quietHours?: QuietHours;
  /** News digests: feeds always; keyword search and AI writer when configured. */
  news?: NewsDeps;
  logger?: boolean;
  /** Proxies in front that append to X-Forwarded-For (Render: 1). Default 1. */
  trustProxyHops?: number;
  /** Verify codes the whole server may start per UTC day. Default 200. */
  verifyDailyCap?: number;
  /** Account, verification, text and call caps and the countries whose numbers are allowed (ADR-702, ADR-704). Defaults: DEFAULT_ABUSE_LIMITS. */
  limits?: Partial<AbuseLimits>;
  /** Calls Doddy places for the user (ADR-500). Needs `cipher` and `publicBaseUrl` too. */
  taskCalls?: TaskCallDeps;
  /** Where task-call log lines go (tests capture them); default: the request logger. */
  taskCallLog?: (msg: string, extra?: object) => void;
  /** Errands (ADR-570): settings and the researcher (needs an Anthropic key). Needs `cipher` too. */
  errands?: ErrandDeps;
  /** Leaflets (ADR-609, SHOPPING.md section 2): settings, the polite fetcher and the Haiku reader. */
  deals?: DealsDeps;
  /** Company registers (ADR-685): CEIDG with the owner's token; absent answers 503 registry_disabled. */
  ceidg?: CeidgClient;
  /** Where errand log lines go (tests capture them); default: the request logger. */
  errandLog?: (msg: string, extra?: object) => void;
  /** Studio (ADR-740): settings and the model API (needs an Anthropic key and Doddy's skills). Needs `cipher` too. */
  studio?: StudioDeps;
  /** File-ready pushes (9 Nov 2026): the backend's address and, in tests, a fake fetch and clock. Needs `cipher` too. */
  fileWatches?: FileWatchDeps;
  /** Where Studio log lines go (tests capture them); default: the request logger. */
  studioLog?: (msg: string, extra?: object) => void;
  /** Messages (ADR-586): the typed conversation asks Claude here. Needs an Anthropic key and the switch on. */
  assistant?: AssistantDeps;
  /** Recaps of calls to Doddy's phone line (decision 2026-11-09-conversation-recaps, step 5). Needs `cipher` and an Anthropic key. */
  phoneRecaps?: PhoneRecapDeps;
  /** Price watches (shopping stage 2, SHOPPING_WATCH.md): settings and the polite fetcher. Needs `cipher` too. */
  watches?: WatchDeps;
  /** Where price-watch log lines go (tests capture them); default: the request logger. */
  watchLog?: (msg: string, extra?: object) => void;
  /** Where texting-Doddy log lines go (tests capture them); default: the request logger. */
  smsChatLog?: (msg: string, extra?: object) => void;
  /** Called with each inbound text's answer in flight (tests await it). */
  onSmsChat?: (done: Promise<import("./smsChat.js").SmsChatOutcome>) => void;
}

/**
 * What the request log line says about a request (engineering audit, 7 Nov 2026): its method, its path
 * without the query string, and Fastify's request id. Fastify's default also logs the client's address,
 * host and port, and the full URL. The database keeps addresses only as keyed hashes (ADR-702), and
 * a query string can carry a capability: the call takeover page's `?t=`.
 */
export function requestLogFields(request: { method: string; url: string; id?: string }): Record<string, string> {
  const query = request.url.indexOf("?");
  return {
    method: request.method,
    url: query >= 0 ? request.url.slice(0, query) : request.url,
    ...(request.id ? { id: request.id } : {}),
  };
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
        'req.headers["x-doddy-tool-secret"]', 'req.headers["x-doddy-session"]', 'req.headers["elevenlabs-signature"]'],
      serializers: { req: requestLogFields },
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

  // Logs carry ids, states, durations and codes only (calls.md, "Privacy summary").
  const taskCtx = taskCallContext(deps.db, deps.taskCalls, deps.cipher, deps.publicBaseUrl, deps.push,
    deps.taskCallLog ?? ((msg, extra = {}) => app.log.info(extra, msg)));
  app.decorate("taskCallContext", taskCtx ?? null);
  const errandCtx = errandContext(deps.db, deps.errands, deps.cipher, deps.push,
    deps.errandLog ?? ((msg, extra = {}) => app.log.info(extra, msg)));
  app.decorate("errandContext", errandCtx ?? null);
  const studioCtx = studioContext(deps.db, deps.studio, deps.cipher, deps.push,
    deps.studioLog ?? ((msg, extra = {}) => app.log.info(extra, msg)));
  app.decorate("studioContext", studioCtx ?? null);
  const fileWatchCtx = fileWatchContext(deps.db, deps.fileWatches, deps.cipher, deps.push,
    deps.studioLog ?? ((msg, extra = {}) => app.log.info(extra, msg)));
  app.decorate("fileWatchContext", fileWatchCtx ?? null);
  const watchCtx = watchContext(deps.db, deps.watches, deps.cipher, deps.push,
    deps.watchLog ?? ((msg, extra = {}) => app.log.info(extra, msg)));
  app.decorate("watchContext", watchCtx ?? null);

  await app.register(accountRoutes(deps, taskCtx));
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
  await app.register(callCaseRoutes(deps, taskCtx));
  await app.register(taskCallWebhookRoutes(deps, taskCtx));
  await app.register(errandRoutes(deps, errandCtx));
  await app.register(studioRoutes(deps, studioCtx));
  await app.register(fileWatchRoutes(deps, fileWatchCtx));
  await app.register(assistantRoutes(deps));
  await app.register(phoneRecapRoutes(deps));
  await app.register(dealsRoutes(deps));
  await app.register(registryRoutes(deps));
  await app.register(watchRoutes(deps, watchCtx));
  return app;
}

/** Parses with zod; on failure sends 400 with the failing field paths (never the values). */
export function parse<T extends z.ZodType>(schema: T, data: unknown, reply: FastifyReply): z.infer<T> | undefined {
  const r = schema.safeParse(data);
  if (r.success) return r.data;
  void reply.code(400).send({ error: "invalid_request", fields: r.error.issues.map((i) => i.path.join(".")) });
  return undefined;
}
