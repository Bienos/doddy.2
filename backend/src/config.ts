import { z } from "zod";

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

  let composio: ComposioSettings | null = null;
  if (e.DODDY_MODE === "live") {
    if (e.DODDY_ENV === "production") {
      // The only session mechanism built is an owner-minted signed token. A public release needs a
      // vetted sign-in (e.g. Sign in with Apple) first; until then production live mode is refused.
      problems.push("DODDY_MODE=live with DODDY_ENV=production is blocked until real app sign-in exists");
    }
    if (e.DODDY_AUTH_MODE !== "signed") problems.push("DODDY_MODE=live requires DODDY_AUTH_MODE=signed");
    const missing = (
      [
        "COMPOSIO_API_KEY",
        "COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID",
        "COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION",
      ] as const
    ).filter((name) => !e[name] || e[name]!.trim() === "");
    for (const name of missing) problems.push(`${name} is required in live mode`);
    if (e.COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION && !/^\d{8}_\d{2}$/.test(e.COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION)) {
      problems.push("COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION must be a pinned version like 20250909_00, not 'latest'");
    }
    if (e.COMPOSIO_COMPLETION_MODE === "callback" && e.DODDY_ENV !== "development") {
      problems.push("COMPOSIO_COMPLETION_MODE=callback is only allowed for single-owner development; use verifier");
    }
    if (missing.length === 0) {
      composio = {
        apiKey: e.COMPOSIO_API_KEY!,
        authConfigId: e.COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID!,
        toolkitVersion: e.COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION!,
        completionMode: e.COMPOSIO_COMPLETION_MODE,
      };
    }
  }

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
    limits: {
      userDailyReads: e.DODDY_LIMIT_USER_DAILY_READS,
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

/** Defaults used by tests; never read from the environment. */
export function testLimits(overrides: Partial<Limits> = {}): Limits {
  return {
    userDailyReads: 30,
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
