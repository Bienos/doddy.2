import { randomUUID } from "node:crypto";
import { CompleteRequestSchema, type ConnectionReason, type ConnectResponse, EmptyRequestSchema, type ReceiptStatus } from "../contracts.js";
import type { Limits } from "../config.js";
import { AppError, ProviderError } from "../errors.js";
import { argumentDigest, UsageLimiter } from "../policy.js";
import type { ConnectionRow, Store } from "../store.js";
import { isSupportedTimeZone } from "../time.js";
import {
  CLOUD_TOOLS,
  type CloudToolDefinition,
  cloudTool,
  evaluateToolkitGrant,
  type GrantVerdict,
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

const APPROVAL_TTL_SECONDS = 120;

export interface ToolsServiceDeps {
  store: Store;
  provider: ToolsProvider;
  limits: Limits;
  publicBaseUrl: string;
  appReturnUrl: string;
  completionMode: "verifier" | "callback" | "mock";
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
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
  private readonly limits: Limits;
  private readonly limiter: UsageLimiter;
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(private readonly deps: ToolsServiceDeps) {
    this.mode = deps.provider.mode;
    if ((deps.completionMode === "mock") !== (this.mode === "mock")) {
      throw new Error("mock completion is only valid with the mock provider");
    }
    this.store = deps.store;
    this.provider = deps.provider;
    this.limits = deps.limits;
    this.limiter = new UsageLimiter(deps.store, deps.limits);
    this.now = deps.now ?? Date.now;
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
    return { mode: this.mode, toolkits: TOOLKIT_IDS.map((id) => this.view(userId, id)) };
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

  // ---------------------------------------------------------------- connect

  async connect(userId: string, toolkitId: string, body: unknown): Promise<ConnectResponse> {
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
    const callbackUrl = `${this.deps.publicBaseUrl}/v1/oauth/return?attempt=${attempt.attemptId}`;
    const link = await this.limiter.withSlot(userId, async () => {
      if (this.mode === "live") this.limiter.reserveToolRun(userId, now);
      try {
        return await this.provider.createConnectionLink({ toolkit: id, composioUserId, callbackUrl, signal: this.timeout() });
      } catch (error) {
        throw toAppError(error);
      }
    });
    this.store.setPendingConnection(attempt.attemptId, link.pendingConnectionId);
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
    const id = toolkit(toolkitId);
    const request = parse(CompleteRequestSchema, body);
    const title = TOOLKITS[id].title;
    const now = this.now();
    const attempt = this.store.consumeAttempt({ attemptId: request.attemptId, userId, provider: id, nonce: request.nonce, now });
    if (!attempt) throw new AppError("attempt_invalid");

    const composioUserId = this.store.composioUserId(userId, now);
    const fail = (errorCode: string, summary: string): never => {
      throw new AppError("attempt_invalid", { message: summary, receipt: this.receipt(userId, id, "connect", null, "failed", summary, errorCode, null) });
    };
    const done = (status: ReceiptStatus, summary: string, errorCode: string | null = null): ToolkitResult => ({
      toolkit: this.view(userId, id),
      receipt: this.receipt(userId, id, "connect", null, status, summary, errorCode, null),
    });

    const result = request.result;
    if (result.kind === "canceled") return done("canceled", "Connecting was canceled. Nothing was connected.");
    if (result.kind !== this.deps.completionMode) return fail("completion_mode_mismatch", "This completion isn't accepted by this server.");

    try {
      let connectionId: string;
      if (result.kind === "mock") {
        const mocked = await this.provider.completeMock({ toolkit: id, composioUserId, approve: result.outcome === "approve" });
        if (!mocked) return done("failed", "Access wasn't granted. Nothing was connected.", "access_denied");
        connectionId = mocked.connectionId;
      } else if (result.kind === "callback") {
        // The redirect's status and ID are hints only; the server re-reads status and ownership below.
        if (result.status !== "success") return done("failed", `${title} wasn't connected.`, "provider_reported_failure");
        if (!result.connectedAccountId || result.connectedAccountId !== attempt.pending_connection_id) {
          return fail("attempt_mismatch", "The connection didn't match this attempt. Nothing was connected.");
        }
        connectionId = result.connectedAccountId;
      } else {
        const verified = await this.provider.completeVerifiedAuth({ composioUserId, sessionUri: result.sessionUri, signal: this.timeout() });
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
      // A fresh connection never inherits switches from an earlier one.
      this.store.disableTools(userId, toolNames(id), this.now());
      return verdict === "ok"
        ? done("succeeded", `${title} connected. Its tools are off until you switch them on.`)
        : done("blocked", blockedSummary(title, verdict), reason);
    } catch (error) {
      if (error instanceof AppError) throw error;
      const appError = toAppError(error);
      throw new AppError(appError.code, { receipt: this.receipt(userId, id, "connect", null, "failed", `${title} couldn't be connected.`, appError.code, null) });
    }
  }

  async disconnect(userId: string, toolkitId: string, body: unknown): Promise<ToolkitResult> {
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

  /** Writes only. Shows exactly what would happen and returns a single-use approval for those arguments. */
  prepare(userId: string, body: unknown): PrepareResult {
    const request = parse(PrepareRequestSchema, body);
    const tool = this.requireTool(request.tool);
    if (tool.risk !== "write" || !tool.preview) throw new AppError("invalid_request", { message: "This tool doesn't need a confirmation." });
    const args = parse(tool.input, request.arguments);
    const now = this.now();
    this.limiter.reserveRequest(userId, now);
    const row = this.checkUsable(userId, tool, "write");
    const { approvalId, expiresAt } = this.store.createApproval({
      userId,
      capability: tool.name,
      accountId: row.connection_id,
      argsDigest: argumentDigest(args),
      now,
      ttlSeconds: APPROVAL_TTL_SECONDS,
    });
    return { mode: this.mode, tool: tool.name, preview: tool.preview(args), approvalId, expiresAt: new Date(expiresAt).toISOString() };
  }

  async run(userId: string, body: unknown): Promise<RunResult> {
    const request = parse(RunRequestSchema, body);
    const tool = this.requireTool(request.tool);
    const args = parse(tool.input, request.arguments);
    if (!isSupportedTimeZone(request.timeZone)) {
      throw new AppError("invalid_request", { message: "Use an IANA time zone such as Europe/Warsaw." });
    }
    const op = tool.risk === "write" ? "write" : "read";
    const now = this.now();
    this.limiter.reserveRequest(userId, now);
    const row = this.checkUsable(userId, tool, op);

    if (tool.risk === "write") {
      const approved =
        request.approvalId !== undefined &&
        this.store.consumeApproval({
          approvalId: request.approvalId,
          userId,
          capability: tool.name,
          accountId: row.connection_id,
          argsDigest: argumentDigest(args),
          now,
        });
      if (!approved) {
        throw new AppError("capability_disabled", {
          message: "This action needs a fresh confirmation.",
          receipt: this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: it wasn't confirmed.", "confirmation_required", null),
        });
      }
    }

    try {
      this.limiter.reserveToolRun(userId, now);
    } catch (error) {
      if (error instanceof AppError) {
        throw new AppError(error.code, { ...error.options, receipt: this.receipt(userId, tool.toolkit, op, tool.name, "blocked", "Not done: a Doddy limit was reached.", error.code, null) });
      }
      throw error;
    }

    const composioUserId = this.store.composioUserId(userId, now);
    const title = TOOLKITS[tool.toolkit].title;
    try {
      return await this.limiter.withSlot(userId, async () => {
        const result = await this.withRetry(tool, (signal) =>
          this.provider.execute({
            toolkit: tool.toolkit,
            slug: tool.composioSlug,
            composioUserId,
            connectionId: row.connection_id,
            arguments: tool.toArguments(args),
            signal,
          }),
        );
        const outcome = tool.normalize(result.raw, args, { timeZone: request.timeZone });
        if (row.status === "error") this.store.updateConnectionStatus(userId, tool.toolkit, "connected", null, this.now());
        const receipt = this.receipt(userId, tool.toolkit, op, tool.name, "succeeded", outcome.summary, null, result.providerReference);
        return { mode: this.mode, tool: tool.name, text: outcome.text, count: outcome.count, truncated: outcome.truncated, receipt };
      });
    } catch (error) {
      if (error instanceof AppError) throw error;
      const appError = toAppError(error);
      if (appError.code === "connection_expired") {
        this.store.updateConnectionStatus(userId, tool.toolkit, "expired", "revoked_or_expired", this.now());
        this.store.disableTools(userId, toolNames(tool.toolkit), this.now());
      }
      // A write that failed on a timeout or provider error may still have happened: say so.
      const unknown = op === "write" && (appError.code === "provider_timeout" || appError.code === "provider_unavailable");
      const receipt = this.receipt(
        userId,
        tool.toolkit,
        op,
        tool.name,
        unknown ? "outcome_unknown" : "failed",
        unknown ? `${title} didn't confirm; it may or may not have gone through. Check there before trying again.` : `${title} wasn't reached or its answer couldn't be used. Nothing is shown instead.`,
        appError.code,
        null,
      );
      throw new AppError(appError.code, { ...appError.options, receipt: receipt });
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
  private async withRetry<T>(tool: CloudToolDefinition, call: (signal: AbortSignal) => Promise<T>): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      try {
        return await call(this.timeout());
      } catch (raw) {
        const error = raw instanceof ProviderError ? raw : new ProviderError("provider_unavailable");
        if (!error.transient || attempt >= tool.maxRetries) throw error;
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
    id: ToolkitId,
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

function toAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  const p = error instanceof ProviderError ? error : new ProviderError("provider_unavailable");
  return new AppError(p.code, p.retryAfterSeconds !== undefined ? { retryAfterSeconds: p.retryAfterSeconds } : {});
}
