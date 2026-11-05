import type { DealsSettings } from "./deals/types.js";
import { DEFAULT_RESEARCH_BUDGET, type ResearchBudget } from "./errands/budget.js";
import { DEFAULT_ALLOWED_COUNTRY_CODES, parseCountryCodes } from "./phoneCountries.js";
import { DEFAULT_NEW_ACCOUNT_HOURS, DEFAULT_NEW_ACCOUNT_POOL } from "./serverUsage.js";
import { parseAffiliateRules, type AffiliateRule } from "./shopping/affiliate.js";
import { parseSearchShops, type SearchShop } from "./deals/further.js";
import { z } from "zod";
import type { StudioSettings } from "./studio/context.js";
import { PLAN_TIER_NAMES, stepModelsFrom, type PlanTier } from "./studio/models.js";

const MODEL_ID = /^[a-z0-9][a-z0-9.\-]{1,63}$/;

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
  // Abuse limits (security review 4 Nov 2026, ADR-702 to ADR-705). Accounts are free and anonymous, so what they can
  // spend is capped per client address, per account and for the server. Every one has a safe default and none is
  // needed at startup. Many phones share one carrier address, so the per-address numbers are generous.
  // Accounts made per UTC day: per client address (IPv6: per /64) and in all, on top of 10 an hour per address.
  ACCOUNTS_DAILY_PER_IP: z.coerce.number().int().min(1).max(100000).default(50),
  ACCOUNTS_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(1000000).default(1000),
  // An account is "established" with a verified phone number or once it is this many hours old; the others share
  // the small daily pools below, inside each feature's server-wide cap. 0: every account counts as established.
  NEW_ACCOUNT_HOURS: z.coerce.number().int().min(0).max(8760).default(DEFAULT_NEW_ACCOUNT_HOURS),
  // Verification codes per client address and per account and UTC day (on top of the per-number and server caps).
  VERIFY_DAILY_PER_IP: z.coerce.number().int().min(1).max(10000).default(20),
  VERIFY_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(1000).default(6),
  // Calling codes (no "+", comma-separated) whose numbers may be verified, texted and called. Default: Poland,
  // the rest of the EU and EEA, the UK and Switzerland.
  PHONE_ALLOWED_COUNTRY_CODES: z.string().default(DEFAULT_ALLOWED_COUNTRY_CODES.join(",")).transform((v, ctx) => {
    try { return parseCountryCodes(v); } catch (err) { ctx.addIssue({ code: "custom", message: (err as Error).message }); return z.NEVER; }
  }),
  // Texts queued per account and for the server per UTC day, and "call me" calls for the server per UTC day (the
  // account's own 10 calls a day stay).
  SMS_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(1000).default(30),
  SMS_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(100000).default(300),
  OUTBOUND_CALLS_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(10000).default(20),
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
  // Numbers Doddy must never call for a user (ADR-705): E.164, comma-separated. An operator's stop list for a callee
  // who asked not to be called; the real opt-out process is for the owner and counsel to decide (calls.md).
  TASK_CALL_BLOCKED_NUMBERS: z.string().default("").transform((v, ctx) => {
    const items = v.split(",").map((x) => x.replace(/[\s-]/g, "")).filter(Boolean);
    const bad = items.findIndex((x) => !/^\+[1-9][0-9]{6,14}$/.test(x));
    if (bad >= 0) {
      // The position, not the number: a startup error is logged and a blocked number is personal data.
      ctx.addIssue({ code: "custom", message: `TASK_CALL_BLOCKED_NUMBERS: entry ${bad + 1} is not an E.164 number such as +48221234567` });
      return z.NEVER;
    }
    return [...new Set(items)];
  }),
  // Prices for the parts Twilio and ElevenLabs don't report per call. Unset = that cost is "unknown".
  PRICE_TWILIO_TRANSCRIPTION_USD_PER_MIN: z.coerce.number().positive().max(1).optional(),
  PRICE_TWILIO_CONFERENCE_USD_PER_PARTICIPANT_MIN: z.coerce.number().positive().max(1).optional(),
  PRICE_ELEVENLABS_USD_PER_CREDIT: z.coerce.number().positive().max(1).optional(),
  // Twilio's own voice for the short fixed lines (apology, goodbye, "przekazuję rozmowę").
  TASK_CALL_SAY_VOICE: z.string().regex(/^[A-Za-z0-9.\-]{1,40}$/).default("Polly.Ewa"),

  // Errands (ADR-570, docs/implementation/ERRANDS.md): Doddy researches a task in the background.
  // Off by default ("0" refuses new errands and starts no queued one); "1" runs them when
  // ANTHROPIC_API_KEY and MEMORY_ENCRYPTION_KEY are set too.
  ERRANDS_ENABLED: z.enum(["0", "1"]).default("0"),
  ERRANDS_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-opus-5-5"),
  ERRANDS_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("high"),
  // A stuck run ends as failed: time_limit instead of running forever. Not a cap on look-ups.
  ERRAND_TIME_LIMIT_MINUTES: z.coerce.number().int().min(1).max(120).default(30),
  // Queued or running errands per account.
  ERRANDS_MAX_OPEN: z.coerce.number().int().min(1).max(20).default(5),
  // Approvals per UTC day (ADR-673): per account, and for the whole server, counted where deleting an
  // account can't give them back. Each errand can run Opus for up to ERRAND_TIME_LIMIT_MINUTES.
  ERRANDS_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(1000).default(10),
  ERRANDS_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(100000).default(30),
  // Of those, what accounts still new may approve together (ADR-702). 0: new accounts can't approve errands.
  ERRANDS_DAILY_NEW_ACCOUNTS: z.coerce.number().int().min(0).max(100000).default(DEFAULT_NEW_ACCOUNT_POOL.errands),
  // The research budget of one errand (ADR-702): web searches, web fetches, research requests (the first and each
  // resume after a pause) and output tokens over all of them. This narrows ADR-570's "no cap on look-ups": a limit of 0
  // means no limit and exists only for an owner who sets it on purpose. The time limit above still applies.
  ERRAND_MAX_SEARCHES: z.coerce.number().int().min(0).max(1000).default(DEFAULT_RESEARCH_BUDGET.maxSearches),
  ERRAND_MAX_FETCHES: z.coerce.number().int().min(0).max(1000).default(DEFAULT_RESEARCH_BUDGET.maxFetches),
  ERRAND_MAX_REQUESTS: z.coerce.number().int().min(0).max(1000).default(DEFAULT_RESEARCH_BUDGET.maxRequests),
  // Below 10000 a request couldn't say anything useful, so only 0 (no limit) or at least 10000 is accepted.
  ERRAND_MAX_OUTPUT_TOKENS: z.coerce.number().int().min(0).max(10_000_000).default(DEFAULT_RESEARCH_BUDGET.maxOutputTokens)
    .refine((n) => n === 0 || n >= 10_000, "ERRAND_MAX_OUTPUT_TOKENS must be 0 (no limit) or at least 10000"),
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
  // Affiliate links (ADR-612): {"shop host": "https template with one {url}"}. Empty by default, so no link is
  // tracked until the owner has a programme with a shop. See docs/implementation/SHOPPING.md.
  AFFILIATE_LINKS: z.string().default("").transform((v, ctx) => {
    try { return parseAffiliateRules(v); } catch (err) { ctx.addIssue({ code: "custom", message: (err as Error).message }); return z.NEVER; }
  }),
  // Leaflets (ADR-609, SHOPPING.md section 2): POST /v1/deals/search reads the official leaflets of
  // Biedronka, Lidl, Dino, Rossmann, Aldi and Żabka on request (ADR-660) and keeps only counts. "0" answers 503 deals_disabled.
  // Image pages need ANTHROPIC_API_KEY (Claude Haiku reads them); the caps count requests per UTC day.
  DEALS_ENABLED: z.enum(["0", "1"]).default("0"),
  DEALS_VISION_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-haiku-5-5"),
  DEALS_MAX_PAGES: z.coerce.number().int().min(0).max(100).default(40),
  DEALS_SCREEN_PAGES: z.coerce.number().int().min(0).max(200).default(120),
  DEALS_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(1000).default(30),
  DEALS_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(100000).default(1000),
  // Of the server's requests, what accounts still new may use together (ADR-702).
  DEALS_DAILY_NEW_ACCOUNTS: z.coerce.number().int().min(0).max(100000).default(DEFAULT_NEW_ACCOUNT_POOL.deals),
  // "Search further" (ADR-666): {"shop name": "https search page with one {q}"}, shown in this order under every
  // leaflet answer. Empty: Allegro and Ceneo; {}: none. Links only, never fetched; AFFILIATE_LINKS wraps them.
  DEALS_SEARCH_SHOPS: z.string().default("").transform((v, ctx) => {
    try { return parseSearchShops(v); } catch (err) { ctx.addIssue({ code: "custom", message: (err as Error).message }); return z.NEVER; }
  }),

  // Price watches (shopping stage 2, docs/implementation/SHOPPING_WATCH.md): after one yes, the worker reads one shop
  // page about four times a day for 30 days and sends one push when the confirmed price is at or below the user's
  // number. No model is used. "0" (the default) answers 503 watches_disabled and checks nothing; it also needs
  // MEMORY_ENCRYPTION_KEY. WATCHES_MAX_OPEN is active watches per account; WATCHES_CHECK_HOURS is the time between
  // two checks of one watch (6 = the four checks a day the card promises; a shorter time checks more often than that).
  WATCHES_ENABLED: z.enum(["0", "1"]).default("0"),
  WATCHES_MAX_OPEN: z.coerce.number().int().min(1).max(20).default(5),
  WATCHES_CHECK_HOURS: z.coerce.number().int().min(6).max(24).default(6),

  // Messages (ADR-585, ADR-586): the app's typed conversation asks Claude here. Text only, no tools.
  // Runs only when ANTHROPIC_API_KEY is set too; "0" answers 503 notConfigured. The daily caps count
  // requests per account and for the whole server (UTC day) and can only be lowered below the ceilings.
  ASSISTANT_ENABLED: z.enum(["0", "1"]).default("0"),
  ASSISTANT_MODEL: z.string().regex(/^[a-z0-9][a-z0-9.\-]{1,63}$/).default("claude-haiku-5-5"),
  ASSISTANT_EFFORT: z.enum(["low", "medium", "high"]).default("medium"),
  ASSISTANT_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(1000).default(100),
  ASSISTANT_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(100000).default(1000),
  // Of the server's requests, what accounts still new may use together (ADR-702).
  ASSISTANT_DAILY_NEW_ACCOUNTS: z.coerce.number().int().min(0).max(100000).default(DEFAULT_NEW_ACCOUNT_POOL.assistant),

  // Studio (ADR-740, docs/implementation/STUDIO.md): research a topic, then make files from it. Off by
  // default; "1" also needs ANTHROPIC_API_KEY, MEMORY_ENCRYPTION_KEY and STUDIO_SKILLS.
  STUDIO_ENABLED: z.enum(["0", "1"]).default("0"),
  // Models per step (owner, 22 Oct: the all-Opus plan cost too much). Defaults: Haiku 5.5 plans, extracts
  // claims and renders; Sonnet 5.5 researches and writes. STUDIO_MODEL, when set, is the starting point for
  // every step; a STUDIO_MODEL_<STEP> then overrides that step.
  STUDIO_TIER: z.enum(PLAN_TIER_NAMES as [PlanTier, ...PlanTier[]]).optional(),
  STUDIO_MODEL: z.string().regex(MODEL_ID).optional(),
  STUDIO_MODEL_PLAN: z.string().regex(MODEL_ID).optional(),
  STUDIO_MODEL_RESEARCH: z.string().regex(MODEL_ID).optional(),
  STUDIO_MODEL_PACK: z.string().regex(MODEL_ID).optional(),
  STUDIO_MODEL_WRITE: z.string().regex(MODEL_ID).optional(),
  STUDIO_MODEL_MAKE: z.string().regex(MODEL_ID).optional(),
  // Doddy's custom skills: comma-separated skill ids, each optionally @version (scripts/studio_skills.sh upload).
  STUDIO_SKILLS: z.string().regex(/^[A-Za-z0-9_]+(@[A-Za-z0-9_.-]+)?(,[A-Za-z0-9_]+(@[A-Za-z0-9_.-]+)?)*$/).optional(),
  STUDIO_MAX_SEARCHES: z.coerce.number().int().min(1).max(50).default(15),
  STUDIO_MAX_FETCHES: z.coerce.number().int().min(1).max(50).default(15),
  // Comma-separated hostnames for web search and fetch to skip (content farms; owner decision).
  STUDIO_BLOCKED_DOMAINS: z.string().regex(/^[a-z0-9.-]+(,[a-z0-9.-]+)*$/).optional(),
  STUDIO_TASK_BUDGET_TOKENS: z.coerce.number().int().min(20_000).max(1_000_000).default(150_000),
  STUDIO_JOB_LIMIT_USD: z.coerce.number().positive().max(50).default(2),
  STUDIO_DAILY_CAP_USD: z.coerce.number().positive().max(500).default(3),
  STUDIO_TIME_LIMIT_MINUTES: z.coerce.number().int().min(5).max(60).default(20),
  STUDIO_MAX_OPEN: z.coerce.number().int().min(1).max(10).default(3),
  // The whole server's limits per UTC day, counted where deleting an item or an account can't give them back (ADR-742,
  // like ADR-673): approvals per account, approvals for the server, the share of those that accounts still new may use
  // (0, the default: new accounts can't start a Studio job, ADR-702), and the dollars the server may commit.
  // Each approval commits STUDIO_JOB_LIMIT_USD of STUDIO_DAILY_SERVER_CAP_USD until the job ends and its real cost is known.
  STUDIO_DAILY_PER_ACCOUNT: z.coerce.number().int().min(1).max(100).default(3),
  STUDIO_DAILY_PER_SERVER: z.coerce.number().int().min(1).max(1000).default(10),
  STUDIO_DAILY_NEW_ACCOUNTS: z.coerce.number().int().min(0).max(1000).default(DEFAULT_NEW_ACCOUNT_POOL.studio),
  STUDIO_DAILY_SERVER_CAP_USD: z.coerce.number().positive().max(5000).default(10),
  // The hard ceiling for a whole UTC calendar month, the most the server can ever commit to Studio (ADR-742). The owner
  // said "100usd cap" with no period; the safest reading is the month and all accounts together.
  STUDIO_MONTHLY_SERVER_CAP_USD: z.coerce.number().positive().max(100000).default(100),
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
  /** Numbers Doddy must not call for anyone (TASK_CALL_BLOCKED_NUMBERS, ADR-705). Absent: none. */
  blockedNumbers?: readonly string[];
}

export type ErrandEffort = "low" | "medium" | "high" | "xhigh" | "max";

/** Errand switches and limits. `enabled` is the env switch only; the key and cipher are checked where wired. */
export interface ErrandSettings {
  enabled: boolean; model: string; effort: ErrandEffort; timeLimitMinutes: number; maxOpen: number;
  dailyPerAccount: number; dailyPerServer: number;
  /** What accounts still new may approve together per UTC day, inside dailyPerServer (ADR-702). Absent: the default pool. */
  dailyForNewAccounts?: number;
  /** Hours after which an account without a verified phone number counts as established. Absent: 24. */
  newAccountHours?: number;
  /** Look-ups, requests and output tokens per errand (ADR-702). Absent: DEFAULT_RESEARCH_BUDGET. */
  budget?: ResearchBudget;
}

/** Shopping errands (ADR-607): the runner's model and the paid look-ups per errand. */
export interface ShoppingSettings {
  model: string; premiumModel: string; premiumAccountIds: string[];
  effort: ErrandEffort; maxOfferSearches: number; maxPageChecks: number; serperApiKey?: string;
  affiliateRules: AffiliateRule[];
}

/** Price watches: `enabled` is the env switch only; the cipher and the fetcher are checked where wired. */
export interface WatchSettings { enabled: boolean; maxOpen: number; checkHours: number }

/** Messages switches and caps (ADR-586). `enabled` is the env switch only; the key is checked where wired. */
export interface AssistantSettings {
  enabled: boolean; model: string; effort: "low" | "medium" | "high"; dailyPerAccount: number; dailyPerServer: number;
  /** What accounts still new may use together per UTC day, inside dailyPerServer (ADR-702). Absent: the default pool. */
  dailyForNewAccounts?: number;
  newAccountHours?: number;
}

/** The abuse limits that do not belong to one feature (ADR-702, ADR-704). Each has a safe default; Deps may override some. */
export interface AbuseLimits {
  accountsPerIpDay: number; accountsPerServerDay: number;
  verifyPerIpDay: number; verifyPerAccountDay: number;
  smsPerAccountDay: number; smsPerServerDay: number;
  outboundCallsPerServerDay: number;
  /** Calling codes without "+", see phoneCountries.ts. */
  allowedCountryCodes: readonly string[];
}

export const DEFAULT_ABUSE_LIMITS: AbuseLimits = {
  accountsPerIpDay: 50, accountsPerServerDay: 1000,
  verifyPerIpDay: 20, verifyPerAccountDay: 6,
  smsPerAccountDay: 30, smsPerServerDay: 300,
  outboundCallsPerServerDay: 20,
  allowedCountryCodes: DEFAULT_ALLOWED_COUNTRY_CODES,
};

/** The defaults with whatever a deployment (or a test) sets over them. */
export const abuseLimits = (over?: Partial<AbuseLimits>): AbuseLimits => ({ ...DEFAULT_ABUSE_LIMITS, ...over });

export interface Config {
  databaseUrl: string;
  port: number;
  trustProxyHops: number;
  verifyDailyCap: number;
  limits: AbuseLimits;
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
  /** "Search further" under a leaflet answer (ADR-666). */
  dealsSearchShops: SearchShop[];
  watchSettings: WatchSettings;
  assistantSettings: AssistantSettings;
  studioSettings: StudioSettings;
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
    limits: {
      accountsPerIpDay: e.ACCOUNTS_DAILY_PER_IP, accountsPerServerDay: e.ACCOUNTS_DAILY_PER_SERVER,
      verifyPerIpDay: e.VERIFY_DAILY_PER_IP, verifyPerAccountDay: e.VERIFY_DAILY_PER_ACCOUNT,
      smsPerAccountDay: e.SMS_DAILY_PER_ACCOUNT, smsPerServerDay: e.SMS_DAILY_PER_SERVER,
      outboundCallsPerServerDay: e.OUTBOUND_CALLS_DAILY_PER_SERVER,
      allowedCountryCodes: e.PHONE_ALLOWED_COUNTRY_CODES,
    },
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
      blockedNumbers: e.TASK_CALL_BLOCKED_NUMBERS,
    },
    errandSettings: {
      enabled: e.ERRANDS_ENABLED === "1",
      model: e.ERRANDS_MODEL,
      effort: e.ERRANDS_EFFORT,
      timeLimitMinutes: e.ERRAND_TIME_LIMIT_MINUTES,
      maxOpen: e.ERRANDS_MAX_OPEN,
      dailyPerAccount: e.ERRANDS_DAILY_PER_ACCOUNT,
      dailyPerServer: e.ERRANDS_DAILY_PER_SERVER,
      dailyForNewAccounts: e.ERRANDS_DAILY_NEW_ACCOUNTS,
      newAccountHours: e.NEW_ACCOUNT_HOURS,
      budget: {
        maxSearches: e.ERRAND_MAX_SEARCHES, maxFetches: e.ERRAND_MAX_FETCHES,
        maxRequests: e.ERRAND_MAX_REQUESTS, maxOutputTokens: e.ERRAND_MAX_OUTPUT_TOKENS,
      },
    },
    shoppingSettings: {
      model: e.SHOPPING_MODEL,
      premiumModel: e.SHOPPING_PREMIUM_MODEL,
      premiumAccountIds: e.SHOPPING_PREMIUM_ACCOUNTS,
      effort: e.SHOPPING_EFFORT,
      maxOfferSearches: e.SHOPPING_MAX_OFFER_SEARCHES,
      maxPageChecks: e.SHOPPING_MAX_PAGE_CHECKS,
      serperApiKey: e.SERPER_API_KEY,
      affiliateRules: e.AFFILIATE_LINKS,
    },
    dealsSettings: {
      enabled: e.DEALS_ENABLED === "1", visionModel: e.DEALS_VISION_MODEL, maxPages: e.DEALS_MAX_PAGES, screenPages: e.DEALS_SCREEN_PAGES,
      dailyPerAccount: e.DEALS_DAILY_PER_ACCOUNT, dailyPerServer: e.DEALS_DAILY_PER_SERVER,
      dailyForNewAccounts: e.DEALS_DAILY_NEW_ACCOUNTS, newAccountHours: e.NEW_ACCOUNT_HOURS,
    },
    dealsSearchShops: e.DEALS_SEARCH_SHOPS,
    watchSettings: { enabled: e.WATCHES_ENABLED === "1", maxOpen: e.WATCHES_MAX_OPEN, checkHours: e.WATCHES_CHECK_HOURS },
    assistantSettings: {
      enabled: e.ASSISTANT_ENABLED === "1",
      model: e.ASSISTANT_MODEL,
      effort: e.ASSISTANT_EFFORT,
      dailyPerAccount: e.ASSISTANT_DAILY_PER_ACCOUNT,
      dailyPerServer: e.ASSISTANT_DAILY_PER_SERVER,
      dailyForNewAccounts: e.ASSISTANT_DAILY_NEW_ACCOUNTS,
      newAccountHours: e.NEW_ACCOUNT_HOURS,
    },
    studioSettings: {
      enabled: e.STUDIO_ENABLED === "1",
      models: stepModelsFrom({
        plan: e.STUDIO_MODEL_PLAN, research: e.STUDIO_MODEL_RESEARCH, pack: e.STUDIO_MODEL_PACK,
        write: e.STUDIO_MODEL_WRITE, make: e.STUDIO_MODEL_MAKE,
      }, e.STUDIO_MODEL, e.STUDIO_TIER),
      skills: e.STUDIO_SKILLS ?? "",
      maxSearches: e.STUDIO_MAX_SEARCHES,
      maxFetches: e.STUDIO_MAX_FETCHES,
      blockedDomains: e.STUDIO_BLOCKED_DOMAINS ? e.STUDIO_BLOCKED_DOMAINS.split(",") : [],
      taskBudgetTokens: e.STUDIO_TASK_BUDGET_TOKENS,
      jobLimitUsd: e.STUDIO_JOB_LIMIT_USD,
      dailyCapUsd: e.STUDIO_DAILY_CAP_USD,
      timeLimitMinutes: e.STUDIO_TIME_LIMIT_MINUTES,
      maxOpen: e.STUDIO_MAX_OPEN,
      dailyPerAccount: e.STUDIO_DAILY_PER_ACCOUNT,
      dailyPerServer: e.STUDIO_DAILY_PER_SERVER,
      dailyForNewAccounts: e.STUDIO_DAILY_NEW_ACCOUNTS,
      newAccountHours: e.NEW_ACCOUNT_HOURS,
      dailyServerCapUsd: e.STUDIO_DAILY_SERVER_CAP_USD,
      monthlyServerCapUsd: e.STUDIO_MONTHLY_SERVER_CAP_USD,
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
  blockedNumbers: [],
};

/** Settings for an injected ErrandDeps without its own (tests): on, Opus 5.5 at high effort, 30 min, 5 open,
 * 10 approvals a day per account and 30 for the server.
 * The environment's ERRANDS_ENABLED defaults to "0": errands start only when the owner turns them on. */
export const DEFAULT_ERRAND_SETTINGS: ErrandSettings = {
  enabled: true, model: "claude-opus-5-5", effort: "high", timeLimitMinutes: 30, maxOpen: 5,
  dailyPerAccount: 10, dailyPerServer: 30,
  dailyForNewAccounts: DEFAULT_NEW_ACCOUNT_POOL.errands, newAccountHours: DEFAULT_NEW_ACCOUNT_HOURS, budget: DEFAULT_RESEARCH_BUDGET,
};

/** Settings for an injected WatchDeps without its own (tests): on, 5 open, a check every 6 hours.
 * The environment's WATCHES_ENABLED defaults to "0": watches run only when the owner turns them on. */
export const DEFAULT_WATCH_SETTINGS: WatchSettings = { enabled: true, maxOpen: 5, checkHours: 6 };

/** Settings for an injected AssistantDeps without its own (tests). The environment's ASSISTANT_ENABLED
 * defaults to "0": the typed conversation reaches Claude only when the owner turns it on. */
export const DEFAULT_ASSISTANT_SETTINGS: AssistantSettings = {
  enabled: true, model: "claude-haiku-5-5", effort: "medium", dailyPerAccount: 100, dailyPerServer: 1000,
  dailyForNewAccounts: DEFAULT_NEW_ACCOUNT_POOL.assistant, newAccountHours: DEFAULT_NEW_ACCOUNT_HOURS,
};
