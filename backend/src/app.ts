import { createServer, type Server } from "node:http";
import { AssistService } from "./assist.js";
import { AnyOfSessionVerifier, DevSessionVerifier, type SessionVerifier, SignedSessionVerifier, SupabaseSessionVerifier } from "./auth.js";
import { defaultRegistry } from "./capabilities.js";
import type { Config } from "./config.js";
import { DeviceSessionIssuer } from "./deviceSession.js";
import { DocumentLinks } from "./documents.js";
import { AnthropicClaudeProvider, type ClaudeProvider, MockClaudeProvider } from "./tools/claude.js";
import { createHandler } from "./http.js";
import { ComposioCalendarProvider } from "./providers/composio.js";
import { MockCalendarProvider } from "./providers/mock.js";
import { UnconfiguredCalendarProvider, UnconfiguredToolsProvider } from "./providers/unconfigured.js";
import type { CalendarProvider } from "./providers/types.js";
import { ConnectedAppsService } from "./service.js";
import { Store } from "./store.js";
import { ComposioToolsProvider } from "./tools/composio.js";
import { MockToolsProvider } from "./tools/mock.js";
import type { ToolsProvider } from "./tools/provider.js";
import { CloudToolsService } from "./tools/service.js";
import { MockWebSearchProvider, MonidWebSearchProvider, type WebSearchProvider } from "./tools/websearch.js";
import { WebRoutes } from "./web/routes.js";
import { oldestKeptDay } from "./web/logbook.js";
import { REDEEM_LIMITS, SESSION_IDLE_MS, WebAuth } from "./web/sessions.js";
import { WebStatic } from "./web/static.js";

/** Composition root: picks adapters strictly from validated config (mock never silently replaces live). */
export async function buildApp(
  config: Config,
  overrides: {
    provider?: CalendarProvider;
    toolsProvider?: ToolsProvider;
    webSearch?: WebSearchProvider | null;
    claude?: ClaudeProvider | null;
    store?: Store;
    verifier?: SessionVerifier;
  } = {},
) {
  const store =
    overrides.store ?? (await Store.open({ url: config.databaseUrl ?? undefined, caCert: config.databaseCaCert ?? undefined, dataDir: config.dbPath }));
  let provider: CalendarProvider;
  if (overrides.provider) provider = overrides.provider;
  else if (config.mode === "live") {
    // Live without Composio (web search only): the calendar says "not set up", never demo data.
    provider = config.composio ? new ComposioCalendarProvider(config.composio) : new UnconfiguredCalendarProvider();
  } else provider = new MockCalendarProvider();

  const verifier: SessionVerifier = overrides.verifier ?? sessionVerifier(config);

  const service = new ConnectedAppsService({
    store,
    provider,
    registry: defaultRegistry(),
    limits: config.limits,
    publicBaseUrl: config.publicBaseUrl,
    appReturnUrl: config.appReturnUrl,
    completionMode: provider.mode === "mock" ? "mock" : (config.composio?.completionMode ?? "verifier"),
  });
  // Online accounts. Live: only toolkits with their own settings are connectable; the rest say so.
  let toolsProvider: ToolsProvider;
  if (overrides.toolsProvider) toolsProvider = overrides.toolsProvider;
  else if (config.mode === "live") {
    toolsProvider = config.composio ? new ComposioToolsProvider(config.composio.apiKey, config.toolkits) : new UnconfiguredToolsProvider();
  }
  else toolsProvider = new MockToolsProvider();
  // Web search: live only with a Monid key (otherwise "not set up"); mock mode uses offline demo results.
  const webSearch =
    overrides.webSearch !== undefined
      ? overrides.webSearch
      : config.mode === "live"
        ? config.monid
          ? new MonidWebSearchProvider(config.monid)
          : null
        : new MockWebSearchProvider();
  // Claude (ADR-564): live only with an Anthropic key; mock mode uses offline demo text.
  const claude =
    overrides.claude !== undefined ? overrides.claude : config.mode === "live" ? (config.claude ? new AnthropicClaudeProvider(config.claude) : null) : new MockClaudeProvider();
  // Document links are signed with the session key; without one, make_document says "not set up".
  const documentLinks = config.sessionSigningKey ? new DocumentLinks(config.sessionSigningKey, config.publicBaseUrl) : null;
  const tools = new CloudToolsService({
    store,
    provider: toolsProvider,
    claude,
    documentLinks,
    webSearch,
    limits: config.limits,
    publicBaseUrl: config.publicBaseUrl,
    appReturnUrl: config.appReturnUrl,
    completionMode: toolsProvider.mode === "mock" ? "mock" : (config.composio?.completionMode ?? "verifier"),
    log: (line) => process.stdout.write(`${JSON.stringify(line)}\n`),
  });
  // Beta device sign-in (ADR-563): first-device, open (ADR-587: other iPhones get Ask Doddy only) or
  // invite codes, and a signing key (config checks both).
  const deviceSessions =
    (config.deviceSignup !== "off" || config.deviceInviteCodes.length > 0) && config.sessionSigningKey
      ? new DeviceSessionIssuer(config.sessionSigningKey, { signup: config.deviceSignup, inviteCodes: config.deviceInviteCodes, store })
      : null;
  // Doddy Web (ADR-585): only when DODDY_WEB_ORIGIN is set.
  const webAuth = config.web
    ? new WebAuth(store, config.web.origin, config.web.trustProxy, { ...REDEEM_LIMITS, perClientPerQuarter: config.web.signInTriesPerClient })
    : null;
  const web =
    config.web && webAuth
      ? { auth: webAuth, routes: new WebRoutes(webAuth, store, verifier, config.limits.maxBodyBytes), pages: new WebStatic(config.web.distDir, config.web.origin) }
      : null;
  // Ask Doddy (ADR-587): always routed; without an Anthropic key it says "not set up" (503).
  const assist = new AssistService({ store, claude, limits: config.limits, log: (line) => process.stdout.write(`${JSON.stringify(line)}\n`) });
  const handler = createHandler({
    service,
    tools,
    verifier,
    deviceSessions,
    web,
    assist,
    documents: documentLinks ? { links: documentLinks, store } : null,
    appReturnUrl: config.appReturnUrl,
    maxBodyBytes: config.limits.maxBodyBytes,
    trustProxy: config.trustProxy,
  });
  // Last line of defence: a handler failure closes that one connection, never the process.
  const server: Server = createServer((req, res) => {
    handler(req, res).catch(() => res.destroy());
  });
  server.requestTimeout = 20_000;
  server.headersTimeout = 10_000;
  // Retention and abandoned sign-ins: once at start, then hourly while the server runs. The sweep
  // runs first so an expired attempt's connection is queued for removal before prune drops the attempt.
  const housekeeping = () => {
    void Promise.allSettled([service.sweepAbandoned(), tools.sweepAbandoned()])
      .then(() => store.prune(Date.now()))
      .then(() => store.pruneDocuments(Date.now()))
      .then(() => store.pruneLogbook(oldestKeptDay(Date.now())))
      .then(() => (web ? store.pruneWeb(Date.now(), SESSION_IDLE_MS) : 0))
      .catch(() => {}); // the store closed with the server; the next start sweeps again
  };
  housekeeping();
  const pruning = setInterval(housekeeping, 3_600_000);
  pruning.unref();
  server.on("close", () => clearInterval(pruning));
  return { server, store, service, tools, provider, assist };
}

/** Which sign-ins this server accepts (ADR-526). */
export function sessionVerifier(config: Config): SessionVerifier {
  if (config.authMode === "dev") return new DevSessionVerifier();
  if (config.authMode === "signed") return new SignedSessionVerifier(config.sessionSigningKey!);
  const supabase = new SupabaseSessionVerifier({ projectUrl: config.supabaseUrl! });
  // Development only (config enforces it): the owner's minted token still works next to Supabase.
  return config.sessionSigningKey ? new AnyOfSessionVerifier([new SignedSessionVerifier(config.sessionSigningKey), supabase]) : supabase;
}
