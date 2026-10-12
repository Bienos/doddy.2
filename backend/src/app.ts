import { createServer, type Server } from "node:http";
import { DevSessionVerifier, type SessionVerifier, SignedSessionVerifier } from "./auth.js";
import { defaultRegistry } from "./capabilities.js";
import type { Config } from "./config.js";
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
import { MockWebSearchProvider, MonidWebSearchProvider, OpenAIWebSearchProvider, type WebSearchProvider } from "./tools/websearch.js";

/** Composition root: picks adapters strictly from validated config (mock never silently replaces live). */
export function buildApp(
  config: Config,
  overrides: { provider?: CalendarProvider; toolsProvider?: ToolsProvider; webSearch?: WebSearchProvider | null } = {},
) {
  const store = new Store(config.dbPath);
  let provider: CalendarProvider;
  if (overrides.provider) provider = overrides.provider;
  else if (config.mode === "live") {
    // Live without Composio (web search only): the calendar says "not set up", never demo data.
    provider = config.composio ? new ComposioCalendarProvider(config.composio) : new UnconfiguredCalendarProvider();
  } else provider = new MockCalendarProvider();

  const verifier: SessionVerifier =
    config.authMode === "signed" ? new SignedSessionVerifier(config.sessionSigningKey!) : new DevSessionVerifier();

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
  // Web search: live only with the chosen provider's key (otherwise "not set up"); mock mode uses
  // offline demo results.
  const webSearch =
    overrides.webSearch !== undefined
      ? overrides.webSearch
      : config.mode === "live"
        ? liveWebSearch(config)
        : new MockWebSearchProvider();
  const tools = new CloudToolsService({
    store,
    provider: toolsProvider,
    webSearch,
    limits: config.limits,
    publicBaseUrl: config.publicBaseUrl,
    appReturnUrl: config.appReturnUrl,
    completionMode: toolsProvider.mode === "mock" ? "mock" : (config.composio?.completionMode ?? "verifier"),
  });
  const handler = createHandler({ service, tools, verifier, appReturnUrl: config.appReturnUrl, maxBodyBytes: config.limits.maxBodyBytes });
  // Last line of defence: a handler failure closes that one connection, never the process.
  const server: Server = createServer((req, res) => {
    handler(req, res).catch(() => res.destroy());
  });
  server.requestTimeout = 20_000;
  server.headersTimeout = 10_000;
  // Retention: once at start, then hourly while the server runs.
  store.prune(Date.now());
  const pruning = setInterval(() => store.prune(Date.now()), 3_600_000);
  pruning.unref();
  server.on("close", () => clearInterval(pruning));
  return { server, store, service, tools, provider };
}

function liveWebSearch(config: Config): WebSearchProvider | null {
  if (config.webSearchProvider === "openai" && config.openai) return new OpenAIWebSearchProvider(config.openai);
  if (config.webSearchProvider === "monid" && config.monid) return new MonidWebSearchProvider(config.monid);
  return null;
}
