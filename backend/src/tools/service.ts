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
const webTitle = (tool: WebTool) => (tool === WEB_SEARCH_TOOL ? WEB_SEARCH_COPY.title : MONID_TOOLS[tool].title);

type SectionId = ToolkitId | typeof WEB_SECTION_ID;

/** How far back prepare looks for the same write (ADR-322). Approvals are kept a day past expiry. */
const EARLIER_WINDOW_MS = 86_400_000;

export interface ToolsServiceDeps {
  store: Store;
  provider: ToolsProvider;
  /** Web search through Monid. Null or absent: the section shows "not set up" and never runs. */
  webSearch?: WebSearchProvider | null;
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
  applyMockScenario(userId: string, scenario: ToolsMockScenario | undefined): void {
    if (scenario === undefined) return;
    if (!(this.provider instanceof MockToolsProvider)) {
      throw new AppError("invalid_request", { message: "Demo scenarios exist only in mock mode." });
    }
    this.provider.setScenario(this.store.composioUserId(userId, this.now()), scenario);
  }

  // ---------------------------------------------------------------- queries

  catalog(userId: string): ToolsCatalog {
    return { mode: this.mode, toolkits: [...TOOLKIT_IDS.map((id) => this.view(userId, id)), this.webView(userId)] };
  }

  receipts(userId: string): ToolReceipt[] {
    return this.store.toolReceipts(userId, 30) as ToolReceipt[];
  }

  private view(userId: string, id: ToolkitId): ToolkitView {
    const def = TOOLKITS[id];
    const row = this.store.getConnection(userId, id);
    const cleanup = this.store.cleanupFor(userId, id);
    const enabled = this.store.enabledTools(userId);
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
  private webView(userId: string): ToolkitView {
    const configured = this.webSearch?.isConfigured() === true;
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
          enabled: configured && this.store.toolEnabled(userId, WEB_SEARCH_TOOL),
        },
        ...MONID_TOOL_NAMES.map((name) => ({
          name,
          title: MONID_TOOLS[name].title,
          blurb: MONID_TOOLS[name].blurb,
          risk: "read" as const,
          enabled: configured && this.store.toolEnabled(userId, name),
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
    const existing = this.store.getConnection(userId, id);
    if (existing?.status === "connected") {
      throw new AppError("invalid_request", { message: `${TOOLKITS[id].title} is already connected. Disconnect it first.` });
    }
    // Reconnecting replaces the old connection; a failed remote cleanup is retried first.
    if (existing || this.store.cleanupFor(userId, id)) {
      if ((await this.removeRemote(userId, id)) === "failed") {
        throw new AppError("provider_unavailable", {
          message: `The previous ${TOOLKITS[id].title} connection couldn't be removed yet, so a new one wasn't started. Try again shortly.`,
        });
      }
    }
    const now = this.now();
    const composioUserId = this.store.composioUserId(userId, now);
    const attempt = this.store.createAttempt({
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
      if (this.mode === "live") this.limiter.reserveToolRun(userId, now);
      try {
        return await this.provider.createConnectionLink({ toolkit: id, composioUserId, callbackUrl, signal: this.timeout() });
      } catch (error) {
        throw toAppError(error, TOOLKITS[id].title);
      }
    });
    if (!this.store.setPendingConnection(attempt.attemptId, link.pendingConnectionId, this.now())) {
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
    const attempt = this.store.consumeAttempt({ attemptId: request.attemptId, userId, provider: id, nonce: request.nonce, now });
    if (!attempt) {
      // Too late: the user may have finished at the provider after the attempt expired. That
      // connection can never be completed, so it is removed instead of left live.
      await this.removeQueued(this.store.expireAttempts(now, [id], userId));
      throw new AppError("attempt_invalid");
    }

    const composioUserId = this.store.composioUserId(userId, now);
    const fail = (errorCode: string, summary: string): never => {
      throw new AppError("attempt_invalid", { message: summary, receipt: this.receipt(userId, id, "connect", null, "failed", summary, errorCode, null) });
    };
    const done = (status: ReceiptStatus, summary: string, errorCode: string | null = null): ToolkitResult => ({
      toolkit: this.view(userId, id),
      receipt: this.receipt(userId, id, "connect", null, status, summary, errorCode, null),
    });

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
    fail: (errorCode: string, summary: string) => never,
    done: (status: ReceiptStatus, summary: string, errorCode?: string | null) => ToolkitResult,
    touched: (string | null)[],
    markRecorded: () => void,
  ): Promise<ToolkitResult> {
    const result = request.result;
    if (result.kind === "canceled") return done("canceled", "Connecting was canceled. Nothing was connected.");
    if (result.kind !== this.deps.completionMode) return fail("completion_mode_mismatch", "This completion isn't accepted by this server.");

    try {
      let connectionId: string;
      if (result.kind === "mock") {
        const mocked = await this.provider.completeMock({ toolkit: id, composioUserId, approve: result.outcome === "approve" });
        if (!mocked) return done("failed", "Access wasn't granted. Nothing was connected.", "access_denied");
        connectionId = mocked.connectionId;
        touched.push(connectionId);
      } else if (result.kind === "callback") {
        // The redirect's status and ID are hints only; the server re-reads status and ownership below.
        if (result.status !== "success") return done("failed", `${title} wasn't connected.`, "provider_reported_failure");
        if (!result.connectedAccountId || result.connectedAccountId !== attempt.pending_connection_id) {
          return fail("attempt_mismatch", "The connection didn't match this attempt. Nothing was connected.");
        }
        connectionId = result.connectedAccountId;
      } else {
        const verified = await this.provider.completeVerifiedAuth({ composioUserId, sessionUri: result.sessionUri, signal: this.timeout() });
        touched.push(verified.connectionId); // redeemed for this user's own Composio id
        if (verified.connectionId !== attempt.pending_connection_id) {
          return fail("attempt_mismatch", "The connection didn't match this attempt. Nothing was connected.");
        }
        connectionId = verified.connectionId;
      }

      const connection = await this.provider.getConnection({ connectionId, signal: this.timeout() });
      const owned = await this.provider.isOwnedBy({ toolkit: id, connectionId, composioUserId, signal: this.timeout() });
      if (!owned || connection.id !== connectionId || connection.toolkitSlug !== TOOLKITS[id].composioToolkit || connection.authConfigId !== this.provider.authConfigId(id)) {
        return fail("verification_failed", "The connection couldn't be verified. Nothing was connected.");
      }
      if (connection.status !== "active") return fail(`connection_${connection.status}`, `${title} didn't finish connecting.`);

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
      this.store.upsertConnection({
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
      this.store.disableTools(userId, toolNames(id), this.now());
      return verdict === "ok"
        ? done("succeeded", `${title} connected. Its tools are off until you switch them on.`)
        : done("blocked", blockedSummary(title, verdict), reason);
    } catch (error) {
      if (error instanceof AppError) throw error;
      const appError = toAppError(error, title);
      throw new AppError(appError.code, { ...appError.options, receipt: this.receipt(userId, id, "connect", null, "failed", `${title} couldn't be connected.`, appError.code, null) });
    }
  }

  async disconnect(userId: string, toolkitId: string, body: unknown): Promise<ToolkitResult> {
    if (toolkitId === WEB_SECTION_ID) {
      // Older app builds show a Disconnect button for every section; for web search it means "off".
      parse(EmptyRequestSchema, body);
      for (const name of [WEB_SEARCH_TOOL, ...MONID_TOOL_NAMES]) this.store.setToolEnabled(userId, name, false, this.now());
      const summary = "Web search has no account to disconnect; it was switched off.";
      return { toolkit: this.webView(userId), receipt: this.receipt(userId, WEB_SECTION_ID, "disconnect", null, "succeeded", summary, null, null) };
    }
    const id = toolkit(toolkitId);
    parse(EmptyRequestSchema, body);
    const title = TOOLKITS[id].title;
    // Switches go off first, so nothing can run during or after the disconnect.
    this.store.disableTools(userId, toolNames(id), this.now());
    const hadLocal = this.store.getConnection(userId, id) !== null;
    const pendingBefore = this.store.cleanupFor(userId, id);
    if (!hadLocal && !pendingBefore) {
      return { toolkit: this.view(userId, id), receipt: this.receipt(userId, id, "disconnect", null, "succeeded", `${title} was already disconnected.`, null, null) };
    }
    const remote = await this.removeRemote(userId, id);
    const receipt =
      remote === "removed"
        ? this.receipt(userId, id, "disconnect", null, "succeeded", `Disconnected. Doddy's access to ${title} was removed.`, null, null)
        : this.receipt(
            userId,
            id,
            "disconnect",
            null,
            "outcome_unknown",
            `Disconnected in Doddy. Removing access at ${title} couldn't be confirmed; try again or remove Doddy in the ${title} account settings.`,
            "remote_cleanup_failed",
            null,
          );
    return { toolkit: this.view(userId, id), receipt };
  }

  /**
   * Hourly (app.ts): ends attempts nobody completed in time and removes their connections at the
   * provider, then retries removals that failed earlier. Without it, a user who finished a
   * provider's consent after leaving Doddy would keep a grant no one tracks once `prune` drops the attempt.
   */
  async sweepAbandoned(): Promise<void> {
    const now = this.now();
    const toolkits = Object.keys(TOOLKITS);
    const ended = this.store.expireAttempts(now, toolkits);
    const retry = this.store.cleanupsToRetry(toolkits, now - CLEANUP_RETRY.afterMs, CLEANUP_RETRY.maxTries, CLEANUP_RETRY.perSweep);
    await this.removeQueued([...ended, ...retry]);
  }

  /** Removes connections a failed completion left at the provider; a failure stays queued and visible. */
  private async discardRemote(userId: string, id: ToolkitId, ids: (string | null)[]): Promise<void> {
    const queued = [...new Set(ids.filter((c): c is string => !!c))].map((connectionId) => {
      this.store.queueCleanup(connectionId, userId, id, this.now());
      return { connectionId, userId, provider: id };
    });
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
      if (result === "removed") this.store.finishCleanup(connectionId);
      else this.store.failCleanup(connectionId, "remote_cleanup_failed");
    }
  }

  private async removeRemote(userId: string, id: ToolkitId): Promise<"removed" | "failed"> {
    const removed = this.store.removeConnectionForCleanup(userId, id, this.now());
    const cleanup = this.store.cleanupFor(userId, id);
    const connectionId = removed?.connection_id ?? cleanup?.connection_id;
    if (!connectionId) return "removed";
    let result: "removed" | "failed";
    try {
      result = await this.provider.removeConnection({ connectionId, signal: this.timeout() });
    } catch {
      result = "failed";
    }
    if (result === "removed") this.store.finishCleanup(connectionId);
    else this.store.failCleanup(connectionId, "remote_cleanup_failed");
    return result;
  }

  // ---------------------------------------------------------------- switches

  setSwitch(userId: string, body: unknown): ToolkitResult {
    const request = parse(SwitchRequestSchema, body);
    if (isWebTool(request.tool)) {
      if (request.enabled && this.webSearch?.isConfigured() !== true) {
        throw new AppError("live_not_configured", { message: "Web search isn't set up on this server." });
      }
      this.store.setToolEnabled(userId, request.tool, request.enabled, this.now());
      const summary = `${webTitle(request.tool)} switched ${request.enabled ? "on" : "off"}.`;
      return { toolkit: this.webView(userId), receipt: this.receipt(userId, WEB_SECTION_ID, "switch", request.tool, "succeeded", summary, null, null) };
    }
    const tool = cloudTool(request.tool);
    if (!tool) throw new AppError("not_found", { message: "That tool doesn't exist." });
    const def = TOOLKITS[tool.toolkit];
    const row = this.store.getConnection(userId, tool.toolkit);
    if (request.enabled) {
      this.requireConfigured(tool.toolkit);
      const reason = this.blockReason(row, def, tool);
      if (reason) throw new AppError(reason.code, { message: reason.message(def.title) });
    }
    this.store.setToolEnabled(userId, tool.name, request.enabled, this.now());
    const copy = TOOL_COPY[tool.name]?.title ?? tool.name;
    return {
      toolkit: this.view(userId, tool.toolkit),
      receipt: this.receipt(userId, tool.toolkit, "switch", tool.name, "succeeded", `${copy} switched ${request.enabled ? "on" : "off"}.`, null, null),
    };
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
    this.limiter.reserveRequest(userId, now);
    const row = this.checkUsable(userId, tool, tool.risk);
    if (tool.risk === "read") {
      const { approvalId, expiresAt } = this.ask.issue({ userId, tool: tool.name, accountId: row.connection_id, argsDigest: argumentDigest(args) });
      return { mode: this.mode, tool: tool.name, preview: tool.preview(args, null), approvalId, expiresAt: new Date(expiresAt).toISOString() };
    }
    let target: ResolvedTarget | null = null;
    if (tool.resolve) {
      this.reserveRuns(userId, tool, now, 1);
      const composioUserId = this.store.composioUserId(userId, now);
      try {
        target = (await this.limiter.withSlot(userId, () => this.lookup(userId, tool, args, composioUserId, row.connection_id, context))).target;
      } catch (error) {
        throw this.failure(userId, tool, error, false);
      }
    }
    const argsDigest = approvalDigest(args, target);
    const { approvalId, expiresAt } = this.ask.issue({ userId, tool: tool.name, accountId: row.connection_id, argsDigest });
    const preview = tool.preview(args, target);
    const result: PrepareResult = { mode: this.mode, tool: tool.name, preview, approvalId, expiresAt: new Date(expiresAt).toISOString() };
    const latest = this.store.latestWrite({ userId, capability: tool.name, argsDigest, since: now - EARLIER_WINDOW_MS });
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
    if (!finder || !this.store.toolEnabled(userId, finder.tool.name)) return false;
    try {
      this.limiter.reserveToolRun(userId, now);
      const listArgs = finder.arguments(args);
      const composioUserId = this.store.composioUserId(userId, now);
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
  private repeatOfUsedApproval(userId: string, tool: CloudToolDefinition, args: Record<string, unknown>, approvalId: string, accountId: string): RunResult | null {
    // A tool with a lookup bound its approval to the target as it was then, which can't be read
    // again (a completed task is gone), so it is matched without the digest and its answer uses
    // no words from this request.
    const earlier = this.store.approvalOutcome({
      approvalId, userId, capability: tool.name, accountId, argsDigest: tool.resolve ? null : argumentDigest(args),
    });
    if (!earlier) return null;
    const title = TOOLKITS[tool.toolkit].title;
    if (earlier.outcome === "succeeded" && tool.replay) {
      const outcome = tool.replay(args, earlier.externalId);
      const receipt = this.receipt(userId, tool.toolkit, "write", tool.name, "succeeded", `${outcome.summary} Answer from the first try; nothing ran again.`, null, null);
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
        receipt: this.receipt(userId, tool.toolkit, "write", tool.name, "blocked", "Not done: it wasn't confirmed.", "confirmation_required", null),
      });
    }
    // Unknown, or used but not finished (still running, or the server stopped mid-run).
    throw new AppError("capability_disabled", {
      message: "The first try with this confirmation may or may not have gone through.",
      receipt: this.receipt(userId, tool.toolkit, "write", tool.name, "outcome_unknown",
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
      receipt: this.receipt(userId, tool.toolkit, "write", tool.name, "blocked", `Not done: ${message}`, "not_found", result.providerReference),
    });
  }

  /** Reserves today's tool runs for this call, with a blocked receipt when a Doddy limit says no. */
  private reserveRuns(userId: string, tool: CloudToolDefinition, now: number, units: number): void {
    try {
      this.limiter.reserveToolRun(userId, now, units);
    } catch (error) {
      if (error instanceof AppError) {
        const op = tool.risk === "write" ? "write" : "read";
        throw new AppError(error.code, { ...error.options, receipt: this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: a Doddy limit was reached.", error.code, null) });
      }
      throw error;
    }
  }

  /**
   * Turns a provider failure into an AppError with a receipt. A write is "outcome_unknown" only once
   * the write itself was sent (`writeSent`) and the error doesn't prove it never ran (DOD-08).
   */
  private failure(userId: string, tool: CloudToolDefinition, error: unknown, writeSent: boolean): AppError {
    if (error instanceof AppError) return error;
    const title = TOOLKITS[tool.toolkit].title;
    const appError = toAppError(error, title);
    const op = tool.risk === "write" ? "write" : "read";
    if (appError.code === "connection_expired") {
      this.store.updateConnectionStatus(userId, tool.toolkit, "expired", "revoked_or_expired", this.now());
      this.store.disableTools(userId, toolNames(tool.toolkit), this.now());
    }
    const unknown = op === "write" && writeSent && !WRITE_NOT_RUN.has(appError.code);
    const summary = unknown
      ? `${title} didn't confirm; it may or may not have gone through. Check there before trying again.`
      : op === "write"
        ? `${title} wasn't reached or its answer couldn't be used. Nothing was changed.`
        : `${title} wasn't reached or its answer couldn't be used. Nothing is shown instead.`;
    const receipt = this.receipt(userId, tool.toolkit, op, tool.name, unknown ? "outcome_unknown" : "failed", summary, appError.code, null);
    // The message matches the receipt: "Nothing was changed" would be false for a write that may have run.
    return new AppError(appError.code, { ...appError.options, message: unknown ? summary : appError.message, receipt });
  }

  async run(userId: string, body: unknown): Promise<RunResult> {
    const request = parse(RunRequestSchema, body);
    if (isWebTool(request.tool)) return this.runWebSearch(userId, request.tool, request);
    const tool = this.requireTool(request.tool);
    const args = parse(tool.input, request.arguments);
    if (!isSupportedTimeZone(request.timeZone)) {
      throw new AppError("invalid_request", { message: "Use an IANA time zone such as Europe/Warsaw." });
    }
    const op = tool.risk === "write" ? "write" : "read";
    const now = this.now();
    this.limiter.reserveRequest(userId, now);
    const row = this.checkUsable(userId, tool, op);

    // A write's approval is checked here but only used up right before the provider call, so a
    // limit or "busy" refusal in between doesn't cost the user their confirmation. For a tool with
    // a lookup the approval is bound to the target too, so before the lookup only its presence is checked.
    // ASK-01: reads are bound to their arguments only (nothing was looked up before the yes).
    const binding = (target: ResolvedTarget | null): AskBinding => ({
      userId, tool: tool.name, accountId: row.connection_id, argsDigest: op === "write" ? approvalDigest(args, target) : argumentDigest(args),
    });
    const approval = (target: ResolvedTarget | null, checkOnly: boolean) => this.ask.allows(binding(target), request.approvalId, checkOnly ? "check" : "use");
    const unconfirmed = () =>
      op === "write"
        ? new AppError("capability_disabled", {
            message: "This action needs a fresh confirmation.",
            receipt: this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: it wasn't confirmed.", "confirmation_required", null),
          })
        : askFirstRefusal(this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    if (tool.risk === "write" && request.approvalId !== undefined) {
      const repeat = this.repeatOfUsedApproval(userId, tool, args, request.approvalId, row.connection_id);
      if (repeat) return repeat;
    }
    if (tool.risk === "write" && (tool.resolve ? request.approvalId === undefined : !approval(null, true))) throw unconfirmed();
    if (tool.risk === "read" && !approval(null, true)) throw unconfirmed();

    // A lookup (before a write, or the search before a read) counts as one more run, reserved together with the main call.
    this.reserveRuns(userId, tool, now, tool.resolve ? 2 : 1);

    const composioUserId = this.store.composioUserId(userId, now);
    let writeSent = false;
    // Set once this run used up its approval, so its outcome is recorded against it (ADR-322).
    let used: string | null = null;
    try {
      return await this.limiter.withSlot(userId, async () => {
        // A read's yes is used up before anything is read, its lookup included: one yes, one read.
        if (tool.risk === "read" && !approval(null, false)) throw unconfirmed();
        // The target is read again right before the write: if it is gone, done, or no longer what the
        // card showed, the approval doesn't match and nothing is written. A read looks up what it opens.
        const found = tool.resolve ? await this.lookup(userId, tool, args, composioUserId, row.connection_id, { timeZone: request.timeZone }) : null;
        if (found?.missing) {
          // Reads only (a write's miss throws): nothing matched, so the main slug isn't run.
          const summary = tool.resolve!.missSummary ?? "Nothing matched.";
          const receipt = this.receipt(userId, tool.toolkit, op, tool.name, "succeeded", summary, null, null);
          return { mode: this.mode, tool: tool.name, text: found.missing, count: 0, truncated: false, receipt };
        }
        const target = found?.target ?? null;
        // Used up here, once: a parallel run with the same approval loses the race and does nothing.
        if (tool.risk === "write" && !approval(target, false)) throw unconfirmed();
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
        if (row.status === "error") this.store.updateConnectionStatus(userId, tool.toolkit, "connected", null, this.now());
        const receipt = this.receipt(userId, tool.toolkit, op, tool.name, "succeeded", outcome.summary, null, result.providerReference);
        if (used) this.store.finishApproval(used, "succeeded", outcome.externalId ?? null, this.now());
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
        this.store.finishApproval(used, WRITE_NOT_RUN.has(code) ? "failed" : "outcome_unknown", null, this.now());
      }
      throw this.failure(userId, tool, error, writeSent);
    }
  }

  /**
   * The card for web search, news or places (ASK-01): the exact words, and what Doddy pays for it
   * (ADR-489: the price is on the card). Nothing is searched.
   */
  private prepareWebSearch(userId: string, tool: WebTool, raw: Record<string, unknown>): PrepareResult {
    const args = tool === WEB_SEARCH_TOOL ? parse(WebSearchInput, raw) : parse(MONID_TOOL_INPUT[tool], raw);
    const now = this.now();
    this.limiter.reserveRequest(userId, now);
    const blocked = (code: "capability_disabled" | "live_not_configured", message: string): never => {
      throw new AppError(code, { message, receipt: this.receipt(userId, WEB_SECTION_ID, "read", tool, "blocked", `Not done: ${message}`, code, null) });
    };
    if (!this.webSearch || !this.webSearch.isConfigured()) return blocked("live_not_configured", "Web search isn't set up on this server.");
    if (!this.store.toolEnabled(userId, tool)) return blocked("capability_disabled", `${webTitle(tool)} is turned off in Settings.`);
    const { approvalId, expiresAt } = this.ask.issue({ userId, tool, accountId: WEB_ACCOUNT, argsDigest: argumentDigest(args) });
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
    this.limiter.reserveRequest(userId, now);
    const blocked = (code: "capability_disabled" | "live_not_configured" | "quota_exceeded", message: string, errorCode: string = code): never => {
      throw new AppError(code, { message, receipt: this.receipt(userId, WEB_SECTION_ID, "read", tool, "blocked", `Not done: ${message}`, errorCode, null) });
    };
    const provider = this.webSearch;
    if (!provider || !provider.isConfigured()) return blocked("live_not_configured", "Web search isn't set up on this server.");
    if (!this.store.toolEnabled(userId, tool)) return blocked("capability_disabled", `${webTitle(tool)} is turned off in Settings.`);
    // ASK-01: the user's yes for exactly these words, checked before the search is counted.
    const binding: AskBinding = { userId, tool, accountId: WEB_ACCOUNT, argsDigest: argumentDigest(args) };
    const unasked = () => askFirstRefusal(this.receipt(userId, WEB_SECTION_ID, "read", tool, "blocked", "Not done: Doddy didn't have a yes for this.", "ask_first_required", null));
    if (!this.ask.allows(binding, request.approvalId, "check")) throw unasked();
    try {
      this.limiter.reserveWebSearch(userId, now);
    } catch (error) {
      if (error instanceof AppError) return blocked("quota_exceeded", "Today's web search limit was reached.", error.code);
      throw error;
    }

    try {
      return await this.limiter.withSlot(userId, async () => {
        if (!this.ask.allows(binding, request.approvalId, "use")) throw unasked();
        const signal = AbortSignal.timeout(WEB_SEARCH_TIMEOUT_MS);
        const result = tool === WEB_SEARCH_TOOL
          ? await provider.search({ query: args.query as string, signal })
          : await provider.call({ tool, args, signal });
        const outcome = tool === WEB_SEARCH_TOOL ? normalizeWebSearch(result.output, args.query as string) : normalizeMonidTool(tool, result.output, args);
        const receipt = this.receipt(userId, WEB_SECTION_ID, "read", tool, "succeeded", outcome.summary, null, result.runId);
        return { mode: this.mode, tool, text: outcome.text, count: outcome.count, truncated: outcome.truncated, receipt };
      });
    } catch (error) {
      if (error instanceof AppError) throw error;
      const appError = toAppError(error, webTitle(tool));
      const message =
        appError.code === "rate_limited" ? "Web search is busy right now. Try again shortly." : appError.code === "malformed_provider_result" ? "Web search sent an answer Doddy couldn't read, so nothing is shown." : "Web search couldn't be reached. Nothing is shown instead.";
      const receipt = this.receipt(userId, WEB_SECTION_ID, "read", tool, "failed", message, appError.code, null);
      throw new AppError(appError.code, { ...appError.options, message, receipt });
    }
  }

  // ---------------------------------------------------------------- helpers

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
  private checkUsable(userId: string, tool: CloudToolDefinition, op: "read" | "write"): ConnectionRow {
    const def = TOOLKITS[tool.toolkit];
    const blocked = (code: "not_connected" | "permission_insufficient" | "connection_expired" | "capability_disabled", message: string): never => {
      throw new AppError(code, { message, receipt: this.receipt(userId, tool.toolkit, op, tool.name, "blocked", `Not done: ${message}`.slice(0, 200), code, null) });
    };
    if (!this.provider.isConfigured(tool.toolkit)) return blocked("not_connected", `${def.title} isn't set up on this server.`);
    if (!this.store.toolEnabled(userId, tool.name)) {
      return blocked("capability_disabled", `${TOOL_COPY[tool.name]?.title ?? tool.name} is turned off in Settings.`);
    }
    const row = this.store.getConnection(userId, tool.toolkit);
    const reason = this.blockReason(row, def, tool);
    if (reason || !row) return blocked(reason?.code ?? "not_connected", (reason?.message ?? ((t: string) => `${t} isn't connected.`))(def.title));
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

  private receipt(
    userId: string,
    id: SectionId,
    operation: ToolReceipt["operation"],
    tool: string | null,
    status: ReceiptStatus,
    summary: string,
    errorCode: string | null,
    providerReference: string | null,
  ): ToolReceipt {
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
    this.store.saveToolReceipt(userId, receipt, this.now());
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
