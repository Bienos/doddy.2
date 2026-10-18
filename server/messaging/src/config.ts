import { z } from "zod";
import { parseClock, QUIET_HOURS_DEFAULT, type QuietHours } from "./quietHours.js";

// Every provider block is optional: a missing block switches that feature off and the API
// answers 503 "not_configured". Nothing is faked.
const optional = z.string().min(1).optional();

const schema = z.object({
  DATABASE_URL: z.string().min(1),
  PORT: z.coerce.number().int().positive().default(3000),
  // Public https origin of this service, used to verify Twilio webhook signatures.
  PUBLIC_BASE_URL: z.string().url().optional(),

  APNS_TEAM_ID: optional,
  APNS_KEY_ID: optional,
  APNS_PRIVATE_KEY: optional, // contents of the .p8 file
  APNS_BUNDLE_ID: optional,

  TWILIO_ACCOUNT_SID: optional,
  TWILIO_AUTH_TOKEN: optional,
  TWILIO_MESSAGING_SERVICE_SID: optional,
  TWILIO_VERIFY_SERVICE_SID: optional,

  ELEVENLABS_API_KEY: optional,

  // S2 phone calls
  MEMORY_ENCRYPTION_KEY: optional, // base64 of 32 random bytes
  // Shared with ElevenLabs as a workspace secret; at least 32 characters (openssl rand -base64 32).
  ELEVENLABS_TOOL_SECRET: z.string().min(32, "ELEVENLABS_TOOL_SECRET must be at least 32 characters").optional(),
  // Proxies in front of the server that append to X-Forwarded-For (Render: 1). The client IP is
  // read that many entries from the right, so a client can't pick its own rate-limit bucket.
  TRUST_PROXY_HOPS: z.coerce.number().int().min(0).max(5).default(1),
  // Verify codes the whole server may start per UTC day (SMS cost cap).
  VERIFY_DAILY_CAP: z.coerce.number().int().positive().default(200),
  // "1": run the worker loop inside the web process (one service; e.g. Render free/starter).
  RUN_WORKER_IN_WEB: z.enum(["0", "1"]).default("0"),
  ELEVENLABS_PHONE_AGENT_ID: optional,
  // News digests
  ANTHROPIC_API_KEY: optional, // Claude writes the one-line summaries
  OPENAI_API_KEY: optional, // or OpenAI, when there is no Anthropic key (ADR-197)
  OPENAI_MODEL: optional, // default gpt-5-mini
  GNEWS_API_KEY: optional, // keyword search across news sources (paid plan for commercial use)
  // Replies to the user's texts (ADR-494) use ANTHROPIC_API_KEY, with this model (owner decision 7).
  TEXT_REPLY_MODEL: optional, // default claude-opus-5-5
  // Hours after a message or call is final before its record is deleted at Twilio (ADR-494).
  // 0 means as soon as Twilio allows (about 2 minutes).
  // An empty value means the default (z.coerce would read "" as 0, deleting at once).
  TWILIO_RECORD_DELETE_AFTER_HOURS: z.preprocess((v) => (v === "" ? undefined : v),
    z.coerce.number().min(0).max(24 * 30).default(24)),
  DODDY_PHONE_NUMBER: z.string().regex(/^\+[1-9][0-9]{6,14}$/).optional(),
  // Quiet hours for scheduled calls, "HH:MM" on the user's own clock (ADR-495). Default 21:00–08:00.
  QUIET_HOURS_START: z.preprocess((v) => (v === "" ? undefined : v),
    z.string().refine((v) => parseClock(v) !== undefined, "QUIET_HOURS_START must be HH:MM").optional()),
  QUIET_HOURS_END: z.preprocess((v) => (v === "" ? undefined : v),
    z.string().refine((v) => parseClock(v) !== undefined, "QUIET_HOURS_END must be HH:MM").optional()),
});

export interface ApnsConfig { teamId: string; keyId: string; privateKey: string; bundleId: string }
export interface TwilioConfig {
  accountSid: string; authToken: string; messagingServiceSid: string; verifyServiceSid: string;
}
/** The phone agent that answers calls this server lets through (ElevenLabs register-call, ADR-490). */
export interface PhoneAgentConfig { apiKey: string; agentId: string }

export interface Config {
  databaseUrl: string;
  port: number;
  trustProxyHops: number;
  verifyDailyCap: number;
  runWorkerInWeb: boolean;
  publicBaseUrl?: string;
  apns?: ApnsConfig;
  twilio?: TwilioConfig;
  memoryEncryptionKey?: string;
  toolSecret?: string;
  phoneAgent?: PhoneAgentConfig;
  doddyPhoneNumber?: string;
  anthropicApiKey?: string;
  openaiApiKey?: string;
  openaiModel?: string;
  gnewsApiKey?: string;
  textReplyModel?: string;
  twilioRecordDeleteAfterHours: number;
  quietHours: QuietHours;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const e = schema.parse(env);
  const all = <T extends object>(o: { [K in keyof T]: T[K] | undefined }): T | undefined =>
    Object.values(o).every((v) => v !== undefined) ? (o as T) : undefined;
  return {
    databaseUrl: e.DATABASE_URL,
    port: e.PORT,
    trustProxyHops: e.TRUST_PROXY_HOPS,
    verifyDailyCap: e.VERIFY_DAILY_CAP,
    runWorkerInWeb: e.RUN_WORKER_IN_WEB === "1",
    publicBaseUrl: e.PUBLIC_BASE_URL?.replace(/\/$/, ""),
    apns: all<ApnsConfig>({
      teamId: e.APNS_TEAM_ID, keyId: e.APNS_KEY_ID,
      // Render env vars often carry the .p8 with literal "\n".
      privateKey: e.APNS_PRIVATE_KEY?.replace(/\\n/g, "\n"), bundleId: e.APNS_BUNDLE_ID,
    }),
    twilio: all<TwilioConfig>({
      accountSid: e.TWILIO_ACCOUNT_SID, authToken: e.TWILIO_AUTH_TOKEN,
      messagingServiceSid: e.TWILIO_MESSAGING_SERVICE_SID, verifyServiceSid: e.TWILIO_VERIFY_SERVICE_SID,
    }),
    memoryEncryptionKey: e.MEMORY_ENCRYPTION_KEY,
    toolSecret: e.ELEVENLABS_TOOL_SECRET,
    phoneAgent: all<PhoneAgentConfig>({
      apiKey: e.ELEVENLABS_API_KEY, agentId: e.ELEVENLABS_PHONE_AGENT_ID,
    }),
    doddyPhoneNumber: e.DODDY_PHONE_NUMBER,
    anthropicApiKey: e.ANTHROPIC_API_KEY,
    openaiApiKey: e.OPENAI_API_KEY,
    openaiModel: e.OPENAI_MODEL,
    gnewsApiKey: e.GNEWS_API_KEY,
    textReplyModel: e.TEXT_REPLY_MODEL,
    twilioRecordDeleteAfterHours: e.TWILIO_RECORD_DELETE_AFTER_HOURS,
    quietHours: {
      start: e.QUIET_HOURS_START ? parseClock(e.QUIET_HOURS_START)! : QUIET_HOURS_DEFAULT.start,
      end: e.QUIET_HOURS_END ? parseClock(e.QUIET_HOURS_END)! : QUIET_HOURS_DEFAULT.end,
    },
  };
}
