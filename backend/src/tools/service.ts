import { randomUUID } from "node:crypto";
import { type CompleteRequest, CompleteRequestSchema, type ConnectionReason, type ConnectResponse, EmptyRequestSchema, type ReceiptStatus } from "../contracts.js";
import type { Limits } from "../config.js";
import { AppError, ProviderError } from "../errors.js";
import { argumentDigest, UsageLimiter } from "../policy.js";
import { AskGate, type AskBinding, WEB_ACCOUNT } from "./askFirst.js";
import { CLEANUP_RETRY, type ConnectionRow, type QueuedCleanup, type Store } from "../store.js";
import { isSupportedTimeZone } from "../time.js";
import {
  CLOUD_TOOLS,
  type CloudToolDefinition,
  type Context,
  cloudTool,
  evaluateToolkitGrant,
  type GrantVerdict,
  type ResolvedTarget,
  TOOL_COPY,
  TOOLKIT_IDS,
  TOOLKITS,
  type ToolkitId,
  toolHasGrant,
} from "./catalog.js";
import {
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
  claudeCard,
  DOCUMENT_TIMEOUT_MS,
  fileName,
  isClaudeTool,
  KIND_INFO,
  MakeDocumentInput,
  type MakeDocumentArgs,
} from "./claude.js";
import type { DocumentLinks } from "../documents.js";
import { MockToolsProvider, type ToolsMockScenario } from "./mock.js";
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
 * Web lookups are on until the user switches them off (ADR-562). Before, every one started off and
 * the only switch was in a Settings screen the app could not reach without a hand-made server
 * token, so "what's the weather?" could never be answered. ASK-01 still asks before every search.
 */
const WEB_TOOLS_ON_BY_DEFAULT: ReadonlySet<WebTool> = new Set<WebTool>([WEB_SEARCH_TOOL, ...MONID_TOOL_NAMES]);
const webTitle = (tool: WebTool) => (tool === WEB_SEARCH_TOOL ? WEB_SEARCH_COPY.title : MONID_TOOLS[tool].title);

type SectionId = ToolkitId | typeof WEB_SECTION_ID | typeof CLAUDE_SECTION_ID;
/** Claude runs have no account either; the approval is bound to this fixed account name. */
const CLAUDE_ACCOUNT = "claude";

/** How far back prepare looks for the same write (ADR-322). Approvals are kept a day past expiry. */
const EARLIER_WINDOW_MS = 86_400_000;

export interface ToolsServiceDeps {
  store: Store;
  provider: ToolsProvider;
  /** Web search through Monid. Null or absent: the section shows "not set up" and never runs. */
  webSearch?: WebSearchProvider | null;
  /** Claude (ADR-563). Null or absent: ask_claude and make_document say "not set up". */
  claude?: ClaudeProvider | null;
  /** Signed links for documents (ADR-563). Null: make_document says "not set up". */
  documentLinks?: DocumentLinks | null;
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
  /** Document jobs still running after their reply (ADR-563); tests wait on them. */
  private readonly background = new Set<Promise<void>>();

  constructor(private readonly deps: ToolsServiceDeps) {
    this.mode = deps.provider.mode;
    if ((deps.completionMode === "mock") !== (this.mode === "mock")) {
      throw new Error("mock completion is only valid with the mock provider");
    }
    this.store = deps.store;
    this.provider = deps.provider;
    this.webSearch = deps.webSearch ?? null;
    if (this.webSearch && this.webSearch.mode !== this.mode) throw new Error("web search and online accounts must both be mock or both live");
    this.limits = deps.limits;
    this.limiter = new UsageLimiter(deps.store, deps.limits);
    this.now = deps.now ?? Date.now;
    this.ask = new AskGate(deps.store, this.now);
    this.sleep = deps.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
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
      // ADR-562: connecting is the user saying "use this", usually from the Connect card in the
      // middle of a request, so the account's tools come on with it. ASK-01 is unchanged: every
      // read still asks, and every send, change or delete still needs a tap on its exact card.
      for (const name of toolNames(id)) await this.store.setToolEnabled(userId, name, true, this.now());
      return await done("succeeded", `${title} connected. Doddy can use it now; he still asks before every look and every change.`);
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
    const retry = await this.store.cleanupsToRetry(toolkits, now - CLEANUP_RETRY.afterMs, CLEANUP_RETRY.maxTries, CLEANUP_RETRY.perSweep);
    await this.removeQueued([...ended, ...retry]);
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
      else await this.store.failCleanup(connectionId, "remote_cleanup_failed");
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
    else await this.store.failCleanup(connectionId, "remote_cleanup_failed");
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

  // ---------------------------------------------------------------- prepare / run

  /**
   * Every tool (ASK-01, ADR-483). Shows exactly what would happen and returns a single-use approval
   * for those arguments; `run` refuses without it. A read's card is made from its arguments alone:
   * nothing is read from the account before the yes. For a write, A tool with a `resolve` lookup first reads its target from the provider (a read,
   * counted like one; never the write), shows that in the preview, and binds the approval to it too.
   * If the same write ran in the last day, the card says so (ADR-322); after a try whose outcome is
   * unknown, a write that can be looked for is looked for first.
   */
  async prepare(userId: string, body: unknown): Promise<PrepareResult> {
    const request = parse(PrepareRequestSchema, body);
    if (isWebTool(request.tool)) return this.prepareWebSearch(userId, request.tool, request.arguments);
    if (isClaudeTool(request.tool)) return this.prepareClaude(userId, request.tool, request.arguments);
    const tool = this.requireTool(request.tool);
    const args = parse(tool.input, request.arguments);
    if (request.timeZone !== undefined && !isSupportedTimeZone(request.timeZone)) {
      throw new AppError("invalid_request", { message: "Use an IANA time zone such as Europe/Warsaw." });
    }
    if (tool.resolve?.needsTimeZone && request.timeZone === undefined) {
      throw new AppError("invalid_request", { message: "This tool needs the user's time zone." });
    }
    const context: Context | undefined = request.timeZone === undefined ? undefined : { timeZone: request.timeZone };
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
        throw await this.failure(userId, tool, error, false);
      }
    }
    const argsDigest = approvalDigest(args, target);
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

  /**
   * After a try whose outcome is unknown: looks for the write with the tool's own read, only if
   * the user has that read switched on. True only when it is found; any failure or "not listed"
   * is false, which proves nothing (ADR-322).
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
   * A repeated run of an approval that was already used (the phone lost the answer): what happened
   * the first time answers it, and nothing runs again (ADR-322). Null when it was never used.
   */
  private async repeatOfUsedApproval(userId: string, tool: CloudToolDefinition, args: Record<string, unknown>, approvalId: string, accountId: string): Promise<RunResult | null> {
    // A tool with a lookup bound its approval to the target as it was then, which can't be read
    // again (a completed task is gone), so it is matched without the digest and its answer uses
    // no words from this request.
    const earlier = await this.store.approvalOutcome({
      approvalId, userId, capability: tool.name, accountId, argsDigest: tool.resolve ? null : argumentDigest(args),
    });
    if (!earlier) return null;
    const title = TOOLKITS[tool.toolkit].title;
    if (earlier.outcome === "succeeded" && tool.replay) {
      const outcome = tool.replay(args, earlier.externalId);
      const receipt = await this.receipt(userId, tool.toolkit, "write", tool.name, "succeeded", `${outcome.summary} Answer from the first try; nothing ran again.`, null, null);
      return {
        mode: this.mode, tool: tool.name, text: outcome.text, count: outcome.count, truncated: outcome.truncated,
        ...(outcome.externalId ? { externalId: outcome.externalId } : {}),
        replayed: true,
        receipt,
      };
    }
    if (earlier.outcome === "failed") {
      throw new AppError("capability_disabled", {
        message: "This action needs a fresh confirmation.",
        receipt: await this.receipt(userId, tool.toolkit, "write", tool.name, "blocked", "Not done: it wasn't confirmed.", "confirmation_required", null),
      });
    }
    // Unknown, or used but not finished (still running, or the server stopped mid-run).
    throw new AppError("capability_disabled", {
      message: "The first try with this confirmation may or may not have gone through.",
      receipt: await this.receipt(userId, tool.toolkit, "write", tool.name, "outcome_unknown",
        `${title} didn't confirm the first try; it may or may not have gone through. Check there before trying again.`, "earlier_outcome_unknown", null),
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
    const message = found?.message ?? lookup.notFound;
    if (tool.risk === "read") return { target: null, missing: message };
    throw new AppError("not_found", {
      message,
      receipt: await this.receipt(userId, tool.toolkit, "write", tool.name, "blocked", `Not done: ${message}`, "not_found", result.providerReference),
    });
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
    if (isWebTool(request.tool)) return this.runWebSearch(userId, request.tool, request);
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

    // A write's approval is checked here but only used up right before the provider call, so a
    // limit or "busy" refusal in between doesn't cost the user their confirmation. For a tool with
    // a lookup the approval is bound to the target too, so before the lookup only its presence is checked.
    // ASK-01: reads are bound to their arguments only (nothing was looked up before the yes).
    const binding = (target: ResolvedTarget | null): AskBinding => ({
      userId, tool: tool.name, accountId: row.connection_id, argsDigest: op === "write" ? approvalDigest(args, target) : argumentDigest(args),
    });
    const approval = (target: ResolvedTarget | null, checkOnly: boolean) => this.ask.allows(binding(target), request.approvalId, checkOnly ? "check" : "use");
    const unconfirmed = async () =>
      op === "write"
        ? new AppError("capability_disabled", {
            message: "This action needs a fresh confirmation.",
            receipt: await this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: it wasn't confirmed.", "confirmation_required", null),
          })
        : askFirstRefusal(await this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    if (tool.risk === "write" && request.approvalId !== undefined) {
      const repeat = await this.repeatOfUsedApproval(userId, tool, args, request.approvalId, row.connection_id);
      if (repeat) return repeat;
    }
    if (tool.risk === "write" && (tool.resolve ? request.approvalId === undefined : !(await approval(null, true)))) throw await unconfirmed();
    if (tool.risk === "read" && !(await approval(null, true))) throw await unconfirmed();

    // A lookup (before a write, or the search before a read) counts as one more run, reserved together with the main call.
    await this.reserveRuns(userId, tool, now, tool.resolve ? 2 : 1);

    const composioUserId = await this.store.composioUserId(userId, now);
    let writeSent = false;
    // Set once this run used up its approval, so its outcome is recorded against it (ADR-322).
    let used: string | null = null;
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
        if (used) await this.store.finishApproval(used, "succeeded", outcome.externalId ?? null, this.now());
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

  // ---------------------------------------------------------------- Claude (ADR-563)

  /** Waits for document jobs still running in the background (tests, shutdown). */
  async settle(): Promise<void> {
    while (this.background.size > 0) await Promise.allSettled([...this.background]);
  }

  private claudeArgs(tool: ClaudeToolName, raw: Record<string, unknown>): Record<string, unknown> {
    return tool === ASK_CLAUDE_TOOL ? parse(AskClaudeInput, raw) : parse(MakeDocumentInput, raw);
  }

  private claudeReady(tool: ClaudeToolName): string | null {
    if (!this.deps.claude || !this.deps.claude.isConfigured()) return "Claude isn't set up on this server.";
    if (tool !== ASK_CLAUDE_TOOL && !this.deps.documentLinks) return "Making files isn't set up on this server.";
    return null;
  }

  /** ASK-01: a card from the arguments alone and a single-use approval. Nothing goes to Anthropic yet. */
  private async prepareClaude(userId: string, tool: ClaudeToolName, raw: Record<string, unknown>): Promise<PrepareResult> {
    const args = this.claudeArgs(tool, raw);
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
    try {
      await this.limiter.reserveClaude(userId, now);
    } catch (error) {
      if (error instanceof AppError) return await blocked("quota_exceeded", "Today's Claude limit was reached.", error.code);
      throw error;
    }
    if (!(await this.ask.allows(binding, request.approvalId, "use"))) throw await unasked();

    if (tool === ASK_CLAUDE_TOOL) {
      try {
        const answer = await claude.ask(args as never, AbortSignal.timeout(ASK_CLAUDE_TIMEOUT_MS));
        const text = `Claude's answer (written for this user; read it out or sum it up, in your own words if it's long):\n${answer.text}`;
        const receipt = await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "succeeded", "Asked Claude.", null, null);
        return { mode: this.mode, tool, text, count: 1, truncated: false, receipt };
      } catch (error) {
        const appError = toAppError(error, "Claude");
        const message = appError.code === "provider_timeout" ? "Claude took too long. For something long, ask Doddy to make it as a document." : appError.code === "rate_limited" ? "Claude is busy right now. Try again shortly." : "Claude couldn't be reached. Nothing is shown instead.";
        const receipt = await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "failed", message, appError.code, null);
        throw new AppError(appError.code, { ...appError.options, message, receipt });
      }
    }

    const doc = args as MakeDocumentArgs;
    const info = KIND_INFO[doc.kind];
    const name = fileName(doc.title, info.ext);
    const id = await this.store.startDocument(userId, name, info.mime, now);
    const url = this.deps.documentLinks!.link(id, new Date(now));
    const job = this.makeDocumentInBackground(id, doc, claude).finally(() => this.background.delete(job));
    this.background.add(job);
    const receipt = await this.receipt(userId, CLAUDE_SECTION_ID, "read", tool, "succeeded", `Started a ${info.label}: ${doc.title}`.slice(0, 200), null, null);
    return {
      mode: this.mode,
      tool,
      text:
        `started: Claude is making the ${info.label} "${doc.title}". It takes one to three minutes. ` +
        "A button to open it is on the user's screen now; it shows the file as soon as it's ready. Tell the user that in one sentence. Don't read out any link.",
      count: 1,
      truncated: false,
      document: { url, name, kind: doc.kind, status: "working" },
      receipt,
    };
  }

  private async makeDocumentInBackground(id: string, args: MakeDocumentArgs, claude: ClaudeProvider): Promise<void> {
    try {
      const file = await claude.makeDocument(args, AbortSignal.timeout(DOCUMENT_TIMEOUT_MS));
      await this.store.finishDocument(id, file.name, file.mime, file.bytes);
      this.deps.log?.({ level: "info", event: "document_ready", kind: args.kind, bytes: file.bytes.length });
    } catch (error) {
      await this.store.failDocument(id).catch(() => {});
      // Content-free: the kind and the error class only.
      this.deps.log?.({ level: "error", event: "document_failed", kind: args.kind, code: error instanceof ProviderError ? error.code : "internal" });
    }
  }

  // ---------------------------------------------------------------- helpers

  /** A web tool's switch: what the user chose, else the default (ADR-562). */
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
    // ADR-562: the account first, then the switch, so a request for an account that isn't
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
 * What an approval is bound to: the validated arguments, plus, for a tool with a lookup, the target
 * the card showed (so a task that changed since the card needs a fresh confirmation).
 */
function approvalDigest(args: Record<string, unknown>, target: ResolvedTarget | null): string {
  return target === null ? argumentDigest(args) : argumentDigest({ arguments: args, target });
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
