import type { DealsSettings } from "./deals/types.js";
import { z } from "zod";

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
  ELEVENLABS_PHONE_NUMBER_ID: optional, // ElevenLabs id of the imported Twilio number
  // News digests
  ANTHROPIC_API_KEY: optional, // Claude writes the one-line summaries
  OPENAI_API_KEY: optional, // or OpenAI, when there is no Anthropic key (ADR-197)
  OPENAI_MODEL: optional, // default gpt-5-mini
  GNEWS_API_KEY: optional, // keyword search across news sources (paid plan for commercial use)
  DODDY_PHONE_NUMBER: z.string().regex(/^\+[1-9][0-9]{6,14}$/).optional(),

  // Calls Doddy makes for the user (call cases, ADR-500). Our server places the Twilio call and
  // ElevenLabs is only the voice (register-call). docs/decisions/calls.md.
  // "1" stops every task call: no new cases, approvals, dials or takeovers; calls in progress end.
  TASK_CALLS_KILL_SWITCH: z.enum(["0", "1"]).default("0"),
  // A dedicated Twilio subaccount (Poland-only voice permissions) is recommended; without these the
  // main TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN are used.
  TWILIO_TASK_ACCOUNT_SID: optional,
  TWILIO_TASK_AUTH_TOKEN: optional,
  // The number the callee sees; must belong to that Twilio account. Default DODDY_PHONE_NUMBER.
  TASK_CALL_FROM_NUMBER: z.string().regex(/^\+[1-9][0-9]{6,14}$/).optional(),
  ELEVENLABS_TASK_AGENT_ID: optional,
  // Secret of the ElevenLabs post-call webhook (HMAC).
  ELEVENLABS_WEBHOOK_SECRET: z.string().min(16).optional(),
  // Spoken after the AI disclosure. "off" until the owner confirms the legal basis (calls.md).
  CALL_RECORDING_NOTICE: z.enum(["off", "nagrywana", "zapisywana"]).default("off"),
  // Limits: these can only be lowered; the maximums are the code's ceilings.
  TASK_CALL_LIMIT_USER_HOUR: z.coerce.number().int().min(0).max(3).default(3),
  TASK_CALL_LIMIT_USER_DAY: z.coerce.number().int().min(0).max(10).default(10),
  TASK_CALL_LIMIT_DEST_USER_DAY: z.coerce.number().int().min(0).max(2).default(2),
  TASK_CALL_LIMIT_DEST_DAY: z.coerce.number().int().min(0).max(3).default(3),
  TASK_CALL_DEST_GAP_MINUTES: z.coerce.number().int().min(15).max(1440).default(15),
  TASK_CALL_LIMIT_GLOBAL_DAY: z.coerce.number().int().min(0).max(200).default(50),
  TASK_CALL_MAX_SECS: z.coerce.number().int().min(60).max(300).default(300),
  // Prices for the parts Twilio and ElevenLabs don't report per call. Unset = that cost is "unknown".
  PRICE_TWILIO_TRANSCRIPTION_USD_PER_MIN: z.coerce.number().positive().max(1).optional(),
  PRICE_TWILIO_CONFERENCE_USD_PER_PARTICIPANT_MIN: z.coerce.number().positive().max(1).optional(),
  PRICE_ELEVENLABS_USD_PER_CREDIT: z.coerce.number().positive().max(1).optional(),
  // Twilio's own voice for the short fixed lines (apology, goodbye, "przekazuję rozmowę").
  TASK_CALL_SAY_VOICE: z.string().regex(/^[A-Za-z0-9.\-]{1,40}$/).default("Polly.Ewa"),

  // Errands (ADR-570, docs/implementation/ERRANDS.md): Doddy researches a task in the background.
  // On by default, but only runs when ANTHROPIC_API_KEY and MEMORY_ENCRYPTION_KEY are set too;
  // "0" refuses new errands and starts no queued one.
  ERRANDS_ENABLED: z.enum(["0", "1"]).default("0"),
  ERRANDS_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-opus-5-5"),
  ERRANDS_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("high"),
  // A stuck run ends as failed: time_limit instead of running forever. Not a cap on look-ups.
  ERRAND_TIME_LIMIT_MINUTES: z.coerce.number().int().min(1).max(120).default(30),
  // Queued or running errands per account.
  ERRANDS_MAX_OPEN: z.coerce.number().int().min(1).max(20).default(5),
  // Shopping errands (ADR-607, docs/implementation/SHOPPING.md): the runner's model and the paid
  // look-ups per errand. Serper is the offer source (Google Shopping for Poland); without its key,
  // find_offers answers "not set up" and the runner reads shop pages it finds through web search.
  // Owner, 24 Oct 2026 (ADR-611): Haiku for everyone, Sonnet for the premium option. There are no plans yet, so
  // premium is the accounts listed in SHOPPING_PREMIUM_ACCOUNTS (comma-separated account ids, empty by default).
  SHOPPING_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-haiku-5-5"),
  SHOPPING_PREMIUM_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-sonnet-5-5"),
  SHOPPING_PREMIUM_ACCOUNTS: z.string().default("").transform((v) => v.split(",").map((x) => x.trim()).filter(Boolean))
    .refine((ids) => ids.every((id) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu.test(id)), "account ids, comma-separated"),
  SHOPPING_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("medium"),
  SHOPPING_MAX_OFFER_SEARCHES: z.coerce.number().int().min(1).max(20).default(8),
  SHOPPING_MAX_PAGE_CHECKS: z.coerce.number().int().min(1).max(40).default(15),
  SERPER_API_KEY: z.string().min(8).optional(),
  // Leaflets (ADR-609, SHOPPING.md section 2): POST /v1/deals/search reads the official leaflets of
  // Biedronka, Lidl, Dino and Rossmann on request and keeps only counts. "0" answers 503 deals_disabled.
  // Image pages need ANTHROPIC_API_KEY (Claude Haiku reads them); the caps count requests per UTC day.
  DEALS_ENABLED: z.enum(["0", "1"]).default("0"),
  DEALS_VISION_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-haiku-5-5"),
  DEALS_MAX_PAGES: z.coerce.number().int().min(0).max(100).default(40),
  DEALS_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(1000).default(30),
  DEALS_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(100000).default(1000),

  // Messages (ADR-585, ADR-586): the app's typed conversation asks Claude here. Text only, no tools.
  // Runs only when ANTHROPIC_API_KEY is set too; "0" answers 503 notConfigured. The daily caps count
  // requests per account and for the whole server (UTC day) and can only be lowered below the ceilings.
  ASSISTANT_ENABLED: z.enum(["0", "1"]).default("0"),
  ASSISTANT_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-haiku-5-5"),
  ASSISTANT_EFFORT: z.enum(["low", "medium", "high"]).default("medium"),
  ASSISTANT_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(1000).default(100),
  ASSISTANT_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(100000).default(1000),
});

export interface ApnsConfig { teamId: string; keyId: string; privateKey: string; bundleId: string }
export interface TwilioConfig {
  accountSid: string; authToken: string; messagingServiceSid: string; verifyServiceSid: string;
}
export interface PhoneAgentConfig { apiKey: string; agentId: string; phoneNumberId: string }

export type RecordingNotice = "off" | "nagrywana" | "zapisywana";

export interface TaskCallLimits {
  userPerHour: number; userPerDay: number; destinationPerUserDay: number; destinationPerDay: number;
  destinationGapMinutes: number; globalPerDay: number; maxDurationSecs: number;
}

export interface TaskCallPrices {
  transcriptionUsdPerMin?: number; conferenceUsdPerParticipantMin?: number; elevenLabsUsdPerCredit?: number;
}

/** Everything a task call needs. Missing pieces leave `taskCalls` undefined: the API answers 503. */
export interface TaskCallConfig {
  twilioAccountSid: string; twilioAuthToken: string; fromNumber: string;
  elevenLabsApiKey: string; agentId: string; webhookSecret: string;
}

export interface TaskCallSettings {
  killSwitch: boolean; notice: RecordingNotice; limits: TaskCallLimits; prices: TaskCallPrices; sayVoice: string;
}

export type ErrandEffort = "low" | "medium" | "high" | "xhigh" | "max";

/** Errand switches and limits. `enabled` is the env switch only; the key and cipher are checked where wired. */
export interface ErrandSettings {
  enabled: boolean; model: string; effort: ErrandEffort; timeLimitMinutes: number; maxOpen: number;
}

/** Shopping errands (ADR-607): the runner's model and the paid look-ups per errand. */
export interface ShoppingSettings {
  model: string; premiumModel: string; premiumAccountIds: string[];
  effort: ErrandEffort; maxOfferSearches: number; maxPageChecks: number; serperApiKey?: string;
}

/** Messages switches and caps (ADR-586). `enabled` is the env switch only; the key is checked where wired. */
export interface AssistantSettings {
  enabled: boolean; model: string; effort: "low" | "medium" | "high"; dailyPerAccount: number; dailyPerServer: number;
}

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
  taskCalls?: TaskCallConfig;
  taskCallSettings: TaskCallSettings;
  errandSettings: ErrandSettings;
  shoppingSettings: ShoppingSettings;
  dealsSettings: DealsSettings;
  assistantSettings: AssistantSettings;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  // A variable left empty (as in a copied .env.example) counts as unset, not as an invalid value.
  const e = schema.parse(Object.fromEntries(Object.entries(env).filter(([, v]) => v !== "")));
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
      apiKey: e.ELEVENLABS_API_KEY, agentId: e.ELEVENLABS_PHONE_AGENT_ID, phoneNumberId: e.ELEVENLABS_PHONE_NUMBER_ID,
    }),
    doddyPhoneNumber: e.DODDY_PHONE_NUMBER,
    anthropicApiKey: e.ANTHROPIC_API_KEY,
    openaiApiKey: e.OPENAI_API_KEY,
    openaiModel: e.OPENAI_MODEL,
    gnewsApiKey: e.GNEWS_API_KEY,
    taskCalls: all<TaskCallConfig>({
      twilioAccountSid: e.TWILIO_TASK_ACCOUNT_SID ?? e.TWILIO_ACCOUNT_SID,
      twilioAuthToken: e.TWILIO_TASK_AUTH_TOKEN ?? e.TWILIO_AUTH_TOKEN,
      fromNumber: e.TASK_CALL_FROM_NUMBER ?? e.DODDY_PHONE_NUMBER,
      elevenLabsApiKey: e.ELEVENLABS_API_KEY,
      agentId: e.ELEVENLABS_TASK_AGENT_ID,
      webhookSecret: e.ELEVENLABS_WEBHOOK_SECRET,
    }),
    taskCallSettings: {
      killSwitch: e.TASK_CALLS_KILL_SWITCH === "1",
      notice: e.CALL_RECORDING_NOTICE,
      limits: {
        userPerHour: e.TASK_CALL_LIMIT_USER_HOUR,
        userPerDay: e.TASK_CALL_LIMIT_USER_DAY,
        destinationPerUserDay: e.TASK_CALL_LIMIT_DEST_USER_DAY,
        destinationPerDay: e.TASK_CALL_LIMIT_DEST_DAY,
        destinationGapMinutes: e.TASK_CALL_DEST_GAP_MINUTES,
        globalPerDay: e.TASK_CALL_LIMIT_GLOBAL_DAY,
        maxDurationSecs: e.TASK_CALL_MAX_SECS,
      },
      prices: {
        transcriptionUsdPerMin: e.PRICE_TWILIO_TRANSCRIPTION_USD_PER_MIN,
        conferenceUsdPerParticipantMin: e.PRICE_TWILIO_CONFERENCE_USD_PER_PARTICIPANT_MIN,
        elevenLabsUsdPerCredit: e.PRICE_ELEVENLABS_USD_PER_CREDIT,
      },
      sayVoice: e.TASK_CALL_SAY_VOICE,
    },
    errandSettings: {
      enabled: e.ERRANDS_ENABLED === "1",
      model: e.ERRANDS_MODEL,
      effort: e.ERRANDS_EFFORT,
      timeLimitMinutes: e.ERRAND_TIME_LIMIT_MINUTES,
      maxOpen: e.ERRANDS_MAX_OPEN,
    },
    shoppingSettings: {
      model: e.SHOPPING_MODEL,
      premiumModel: e.SHOPPING_PREMIUM_MODEL,
      premiumAccountIds: e.SHOPPING_PREMIUM_ACCOUNTS,
      effort: e.SHOPPING_EFFORT,
      maxOfferSearches: e.SHOPPING_MAX_OFFER_SEARCHES,
      maxPageChecks: e.SHOPPING_MAX_PAGE_CHECKS,
      serperApiKey: e.SERPER_API_KEY,
    },
    dealsSettings: {
      enabled: e.DEALS_ENABLED === "1", visionModel: e.DEALS_VISION_MODEL, maxPages: e.DEALS_MAX_PAGES,
      dailyPerAccount: e.DEALS_DAILY_PER_ACCOUNT, dailyPerServer: e.DEALS_DAILY_PER_SERVER,
    },
    assistantSettings: {
      enabled: e.ASSISTANT_ENABLED === "1",
      model: e.ASSISTANT_MODEL,
      effort: e.ASSISTANT_EFFORT,
      dailyPerAccount: e.ASSISTANT_DAILY_PER_ACCOUNT,
      dailyPerServer: e.ASSISTANT_DAILY_PER_SERVER,
    },
  };
}

/** The defaults a test or a server without the variables gets: the code's ceilings, switch off. */
export const DEFAULT_TASK_CALL_SETTINGS: TaskCallSettings = {
  killSwitch: false,
  notice: "off",
  limits: {
    userPerHour: 3, userPerDay: 10, destinationPerUserDay: 2, destinationPerDay: 3,
    destinationGapMinutes: 15, globalPerDay: 50, maxDurationSecs: 300,
  },
  prices: {},
  sayVoice: "Polly.Ewa",
};

/** Settings for an injected ErrandDeps without its own (tests): on, Opus 5.5 at high effort, 30 min, 5 open.
 * The environment's ERRANDS_ENABLED defaults to "0": errands start only when the owner turns them on. */
export const DEFAULT_ERRAND_SETTINGS: ErrandSettings = {
  enabled: true, model: "claude-opus-5-5", effort: "high", timeLimitMinutes: 30, maxOpen: 5,
};

/** Settings for an injected AssistantDeps without its own (tests). The environment's ASSISTANT_ENABLED
 * defaults to "0": the typed conversation reaches Claude only when the owner turns it on. */
export const DEFAULT_ASSISTANT_SETTINGS: AssistantSettings = {
  enabled: true, model: "claude-haiku-5-5", effort: "medium", dailyPerAccount: 100, dailyPerServer: 1000,
};
