import { randomUUID } from "node:crypto";
import { type CompleteRequest, CompleteRequestSchema, type ConnectionReason, type ConnectResponse, EmptyRequestSchema, type ReceiptStatus } from "../contracts.js";
import type { Limits } from "../config.js";
import { AppError, ProviderError } from "../errors.js";
import { argumentDigest, UsageLimiter } from "../policy.js";
import { AccessRequestSchema, type AppAccess, isAppsTool, toolsForAccess, translateAppsCall } from "./apps.js";
import { AskGate, type AskBinding, WEB_ACCOUNT } from "./askFirst.js";
import { ANTHROPIC_FILE_CLEANUP, type ApprovalRun, CLEANUP_RETRY, type ConnectionRow, type QueuedCleanup, type Store, stuckCleanupLine } from "../store.js";
import { isSupportedTimeZone } from "../time.js";
import {
  bindsTimeZone,
  CLOUD_TOOLS,
  type CloudToolDefinition,
  type Context,
  cloudTool,
  evaluateToolkitGrant,
  type GrantVerdict,
  type ResolvedTarget,
  TOOL_COPY,
  type ToolOutcome,
  TOOLKIT_IDS,
  TOOLKITS,
  type ToolkitId,
  toolHasGrant,
  READ_EMAIL,
  TRAVEL_GMAIL_FETCH,
} from "./catalog.js";
import {
  FLIGHTS_SECTION_ID,
  PrepareRequestSchema,
  type PrepareResult,
  RunRequestSchema,
  type RunResult,
  SwitchRequestSchema,
  type ToolReceipt,
  type ToolsCatalog,
  type ToolkitResult,
  type ToolkitView,
} from "./contracts.js";
import {
  ASK_CLAUDE_TIMEOUT_MS,
  ASK_CLAUDE_TOOL,
  AskClaudeInput,
  CLAUDE_SECTION_ID,
  type ClaudeProvider,
  type ClaudeToolName,
  type ProviderFileLedger,
  claudeCard,
  DOCUMENT_TIMEOUT_MS,
  fileName,
  isClaudeTool,
  KIND_INFO,
  MAKE_DOCUMENT_TOOL,
  MakeDocumentInput,
  type MakeDocumentArgs,
  MODEL_TEXT_LABEL,
} from "./claude.js";
import { judgeDocumentRequest, needDetailsMessage } from "./documentDetails.js";
import type { DocumentLinks } from "../documents.js";
import { UsageScope } from "../usageLedger.js";
import { MockWikimedia } from "../decks/demo.js";
import { DeckMaker } from "../decks/maker.js";
import { type Wikimedia, WikimediaClient } from "../decks/research.js";
import { MockToolsProvider, type ToolsMockScenario } from "./mock.js";
import { z } from "zod";
import { ClaudeTravelReader } from "../travel/claudeReader.js";
import { mergeBookings, type ReadEmail } from "../travel/merge.js";
import { MAX_TRAVEL_EMAILS, readTravelEmail, senderDomain, TRAVEL_GMAIL_QUERY, type TravelReader } from "../travel/reader.js";
import type { TravelBooking } from "../travel/schema.js";
import { FlightSearchError, type FlightSearch, MockFlightSearch } from "../travel/kiwi.js";
import {
  assumptions, BRIEF_JSON_SCHEMA, cleanBrief, EMPTY_BRIEF, missing, pickOptions, stayLinks, toQuery, TripBrief,
  UNDERSTAND_STEP, UNDERSTAND_SYSTEM, type Assumption, type Needed, type PlanLinks, type PlanOption,
} from "../travel/plan.js";
import type { DuffelClient } from "../flights/duffel.js";
import { type KiwiClient, KiwiTripSearch, KIWI_TIMEOUT_MS } from "../flights/kiwi.js";
import { FlightsService, isFlightTool } from "../flights/service.js";
import type { ToolsProvider } from "./provider.js";
import {
  normalizeWebSearch,
  WEB_SEARCH_COPY,
  WEB_SEARCH_TIMEOUT_MS,
  WEB_SEARCH_TOOL,
  WEB_SECTION,
  WEB_SECTION_ID,
  type WebSearchProvider,
  WebSearchInput,
  isMonidTool,
  MONID_TOOL_INPUT,
  MONID_TOOL_NAMES,
  MONID_TOOLS,
  monidCard,
  type MonidToolName,
  normalizeMonidTool,
} from "./websearch.js";

/** Web search and the other fixed Monid tools (ADR-489): no account, a switch each, Doddy pays. */
type WebTool = typeof WEB_SEARCH_TOOL | MonidToolName;
const isWebTool = (name: string): name is WebTool => name === WEB_SEARCH_TOOL || isMonidTool(name);
/**
 * Web lookups are on until the user switches them off (ADR-563). Before, every one started off and
 * the only switch was in a Settings screen the app could not reach without a hand-made server
 * token, so "what's the weather?" could never be answered. ASK-01 still asks before every search.
 */
const WEB_TOOLS_ON_BY_DEFAULT: ReadonlySet<WebTool> = new Set<WebTool>([WEB_SEARCH_TOOL, ...MONID_TOOL_NAMES]);
const webTitle = (tool: WebTool) => (tool === WEB_SEARCH_TOOL ? WEB_SEARCH_COPY.title : MONID_TOOLS[tool].title);

type SectionId = ToolkitId | typeof WEB_SECTION_ID | typeof CLAUDE_SECTION_ID | typeof FLIGHTS_SECTION_ID;
/** Claude runs have no account either; the approval is bound to this fixed account name. */
const CLAUDE_ACCOUNT = "claude";

/** How far back prepare looks for the same write (ADR-322). Approvals are kept a day past expiry. */
const EARLIER_WINDOW_MS = 86_400_000;

export interface ToolsServiceDeps {
  store: Store;
  provider: ToolsProvider;
  /** Web search through Monid. Null or absent: the section shows "not set up" and never runs. */
  webSearch?: WebSearchProvider | null;
  /** Claude (ADR-564). Null or absent: ask_claude and make_document say "not set up". */
  claude?: ClaudeProvider | null;
  /** The small model that reads booking emails for the trip screen. Absent: `claude`; null: "not set up". */
  travelClaude?: ClaudeProvider | null;
  /** Tests only: a reader instead of the model. */
  travelReader?: TravelReader;
  /** The trip planner's flights. Absent: Kiwi.com in live mode, the mock in mock mode. */
  flightSearch?: FlightSearch;
  /** Signed links for documents (ADR-564). Null: make_document says "not set up". */
  documentLinks?: DocumentLinks | null;
  /** Flights (decision 2026-11-11-flights-kiwi-search-duffel-booking). Absent: every flight tool says "not set up". */
  flights?: { kiwi: KiwiClient | null; duffel: DuffelClient | null; bookingEnabled: boolean; bookingWaitMs?: number } | null;
  /** Wikipedia and Commons for a deck's research (decision 2026-11-10-better-presentations). Absent: live in live mode, offline demo in mock mode. */
  wikimedia?: Wikimedia;
  limits: Limits;
  publicBaseUrl: string;
  appReturnUrl: string;
  completionMode: "verifier" | "callback" | "mock";
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
  /** Operational log (no tokens, no email content). Default: nothing. */
  log?: (line: Record<string, unknown>) => void;
}

/**
 * Online accounts through Composio: connect, per-tool on/off switches, read tools, and write tools
 * that run only with a fresh, single-use approval bound to the exact arguments the user saw.
 * Order for every run: signed-in owner -> known tool -> valid arguments -> switch on -> account
 * connected -> grants acceptable -> approval (writes) -> limits -> provider -> normalized result
 * -> receipt. The provider only ever receives arguments built by the tool's own `toArguments`.
 */
export class CloudToolsService {
  readonly mode: "mock" | "live";
  private readonly store: Store;
  private readonly provider: ToolsProvider;
  private readonly webSearch: WebSearchProvider | null;
  private readonly limits: Limits;
  private readonly limiter: UsageLimiter;
  /** ASK-01: the one place that decides whether a tool may run (askFirst.ts). */
  private readonly ask: AskGate;
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;
  /** Document jobs still running after their reply (ADR-564); tests wait on them. */
  private readonly background = new Set<Promise<void>>();
  /** Document jobs running now, per user and in all (ADR-710). Per process, like the provider slots in `UsageLimiter`. */
  private readonly documentJobs = new Map<string, number>();
  private documentJobsTotal = 0;
  /** Wikipedia and Commons for decks: live in live mode, offline in mock mode. */
  private readonly wikimedia: Wikimedia;
  /** Kiwi.com search and Duffel booking, on the same ASK-01 gate (flights/service.ts). */
  private readonly flights: FlightsService;

  constructor(private readonly deps: ToolsServiceDeps) {
    this.mode = deps.provider.mode;
    if ((deps.completionMode === "mock") !== (this.mode === "mock")) {
      throw new Error("mock completion is only valid with the mock provider");
    }
    this.store = deps.store;
    this.provider = deps.provider;
    this.webSearch = deps.webSearch ?? null;
    if (this.webSearch && this.webSearch.mode !== this.mode) throw new Error("web search and online accounts must both be mock or both live");
    this.wikimedia = deps.wikimedia ?? (this.mode === "live" ? new WikimediaClient() : new MockWikimedia());
    if (this.wikimedia.mode !== this.mode) throw new Error("Wikimedia and online accounts must both be mock or both live");
    this.limits = deps.limits;
    this.limiter = new UsageLimiter(deps.store, deps.limits);
    this.now = deps.now ?? Date.now;
    this.ask = new AskGate(deps.store, this.now);
    this.sleep = deps.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
    this.flights = new FlightsService({
      store: deps.store, ask: this.ask, limiter: this.limiter, mode: this.mode, now: this.now,
      kiwi: deps.flights?.kiwi ?? null, duffel: deps.flights?.duffel ?? null, bookingEnabled: deps.flights?.bookingEnabled ?? false,
      background: this.background, ...(deps.log ? { log: deps.log } : {}),
      ...(deps.flights?.bookingWaitMs !== undefined ? { bookingWaitMs: deps.flights.bookingWaitMs } : {}),
    });
  }

  /** A flight tool's receipts go under the "flights" section. */
  private flightReceipt(userId: string) {
    return (operation: "read" | "write", tool: string, status: ReceiptStatus, summary: string, errorCode: string | null, providerReference: string | null) =>
      this.receipt(userId, FLIGHTS_SECTION_ID, operation, tool, status, summary, errorCode, providerReference);
  }

  /** Demo scenarios exist only with the mock provider. */
  async applyMockScenario(userId: string, scenario: ToolsMockScenario | undefined): Promise<void> {
    if (scenario === undefined) return;
    if (!(this.provider instanceof MockToolsProvider)) {
      throw new AppError("invalid_request", { message: "Demo scenarios exist only in mock mode." });
    }
    this.provider.setScenario(await this.store.composioUserId(userId, this.now()), scenario);
  }

  // ---------------------------------------------------------------- queries

  async catalog(userId: string): Promise<ToolsCatalog> {
    const toolkits = await Promise.all(TOOLKIT_IDS.map((id) => this.view(userId, id)));
    return { mode: this.mode, toolkits: [...toolkits, await this.webView(userId)] };
  }

  async receipts(userId: string): Promise<ToolReceipt[]> {
    return (await this.store.toolReceipts(userId, 30)) as ToolReceipt[];
  }

  private async view(userId: string, id: ToolkitId): Promise<ToolkitView> {
    const def = TOOLKITS[id];
    const row = await this.store.getConnection(userId, id);
    const cleanup = await this.store.cleanupFor(userId, id);
    const enabled = await this.store.enabledTools(userId);
    const usable = row?.status === "connected" || row?.status === "error";
    const scopes = parseScopes(row);
    const status = !this.provider.isConfigured(id) ? "unavailable" : (row?.status ?? "disconnected");
    return {
      id,
      title: def.title,
      access: def.access,
      needsAccount: true,
      status,
      reason: row?.reason ?? null,
      connectedAt: row ? new Date(row.connected_at).toISOString() : null,
      remoteCleanup: cleanup ? cleanup.state : "none",
      tools: CLOUD_TOOLS.filter((t) => t.toolkit === id).map((t) => ({
        name: t.name,
        title: TOOL_COPY[t.name]?.title ?? t.name,
        blurb: TOOL_COPY[t.name]?.blurb ?? "",
        risk: t.risk,
        // A switch only counts while the account is connected with an acceptable grant.
        enabled: enabled.has(t.name) && usable && this.provider.isConfigured(id) && grantsOk(def, t, scopes),
      })),
    };
  }

  /** Web search has no account: it is "connected" whenever this server has Monid set up. */
  private async webView(userId: string): Promise<ToolkitView> {
    const configured = this.webSearch?.isConfigured() === true;
    const on = new Map<WebTool, boolean>();
    for (const name of [WEB_SEARCH_TOOL, ...MONID_TOOL_NAMES] as WebTool[]) on.set(name, await this.webToolOn(userId, name));
    const enabled = { has: (name: WebTool) => on.get(name) === true };
    return {
      id: WEB_SECTION_ID,
      title: WEB_SECTION.title,
      access: WEB_SECTION.access,
      needsAccount: false,
      status: configured ? "connected" : "unavailable",
      reason: null,
      connectedAt: null,
      remoteCleanup: "none",
      tools: [
        {
          name: WEB_SEARCH_TOOL,
          title: WEB_SEARCH_COPY.title,
          blurb: WEB_SEARCH_COPY.blurb,
          risk: "read",
          enabled: configured && enabled.has(WEB_SEARCH_TOOL),
        },
        ...MONID_TOOL_NAMES.map((name) => ({
          name,
          title: MONID_TOOLS[name].title,
          blurb: MONID_TOOLS[name].blurb,
          risk: "read" as const,
          enabled: configured && enabled.has(name),
        })),
      ],
    };
  }

  // ---------------------------------------------------------------- connect

  async connect(userId: string, toolkitId: string, body: unknown): Promise<ConnectResponse> {
    if (toolkitId === WEB_SECTION_ID) throw new AppError("invalid_request", { message: "Web search needs no sign-in. Switch it on instead." });
    const id = toolkit(toolkitId);
    parse(EmptyRequestSchema, body);
    this.requireConfigured(id);
    const existing = await this.store.getConnection(userId, id);
    if (existing?.status === "connected") {
      throw new AppError("invalid_request", { message: `${TOOLKITS[id].title} is already connected. Disconnect it first.` });
    }
    // Reconnecting replaces the old connection; a failed remote cleanup is retried first.
    if (existing || (await this.store.cleanupFor(userId, id))) {
      if ((await this.removeRemote(userId, id)) === "failed") {
        throw new AppError("provider_unavailable", {
          message: `The previous ${TOOLKITS[id].title} connection couldn't be removed yet, so a new one wasn't started. Try again shortly.`,
        });
      }
    }
    const now = this.now();
    const composioUserId = await this.store.composioUserId(userId, now);
    const attempt = await this.store.createAttempt({
      userId,
      provider: id,
      authConfigId: this.provider.authConfigId(id),
      now,
      ttlSeconds: this.limits.attemptTtlSeconds,
    });
    // The unfinished attempt this one replaces can still be finished at the provider: its connection goes.
    await this.removeQueued(attempt.superseded);
    const callbackUrl = `${this.deps.publicBaseUrl}/v1/oauth/return?attempt=${attempt.attemptId}`;
    const link = await this.limiter.withSlot(userId, async () => {
      if (this.mode === "live") await this.limiter.reserveToolRun(userId, now);
      try {
        return await this.provider.createConnectionLink({ toolkit: id, composioUserId, callbackUrl, signal: this.timeout() });
      } catch (error) {
        throw toAppError(error, TOOLKITS[id].title);
      }
    });
    if (!(await this.store.setPendingConnection(attempt.attemptId, link.pendingConnectionId, this.now()))) {
      // A newer Connect replaced this one while the link was made; this link must not be used.
      if (link.pendingConnectionId) await this.removeQueued([{ connectionId: link.pendingConnectionId, userId, provider: id }]);
      throw new AppError("attempt_invalid", { message: "A newer Connect replaced this one. Use the newest link." });
    }
    return {
      mode: this.mode,
      attemptId: attempt.attemptId,
      nonce: attempt.nonce,
      authorizationUrl: link.redirectUrl,
      callbackScheme: new URL(this.deps.appReturnUrl).protocol.replace(/:$/, ""),
      expiresAt: new Date(attempt.expiresAt).toISOString(),
    };
  }

  async complete(userId: string, toolkitId: string, body: unknown): Promise<ToolkitResult> {
    if (toolkitId === WEB_SECTION_ID) throw new AppError("invalid_request", { message: "Web search needs no sign-in." });
    const id = toolkit(toolkitId);
    const request = parse(CompleteRequestSchema, body);
    const title = TOOLKITS[id].title;
    const now = this.now();
    const attempt = await this.store.consumeAttempt({ attemptId: request.attemptId, userId, provider: id, nonce: request.nonce, now });
    if (!attempt) {
      // Too late: the user may have finished at the provider after the attempt expired. That
      // connection can never be completed, so it is removed instead of left live.
      await this.removeQueued(await this.store.expireAttempts(now, [id], userId));
      throw new AppError("attempt_invalid");
    }

    const composioUserId = await this.store.composioUserId(userId, now);
    const fail = async (errorCode: string, summary: string): Promise<never> => {
      throw new AppError("attempt_invalid", { message: summary, receipt: await this.receipt(userId, id, "connect", null, "failed", summary, errorCode, null) });
    };
    const done = async (status: ReceiptStatus, summary: string, errorCode: string | null = null): Promise<ToolkitResult> => {
      const receipt = await this.receipt(userId, id, "connect", null, status, summary, errorCode, null);
      return { toolkit: await this.view(userId, id), receipt };
    };

    // Every remote connection this completion touched that belongs to this user. Unless it ends
    // recorded as this user's connection, each is removed at the provider (or queued for removal),
    // so no grant stays live that Disconnect couldn't find. Never the unverified callback hint.
    const touched: (string | null)[] = [attempt.pending_connection_id];
    let recorded = false;
    try {
      return await this.completeAttempt(userId, id, title, request, attempt, composioUserId, fail, done, touched, () => { recorded = true; });
    } finally {
      if (!recorded) await this.discardRemote(userId, id, touched);
    }
  }

  private async completeAttempt(
    userId: string,
    id: ToolkitId,
    title: string,
    request: CompleteRequest,
    attempt: { pending_connection_id: string | null },
    composioUserId: string,
    fail: (errorCode: string, summary: string) => Promise<never>,
    done: (status: ReceiptStatus, summary: string, errorCode?: string | null) => Promise<ToolkitResult>,
    touched: (string | null)[],
    markRecorded: () => void,
  ): Promise<ToolkitResult> {
    const result = request.result;
    if (result.kind === "canceled") return await done("canceled", "Connecting was canceled. Nothing was connected.");
    if (result.kind !== this.deps.completionMode) return await fail("completion_mode_mismatch", "This completion isn't accepted by this server.");

    try {
      let connectionId: string;
      if (result.kind === "mock") {
        const mocked = await this.provider.completeMock({ toolkit: id, composioUserId, approve: result.outcome === "approve" });
        if (!mocked) return await done("failed", "Access wasn't granted. Nothing was connected.", "access_denied");
        connectionId = mocked.connectionId;
        touched.push(connectionId);
      } else if (result.kind === "callback") {
        // The redirect's status and ID are hints only; the server re-reads status and ownership below.
        if (result.status !== "success") return await done("failed", `${title} wasn't connected.`, "provider_reported_failure");
        if (!result.connectedAccountId || result.connectedAccountId !== attempt.pending_connection_id) {
          return await fail("attempt_mismatch", "The connection didn't match this attempt. Nothing was connected.");
        }
        connectionId = result.connectedAccountId;
      } else {
        const verified = await this.provider.completeVerifiedAuth({ composioUserId, sessionUri: result.sessionUri, signal: this.timeout() });
        touched.push(verified.connectionId); // redeemed for this user's own Composio id
        if (verified.connectionId !== attempt.pending_connection_id) {
          return await fail("attempt_mismatch", "The connection didn't match this attempt. Nothing was connected.");
        }
        connectionId = verified.connectionId;
      }

      const connection = await this.provider.getConnection({ connectionId, signal: this.timeout() });
      const owned = await this.provider.isOwnedBy({ toolkit: id, connectionId, composioUserId, signal: this.timeout() });
      if (!owned || connection.id !== connectionId || connection.toolkitSlug !== TOOLKITS[id].composioToolkit || connection.authConfigId !== this.provider.authConfigId(id)) {
        return await fail("verification_failed", "The connection couldn't be verified. Nothing was connected.");
      }
      if (connection.status !== "active") return await fail(`connection_${connection.status}`, `${title} didn't finish connecting.`);

      const verdict = evaluateToolkitGrant(TOOLKITS[id], connection.grantedScopes);
      // Which permissions the account granted, by name only (never a token), so a "too broad"
      // grant can be fixed in the auth config. Scope names are public OAuth identifiers.
      const allowed = TOOLKITS[id].allowedGrants;
      this.deps.log?.({
        level: "info",
        event: "grant_checked",
        toolkit: id,
        verdict,
        scopes: connection.grantedScopes ?? null,
        notAllowed: allowed && connection.grantedScopes ? connection.grantedScopes.filter((g) => !allowed.has(g)) : null,
      });
      const { status, reason } = statusForVerdict(verdict);
      await this.store.upsertConnection({
        user_id: userId,
        provider: id,
        connection_id: connectionId,
        status,
        reason,
        account_label: null,
        scopes_json: connection.grantedScopes ? JSON.stringify(connection.grantedScopes) : null,
        connected_at: this.now(),
        last_checked_at: this.now(),
      });
      markRecorded();
      // A fresh connection never inherits switches from an earlier one.
      await this.store.disableTools(userId, toolNames(id), this.now());
      if (verdict !== "ok") return await done("blocked", blockedSummary(title, verdict), reason);
      // ADR-816 (replaces ADR-563's "tools come on with the connection"): a connection starts with
      // every tool off, and the user chooses Off, Read only or Read and act for the app
      // (PUT /v1/tools/access). ASK-01 is unchanged: every read still asks, and every send,
      // change or delete still needs a tap on its exact card.
      return await done("succeeded", `${title} connected. Doddy won't use it until you choose what he may do: look only, or look and act.`);
    } catch (error) {
      if (error instanceof AppError) throw error;
      const appError = toAppError(error, title);
      throw new AppError(appError.code, { ...appError.options, receipt: await this.receipt(userId, id, "connect", null, "failed", `${title} couldn't be connected.`, appError.code, null) });
    }
  }

  async disconnect(userId: string, toolkitId: string, body: unknown): Promise<ToolkitResult> {
    if (toolkitId === WEB_SECTION_ID) {
      // Older app builds show a Disconnect button for every section; for web search it means "off".
      parse(EmptyRequestSchema, body);
      for (const name of [WEB_SEARCH_TOOL, ...MONID_TOOL_NAMES]) await this.store.setToolEnabled(userId, name, false, this.now());
      const summary = "Web search has no account to disconnect; it was switched off.";
      const receipt = await this.receipt(userId, WEB_SECTION_ID, "disconnect", null, "succeeded", summary, null, null);
      return { toolkit: await this.webView(userId), receipt };
    }
    const id = toolkit(toolkitId);
    parse(EmptyRequestSchema, body);
    const title = TOOLKITS[id].title;
    // Switches go off first, so nothing can run during or after the disconnect.
    await this.store.disableTools(userId, toolNames(id), this.now());
    const hadLocal = (await this.store.getConnection(userId, id)) !== null;
    const pendingBefore = await this.store.cleanupFor(userId, id);
    if (!hadLocal && !pendingBefore) {
      const receipt = await this.receipt(userId, id, "disconnect", null, "succeeded", `${title} was already disconnected.`, null, null);
      return { toolkit: await this.view(userId, id), receipt };
    }
    const remote = await this.removeRemote(userId, id);
    const receipt =
      remote === "removed"
        ? await this.receipt(userId, id, "disconnect", null, "succeeded", `Disconnected. Doddy's access to ${title} was removed.`, null, null)
        : await this.receipt(
            userId,
            id,
            "disconnect",
            null,
            "outcome_unknown",
            `Disconnected in Doddy. Removing access at ${title} couldn't be confirmed; try again or remove Doddy in the ${title} account settings.`,
            "remote_cleanup_failed",
            null,
          );
    return { toolkit: await this.view(userId, id), receipt };
  }

  /**
   * Hourly (app.ts): ends attempts nobody completed in time and removes their connections at the
   * provider, then retries removals that failed earlier. Without it, a user who finished a
   * provider's consent after leaving Doddy would keep a grant no one tracks once `prune` drops the attempt.
   */
  async sweepAbandoned(): Promise<void> {
    const now = this.now();
    const toolkits = Object.keys(TOOLKITS);
    const ended = await this.store.expireAttempts(now, toolkits);
    const retry = await this.store.cleanupsToRetry(toolkits, now, CLEANUP_RETRY.perSweep);
    await this.removeQueued([...ended, ...retry]);
    await this.sweepDocumentFiles();
  }

  /** Kept queued for the sweep, put off a little longer each time; reported once when it is stuck. */
  private async failedCleanup(connectionId: string): Promise<void> {
    const failure = await this.store.failCleanup(connectionId, "remote_cleanup_failed", this.now());
    if (failure?.stuckNow) this.deps.log?.(stuckCleanupLine(failure));
  }

  /** Removes connections a failed completion left at the provider; a failure stays queued and visible. */
  private async discardRemote(userId: string, id: ToolkitId, ids: (string | null)[]): Promise<void> {
    const queued: QueuedCleanup[] = [];
    for (const connectionId of new Set(ids.filter((c): c is string => !!c))) {
      await this.store.queueCleanup(connectionId, userId, id, this.now());
      queued.push({ connectionId, userId, provider: id });
    }
    await this.removeQueued(queued);
  }

  /** Already queued: removed at the provider and dequeued, or kept as `failed` to retry. */
  private async removeQueued(queued: readonly QueuedCleanup[]): Promise<void> {
    for (const connectionId of new Set(queued.map((q) => q.connectionId))) {
      let result: "removed" | "failed";
      try {
        result = await this.provider.removeConnection({ connectionId, signal: this.timeout() });
      } catch {
        result = "failed";
      }
      if (result === "removed") await this.store.finishCleanup(connectionId);
      else await this.failedCleanup(connectionId);
    }
  }

  private async removeRemote(userId: string, id: ToolkitId): Promise<"removed" | "failed"> {
    const removed = await this.store.removeConnectionForCleanup(userId, id, this.now());
    const cleanup = await this.store.cleanupFor(userId, id);
    const connectionId = removed?.connection_id ?? cleanup?.connection_id;
    if (!connectionId) return "removed";
    let result: "removed" | "failed";
    try {
      result = await this.provider.removeConnection({ connectionId, signal: this.timeout() });
    } catch {
      result = "failed";
    }
    if (result === "removed") await this.store.finishCleanup(connectionId);
    else await this.failedCleanup(connectionId);
    return result;
  }

  // ---------------------------------------------------------------- switches

  async setSwitch(userId: string, body: unknown): Promise<ToolkitResult> {
    const request = parse(SwitchRequestSchema, body);
    if (isWebTool(request.tool)) {
      if (request.enabled && this.webSearch?.isConfigured() !== true) {
        throw new AppError("live_not_configured", { message: "Web search isn't set up on this server." });
      }
      await this.store.setToolEnabled(userId, request.tool, request.enabled, this.now());
      const summary = `${webTitle(request.tool)} switched ${request.enabled ? "on" : "off"}.`;
      const receipt = await this.receipt(userId, WEB_SECTION_ID, "switch", request.tool, "succeeded", summary, null, null);
      return { toolkit: await this.webView(userId), receipt };
    }
    const tool = cloudTool(request.tool);
    if (!tool) throw new AppError("not_found", { message: "That tool doesn't exist." });
    const def = TOOLKITS[tool.toolkit];
    const row = await this.store.getConnection(userId, tool.toolkit);
    if (request.enabled) {
      this.requireConfigured(tool.toolkit);
      const reason = this.blockReason(row, def, tool);
      if (reason) throw new AppError(reason.code, { message: reason.message(def.title) });
    }
    await this.store.setToolEnabled(userId, tool.name, request.enabled, this.now());
    const copy = TOOL_COPY[tool.name]?.title ?? tool.name;
    const receipt = await this.receipt(userId, tool.toolkit, "switch", tool.name, "succeeded", `${copy} switched ${request.enabled ? "on" : "off"}.`, null, null);
    return { toolkit: await this.view(userId, tool.toolkit), receipt };
  }

  /**
   * One choice per app (ADR-815): Off, Read only, or Read and act. It only sets the app's existing
   * per-tool switches in bulk, so everything those switches already mean still holds, and ASK-01
   * still asks before every look and every change. Only tools the account can run come on (the
   * grant may not cover them all); if none can, nothing changes and the reason is returned.
   */
  async setAppAccess(userId: string, body: unknown): Promise<ToolkitResult> {
    const request = parse(AccessRequestSchema, body);
    const id = toolkit(request.app);
    const def = TOOLKITS[id];
    const wanted = toolsForAccess(id, request.mode);
    let on = wanted.on;
    let off = wanted.off;
    if (on.length > 0) {
      this.requireConfigured(id);
      const row = await this.store.getConnection(userId, id);
      const blocks = on.map((name) => this.blockReason(row, def, this.requireTool(name)));
      // Only tools the account can really run come on (the grant may not cover them all). If none
      // can, the account itself is the problem (not connected, expired, wrong grant): refuse, change nothing.
      const usable = on.filter((_, i) => blocks[i] === null);
      if (usable.length === 0) {
        const reason = blocks.find((b) => b !== null)!;
        throw new AppError(reason.code, { message: reason.message(def.title) });
      }
      off = [...off, ...on.filter((name) => !usable.includes(name))];
      on = usable;
    }
    for (const name of off) await this.store.setToolEnabled(userId, name, false, this.now());
    for (const name of on) await this.store.setToolEnabled(userId, name, true, this.now());
    const label: Record<AppAccess, string> = { off: "off", read: "read only", act: "read and act" };
    const receipt = await this.receipt(userId, id, "switch", null, "succeeded", `${def.title} access set to ${label[request.mode]}.`, null, null);
    return { toolkit: await this.view(userId, id), receipt };
  }

  // ---------------------------------------------------------------- prepare / run

  /**
   * Every tool (ASK-01, ADR-483). Shows exactly what would happen and returns a single-use approval
   * for those arguments; `run` refuses without it. A read's card is made from its arguments alone:
   * nothing is read from the account before the yes. For a write, A tool with a `resolve` lookup first reads its target from the provider (a read,
   * counted like one; never the write), shows that in the preview, and binds the approval to it too.
   * If the same write ran in the last day, the card says so (ADR-322); after a try whose outcome is
   * unknown, a write that can be looked for is looked for first.
   *
   * ADR-708: that lookup is a read of the account before the user's yes. The card needs it, so it stays,
   * but what it finds goes ONLY into `preview` (the card the user reads); when it gives no card, every
   * kind of failure (nothing found, several found, no usable sender, a provider error) answers alike,
   * so the answer isn't a way to ask the account what it holds. A run can't use the lookup without a
   * card either (`run`). Nothing here proves a person tapped: that is the app's half (`askFirst.ts`).
   */
  async prepare(userId: string, body: unknown): Promise<PrepareResult> {
    const request = parse(PrepareRequestSchema, body);
    if (isAppsTool(request.tool)) {
      // A1 (ADR-815): a generic call becomes the one reviewed read it maps to, and everything below
      // (switch, grants, ASK-01 approval bound to the translated arguments, caps) applies to that.
      const call = translateAppsCall(request.tool, request.arguments);
      return { ...(await this.prepare(userId, { ...request, tool: call.tool, arguments: call.arguments })), tool: request.tool };
    }
    if (isWebTool(request.tool)) return this.prepareWebSearch(userId, request.tool, request.arguments);
    if (isFlightTool(request.tool)) return this.flights.prepare(userId, request.tool, request.arguments, this.flightReceipt(userId));
    if (isClaudeTool(request.tool)) return this.prepareClaude(userId, request.tool, request.arguments);
    const tool = this.requireTool(request.tool);
    const args = parse(tool.input, request.arguments);
    if (request.timeZone !== undefined && !isSupportedTimeZone(request.timeZone)) {
      throw new AppError("invalid_request", { message: "Use an IANA time zone such as Europe/Warsaw." });
    }
    if ((tool.resolve?.needsTimeZone || bindsTimeZone(tool)) && request.timeZone === undefined) {
      throw new AppError("invalid_request", { message: "This tool needs the user's time zone." });
    }
    const context: Context | undefined = request.timeZone === undefined ? undefined : { timeZone: request.timeZone };
    // ADR-710: for a write that reads the zone, the zone the card was made for is part of the approval.
    const boundZone = bindsTimeZone(tool) ? (request.timeZone ?? null) : null;
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    const row = await this.checkUsable(userId, tool, tool.risk);
    if (tool.risk === "read") {
      const { approvalId, expiresAt } = await this.ask.issue({ userId, tool: tool.name, accountId: row.connection_id, argsDigest: argumentDigest(args) });
      return { mode: this.mode, tool: tool.name, preview: tool.preview(args, null), approvalId, expiresAt: new Date(expiresAt).toISOString() };
    }
    let target: ResolvedTarget | null = null;
    if (tool.resolve) {
      await this.reserveRuns(userId, tool, now, 1);
      const composioUserId = await this.store.composioUserId(userId, now);
      try {
        target = (await this.limiter.withSlot(userId, () => this.lookup(userId, tool, args, composioUserId, row.connection_id, context))).target;
      } catch (error) {
        throw await this.lookupFailure(userId, tool, error);
      }
    }
    const argsDigest = approvalDigest(args, target, boundZone);
    const { approvalId, expiresAt } = await this.ask.issue({ userId, tool: tool.name, accountId: row.connection_id, argsDigest });
    const preview = tool.preview(args, target);
    const result: PrepareResult = { mode: this.mode, tool: tool.name, preview, approvalId, expiresAt: new Date(expiresAt).toISOString() };
    const latest = await this.store.latestWrite({ userId, capability: tool.name, argsDigest, since: now - EARLIER_WINDOW_MS });
    if (!latest) return result;
    const title = TOOLKITS[tool.toolkit].title;
    const at = new Date(latest.finishedAt).toISOString();
    const withLine = (line: string) => ({ ...preview, lines: [...preview.lines, line] });
    if (latest.outcome === "succeeded") {
      return { ...result, earlier: { status: "succeeded", at }, preview: withLine("Doddy already did exactly this once in the last day.") };
    }
    if (await this.foundExisting(userId, tool, args, row, now)) {
      return { ...result, earlier: { status: "found", at }, preview: withLine(`An earlier try went through: it is already in ${title}.`) };
    }
    return { ...result, earlier: { status: "outcome_unknown", at }, preview: withLine(`An earlier try in the last day may have gone through. Check ${title} before doing it again.`) };
  }

  // ---------------------------------------------------------------- travel: trips from booking emails

  /**
   * The trip screen's "find my trips" (decision 2026-11-11-travel-agent-plan; TRAVEL_EMAILS.md). Owner:
   * Gmail is read only on request ("Tylko na żądanie"). Same gates as read_email, whose switch it uses:
   * Gmail connected, grants fine, the switch on; then its own ask-first card, bound to this search.
   */
  async prepareTravelScan(userId: string, body: unknown): Promise<PrepareResult> {
    parse(TravelScanPrepare, body);
    const tool = this.requireTool(READ_EMAIL.name);
    await this.limiter.reserveRequest(userId, this.now());
    const row = await this.checkUsable(userId, tool, "read");
    this.travelReaderOrRefuse(userId);
    const { approvalId, expiresAt } = await this.ask.issue({ userId, tool: TRAVEL_SCAN, accountId: row.connection_id, argsDigest: TRAVEL_SCAN_DIGEST });
    return {
      mode: this.mode,
      tool: TRAVEL_SCAN,
      preview: {
        title: "Find your trips in Gmail?",
        lines: [
          `Doddy searches Gmail for booking emails from the last 400 days (airlines, Booking.com, Airbnb, travel agents, trains) and reads up to ${MAX_TRAVEL_EMAILS}.`,
          "Links, PINs and card numbers are removed first. The rest of each email goes to Anthropic to be read, then nothing is kept on Doddy's server.",
        ],
        confirmLabel: "Search Gmail",
      },
      approvalId,
      expiresAt: new Date(expiresAt).toISOString(),
    };
  }

  async runTravelScan(userId: string, body: unknown): Promise<TravelScanResult> {
    const request = parse(TravelScanRun, body);
    const tool = this.requireTool(READ_EMAIL.name);
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    const row = await this.checkUsable(userId, tool, "read");
    const reader = this.travelReaderOrRefuse(userId);
    const binding: AskBinding = { userId, tool: TRAVEL_SCAN, accountId: row.connection_id, argsDigest: TRAVEL_SCAN_DIGEST };
    const unasked = async () =>
      askFirstRefusal(await this.receipt(userId, tool.toolkit, "read", TRAVEL_SCAN, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    if (!(await this.ask.allows(binding, request.approvalId, "check"))) throw await unasked();
    await this.reserveRuns(userId, tool, now, 1);
    const composioUserId = await this.store.composioUserId(userId, now);
    try {
      return await this.limiter.withSlot(userId, async () => {
        if (!(await this.ask.allows(binding, request.approvalId, "use"))) throw await unasked();
        const result = await this.withRetry(TRAVEL_GMAIL_FETCH.maxRetries, (signal) =>
          this.provider.execute({
            toolkit: TRAVEL_GMAIL_FETCH.toolkit, slug: TRAVEL_GMAIL_FETCH.slug, composioUserId, connectionId: row.connection_id,
            arguments: TRAVEL_GMAIL_FETCH.toArguments(TRAVEL_GMAIL_QUERY, MAX_TRAVEL_EMAILS), signal,
          }),
        );
        const emails = TRAVEL_GMAIL_FETCH.emails(result.raw).slice(0, MAX_TRAVEL_EMAILS);
        // One Claude unit per five emails read, against the same daily Claude limit as ask_claude.
        if (emails.length > 0) await this.limiter.reserveClaude(userId, this.now(), Math.ceil(emails.length / 5));
        const read: ReadEmail[] = [];
        let unreadable = 0, notTravel = 0, removedSecrets = 0;
        for (let i = 0; i < emails.length; i += TRAVEL_READ_PARALLEL) {
          const batch = emails.slice(i, i + TRAVEL_READ_PARALLEL);
          const outcomes = await Promise.all(batch.map((email) => readTravelEmail(email, reader)));
          outcomes.forEach((outcome, j) => {
            if (outcome.kind !== "read") { unreadable++; return; }
            removedSecrets += outcome.removedSecrets;
            if (outcome.reading.kind === "not_travel") notTravel++;
            const email = batch[j]!;
            read.push({ messageId: email.messageId, receivedAt: email.receivedAt, senderDomain: senderDomain(email.sender), reading: outcome.reading });
          });
        }
        const bookings = mergeBookings(read);
        if (row.status === "error") await this.store.updateConnectionStatus(userId, tool.toolkit, "connected", null, this.now());
        const summary = `Read ${emails.length} email${emails.length === 1 ? "" : "s"}; found ${bookings.length} booking${bookings.length === 1 ? "" : "s"}.`;
        const receipt = await this.receipt(userId, tool.toolkit, "read", TRAVEL_SCAN, "succeeded", summary, null, result.providerReference);
        // Counts only: no subject, sender, place or reference reaches the log.
        this.deps.log?.({ event: "travel_scan", emails: emails.length, unreadable, notTravel, bookings: bookings.length, removedSecrets,
          ...(reader instanceof ClaudeTravelReader ? { inputTokens: reader.usage.inputTokens, outputTokens: reader.usage.outputTokens } : {}) });
        return { mode: this.mode, emailsFound: emails.length, emailsUnreadable: unreadable, emailsNotTravel: notTravel, bookings, receipt };
      });
    } catch (error) {
      throw await this.failure(userId, tool, error, false);
    }
  }

  // ---------------------------------------------------------------- travel: the trip planner

  /**
   * The planner's first step (decision 2026-11-11-travel-agent-plan, stage 2): the person's words, and the
   * brief so far, become a brief. The model only fills fields; code drops what can't be right, then says
   * what is still needed (the app asks for the first) and what it assumes. One Claude unit.
   */
  async understandTrip(userId: string, body: unknown): Promise<PlanUnderstood> {
    const request = parse(PlanUnderstandRequest, body);
    const claude = this.deps.travelClaude !== undefined ? this.deps.travelClaude : (this.deps.claude ?? null);
    if (!claude || !claude.isConfigured()) throw new AppError("live_not_configured", { message: "The trip planner isn't set up on this server." });
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    await this.limiter.reserveClaude(userId, now, 1);
    const before = request.brief ?? EMPTY_BRIEF;
    let proposed: unknown;
    try {
      const result = await claude.structured(
        {
          system: UNDERSTAND_SYSTEM,
          user: JSON.stringify({ today: request.today, briefSoFar: before, newWords: request.words }),
          schema: BRIEF_JSON_SCHEMA,
          maxTokens: 800,
          effort: "low",
          name: UNDERSTAND_STEP,
        },
        AbortSignal.timeout(15_000),
        new UsageScope(userId, "travel_plan"),
      );
      proposed = result.value;
    } catch (error) {
      throw toAppError(error, "Claude");
    }
    const parsed = TripBrief.safeParse(proposed);
    // An answer of the wrong shape changes nothing: the brief stays as it was.
    const brief = cleanBrief(parsed.success ? parsed.data : before, request.today);
    return { brief, missing: missing(brief), assumptions: assumptions(brief) };
  }

  /** The planner's search: Kiwi.com's flights for a complete brief, three options chosen by code, links out. */
  async searchTrip(userId: string, body: unknown): Promise<PlanResult> {
    const request = parse(PlanSearchRequest, body);
    const brief = cleanBrief(request.brief, request.today);
    const query = toQuery(brief);
    if (!query) throw new AppError("invalid_request", { message: `The trip isn't complete yet: ${missing(brief).join(", ")}.` });
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    await this.limiter.reserveToolRun(userId, now);
    const flights = this.deps.flightSearch ?? (this.mode === "live" ? new KiwiTripSearch() : new MockFlightSearch());
    let answer: Awaited<ReturnType<FlightSearch["search"]>>;
    try {
      answer = await flights.search(query, AbortSignal.timeout(KIWI_TIMEOUT_MS));
    } catch (error) {
      const reason = error instanceof FlightSearchError ? error.reason : "unavailable";
      throw new AppError("provider_unavailable", { message: reason === "refused" ? "Kiwi.com didn't answer this search." : "Kiwi.com couldn't be reached. Try again in a moment." });
    }
    const options = pickOptions(answer.itineraries, answer.currency, brief.budget);
    this.deps.log?.({ event: "trip_search", results: answer.itineraries.length, options: options.length });
    return {
      brief,
      options: options.map((option) => ({ ...option, links: stayLinks(option, brief) })),
      source: "Kiwi.com",
      checkedAt: new Date(this.now()).toISOString(),
    };
  }

  private travelReaderOrRefuse(userId?: string): TravelReader {
    if (this.deps.travelReader) return this.deps.travelReader;
    const claude = this.deps.travelClaude !== undefined ? this.deps.travelClaude : (this.deps.claude ?? null);
    if (!claude || !claude.isConfigured()) {
      throw new AppError("live_not_configured", { message: "Reading booking emails isn't set up on this server." });
    }
    // A new reader per run, so its token count is this run's.
    return new ClaudeTravelReader(claude, undefined, userId);
  }

  /**
   * After a try whose outcome is unknown: looks for the write with the tool's own read, only if
   * the user has that read switched on. True only when it is found; any failure or "not listed"
   * is false, which proves nothing (ADR-322).
   *
   * ASK-01 (ADR-708): this list-read happens before a yes for the new card, so the user's own switch
   * for that read gates it, on the first line below. A user who switched it off is never read from
   * here, and the card only warns that the earlier try may have gone through.
   */
  private async foundExisting(userId: string, tool: CloudToolDefinition, args: Record<string, unknown>, row: ConnectionRow, now: number): Promise<boolean> {
    const finder = tool.findExisting;
    if (!finder || !(await this.store.toolEnabled(userId, finder.tool.name))) return false;
    try {
      await this.limiter.reserveToolRun(userId, now);
      const listArgs = finder.arguments(args);
      const composioUserId = await this.store.composioUserId(userId, now);
      const result = await this.withRetry(finder.tool.maxRetries, (signal) =>
        this.provider.execute({
          toolkit: finder.tool.toolkit,
          slug: finder.tool.composioSlug,
          composioUserId,
          connectionId: row.connection_id,
          arguments: finder.tool.toArguments(listArgs),
          signal,
        }),
      );
      const listed = finder.tool.normalize(result.raw, listArgs, { timeZone: "UTC" }, null);
      return (listed.items ?? []).some((item) => finder.matches(item, args));
    } catch {
      return false;
    }
  }

  /**
   * A repeated run of an approval that a run already took (the phone lost the answer, or asked again
   * while the first try was still running): what happened the first time answers it, and nothing runs
   * again (ADR-322). Null when no run has it. A repeat must ask for exactly what the first try asked
   * for (`requestDigest`: the arguments and the time zone, also for a write with a lookup); otherwise
   * it is refused before anything about the first try is said.
   */
  private async repeatOfStartedApproval(
    userId: string, tool: CloudToolDefinition, args: Record<string, unknown>, approvalId: string, accountId: string, requestDigest: string,
    unconfirmed: () => Promise<AppError>,
  ): Promise<RunResult | null> {
    const first = await this.store.approvalRun({ approvalId, userId, capability: tool.name, accountId });
    if (!first) return null;
    // Runs from before the request was kept: a write without a lookup is bound to its arguments by the approval itself.
    const asked = first.requestDigest ?? (tool.resolve ? null : first.argsDigest);
    if (asked !== null && asked !== requestDigest) throw await unconfirmed();
    const title = TOOLKITS[tool.toolkit].title;
    const replay = first.outcome === "succeeded" ? replayOf(tool, args, first) : null;
    if (replay) {
      const receipt = await this.receipt(userId, tool.toolkit, "write", tool.name, "succeeded", `${replay.summary} Answer from the first try; nothing ran again.`, null, null);
      return {
        mode: this.mode, tool: tool.name, text: replay.text, count: replay.count, truncated: replay.truncated,
        ...(replay.externalId ? { externalId: replay.externalId } : {}),
        replayed: true,
        receipt,
      };
    }
    if (first.outcome === "failed") {
      // The first try provably never ran at the provider. The receipt is `failed` (the first try's own
      // status), so the app can tell it from a refusal of this request (`blocked`); the code is the
      // one older apps already read as "nothing was done".
      throw new AppError("capability_disabled", {
        message: "The first try with this confirmation didn't go through. It needs a fresh confirmation.",
        receipt: await this.receipt(userId, tool.toolkit, "write", tool.name, "failed", "Not done: the first try with this confirmation didn't go through.", "confirmation_required", null),
      });
    }
    // Unknown; still running (its lookup, or the write itself); or the server stopped mid-run. Never "busy" or
    // "needs a confirmation": the first try may still go through.
    const summary = first.outcome === null
      ? `The first try at ${title} hasn't finished yet; it may or may not go through. Check there before trying again.`
      : `${title} didn't confirm the first try; it may or may not have gone through. Check there before trying again.`;
    throw new AppError("capability_disabled", {
      message: "The first try with this confirmation may or may not have gone through.",
      receipt: await this.receipt(userId, tool.toolkit, "write", tool.name, "outcome_unknown", summary, "earlier_outcome_unknown", null),
    });
  }

  /**
   * Reads a tool's target (no retry beyond a read's one). Never runs the write itself. For a write,
   * missing or already done is a refusal with a receipt, before any approval is made or used. For
   * a read, it is `{ missing }`: the caller says nothing matched instead of guessing.
   */
  private async lookup(
    userId: string,
    tool: CloudToolDefinition,
    args: Record<string, unknown>,
    composioUserId: string,
    connectionId: string,
    context?: Context,
  ): Promise<{ target: ResolvedTarget; missing: null } | { target: null; missing: string }> {
    const lookup = tool.resolve!;
    const result = await this.withRetry(LOOKUP_RETRIES, (signal) =>
      this.provider.execute({ toolkit: tool.toolkit, slug: lookup.slug, composioUserId, connectionId, arguments: lookup.toArguments(args, context), signal }),
    );
    const found = lookup.read(result.raw, args, context);
    if (found !== null && found.kind !== "missing") return { target: found, missing: null };
    // A read says what it found (or that nothing matched) after the user's yes for it. A write's miss
    // is one answer for every cause (ADR-708): the lookup came before any yes.
    if (tool.risk === "read") return { target: null, missing: found?.message ?? lookup.notFound };
    throw await this.lookupFailed(userId, tool, "not_found");
  }

  /**
   * The one answer for a write whose lookup gave no card (ADR-708): one code, one message, one receipt,
   * whatever the cause. Which cause it was goes to the server's log as a fixed word, never to the caller.
   */
  private async lookupFailed(userId: string, tool: CloudToolDefinition, kind: string): Promise<AppError> {
    this.deps.log?.({ level: "info", event: "lookup_failed", tool: tool.name, kind });
    const receipt = await this.receipt(userId, tool.toolkit, "write", tool.name, "blocked", `Not done: ${LOOKUP_FAILED}`, "not_found", null);
    return new AppError("not_found", { message: LOOKUP_FAILED, receipt });
  }

  /**
   * A failure while a write looked up its target before the card. Everything that depends on the target
   * or on what the provider made of it is `lookupFailed`. Two things are not: Doddy's own `busy` (nothing
   * was looked up), and a dead connection, which is a fact about the account rather than what it holds
   * and which the app answers with a Connect button.
   */
  private async lookupFailure(userId: string, tool: CloudToolDefinition, error: unknown): Promise<AppError> {
    if (error instanceof AppError) return error;
    const failed = toAppError(error, TOOLKITS[tool.toolkit].title);
    if (failed.code === "connection_expired" || failed.code === "permission_insufficient") return this.failure(userId, tool, error, false);
    return this.lookupFailed(userId, tool, failed.code);
  }

  /** Reserves today's tool runs for this call, with a blocked receipt when a Doddy limit says no. */
  private async reserveRuns(userId: string, tool: CloudToolDefinition, now: number, units: number): Promise<void> {
    try {
      await this.limiter.reserveToolRun(userId, now, units);
    } catch (error) {
      if (error instanceof AppError) {
        const op = tool.risk === "write" ? "write" : "read";
        throw new AppError(error.code, { ...error.options, receipt: await this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: a Doddy limit was reached.", error.code, null) });
      }
      throw error;
    }
  }

  /**
   * Turns a provider failure into an AppError with a receipt. A write is "outcome_unknown" only once
   * the write itself was sent (`writeSent`) and the error doesn't prove it never ran (DOD-08).
   */
  private async failure(userId: string, tool: CloudToolDefinition, error: unknown, writeSent: boolean): Promise<AppError> {
    if (error instanceof AppError) return error;
    const title = TOOLKITS[tool.toolkit].title;
    const appError = toAppError(error, title);
    const op = tool.risk === "write" ? "write" : "read";
    if (appError.code === "connection_expired") {
      await this.store.updateConnectionStatus(userId, tool.toolkit, "expired", "revoked_or_expired", this.now());
      await this.store.disableTools(userId, toolNames(tool.toolkit), this.now());
    }
    const unknown = op === "write" && writeSent && !WRITE_NOT_RUN.has(appError.code);
    const summary = unknown
      ? `${title} didn't confirm; it may or may not have gone through. Check there before trying again.`
      : op === "write"
        ? `${title} wasn't reached or its answer couldn't be used. Nothing was changed.`
        : `${title} wasn't reached or its answer couldn't be used. Nothing is shown instead.`;
    const receipt = await this.receipt(userId, tool.toolkit, op, tool.name, unknown ? "outcome_unknown" : "failed", summary, appError.code, null);
    // The message matches the receipt: "Nothing was changed" would be false for a write that may have run.
    return new AppError(appError.code, { ...appError.options, message: unknown ? summary : appError.message, receipt });
  }

  async run(userId: string, body: unknown): Promise<RunResult> {
    const request = parse(RunRequestSchema, body);
    if (isAppsTool(request.tool)) {
      const call = translateAppsCall(request.tool, request.arguments);
      return { ...(await this.run(userId, { ...request, tool: call.tool, arguments: call.arguments })), tool: request.tool };
    }
    if (isWebTool(request.tool)) return this.runWebSearch(userId, request.tool, request);
    if (isFlightTool(request.tool)) return this.flights.run(userId, request.tool, request, this.flightReceipt(userId));
    if (isClaudeTool(request.tool)) return this.runClaude(userId, request.tool, request);
    const tool = this.requireTool(request.tool);
    const args = parse(tool.input, request.arguments);
    if (!isSupportedTimeZone(request.timeZone)) {
      throw new AppError("invalid_request", { message: "Use an IANA time zone such as Europe/Warsaw." });
    }
    const op = tool.risk === "write" ? "write" : "read";
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    const row = await this.checkUsable(userId, tool, op);

    // A write's approval is taken here but only used up right before the provider call; a limit or
    // "busy" refusal in between gives it back, so it doesn't cost the user their confirmation. For a tool
    // with a lookup the approval is bound to the target too, so it can only be matched in full after the lookup.
    // ASK-01: reads are bound to their arguments only (nothing was looked up before the yes).
    // ADR-710: a write that reads the zone runs only in the zone its approval was made for. The digest
    // below includes the zone this request names, so an approval from another zone doesn't match.
    const boundZone = bindsTimeZone(tool) ? request.timeZone : null;
    const binding = (target: ResolvedTarget | null): AskBinding => ({
      userId, tool: tool.name, accountId: row.connection_id, argsDigest: op === "write" ? approvalDigest(args, target, boundZone) : argumentDigest(args),
    });
    const approval = (target: ResolvedTarget | null, checkOnly: boolean) => this.ask.allows(binding(target), request.approvalId, checkOnly ? "check" : "use");
    const unconfirmed = async () =>
      op === "write"
        ? new AppError("capability_disabled", {
            message: "This action needs a fresh confirmation.",
            receipt: await this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: it wasn't confirmed.", "confirmation_required", null),
          })
        : askFirstRefusal(await this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    // A write takes its approval first, before its lookup (which can take seconds): a repeat that comes
    // meanwhile (the phone lost the answer and asks again) finds it taken and hears that the first try
    // may still go through, never "busy" or "needs a confirmation". Taking it checks only that `prepare`
    // issued it to this user for this tool and account, and, for a write without a lookup, these
    // arguments: a write with a lookup can only match its approval in full after the lookup (ADR-708),
    // so a run with no card, or a made-up approval, looks nothing up.
    let held: { approvalId: string; startedAt: number } | null = null;
    if (tool.risk === "write") {
      const requestDigest = approvalDigest(args, null, boundZone);
      const approvalId = request.approvalId;
      if (approvalId === undefined) throw await unconfirmed();
      const took = await this.ask.take({ userId, tool: tool.name, accountId: row.connection_id, argsDigest: tool.resolve ? null : requestDigest }, approvalId, requestDigest);
      if (!took) {
        const repeat = await this.repeatOfStartedApproval(userId, tool, args, approvalId, row.connection_id, requestDigest, unconfirmed);
        if (repeat) return repeat;
        throw await unconfirmed();
      }
      held = { approvalId, startedAt: took.startedAt };
    }
    if (tool.risk === "read" && !(await approval(null, true))) throw await unconfirmed();

    let writeSent = false;
    // Set once this run used up its approval, so its outcome is recorded against it (ADR-322).
    let used: string | null = null;
    // Taken but not used: the write was never sent (a limit, busy, the lookup), so the yes is given back.
    // If the server stops first, it stays taken: a repeat hears "may or may not", and nothing runs it again (DOD-08).
    const giveBack = async () => {
      if (held && !used) await this.ask.giveBack(held.approvalId, held.startedAt).catch(() => {});
    };

    // A lookup (before a write, or the search before a read) counts as one more run, reserved together with the main call.
    try {
      await this.reserveRuns(userId, tool, now, tool.resolve ? 2 : 1);
    } catch (error) {
      await giveBack();
      throw error;
    }

    const composioUserId = await this.store.composioUserId(userId, now);
    try {
      return await this.limiter.withSlot(userId, async () => {
        // A read's yes is used up before anything is read, its lookup included: one yes, one read.
        if (tool.risk === "read" && !(await approval(null, false))) throw await unconfirmed();
        // The target is read again right before the write: if it is gone, done, or no longer what the
        // card showed, the approval doesn't match and nothing is written. A read looks up what it opens.
        const found = tool.resolve ? await this.lookup(userId, tool, args, composioUserId, row.connection_id, { timeZone: request.timeZone }) : null;
        if (found?.missing) {
          // Reads only (a write's miss throws): nothing matched, so the main slug isn't run.
          const summary = tool.resolve!.missSummary ?? "Nothing matched.";
          const receipt = await this.receipt(userId, tool.toolkit, op, tool.name, "succeeded", summary, null, null);
          return { mode: this.mode, tool: tool.name, text: found.missing, count: 0, truncated: false, receipt };
        }
        const target = found?.target ?? null;
        // Used up here, once: a parallel run with the same approval loses the race and does nothing.
        if (tool.risk === "write" && !(await approval(target, false))) throw await unconfirmed();
        writeSent = tool.risk === "write";
        if (writeSent) used = request.approvalId ?? null;
        const result = await this.withRetry(tool.maxRetries, (signal) =>
          this.provider.execute({
            toolkit: tool.toolkit,
            slug: tool.composioSlug,
            composioUserId,
            connectionId: row.connection_id,
            arguments: tool.toArguments(args, target, { timeZone: request.timeZone }),
            signal,
          }),
        );
        const outcome = tool.normalize(result.raw, args, { timeZone: request.timeZone }, target);
        if (row.status === "error") await this.store.updateConnectionStatus(userId, tool.toolkit, "connected", null, this.now());
        const receipt = await this.receipt(userId, tool.toolkit, op, tool.name, "succeeded", outcome.summary, null, result.providerReference);
        // What a repeat answers with: the result word and the receipt's summary, never names or text.
        if (used) await this.store.finishApproval(used, "succeeded", outcome.externalId ?? null, this.now(), { word: resultWord(outcome.text), summary: receipt.summary });
        return {
          mode: this.mode, tool: tool.name, text: outcome.text, count: outcome.count, truncated: outcome.truncated,
          ...(outcome.items ? { items: outcome.items } : {}),
          ...(outcome.externalId ? { externalId: outcome.externalId } : {}),
          receipt,
        };
      });
    } catch (error) {
      // A write is "failed" only when the error proves the provider never ran it. Anything else
      // after it was sent (timeout, provider error, an answer Doddy couldn't read) may have
      // happened: say so (DOD-08).
      if (used) {
        const code = error instanceof AppError ? error.code : toAppError(error, TOOLKITS[tool.toolkit].title).code;
        await this.store.finishApproval(used, WRITE_NOT_RUN.has(code) ? "failed" : "outcome_unknown", null, this.now());
      } else {
        await giveBack();
      }
      throw await this.failure(userId, tool, error, writeSent);
    }
  }

  /**
   * The card for web search, news or places (ASK-01): the exact words, and what Doddy pays for it
   * (ADR-489: the price is on the card). Nothing is searched.
   */
  private async prepareWebSearch(userId: string, tool: WebTool, raw: Record<string, unknown>): Promise<PrepareResult> {
    const args = tool === WEB_SEARCH_TOOL ? parse(WebSearchInput, raw) : parse(MONID_TOOL_INPUT[tool], raw);
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    const blocked = async (code: "capability_disabled" | "live_not_configured", message: string): Promise<never> => {
      throw new AppError(code, { message, receipt: await this.receipt(userId, WEB_SECTION_ID, "read", tool, "blocked", `Not done: ${message}`, code, null) });
    };
    if (!this.webSearch || !this.webSearch.isConfigured()) return await blocked("live_not_configured", "Web search isn't set up on this server.");
    if (!(await this.webToolOn(userId, tool))) return await blocked("capability_disabled", `${webTitle(tool)} is turned off in Settings.`);
    const { approvalId, expiresAt } = await this.ask.issue({ userId, tool, accountId: WEB_ACCOUNT, argsDigest: argumentDigest(args) });
    const preview =
      tool === WEB_SEARCH_TOOL
        ? {
            title: "Search the web?",
            lines: [`Search words: ${(args as { query: string }).query}`, "They go to Doddy's server and a search provider (Monid). Doddy pays about $0.001 per search; there is a daily limit."],
            confirmLabel: "Yes, search",
          }
        : monidCard(tool, args);
    return { mode: this.mode, tool, preview, approvalId, expiresAt: new Date(expiresAt).toISOString() };
  }

  /**
   * Same order as account tools, minus the account: known tool -> valid arguments -> switch on ->
   * set up -> limits (incl. the web search caps) -> one Monid call (never retried: each run is billed)
   * -> normalized result -> receipt. Search words are not stored anywhere, receipts included.
   */
  private async runWebSearch(userId: string, tool: WebTool, request: { arguments: Record<string, unknown>; timeZone: string; approvalId?: string | undefined }): Promise<RunResult> {
    const args: Record<string, unknown> = tool === WEB_SEARCH_TOOL ? parse(WebSearchInput, request.arguments) : parse(MONID_TOOL_INPUT[tool], request.arguments);
    if (!isSupportedTimeZone(request.timeZone)) {
      throw new AppError("invalid_request", { message: "Use an IANA time zone such as Europe/Warsaw." });
    }
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    const blocked = async (code: "capability_disabled" | "live_not_configured" | "quota_exceeded", message: string, errorCode: string = code): Promise<never> => {
      throw new AppError(code, { message, receipt: await this.receipt(userId, WEB_SECTION_ID, "read", tool, "blocked", `Not done: ${message}`, errorCode, null) });
    };
    const provider = this.webSearch;
    if (!provider || !provider.isConfigured()) return await blocked("live_not_configured", "Web search isn't set up on this server.");
    if (!(await this.webToolOn(userId, tool))) return await blocked("capability_disabled", `${webTitle(tool)} is turned off in Settings.`);
    // ASK-01: the user's yes for exactly these words, checked before the search is counted.
    const binding: AskBinding = { userId, tool, accountId: WEB_ACCOUNT, argsDigest: argumentDigest(args) };
    const unasked = async () => askFirstRefusal(await this.receipt(userId, WEB_SECTION_ID, "read", tool, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    if (!(await this.ask.allows(binding, request.approvalId, "check"))) throw await unasked();
    try {
      await this.limiter.reserveWebSearch(userId, now);
    } catch (error) {
      if (error instanceof AppError) return await blocked("quota_exceeded", "Today's web search limit was reached.", error.code);
      throw error;
    }

    try {
      return await this.limiter.withSlot(userId, async () => {
        if (!(await this.ask.allows(binding, request.approvalId, "use"))) throw await unasked();
        const signal = AbortSignal.timeout(WEB_SEARCH_TIMEOUT_MS);
        const result = tool === WEB_SEARCH_TOOL
          ? await provider.search({ query: args.query as string, signal })
          : await provider.call({ tool, args, signal });
        const outcome = tool === WEB_SEARCH_TOOL ? normalizeWebSearch(result.output, args.query as string) : normalizeMonidTool(tool, result.output, args);
        const receipt = await this.receipt(userId, WEB_SECTION_ID, "read", tool, "succeeded", outcome.summary, null, result.runId);
        return { mode: this.mode, tool, text: outcome.text, count: outcome.count, truncated: outcome.truncated, receipt };
      });
    } catch (error) {
      if (error instanceof AppError) throw error;
      const appError = toAppError(error, webTitle(tool));
      const message =
        appError.code === "rate_limited" ? "Web search is busy right now. Try again shortly." : appError.code === "malformed_provider_result" ? "Web search sent an answer Doddy couldn't read, so nothing is shown." : "Web search couldn't be reached. Nothing is shown instead.";
      const receipt = await this.receipt(userId, WEB_SECTION_ID, "read", tool, "failed", message, appError.code, null);
      throw new AppError(appError.code, { ...appError.options, message, receipt });
    }
  }

  // ---------------------------------------------------------------- Claude (ADR-564)

  /** Waits for document jobs still running in the background (tests, shutdown). */
  async settle(): Promise<void> {
    while (this.background.size > 0) await Promise.allSettled([...this.background]);
  }

  private claudeArgs(tool: ClaudeToolName, raw: Record<string, unknown>): Record<string, unknown> {
    return tool === ASK_CLAUDE_TOOL ? parse(AskClaudeInput, raw) : parse(MakeDocumentInput, raw);
  }

  private claudeReady(tool: ClaudeToolName): string | null {
    if (!this.deps.claude || !this.deps.claude.isConfigured()) return "Claude isn't set up on this server.";
    // A file is kept only encrypted (decision 2026-11-12-documents-at-rest): no key, no files.
    if (tool !== ASK_CLAUDE_TOOL && (!this.deps.documentLinks || !this.store.keepsDocuments)) return "Making files isn't set up on this server.";
    return null;
  }

  /** ASK-01: a card from the arguments alone and a single-use approval. Nothing goes to Anthropic yet. */
  private async prepareClaude(userId: string, tool: ClaudeToolName, raw: Record<string, unknown>): Promise<PrepareResult> {
    const args = this.claudeArgs(tool, raw);
    // A too-thin file request is turned away first: no approval, no daily cap, no Claude (decision 2026-11-10-files-ask-for-details).
    if (tool === MAKE_DOCUMENT_TOOL) {
      const verdict = judgeDocumentRequest(args as MakeDocumentArgs);
      if (!verdict.ok) throw new AppError("need_details", { message: needDetailsMessage(verdict.missing) });
    }
    await this.limiter.reserveRequest(userId, this.now());
    const missing = this.claudeReady(tool);
    if (missing) {
      throw new AppError("live_not_configured", { message: missing, receipt: await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "blocked", `Not done: ${missing}`, "live_not_configured", null) });
    }
    const { approvalId, expiresAt } = await this.ask.issue({ userId, tool, accountId: CLAUDE_ACCOUNT, argsDigest: argumentDigest(args) });
    return { mode: this.mode, tool, preview: claudeCard(tool, args), approvalId, expiresAt: new Date(expiresAt).toISOString() };
  }

  /**
   * known tool -> valid arguments -> set up -> the user's yes (ASK-01) -> daily caps -> Claude.
   * ask_claude answers now (under 18 s). make_document starts a background job and answers at once
   * with a link that says "still making" until the file is ready. Requests aren't stored; the
   * document is, for a week, so its link works.
   */
  private async runClaude(userId: string, tool: ClaudeToolName, request: { arguments: Record<string, unknown>; approvalId?: string | undefined }): Promise<RunResult> {
    const args = this.claudeArgs(tool, request.arguments);
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    const blocked = async (code: "live_not_configured" | "quota_exceeded", message: string, errorCode: string = code): Promise<never> => {
      throw new AppError(code, { message, receipt: await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "blocked", `Not done: ${message}`, errorCode, null) });
    };
    const missing = this.claudeReady(tool);
    if (missing) return await blocked("live_not_configured", missing);
    const claude = this.deps.claude!;
    const binding: AskBinding = { userId, tool, accountId: CLAUDE_ACCOUNT, argsDigest: argumentDigest(args) };
    const unasked = async () => askFirstRefusal(await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    if (!(await this.ask.allows(binding, request.approvalId, "check"))) throw await unasked();

    // ADR-710: a document is minutes of Anthropic time and up to nine calls, so only so many are made at
    // once, per user and in all. Past that it is refused here, before anything is counted and before the
    // yes is used up, so the user can say yes again in a few minutes.
    const slot = tool === MAKE_DOCUMENT_TOOL ? this.takeDocumentSlot(userId) : null;
    if (tool === MAKE_DOCUMENT_TOOL && slot === null) {
      const message = "Doddy is already making files and can't start another yet. Try again in a few minutes.";
      throw new AppError("busy", {
        message,
        retryAfterSeconds: 120,
        receipt: await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "blocked", `Not done: ${message}`, "busy", null),
      });
    }
    // True once the running job owns the slot and gives it back itself when it ends.
    let jobOwnsSlot = false;
    try {
      try {
        // A document counts as several runs against both daily caps (ADR-710); a quick answer is one.
        await this.limiter.reserveClaude(userId, now, tool === MAKE_DOCUMENT_TOOL ? this.limits.documentClaudeUnits : 1);
      } catch (error) {
        if (error instanceof AppError) return await blocked("quota_exceeded", "Today's Claude limit was reached.", error.code);
        throw error;
      }
      if (!(await this.ask.allows(binding, request.approvalId, "use"))) throw await unasked();

      if (tool === ASK_CLAUDE_TOOL) {
        try {
          const answer = await claude.ask(args as never, AbortSignal.timeout(ASK_CLAUDE_TIMEOUT_MS), new UsageScope(userId, "ask_claude"));
          // ADR-710: Claude worked from material that may be untrusted (an email, a page), so what it wrote
          // goes back marked as information, the way the read tools mark theirs.
          const text = `Claude's answer (written for this user; read it out or sum it up, in your own words if it's long). ${MODEL_TEXT_LABEL}\n${answer.text}`;
          const receipt = await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "succeeded", "Asked Claude.", null, null);
          return { mode: this.mode, tool, text, count: 1, truncated: false, receipt };
        } catch (error) {
          const appError = toAppError(error, "Claude");
          this.deps.log?.({ level: "info", event: "ask_claude_failed", code: appError.code, ...providerLog(error) });
          const message = appError.code === "provider_timeout" ? "Claude took too long. For something long, ask Doddy to make it as a document." : appError.code === "rate_limited" ? "Claude is busy right now. Try again shortly." : "Claude couldn't be reached. Nothing is shown instead.";
          const receipt = await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "failed", message, appError.code, null);
          throw new AppError(appError.code, { ...appError.options, message, receipt });
        }
      }

      const doc = args as MakeDocumentArgs;
      const info = KIND_INFO[doc.kind];
      const name = fileName(doc.title, info.ext);
      const id = await this.store.startDocument(userId, name, info.mime, now);
      const url = this.deps.documentLinks!.link(id, userId, new Date(now));
      const job = this.makeDocumentInBackground(userId, id, doc, claude).finally(() => {
        slot?.();
        this.background.delete(job);
      });
      jobOwnsSlot = true;
      this.background.add(job);
      // The kind only: the title is the user's own words, and receipts are kept as a log (decision 2026-11-12-documents-at-rest).
      const receipt = await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "succeeded", `Started a ${info.label}.`, null, null);
      return {
        mode: this.mode,
        tool,
        text:
          `started: Claude is making the ${info.label} "${doc.title}". It takes one to three minutes. ` +
          // Owner, 13 Nov 2026: Doddy told the person to tap a card while they were talking. Nothing needs a tap now; the
          // iPhone (from the build with MadeFileStart) answers the agent with its own words and this line is for older builds.
          "When it's ready it arrives as Doddy's message in Messages in the app, with a notification; there Share saves it to Files or sends it on. " +
          "The user doesn't need to tap anything now. Tell the user in one short sentence what you're making and that it will be in Messages; " +
          "don't ask them to tap, open or look at anything, and don't read out any link. " +
          MODEL_TEXT_LABEL,
        count: 1,
        truncated: false,
        document: { url, name, kind: doc.kind, status: "working" },
        receipt,
      };
    } finally {
      if (!jobOwnsSlot) slot?.();
    }
  }

  /**
   * One web search for a deck's research (decision 2026-11-10-better-presentations): only when web search is set up, the
   * user's own web search switch is on, and it fits the same daily caps as a web search asked for by voice. Otherwise
   * the deck is researched from Wikipedia and the material alone.
   */
  private async deckSearchAllowed(userId: string): Promise<boolean> {
    if (!this.webSearch?.isConfigured() || !(await this.webToolOn(userId, WEB_SEARCH_TOOL))) return false;
    try {
      await this.limiter.reserveWebSearch(userId, this.now());
      return true;
    } catch {
      return false;
    }
  }

  /** A place for one more document job, or null when this user or the whole server is at its limit (ADR-710). The returned function gives it back; calling it twice is harmless. */
  private takeDocumentSlot(userId: string): (() => void) | null {
    const mine = this.documentJobs.get(userId) ?? 0;
    if (mine >= this.limits.userDocumentJobs || this.documentJobsTotal >= this.limits.serviceDocumentJobs) return null;
    this.documentJobs.set(userId, mine + 1);
    this.documentJobsTotal += 1;
    let given = false;
    return () => {
      if (given) return;
      given = true;
      const left = (this.documentJobs.get(userId) ?? 1) - 1;
      if (left <= 0) this.documentJobs.delete(userId);
      else this.documentJobs.set(userId, left);
      this.documentJobsTotal -= 1;
    };
  }

  private async makeDocumentInBackground(userId: string, id: string, args: MakeDocumentArgs, claude: ClaudeProvider): Promise<void> {
    try {
      const signal = AbortSignal.timeout(DOCUMENT_TIMEOUT_MS);
      // A deck is researched, outlined, checked and laid out here (decision 2026-11-10-better-presentations);
      // the other kinds are made by Claude's own skills as before.
      const file =
        args.kind === "deck"
          ? await new DeckMaker({ claude, wikimedia: this.wikimedia, webSearch: this.webSearch, now: () => new Date(this.now()), ...(this.deps.log ? { log: this.deps.log } : {}) }).make(
              args,
              () => this.deckSearchAllowed(userId),
              signal,
              { userId, requestId: id },
            )
          : await claude.makeDocument(args, signal, this.fileLedger(userId), new UsageScope(userId, "make_document", id));
      await this.store.finishDocument(userId, id, file.name, file.mime, file.bytes);
      this.deps.log?.({ level: "info", event: "document_ready", kind: args.kind, bytes: file.bytes.length });
    } catch (error) {
      await this.store.failDocument(id).catch(() => {});
      // Content-free: the kind and the error class only.
      this.deps.log?.({ level: "error", event: "document_failed", kind: args.kind, code: error instanceof ProviderError ? error.code : "internal", ...providerLog(error) });
    }
  }

  /**
   * Copies Claude makes at Anthropic for this person's document are owed a deletion from the moment they
   * exist: the id is written to `cleanups` (ids only) before anything else can fail, and leaves it only
   * when Anthropic confirms. It survives a restart and the person's account being erased (ADR-674).
   */
  private fileLedger(userId: string): ProviderFileLedger {
    return {
      track: (fileId) => this.store.queueCleanup(fileId, userId, ANTHROPIC_FILE_CLEANUP, this.now()),
      confirmed: (fileId) => this.store.finishCleanup(fileId),
      failed: (fileId) => this.failDocumentFile(fileId),
    };
  }

  /** One failed deletion at Anthropic: tried again later (CLEANUP_RETRY), reported once if it gets stuck. */
  private async failDocumentFile(fileId: string): Promise<void> {
    const failure = await this.store.failCleanup(fileId, "remote_cleanup_failed", this.now());
    if (failure?.stuckNow) this.deps.log?.(stuckCleanupLine(failure));
  }

  /**
   * Deletes the copies still owed at Anthropic. Only rows older than a document job can run
   * (`DOCUMENT_TIMEOUT_MS`, plus a minute), so a job still working is never raced; a failed one comes
   * back when due, with no last try (CLEANUP_RETRY). Logs counts only.
   */
  private async sweepDocumentFiles(): Promise<void> {
    const claude = this.deps.claude;
    if (!claude?.isConfigured()) return;
    const now = this.now();
    const due = await this.store.cleanupsToRetry([ANTHROPIC_FILE_CLEANUP], now, CLEANUP_RETRY.perSweep, now - DOCUMENT_TIMEOUT_MS - 60_000);
    let removed = 0;
    for (const { connectionId } of due) {
      let result: "removed" | "failed";
      try {
        result = await claude.deleteFile(connectionId, this.timeout());
      } catch {
        result = "failed";
      }
      if (result === "removed") {
        await this.store.finishCleanup(connectionId);
        removed++;
      } else {
        await this.failDocumentFile(connectionId);
      }
    }
    if (due.length > 0) this.deps.log?.({ level: due.length > removed ? "warn" : "info", event: "document_files_swept", due: due.length, removed, failed: due.length - removed });
  }

  // ---------------------------------------------------------------- helpers

  /** A web tool's switch: what the user chose, else the default (ADR-563). */
  private async webToolOn(userId: string, tool: WebTool): Promise<boolean> {
    const stored = await this.store.toolSwitch(userId, tool);
    return stored ?? WEB_TOOLS_ON_BY_DEFAULT.has(tool);
  }

  private requireTool(name: string): CloudToolDefinition {
    const tool = cloudTool(name);
    if (!tool) throw new AppError("not_found", { message: "That tool doesn't exist." });
    return tool;
  }

  private requireConfigured(id: ToolkitId): void {
    if (!this.provider.isConfigured(id)) {
      throw new AppError("live_not_configured", { message: `${TOOLKITS[id].title} isn't set up on this server.` });
    }
  }

  /** Why this tool cannot run right now, or null when it can. */
  private blockReason(
    row: ConnectionRow | null,
    def: (typeof TOOLKITS)[ToolkitId],
    tool: CloudToolDefinition,
  ): { code: "not_connected" | "permission_insufficient" | "connection_expired"; message: (title: string) => string } | null {
    if (!row) return { code: "not_connected", message: (t) => `${t} isn't connected.` };
    if (row.status === "expired") return { code: "connection_expired", message: (t) => `${t} access expired or was removed. Reconnect to continue.` };
    if (row.status === "permission_insufficient") {
      return { code: "permission_insufficient", message: (t) => `The access granted to ${t} isn't what Doddy expects, so it won't use it. Disconnect and reconnect.` };
    }
    if (row.status !== "connected" && row.status !== "error") return { code: "connection_expired", message: (t) => `${t} needs attention.` };
    // Grants are checked again on every run, not only at connect time.
    if (!grantsOk(def, tool, parseScopes(row))) {
      return { code: "permission_insufficient", message: (t) => `The access granted to ${t} doesn't cover this tool. Disconnect and reconnect.` };
    }
    return null;
  }

  /** Switch on, account connected, grants fine. Writes a blocked receipt when not. */
  private async checkUsable(userId: string, tool: CloudToolDefinition, op: "read" | "write"): Promise<ConnectionRow> {
    const def = TOOLKITS[tool.toolkit];
    const blocked = async (code: "not_connected" | "permission_insufficient" | "connection_expired" | "capability_disabled", message: string): Promise<never> => {
      throw new AppError(code, { message, receipt: await this.receipt(userId, tool.toolkit, op, tool.name, "blocked", `Not done: ${message}`.slice(0, 200), code, null) });
    };
    if (!this.provider.isConfigured(tool.toolkit)) return await blocked("not_connected", `${def.title} isn't set up on this server.`);
    // ADR-563: the account first, then the switch, so a request for an account that isn't
    // connected answers `not_connected` and the app can offer Connect right there.
    const row = await this.store.getConnection(userId, tool.toolkit);
    const reason = this.blockReason(row, def, tool);
    if (reason || !row) return await blocked(reason?.code ?? "not_connected", (reason?.message ?? ((t: string) => `${t} isn't connected.`))(def.title));
    if (!(await this.store.toolEnabled(userId, tool.name))) {
      return await blocked("capability_disabled", `${TOOL_COPY[tool.name]?.title ?? tool.name} is turned off in Settings.`);
    }
    return row;
  }

  /** Reads retry once on a transient failure, with a short wait. Writes never retry. */
  private async withRetry<T>(maxRetries: number, call: (signal: AbortSignal) => Promise<T>): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      try {
        return await call(this.timeout());
      } catch (raw) {
        const error = raw instanceof ProviderError ? raw : new ProviderError("provider_unavailable");
        if (!error.transient || attempt >= maxRetries) throw error;
        const wait = error.retryAfterSeconds !== undefined ? error.retryAfterSeconds * 1000 : 250;
        if (wait > 2_000) throw error;
        await this.sleep(wait);
      }
    }
  }

  private timeout(): AbortSignal {
    return AbortSignal.timeout(this.limits.providerTimeoutMs);
  }

  private async receipt(
    userId: string,
    id: SectionId,
    operation: ToolReceipt["operation"],
    tool: string | null,
    status: ReceiptStatus,
    summary: string,
    errorCode: string | null,
    providerReference: string | null,
  ): Promise<ToolReceipt> {
    const receipt: ToolReceipt = {
      operationId: randomUUID(),
      operation,
      toolkit: id,
      tool,
      timestamp: new Date(this.now()).toISOString(),
      mode: this.mode,
      status,
      summary: summary.slice(0, 200),
      errorCode,
      providerReference,
    };
    await this.store.saveToolReceipt(userId, receipt, this.now());
    return receipt;
  }
}

/** A lookup before a write is a read: one retry on a transient failure, like the read tools. */
const LOOKUP_RETRIES = 1;

/**
 * What a write answers when its lookup gave no card, whatever the cause (ADR-708): nothing found, several
 * found, a sender with no address, a provider error. Nothing the lookup found is in it.
 */
export const LOOKUP_FAILED = "Doddy couldn't find that, so nothing was changed. Ask the user which one they meant.";

/**
 * What an approval is bound to: the validated arguments, plus, for a tool with a lookup, the target
 * the card showed (so a task that changed since the card needs a fresh confirmation), plus, for a
 * write that reads the time zone, the zone the card was made for (ADR-710). Without a zone the digest
 * is what it always was, so earlier approvals and the "already done in the last day" check still match.
 */
function approvalDigest(args: Record<string, unknown>, target: ResolvedTarget | null, timeZone: string | null = null): string {
  if (timeZone !== null) return argumentDigest({ arguments: args, ...(target === null ? {} : { target }), timeZone });
  return target === null ? argumentDigest(args) : argumentDigest({ arguments: args, target });
}

/**
 * The answer for a repeat of a write that went through (ADR-322), or null when it can't be given. A write
 * without a lookup is bound to its arguments by its approval (a repeat with other words never gets here),
 * so its own `replay` may name them. A write with a lookup says only what its first run recorded: the
 * result word and the receipt summary, never a word of this request. A first run from before that was
 * recorded gives null, and the repeat hears that it may or may not have gone through.
 */
function replayOf(tool: CloudToolDefinition, args: Record<string, unknown>, first: ApprovalRun): ToolOutcome | null {
  if (!tool.resolve) {
    if (!tool.replay) return null;
    const outcome = tool.replay(args, first.externalId);
    return first.resultSummary === null ? outcome : { ...outcome, summary: first.resultSummary };
  }
  if (first.resultSummary === null) return null;
  return {
    text: `${first.resultWord === null ? "" : `${first.resultWord}: `}${first.resultSummary} Done on the first try; nothing ran again.`,
    count: 1,
    truncated: false,
    summary: first.resultSummary,
    ...(first.externalId ? { externalId: first.externalId } : {}),
  };
}

/** The fixed word a write's answer starts with ("sent", "changed", …), or null. Nothing else of the answer is kept. */
function resultWord(text: string): string | null {
  return /^([a-z]{2,16}):/.exec(text)?.[1] ?? null;
}

/** ASK-01: a run that came without the user's yes for exactly this. Nothing was looked up or sent. */
function askFirstRefusal(receipt: ToolReceipt): AppError {
  return new AppError("capability_disabled", { message: "Doddy has to ask first: this needs the user's yes on the card.", receipt });
}

/** Error codes that mean a write never reached the point of running at the provider. */
const WRITE_NOT_RUN = new Set(["rate_limited", "quota_exceeded", "busy", "connection_expired", "permission_insufficient"]);

const toolNames = (id: ToolkitId) => CLOUD_TOOLS.filter((t) => t.toolkit === id).map((t) => t.name);

function toolkit(value: string): ToolkitId {
  if (!(TOOLKIT_IDS as readonly string[]).includes(value)) throw new AppError("not_found");
  return value as ToolkitId;
}

function parseScopes(row: ConnectionRow | null): string[] | null {
  if (!row?.scopes_json) return null;
  try {
    const value = JSON.parse(row.scopes_json) as unknown;
    return Array.isArray(value) && value.every((s) => typeof s === "string") ? (value as string[]) : null;
  } catch {
    return null;
  }
}

function grantsOk(def: (typeof TOOLKITS)[ToolkitId], tool: CloudToolDefinition, scopes: string[] | null): boolean {
  return evaluateToolkitGrant(def, scopes) === "ok" && toolHasGrant(tool, def.allowedGrants === null ? [] : scopes);
}

function statusForVerdict(verdict: GrantVerdict): { status: ConnectionRow["status"]; reason: ConnectionReason | null } {
  switch (verdict) {
    case "ok":
      return { status: "connected", reason: null };
    case "too_broad":
      return { status: "permission_insufficient", reason: "grant_too_broad" };
    case "unverifiable":
      return { status: "permission_insufficient", reason: "grant_unverifiable" };
    case "missing":
      return { status: "permission_insufficient", reason: "missing_read_scope" };
  }
}

function blockedSummary(title: string, verdict: GrantVerdict): string {
  return verdict === "too_broad"
    ? `Connected, but the access granted to ${title} is broader than Doddy needs, so Doddy won't use it. Disconnect and reconnect.`
    : `Connected, but Doddy couldn't confirm what access ${title} granted, so it won't use it.`;
}

function parse<T>(schema: { safeParse(v: unknown): { success: true; data: T } | { success: false } }, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success) throw new AppError("invalid_request");
  return result.data;
}

/**
 * A provider failure in the words of the account it came from. The shared default messages in
 * errors.ts name Google Calendar, and the Online accounts screen shows `message` as it is.
 */
function toAppError(error: unknown, title: string): AppError {
  if (error instanceof AppError) return error;
  const p = error instanceof ProviderError ? error : new ProviderError("provider_unavailable");
  return new AppError(p.code, { message: providerMessage(p.code, title), ...(p.retryAfterSeconds !== undefined ? { retryAfterSeconds: p.retryAfterSeconds } : {}) });
}

function providerMessage(code: ProviderError["code"], title: string): string {
  switch (code) {
    case "rate_limited":
      return `${title} is busy right now. Try again shortly.`;
    case "provider_timeout":
      return `${title} took too long to answer. Nothing was changed.`;
    case "malformed_provider_result":
      return `${title} sent an answer Doddy couldn't read, so nothing is shown.`;
    case "connection_expired":
      return `${title} access expired or was removed. Reconnect it in Settings, Online accounts.`;
    case "permission_insufficient":
      return `This ${title} connection doesn't have the access Doddy needs. Reconnect it in Settings, Online accounts.`;
    case "provider_unavailable":
      return `${title} couldn't be reached. Nothing was changed.`;
  }
}

/** A provider's status, error type and hint for the log (content-free); nothing for any other error. */
function providerLog(error: unknown): Record<string, unknown> {
  return error instanceof ProviderError && error.detail
    ? { providerStatus: error.detail.status, providerError: error.detail.type, providerHint: error.detail.hint }
    : {};
}

// ---------------------------------------------------------------- travel

/** The ask-first and receipt name of the trip screen's Gmail search. Not a voice tool. */
export const TRAVEL_SCAN = "find_trips_in_gmail";
/** The search is fixed, so the approval is bound to its query and size. */
const TRAVEL_SCAN_DIGEST = argumentDigest({ query: TRAVEL_GMAIL_QUERY, max: MAX_TRAVEL_EMAILS });
/**
 * Emails read at once: all of them, so the whole search fits in the app's 20-second request
 * (Gmail's answer, then one round of reads, each cut at TRAVEL_READ_TIMEOUT_MS). Each is one small,
 * low-effort model call.
 */
const TRAVEL_READ_PARALLEL = MAX_TRAVEL_EMAILS;
const TravelScanPrepare = z.object({ timeZone: z.string().max(64).optional() }).strict();
const TravelScanRun = z.object({ approvalId: z.string().uuid(), timeZone: z.string().max(64).optional() }).strict();

export interface TravelScanResult {
  mode: "mock" | "live";
  emailsFound: number;
  emailsUnreadable: number;
  emailsNotTravel: number;
  bookings: TravelBooking[];
  receipt: ToolReceipt;
}

// ---------------------------------------------------------------- trip planner

const PlanDay = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const PlanUnderstandRequest = z.object({ words: z.string().trim().min(1).max(600), brief: TripBrief.optional(), today: PlanDay }).strict();
const PlanSearchRequest = z.object({ brief: TripBrief, today: PlanDay }).strict();

export interface PlanUnderstood { brief: TripBrief; missing: Needed[]; assumptions: Assumption[] }
export interface PlanResult {
  brief: TripBrief;
  options: (PlanOption & { links: PlanLinks })[];
  source: "Kiwi.com";
  checkedAt: string;
}
