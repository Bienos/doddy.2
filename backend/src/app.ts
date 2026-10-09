import { createServer, type Server } from "node:http";
import { DevSessionVerifier, type SessionVerifier, SignedSessionVerifier } from "./auth.js";
import { defaultRegistry } from "./capabilities.js";
import type { Config } from "./config.js";
import { createHandler } from "./http.js";
import { ComposioCalendarProvider } from "./providers/composio.js";
import { MockCalendarProvider } from "./providers/mock.js";
import type { CalendarProvider } from "./providers/types.js";
import { ConnectedAppsService } from "./service.js";
import { Store } from "./store.js";

/** Composition root: picks adapters strictly from validated config (mock never silently replaces live). */
export function buildApp(config: Config, overrides: { provider?: CalendarProvider } = {}) {
  const store = new Store(config.dbPath);
  let provider: CalendarProvider;
  if (overrides.provider) provider = overrides.provider;
  else if (config.mode === "live") {
    if (!config.composio) throw new Error("live mode without Composio settings");
    provider = new ComposioCalendarProvider(config.composio);
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
    completionMode: provider.mode === "mock" ? "mock" : config.composio!.completionMode,
  });
  const handler = createHandler({ service, verifier, appReturnUrl: config.appReturnUrl, maxBodyBytes: config.limits.maxBodyBytes });
  const server: Server = createServer((req, res) => void handler(req, res));
  server.requestTimeout = 20_000;
  server.headersTimeout = 10_000;
  return { server, store, service, provider };
}
