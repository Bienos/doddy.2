import { z } from "zod";
import { CdpKeyError, type CdpSettings, loadCdpKeys } from "./payments/coinbase.js";
import { NETWORK_IDS, type NetworkId, parseUsdc } from "./payments/x402.js";
import { TOOLKIT_IDS, type ToolkitId } from "./tools/catalog.js";
import { MONID_DEFAULT_BASE_URL } from "./tools/websearch.js";

/**
 * Environment configuration. Every value is read once at start-up and validated.
 * Live mode fails closed: a missing or malformed live prerequisite stops the server
 * instead of falling back to demo data. Error messages name variables, never values.
 */

export type Mode = "mock" | "live";
export type Env = "development" | "test" | "production";
export type AuthMode = "dev" | "signed";
export type CompletionMode = "verifier" | "callback";

export interface Limits {
  userDailyReads: number;
  /** Online-account tool runs (Gmail, Drive, Notion, Todoist, Outlook) per user per UTC day. */
  userDailyToolRuns: number;
  /** Web searches (Monid, paid by Doddy) per user, and for the whole service, per UTC day. */
  userDailyWebSearches: number;
  serviceDailyWebSearches: number;
  serviceDailyCalls: number;
  serviceMonthlyCalls: number;
  userConcurrency: number;
  serviceConcurrency: number;
  providerTimeoutMs: number;
  maxPages: number;
  pageSize: number;
  maxEvents: number;
  attemptTtlSeconds: number;
  maxBodyBytes: number;
}

export interface ComposioSettings {
  apiKey: string;
  authConfigId: string;
  toolkitVersion: string;
  completionMode: CompletionMode;
}

/** One online account (toolkit) that is set up on this server. Absent from the map: not set up. */
export interface ToolkitSettings {
  authConfigId: string;
  toolkitVersion: string;
}

/** Monid web search. Absent: web search shows as "not set up" and never runs. */
export interface MonidSettings {
  apiKey: string;
  baseUrl: string;
}

/**
 * Paying for things (x402). Off unless the owner sets a wallet: `wallet: "none"` is the default and
 * means no payment route can run. The Coinbase wallet is one optional choice, never an implied one.
 * Amounts are atomic USDC units (6 decimals).
 */
export interface PaymentsSettings {
  wallet: "none" | "coinbase_cdp";
  /** Defaults to the Base test network: real money needs an explicit `base`. */
  network: NetworkId;
  maxPerPayment: number;
  /** From this amount up, the person must also type the amount to confirm (enforced by the server). */
  confirmAmount: number;
  userDaily: number;
  serviceDaily: number;
  /** Empty: any public https site. Each payment still needs its own approval. */
  allowedHosts: string[];
  /** Live mode with wallet "coinbase_cdp" only. */
  cdp: CdpSettings | null;
}

export interface Config {
  mode: Mode;
  env: Env;
  host: string;
  port: number;
  publicBaseUrl: string;
  appReturnUrl: string;
  dbPath: string;
  authMode: AuthMode;
  sessionSigningKey: Buffer | null;
  composio: ComposioSettings | null;
  /** Gmail, Drive, Notion, Todoist, Outlook: only toolkits with both an auth config and a pinned version. */
  toolkits: Partial<Record<ToolkitId, ToolkitSettings>>;
  /** Live mode only; mock mode uses the offline demo search. */
  monid: MonidSettings | null;
  payments: PaymentsSettings;
  limits: Limits;
}

export class ConfigError extends Error {
  constructor(readonly problems: string[]) {
    super(`Invalid configuration: ${problems.join("; ")}`);
    this.name = "ConfigError";
  }
}

const LOOPBACK_HOSTS = new Set(["127.0.0.1", "::1", "localhost"]);

export function isLoopbackHost(host: string): boolean {
  return LOOPBACK_HOSTS.has(host);
}

function isLoopbackUrl(url: URL): boolean {
  return isLoopbackHost(url.hostname.replace(/^\[|\]$/g, ""));
}

const intSetting = (fallback: number, min: number, max: number) =>
  z.preprocess(
    (v) => (v === undefined || v === "" ? fallback : Number(v)),
    z.number().int().min(min).max(max),
  );

const EnvSchema = z.object({
  DODDY_MODE: z.enum(["mock", "live"]).default("mock"),
  DODDY_ENV: z.enum(["development", "test", "production"]).default("development"),
  DODDY_HOST: z.string().min(1).default("127.0.0.1"),
  DODDY_PORT: intSetting(8787, 1, 65535),
  DODDY_PUBLIC_BASE_URL: z.string().optional(),
  DODDY_APP_RETURN_URL: z.string().default("doddy-dev://connected-apps/return"),
  DODDY_DB_PATH: z.string().min(1).default("./data/doddy-backend.sqlite"),
  DODDY_AUTH_MODE: z.enum(["dev", "signed"]).default("dev"),
  DODDY_SESSION_SIGNING_KEY: z.string().optional(),
  COMPOSIO_API_KEY: z.string().optional(),
  COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID: z.string().optional(),
  COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: z.string().optional(),
  COMPOSIO_COMPLETION_MODE: z.enum(["verifier", "callback"]).default("verifier"),
  DODDY_LIMIT_USER_DAILY_READS: intSetting(30, 1, 10_000),
  DODDY_LIMIT_USER_DAILY_TOOL_RUNS: intSetting(100, 1, 10_000),
  COMPOSIO_GMAIL_AUTH_CONFIG_ID: z.string().optional(),
  COMPOSIO_GMAIL_TOOLKIT_VERSION: z.string().optional(),
  COMPOSIO_GOOGLEDRIVE_AUTH_CONFIG_ID: z.string().optional(),
  COMPOSIO_GOOGLEDRIVE_TOOLKIT_VERSION: z.string().optional(),
  COMPOSIO_NOTION_AUTH_CONFIG_ID: z.string().optional(),
  COMPOSIO_NOTION_TOOLKIT_VERSION: z.string().optional(),
  COMPOSIO_TODOIST_AUTH_CONFIG_ID: z.string().optional(),
  COMPOSIO_TODOIST_TOOLKIT_VERSION: z.string().optional(),
  COMPOSIO_OUTLOOK_AUTH_CONFIG_ID: z.string().optional(),
  COMPOSIO_OUTLOOK_TOOLKIT_VERSION: z.string().optional(),
  MONID_API_KEY: z.string().optional(),
  MONID_BASE_URL: z.string().default(MONID_DEFAULT_BASE_URL),
  DODDY_PAYMENTS_WALLET: z.enum(["none", "coinbase_cdp"]).default("none"),
  DODDY_PAYMENTS_NETWORK: z.enum(NETWORK_IDS).default("base-sepolia"),
  DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC: z.string().default("0.25"),
  DODDY_PAYMENTS_CONFIRM_AMOUNT_USDC: z.string().default("0.10"),
  DODDY_PAYMENTS_USER_DAILY_USDC: z.string().default("1.00"),
  DODDY_PAYMENTS_SERVICE_DAILY_USDC: z.string().default("5.00"),
  DODDY_PAYMENTS_ALLOWED_HOSTS: z.string().default(""),
  CDP_API_KEY_ID: z.string().optional(),
  CDP_API_KEY_SECRET: z.string().optional(),
  CDP_WALLET_SECRET: z.string().optional(),
  CDP_PAYMENT_ACCOUNT_ADDRESS: z.string().optional(),
  DODDY_LIMIT_USER_DAILY_WEB_SEARCHES: intSetting(30, 1, 10_000),
  DODDY_LIMIT_SERVICE_DAILY_WEB_SEARCHES: intSetting(200, 1, 100_000),
  DODDY_LIMIT_SERVICE_DAILY_CALLS: intSetting(300, 1, 1_000_000),
  DODDY_LIMIT_SERVICE_MONTHLY_CALLS: intSetting(3_000, 1, 10_000_000),
  DODDY_LIMIT_USER_CONCURRENCY: intSetting(1, 1, 10),
  DODDY_LIMIT_SERVICE_CONCURRENCY: intSetting(4, 1, 100),
  DODDY_PROVIDER_TIMEOUT_MS: intSetting(10_000, 1_000, 60_000),
  DODDY_MAX_PAGES: intSetting(3, 1, 10),
  DODDY_PAGE_SIZE: intSetting(50, 1, 250),
  DODDY_MAX_EVENTS: intSetting(100, 1, 500),
  DODDY_ATTEMPT_TTL_SECONDS: intSetting(600, 60, 3_600),
});

/** Custom scheme (`doddy-dev://…`) or https. No query, no fragment: the server adds its own parameters. */
function validateReturnUrl(raw: string, problems: string[]): void {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    problems.push("DODDY_APP_RETURN_URL is not a URL");
    return;
  }
  const customScheme = /^doddy(-[a-z]+)?:$/.test(url.protocol);
  if (!customScheme && url.protocol !== "https:") {
    problems.push("DODDY_APP_RETURN_URL must use https or a doddy custom scheme");
  }
  if (url.search || url.hash) problems.push("DODDY_APP_RETURN_URL must not contain a query or fragment");
}

export function loadConfig(source: NodeJS.ProcessEnv = process.env): Config {
  const parsed = EnvSchema.safeParse(source);
  if (!parsed.success) {
    throw new ConfigError(parsed.error.issues.map((i) => `${i.path.join(".")} is invalid`));
  }
  const e = parsed.data;
  const problems: string[] = [];

  validateReturnUrl(e.DODDY_APP_RETURN_URL, problems);

  const publicBaseUrl = e.DODDY_PUBLIC_BASE_URL ?? `http://${e.DODDY_HOST}:${e.DODDY_PORT}`;
  try {
    const url = new URL(publicBaseUrl);
    if (url.protocol !== "https:" && !(url.protocol === "http:" && isLoopbackUrl(url))) {
      problems.push("DODDY_PUBLIC_BASE_URL must be https outside loopback development");
    }
    if (url.pathname !== "/" || url.search || url.hash) {
      problems.push("DODDY_PUBLIC_BASE_URL must be an origin without a path");
    }
  } catch {
    problems.push("DODDY_PUBLIC_BASE_URL is not a URL");
  }

  // Test identities exist only for loopback mock runs. They can never authenticate a live request.
  if (e.DODDY_AUTH_MODE === "dev") {
    if (e.DODDY_MODE !== "mock") problems.push("DODDY_AUTH_MODE=dev is only allowed with DODDY_MODE=mock");
    if (e.DODDY_ENV === "production") problems.push("DODDY_AUTH_MODE=dev is not allowed in production");
    if (!isLoopbackHost(e.DODDY_HOST)) problems.push("DODDY_AUTH_MODE=dev requires a loopback DODDY_HOST");
  }

  let sessionSigningKey: Buffer | null = null;
  if (e.DODDY_AUTH_MODE === "signed") {
    const key = e.DODDY_SESSION_SIGNING_KEY ? Buffer.from(e.DODDY_SESSION_SIGNING_KEY, "base64") : null;
    if (!key || key.length < 32) {
      problems.push("DODDY_SESSION_SIGNING_KEY must be base64 of at least 32 random bytes");
    } else {
      sessionSigningKey = key;
    }
  }

  // Live mode needs Composio (accounts) or Monid (web search), or both. Composio is optional: a
  // server can run web search only, and the accounts then show "Not set up" (never demo data).
  let composio: ComposioSettings | null = null;
  const composioNames = ["COMPOSIO_API_KEY", "COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID", "COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION"] as const;
  const composioGiven = composioNames.some((name) => (e[name] ?? "").trim() !== "");
  if (e.DODDY_MODE === "live") {
    if (e.DODDY_ENV === "production") {
      // The only session mechanism built is an owner-minted signed token. A public release needs a
      // vetted sign-in (e.g. Sign in with Apple) first; until then production live mode is refused.
      problems.push("DODDY_MODE=live with DODDY_ENV=production is blocked until real app sign-in exists");
    }
    if (e.DODDY_AUTH_MODE !== "signed") problems.push("DODDY_MODE=live requires DODDY_AUTH_MODE=signed");
    if (!composioGiven && (e.MONID_API_KEY ?? "").trim() === "") {
      problems.push("DODDY_MODE=live needs Composio (COMPOSIO_API_KEY and the Google Calendar pair) or MONID_API_KEY");
    }
    // Half a Composio setup is a mistake, not a feature: all three or none.
    const missing = composioGiven ? composioNames.filter((name) => !e[name] || e[name]!.trim() === "") : [];
    for (const name of missing) problems.push(`${name} is required when Composio is set up in live mode`);
    if (e.COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION && !/^\d{8}_\d{2}$/.test(e.COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION)) {
      problems.push("COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION must be a pinned version like 20250909_00, not 'latest'");
    }
    if (e.COMPOSIO_COMPLETION_MODE === "callback" && e.DODDY_ENV !== "development") {
      problems.push("COMPOSIO_COMPLETION_MODE=callback is only allowed for single-owner development; use verifier");
    }
    if (composioGiven && missing.length === 0) {
      composio = {
        apiKey: e.COMPOSIO_API_KEY!,
        authConfigId: e.COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID!,
        toolkitVersion: e.COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION!,
        completionMode: e.COMPOSIO_COMPLETION_MODE,
      };
    }
  }

  // Online accounts. Each toolkit needs both values; half a setup is a mistake, not a feature.
  const toolkits: Partial<Record<ToolkitId, ToolkitSettings>> = {};
  for (const id of TOOLKIT_IDS) {
    const prefix = `COMPOSIO_${id.toUpperCase()}`;
    const authConfigId = (source[`${prefix}_AUTH_CONFIG_ID`] ?? "").trim();
    const toolkitVersion = (source[`${prefix}_TOOLKIT_VERSION`] ?? "").trim();
    if (authConfigId === "" && toolkitVersion === "") continue;
    if (e.DODDY_MODE !== "live") continue; // mock mode never uses Composio settings
    if (authConfigId === "") problems.push(`${prefix}_AUTH_CONFIG_ID is required when ${prefix}_TOOLKIT_VERSION is set`);
    else if (toolkitVersion === "") problems.push(`${prefix}_TOOLKIT_VERSION is required when ${prefix}_AUTH_CONFIG_ID is set`);
    else if (!/^\d{8}_\d{2}$/.test(toolkitVersion)) problems.push(`${prefix}_TOOLKIT_VERSION must be a pinned version like 20250909_00, not 'latest'`);
    else if (!e.COMPOSIO_API_KEY) problems.push("COMPOSIO_API_KEY is required in live mode");
    else toolkits[id] = { authConfigId, toolkitVersion };
  }

  // Web search. Optional in live mode; mock mode never calls Monid.
  let monid: MonidSettings | null = null;
  const monidKey = (e.MONID_API_KEY ?? "").trim();
  if (e.DODDY_MODE === "live" && monidKey !== "") {
    if (!/^monid_[a-z]+_[A-Za-z0-9_-]{8,}$/.test(monidKey)) problems.push("MONID_API_KEY must look like monid_<stage>_<secret>");
    let base: URL | null = null;
    try {
      base = new URL(e.MONID_BASE_URL);
    } catch {
      problems.push("MONID_BASE_URL is not a URL");
    }
    if (base && (base.protocol !== "https:" || base.pathname !== "/" || base.search || base.hash)) {
      problems.push("MONID_BASE_URL must be an https origin without a path");
    }
    if (base) monid = { apiKey: monidKey, baseUrl: base.origin };
  }

  const payments = loadPayments(e, problems);

  if (problems.length > 0) throw new ConfigError(problems);

  return {
    mode: e.DODDY_MODE,
    env: e.DODDY_ENV,
    host: e.DODDY_HOST,
    port: e.DODDY_PORT,
    publicBaseUrl: publicBaseUrl.replace(/\/$/, ""),
    appReturnUrl: e.DODDY_APP_RETURN_URL,
    dbPath: e.DODDY_DB_PATH,
    authMode: e.DODDY_AUTH_MODE,
    sessionSigningKey,
    composio,
    toolkits,
    monid,
    payments,
    limits: {
      userDailyReads: e.DODDY_LIMIT_USER_DAILY_READS,
      userDailyToolRuns: e.DODDY_LIMIT_USER_DAILY_TOOL_RUNS,
      userDailyWebSearches: e.DODDY_LIMIT_USER_DAILY_WEB_SEARCHES,
      serviceDailyWebSearches: e.DODDY_LIMIT_SERVICE_DAILY_WEB_SEARCHES,
      serviceDailyCalls: e.DODDY_LIMIT_SERVICE_DAILY_CALLS,
      serviceMonthlyCalls: e.DODDY_LIMIT_SERVICE_MONTHLY_CALLS,
      userConcurrency: e.DODDY_LIMIT_USER_CONCURRENCY,
      serviceConcurrency: e.DODDY_LIMIT_SERVICE_CONCURRENCY,
      providerTimeoutMs: e.DODDY_PROVIDER_TIMEOUT_MS,
      maxPages: e.DODDY_MAX_PAGES,
      pageSize: e.DODDY_PAGE_SIZE,
      maxEvents: e.DODDY_MAX_EVENTS,
      attemptTtlSeconds: e.DODDY_ATTEMPT_TTL_SECONDS,
      maxBodyBytes: 8 * 1024,
    },
  };
}

const HOSTNAME = /^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$/;

/**
 * Payments are strictly opt-in: wallet "none" (the default) leaves every payment route unavailable.
 * Mock mode never reads live wallet settings. Messages name variables, never values.
 */
function loadPayments(e: z.infer<typeof EnvSchema>, problems: string[]): PaymentsSettings {
  const amount = (name: string, value: string, min = 10_000): number => {
    const parsed = parseUsdc(value);
    if (parsed === null || parsed < min || parsed > 10_000 * 1_000_000) {
      problems.push(`${name} must be an amount of USDC between 0.01 and 10000, like 0.25`);
      return 0;
    }
    return parsed;
  };
  const maxPerPayment = amount("DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC", e.DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC);
  const confirmAmount = amount("DODDY_PAYMENTS_CONFIRM_AMOUNT_USDC", e.DODDY_PAYMENTS_CONFIRM_AMOUNT_USDC);
  const userDaily = amount("DODDY_PAYMENTS_USER_DAILY_USDC", e.DODDY_PAYMENTS_USER_DAILY_USDC);
  const serviceDaily = amount("DODDY_PAYMENTS_SERVICE_DAILY_USDC", e.DODDY_PAYMENTS_SERVICE_DAILY_USDC);
  if (maxPerPayment > userDaily && userDaily > 0) problems.push("DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC must not exceed DODDY_PAYMENTS_USER_DAILY_USDC");
  if (userDaily > serviceDaily && serviceDaily > 0) problems.push("DODDY_PAYMENTS_USER_DAILY_USDC must not exceed DODDY_PAYMENTS_SERVICE_DAILY_USDC");

  const allowedHosts = e.DODDY_PAYMENTS_ALLOWED_HOSTS.split(",").map((h) => h.trim().toLowerCase()).filter((h) => h !== "");
  if (allowedHosts.some((h) => !HOSTNAME.test(h))) problems.push("DODDY_PAYMENTS_ALLOWED_HOSTS must be comma-separated host names like example.com");

  let cdp: CdpSettings | null = null;
  const names = ["CDP_API_KEY_ID", "CDP_API_KEY_SECRET", "CDP_WALLET_SECRET", "CDP_PAYMENT_ACCOUNT_ADDRESS"] as const;
  if (e.DODDY_MODE === "live" && e.DODDY_PAYMENTS_WALLET === "coinbase_cdp") {
    const missing = names.filter((n) => (e[n] ?? "").trim() === "");
    for (const n of missing) problems.push(`${n} is required when DODDY_PAYMENTS_WALLET=coinbase_cdp`);
    if (missing.length === 0) {
      const candidate: CdpSettings = {
        apiKeyId: e.CDP_API_KEY_ID!.trim(),
        apiKeySecret: e.CDP_API_KEY_SECRET!.trim(),
        walletSecret: e.CDP_WALLET_SECRET!.trim(),
        accountAddress: e.CDP_PAYMENT_ACCOUNT_ADDRESS!.trim(),
      };
      try {
        loadCdpKeys(candidate);
        cdp = candidate;
      } catch (error) {
        problems.push(error instanceof CdpKeyError ? error.message : "the Coinbase wallet settings are invalid");
      }
    }
  }
  return {
    wallet: e.DODDY_PAYMENTS_WALLET,
    network: e.DODDY_PAYMENTS_NETWORK,
    maxPerPayment,
    confirmAmount,
    userDaily,
    serviceDaily,
    allowedHosts,
    cdp,
  };
}

/** Defaults used by tests; never read from the environment. */
export function testLimits(overrides: Partial<Limits> = {}): Limits {
  return {
    userDailyReads: 30,
    userDailyToolRuns: 100,
    userDailyWebSearches: 30,
    serviceDailyWebSearches: 200,
    serviceDailyCalls: 300,
    serviceMonthlyCalls: 3_000,
    userConcurrency: 1,
    serviceConcurrency: 4,
    providerTimeoutMs: 2_000,
    maxPages: 3,
    pageSize: 50,
    maxEvents: 100,
    attemptTtlSeconds: 600,
    maxBodyBytes: 8 * 1024,
    ...overrides,
  };
}
