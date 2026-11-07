import { createServer, type Server } from "node:http";
import { AccountEraser } from "./account.js";
import { AssistService } from "./assist.js";
import { AnyOfSessionVerifier, DevSessionVerifier, RevocableSessionVerifier, type SessionVerifier, SignedSessionVerifier, SupabaseSessionVerifier, TokenFloors } from "./auth.js";
import { defaultRegistry } from "./capabilities.js";
import type { Config } from "./config.js";
import { DeviceSessionIssuer } from "./deviceSession.js";
import { DocumentLinks } from "./documents.js";
import { AnthropicClaudeProvider, type ClaudeProvider, MockClaudeProvider } from "./tools/claude.js";
import { createHandler } from "./http.js";
import { MemoryChat } from "./memory/chat.js";
import { MemoryCipher } from "./memory/crypto.js";
import { MEMORY_KEPT_DAYS } from "./memory/contract.js";
import { MemoryService } from "./memory/service.js";
import { ThreadService } from "./messages/service.js";
import { CoinbaseCdpWallet } from "./payments/coinbase.js";
import { MockPaymentSeller } from "./payments/mockSeller.js";
import { PublicHttps, type SellerHttp } from "./payments/net.js";
import { PaymentsService } from "./payments/service.js";
import { MockPaymentWallet, type PaymentWallet } from "./payments/wallet.js";
import { ComposioCalendarProvider } from "./providers/composio.js";
import { MockCalendarProvider } from "./providers/mock.js";
import { UnconfiguredCalendarProvider, UnconfiguredToolsProvider } from "./providers/unconfigured.js";
import type { CalendarProvider } from "./providers/types.js";
import { ConnectedAppsService, PROVIDER as CALENDAR_PROVIDER } from "./service.js";
import { Store, SUPABASE_AUTH_CLEANUP } from "./store.js";
import { TOOLKITS } from "./tools/catalog.js";
import { ComposioToolsProvider } from "./tools/composio.js";
import { MockToolsProvider } from "./tools/mock.js";
import type { ToolsProvider } from "./tools/provider.js";
import { CloudToolsService } from "./tools/service.js";
import { MockWebSearchProvider, MonidWebSearchProvider, type WebSearchProvider } from "./tools/websearch.js";
import { AccountContext } from "./web/chatContext.js";
import { WebRoutes } from "./web/routes.js";
import { oldestKeptDay } from "./web/logbook.js";
import { REDEEM_LIMITS, SESSION_IDLE_MS, WebAuth } from "./web/sessions.js";
import { SocialSignIn, SupabaseUserRemover } from "./web/social.js";
import { WebStatic } from "./web/static.js";

/** Composition root: picks adapters strictly from validated config (mock never silently replaces live). */
export async function buildApp(
  config: Config,
  overrides: {
    provider?: CalendarProvider;
    toolsProvider?: ToolsProvider;
    webSearch?: WebSearchProvider | null;
    claude?: ClaudeProvider | null;
    /** The model that chats with a person's kept notes and conversations (ADR-603). */
    chatClaude?: ClaudeProvider | null;
    store?: Store;
    verifier?: SessionVerifier;
    paymentWallet?: PaymentWallet | null;
    sellerHttp?: SellerHttp;
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

  // A person's cut-off second (ADR-709): deleting the account ends every token issued before it, for
  // any verifier this server builds. A verifier handed in by a test is used as it is.
  const floors = new TokenFloors(store);
  const verifier: SessionVerifier = overrides.verifier ?? new RevocableSessionVerifier(sessionVerifier(config), floors);

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
  // invite codes, and a signing key (config checks both). Whether the first caller may claim a server
  // with no owner yet (ADR-707) and the invite limits (ADR-709) come from config.
  const deviceSessions =
    (config.deviceSignup !== "off" || config.deviceInviteCodes.length > 0) && config.sessionSigningKey
      ? new DeviceSessionIssuer(config.sessionSigningKey, {
          signup: config.deviceSignup,
          inviteCodes: config.deviceInviteCodes,
          store,
          ownerClaim: config.ownerClaim,
          inviteLimits: config.inviteLimits,
          log: (line) => process.stdout.write(`${JSON.stringify(line)}\n`),
        })
      : null;
  // Doddy Web (ADR-600): only when DODDY_WEB_ORIGIN is set.
  const webAuth = config.web
    ? new WebAuth(store, config.web.origin, config.web.trustProxy, { ...REDEEM_LIMITS, perClientPerQuarter: config.web.signInTriesPerClient })
    : null;
  // Notes and conversations kept on request, and chat over them (ADR-603). Without DODDY_MEMORY_KEY the
  // routes answer "not set up"; chat uses its own (smaller) model, live only with an Anthropic key.
  const log = (line: Record<string, unknown>) => process.stdout.write(`${JSON.stringify(line)}\n`);
  const memory = new MemoryService({ store, cipher: config.memoryKey ? new MemoryCipher(config.memoryKey) : null, log });
  const chatClaude =
    overrides.chatClaude !== undefined ? overrides.chatClaude : config.mode === "live" ? (config.chatClaude ? new AnthropicClaudeProvider(config.chatClaude) : null) : claude;
  // The chat also reads the account's other parts (ADR-604): Logbook, apps, documents, receipts.
  const account = new AccountContext({ store, memory, tools });
  const memoryChat = new MemoryChat({ memory, store, claude: chatClaude, limits: config.limits, account, log });
  // The Messages copy for the web, with the same key; without it the routes answer "not set up".
  const thread = new ThreadService({ store, cipher: config.memoryKey ? new MemoryCipher(config.memoryKey) : null, log });
  // Deleting the account (ADR-674): each connection is removed by the provider that made it, and
  // each linked Google or Apple sign-in at Supabase, with the secret key (ADR-818).
  const supabaseUsers = config.web?.social?.secretKey ? new SupabaseUserRemover(config.web.social.projectUrl, config.web.social.secretKey) : null;
  const accountEraser = new AccountEraser({
    store,
    removers: [
      { providers: [CALENDAR_PROVIDER], remove: (connectionId, signal) => provider.removeConnection({ connectionId, signal }) },
      { providers: Object.keys(TOOLKITS), remove: (connectionId, signal) => toolsProvider.removeConnection({ connectionId, signal }) },
      ...(supabaseUsers ? [supabaseUsers] : []),
    ],
    timeoutMs: config.limits.providerTimeoutMs,
    floors,
    log,
  });
  // Payments. Live: a wallet exists only when the owner chose and configured one (default: none, so
  // every payment route says "not set up"). Mock mode uses the demo wallet and the offline demo seller.
  const paymentWallet: PaymentWallet | null =
    overrides.paymentWallet !== undefined
      ? overrides.paymentWallet
      : config.mode === "mock"
        ? new MockPaymentWallet()
        : config.payments.wallet === "coinbase_cdp" && config.payments.cdp
          ? new CoinbaseCdpWallet(config.payments.cdp)
          : null;
  const payments = new PaymentsService({
    store,
    mode: config.mode,
    wallet: paymentWallet,
    http: overrides.sellerHttp ?? (config.mode === "mock" ? new MockPaymentSeller(config.payments.network) : new PublicHttps()),
    policy: {
      network: config.payments.network,
      maxPerPayment: config.payments.maxPerPayment,
      confirmAmount: config.payments.confirmAmount,
      userDaily: config.payments.userDaily,
      serviceDaily: config.payments.serviceDaily,
      allowedHosts: config.payments.allowedHosts,
    },
    limits: config.limits,
  });
  // Apple and Google on the web (ADR-818): only with the Supabase project's URL and publishable key.
  const social =
    config.web?.social && webAuth
      ? new SocialSignIn(store, webAuth, config.web.social, { appScheme: appScheme(config.appReturnUrl), trustProxy: config.web.trustProxy, log })
      : null;
  const web =
    config.web && webAuth
      ? {
          auth: webAuth,
          routes: new WebRoutes(webAuth, store, verifier, config.limits.maxBodyBytes, { service: memory, chat: memoryChat }, thread, social, accountEraser, deviceSessions),
          pages: new WebStatic(config.web.distDir, config.web.origin),
        }
      : null;
  // Ask Doddy (ADR-587): always routed; without an Anthropic key it says "not set up" (503).
  const assist = new AssistService({ store, claude, limits: config.limits, log: (line) => process.stdout.write(`${JSON.stringify(line)}\n`) });
  const handler = createHandler({
    service,
    tools,
    payments,
    verifier,
    deviceSessions,
    web,
    assist,
    account: accountEraser,
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
    void Promise.allSettled([
      service.sweepAbandoned(),
      tools.sweepAbandoned(),
      // ADR-818: a deleted person's Supabase sign-in, when the first try failed.
      ...(supabaseUsers ? [accountEraser.sweep([SUPABASE_AUTH_CLEANUP])] : []),
    ])
      .then(() => store.prune(Date.now()))
      .then(() => store.pruneDocuments(Date.now()))
      .then(() => store.pruneLogbook(oldestKeptDay(Date.now())))
      .then(() => store.pruneTokenFloors(Date.now()))
      .then(() => (web ? store.pruneWeb(Date.now(), SESSION_IDLE_MS) : 0))
      .catch(() => {}); // the store closed with the server; the next start sweeps again
    // Kept memory (ADR-603) is swept on its own, so a failure in the steps above can't skip it, and its
    // own failure is logged (the step's name only, never a row) instead of going unseen.
    const cutoff = Date.now() - MEMORY_KEPT_DAYS * 86_400_000;
    for (const [step, sweep] of [
      ["conversations", () => store.pruneMemoryConversations(cutoff)],
      ["notes", () => store.pruneMemoryNotes(cutoff)],
      ["messages", () => store.pruneMessageThreads(cutoff)],
    ] as const) {
      sweep().catch(() => log({ level: "warn", event: "memory_sweep_failed", step }));
    }
  };
  housekeeping();
  const pruning = setInterval(housekeeping, 3_600_000);
  pruning.unref();
  server.on("close", () => clearInterval(pruning));
  return { server, store, service, tools, payments, provider, assist };
}

/** Which sign-ins this server accepts (ADR-526). */
export function sessionVerifier(config: Config): SessionVerifier {
  if (config.authMode === "dev") return new DevSessionVerifier();
  if (config.authMode === "signed") return new SignedSessionVerifier(config.sessionSigningKey!);
  const supabase = new SupabaseSessionVerifier({ projectUrl: config.supabaseUrl! });
  // Development only (config enforces it): the owner's minted token still works next to Supabase.
  return config.sessionSigningKey ? new AnyOfSessionVerifier([new SignedSessionVerifier(config.sessionSigningKey), supabase]) : supabase;
}

/** The iPhone's own URL scheme, where its Apple or Google sign-in sheet ends (ADR-818): DODDY_APP_RETURN_URL's when it is a doddy scheme. */
export function appScheme(appReturnUrl: string): string {
  const scheme = new URL(appReturnUrl).protocol.slice(0, -1);
  return /^doddy(-[a-z]+)?$/.test(scheme) ? scheme : "doddy";
}
