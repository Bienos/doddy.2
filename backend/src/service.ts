import { randomUUID } from "node:crypto";
import { maskLabel, normalizePage, sortEvents } from "./calendar.js";
import {
  CALENDAR_LIST_EVENTS,
  type CapabilityRegistry,
  evaluateGrant,
  GOOGLE_CALENDAR_REQUESTED_SCOPE,
  type GrantVerdict,
} from "./capabilities.js";
import type { Limits } from "./config.js";
import {
  type CalendarEvent,
  type CompleteRequest,
  CompleteRequestSchema,
  type ConnectionReason,
  type ConnectionResult,
  type ConnectionView,
  type ConnectResponse,
  EmptyRequestSchema,
  type EventsResult,
  type MockScenario,
  type Receipt,
  type ReceiptStatus,
} from "./contracts.js";
import { AppError, ProviderError } from "./errors.js";
import { ConfirmationPolicy, UsageLimiter } from "./policy.js";
import { MockCalendarProvider } from "./providers/mock.js";
import type { CalendarProvider } from "./providers/types.js";
import { CLEANUP_RETRY, type ConnectionRow, type QueuedCleanup, type Store } from "./store.js";
import { addDays, isSupportedTimeZone, isValidDateString, localDate, localDayWindow, rfc3339Local } from "./time.js";

export const PROVIDER = "google_calendar";
const RESULT_TTL_MS = 15 * 60_000;
const STATUS_REFRESH_MS = 30_000;
const MAX_DAYS_AHEAD = 7;

export const ACCESS_SUMMARY =
  "Doddy reads events on your primary Google Calendar (titles and times) when you ask, for example for tomorrow's plans. " +
  "It can't create, change or delete events, and it doesn't keep your calendar.";

export interface ServiceDeps {
  store: Store;
  provider: CalendarProvider;
  registry: CapabilityRegistry;
  limits: Limits;
  publicBaseUrl: string;
  appReturnUrl: string;
  completionMode: "verifier" | "callback" | "mock";
  now?: () => number;
  sleep?: (ms: number) => Promise<void>;
}

export class ConnectedAppsService {
  readonly mode: "mock" | "live";
  private readonly store: Store;
  private readonly provider: CalendarProvider;
  private readonly registry: CapabilityRegistry;
  private readonly limits: Limits;
  private readonly limiter: UsageLimiter;
  readonly confirmations: ConfirmationPolicy;
  private readonly now: () => number;
  private readonly sleep: (ms: number) => Promise<void>;

  constructor(private readonly deps: ServiceDeps) {
    this.mode = deps.provider.mode;
    if ((deps.completionMode === "mock") !== (this.mode === "mock")) {
      throw new Error("mock completion is only valid with the mock provider");
    }
    this.store = deps.store;
    this.provider = deps.provider;
    this.registry = deps.registry;
    this.limits = deps.limits;
    this.limiter = new UsageLimiter(deps.store, deps.limits);
    this.confirmations = new ConfirmationPolicy(deps.store);
    this.now = deps.now ?? Date.now;
    this.sleep = deps.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  }

  // ---------------------------------------------------------------- queries

  async view(userId: string): Promise<ConnectionView> {
    const row = await this.store.getConnection(userId, PROVIDER);
    const cleanup = await this.store.cleanupFor(userId, PROVIDER);
    return {
      provider: PROVIDER,
      mode: this.mode,
      status: row?.status ?? "disconnected",
      reason: row?.reason ?? null,
      accountLabel: row?.account_label ?? null,
      connectedAt: row ? iso(row.connected_at) : null,
      lastCheckedAt: row?.last_checked_at ? iso(row.last_checked_at) : null,
      remoteCleanup: cleanup ? cleanup.state : "none",
      access: { summary: ACCESS_SUMMARY, canWrite: false, requestedScopes: [GOOGLE_CALENDAR_REQUESTED_SCOPE] },
    };
  }

  receipts(userId: string): Promise<Receipt[]> {
    return this.store.receipts(userId, 20);
  }

  /** User-triggered status check; at most one provider lookup per 30 s per user. */
  async refreshStatus(userId: string): Promise<ConnectionView> {
    const row = await this.store.getConnection(userId, PROVIDER);
    if (!row || (row.last_checked_at !== null && this.now() - row.last_checked_at < STATUS_REFRESH_MS)) {
      return this.view(userId);
    }
    try {
      await this.limiter.withSlot(userId, async () => {
        await this.limiter.reserveCall(userId, this.now());
        const connection = await this.provider.getConnection({ connectionId: row.connection_id, signal: this.timeout() });
        if (connection.status === "active") {
          const verdict = evaluateGrant(connection.grantedScopes);
          const { status, reason } = statusForVerdict(verdict);
          await this.store.updateConnectionStatus(userId, PROVIDER, status, reason, this.now());
          if (verdict === "read_only") await this.saveScopes(row, connection.grantedScopes);
        } else if (connection.status !== "pending") {
          await this.store.updateConnectionStatus(userId, PROVIDER, "expired", "revoked_or_expired", this.now());
        }
      });
    } catch (error) {
      if (error instanceof ProviderError && error.code === "connection_expired") {
        await this.store.updateConnectionStatus(userId, PROVIDER, "expired", "revoked_or_expired", this.now());
      } else if (error instanceof AppError) {
        throw error;
      } else {
        // Status unknown right now: keep the stored state but say it couldn't be checked.
        await this.store.updateConnectionStatus(userId, PROVIDER, "error", "provider_unavailable", this.now());
      }
    }
    return this.view(userId);
  }

  // ---------------------------------------------------------------- connect

  async connect(userId: string, body: unknown, mockScenario?: MockScenario): Promise<ConnectResponse> {
    parse(EmptyRequestSchema, body);
    this.requireEnabled();
    await this.applyMockScenario(userId, mockScenario);
    const existing = await this.store.getConnection(userId, PROVIDER);
    if (existing?.status === "connected") {
      throw new AppError("invalid_request", { message: "Google Calendar is already connected. Disconnect it first." });
    }
    // Reconnecting from an expired/insufficient state replaces the old connection; a remote cleanup
    // that failed earlier is retried first so no stale active connection blocks the new link.
    if (existing || (await this.store.cleanupFor(userId, PROVIDER))) {
      if ((await this.removeRemote(userId)) === "failed") {
        throw new AppError("provider_unavailable", {
          message: "The previous Google Calendar connection couldn't be removed yet, so a new one wasn't started. Try again shortly.",
        });
      }
    }

    const now = this.now();
    const composioUserId = await this.store.composioUserId(userId, now);
    const attempt = await this.store.createAttempt({
      userId,
      provider: PROVIDER,
      authConfigId: this.provider.authConfigId,
      now,
      ttlSeconds: this.limits.attemptTtlSeconds,
    });
    // The unfinished attempt this one replaces can still be finished at Google: its connection goes.
    await this.removeQueued(attempt.superseded);
    const callbackUrl = `${this.deps.publicBaseUrl}/v1/oauth/return?attempt=${attempt.attemptId}`;
    const link = await this.limiter.withSlot(userId, async () => {
      if (this.mode === "live") await this.limiter.reserveCall(userId, now);
      try {
        return await this.provider.createConnectionLink({ composioUserId, callbackUrl, signal: this.timeout() });
      } catch (error) {
        throw toAppError(error);
      }
    });
    if (!(await this.store.setPendingConnection(attempt.attemptId, link.pendingConnectionId, this.now()))) {
      // A newer Connect replaced this one while the link was made; this link must not be used.
      if (link.pendingConnectionId) await this.removeQueued([{ connectionId: link.pendingConnectionId, userId, provider: PROVIDER }]);
      throw new AppError("attempt_invalid", { message: "A newer Connect replaced this one. Use the newest link." });
    }
    return {
      mode: this.mode,
      attemptId: attempt.attemptId,
      nonce: attempt.nonce,
      authorizationUrl: link.redirectUrl,
      callbackScheme: new URL(this.deps.appReturnUrl).protocol.replace(/:$/, ""),
      expiresAt: iso(attempt.expiresAt),
    };
  }

  async complete(userId: string, body: unknown): Promise<ConnectionResult> {
    const request = parse(CompleteRequestSchema, body);
    const now = this.now();
    const attempt = await this.store.consumeAttempt({
      attemptId: request.attemptId,
      userId,
      provider: PROVIDER,
      nonce: request.nonce,
      now,
    });
    if (!attempt) {
      // Too late: the user may have finished at Google after the attempt expired. That connection
      // can never be completed, so it is removed instead of left live.
      await this.removeQueued(await this.store.expireAttempts(now, [PROVIDER], userId));
      throw new AppError("attempt_invalid");
    }

    const composioUserId = await this.store.composioUserId(userId, now);
    const fail = async (errorCode: string, summary: string): Promise<never> => {
      const receipt = await this.receipt(userId, "connect", "failed", summary, errorCode, null);
      throw new AppError("attempt_invalid", { receipt });
    };
    // Every remote connection this completion touched that belongs to this user. Unless it ends
    // recorded as this user's connection, each is removed at the provider (or queued for removal),
    // so no grant stays live that Disconnect couldn't find. Never the unverified callback hint.
    const touched: (string | null)[] = [attempt.pending_connection_id];
    let recorded = false;
    try {
      return await this.completeAttempt(userId, request, attempt, composioUserId, fail, touched, () => { recorded = true; });
    } finally {
      if (!recorded) await this.discardRemote(userId, touched);
    }
  }

  private async completeAttempt(
    userId: string,
    request: CompleteRequest,
    attempt: { pending_connection_id: string | null },
    composioUserId: string,
    fail: (errorCode: string, summary: string) => Promise<never>,
    touched: (string | null)[],
    markRecorded: () => void,
  ): Promise<ConnectionResult> {
    let connectionId: string;
    const result = request.result;
    if (result.kind === "canceled") {
      const receipt = await this.receipt(userId, "connect", "canceled", "Connecting was canceled. Nothing was connected.", null, null);
      return { connection: await this.view(userId), receipt };
    }
    if (result.kind !== this.deps.completionMode) {
      return await fail("completion_mode_mismatch", "This completion isn't accepted by this server.");
    }
    try {
      if (result.kind === "mock") {
        const done = await this.provider.completeMock({ composioUserId, approve: result.outcome === "approve" });
        if (!done) {
          const receipt = await this.receipt(userId, "connect", "failed", "Access wasn't granted. Nothing was connected.", "access_denied", null);
          return { connection: await this.view(userId), receipt };
        }
        connectionId = done.connectionId;
        touched.push(connectionId);
      } else if (result.kind === "callback") {
        // The redirect's status/ID are hints only; they must match the attempt we created, and the
        // server re-reads status and ownership below. A forged "success" changes nothing.
        if (result.status !== "success") {
          const receipt = await this.receipt(userId, "connect", "failed", "Google Calendar wasn't connected.", "provider_reported_failure", null);
          return { connection: await this.view(userId), receipt };
        }
        if (!result.connectedAccountId || result.connectedAccountId !== attempt.pending_connection_id) {
          return await fail("attempt_mismatch", "The connection didn't match this attempt. Nothing was connected.");
        }
        connectionId = result.connectedAccountId;
      } else {
        const done = await this.provider.completeVerifiedAuth({ composioUserId, sessionUri: result.sessionUri, signal: this.timeout() });
        touched.push(done.connectionId); // redeemed for this user's own Composio id
        if (done.connectionId !== attempt.pending_connection_id) {
          return await fail("attempt_mismatch", "The connection didn't match this attempt. Nothing was connected.");
        }
        connectionId = done.connectionId;
      }

      const connection = await this.provider.getConnection({ connectionId, signal: this.timeout() });
      const owned = await this.provider.isOwnedBy({ connectionId, composioUserId, signal: this.timeout() });
      if (
        !owned ||
        connection.id !== connectionId ||
        connection.toolkitSlug !== "googlecalendar" ||
        connection.authConfigId !== this.provider.authConfigId
      ) {
        return await fail("verification_failed", "The connection couldn't be verified. Nothing was connected.");
      }
      if (connection.status !== "active") {
        return await fail(`connection_${connection.status}`, "Google Calendar didn't finish connecting.");
      }
      const verdict = evaluateGrant(connection.grantedScopes);
      const { status, reason } = statusForVerdict(verdict);
      await this.store.upsertConnection({
        user_id: userId,
        provider: PROVIDER,
        connection_id: connectionId,
        status,
        reason,
        account_label: null,
        scopes_json: connection.grantedScopes ? JSON.stringify(connection.grantedScopes) : null,
        connected_at: this.now(),
        last_checked_at: this.now(),
      });
      markRecorded();
      const receipt =
        verdict === "read_only"
          ? await this.receipt(userId, "connect", "succeeded", "Google Calendar connected with read-only access.", null, null)
          : await this.receipt(userId, "connect", "blocked", blockedSummary(verdict), reason, null);
      return { connection: await this.view(userId), receipt };
    } catch (error) {
      if (error instanceof AppError) throw error;
      const appError = toAppError(error);
      const receipt = await this.receipt(userId, "connect", "failed", "Google Calendar couldn't be connected.", appError.code, null);
      throw new AppError(appError.code, { receipt });
    }
  }

  // ---------------------------------------------------------------- read

  async listEvents(userId: string, body: unknown, mockScenario?: MockScenario): Promise<EventsResult> {
    const capability = CALENDAR_LIST_EVENTS;
    this.requireEnabled();
    await this.applyMockScenario(userId, mockScenario);
    const request = parse(capability.input, body) as { date: string; timeZone: string };
    if (!isSupportedTimeZone(request.timeZone) || !isValidDateString(request.date)) {
      throw new AppError("invalid_request", { message: "Use a real date and an IANA time zone such as Europe/Warsaw." });
    }
    const now = this.now();
    await this.limiter.reserveRequest(userId, now);
    const today = localDate(now, request.timeZone);
    if (request.date < today || request.date > addDays(today, MAX_DAYS_AHEAD)) {
      throw new AppError("invalid_request", { message: `Only today and the next ${MAX_DAYS_AHEAD} days can be checked.` });
    }

    const blocked = async (code: "not_connected" | "permission_insufficient" | "connection_expired", summary: string): Promise<never> => {
      const receipt = await this.receipt(userId, "read", "blocked", summary, code, null);
      throw new AppError(code, { receipt });
    };
    const row = await this.store.getConnection(userId, PROVIDER);
    if (!row) return await blocked("not_connected", "Not read: Google Calendar isn't connected.");
    if (row.status === "permission_insufficient") return await blocked("permission_insufficient", "Not read: the connection doesn't have read-only access.");
    if (row.status === "expired") return await blocked("connection_expired", "Not read: Google Calendar access expired.");
    // "error" only means the last status check couldn't reach the provider; the read itself will tell.
    if (row.status !== "connected" && row.status !== "error") return await blocked("connection_expired", "Not read: the connection needs attention.");
    // Grants are checked again at execution time, not only at connect time.
    if (evaluateGrant(row.scopes_json ? (JSON.parse(row.scopes_json) as string[]) : null) !== "read_only") {
      return await blocked("permission_insufficient", "Not read: the connection doesn't have read-only access.");
    }
    await this.confirmations.require({ userId, capability, accountId: row.connection_id, args: request, approvalId: undefined, now });
    await this.limiter.reserveRead(userId, now);

    const window = localDayWindow(request.date, request.timeZone);
    const composioUserId = await this.store.composioUserId(userId, now);
    try {
      return await this.limiter.withSlot(userId, async () => {
        const events: CalendarEvent[] = [];
        let cancelledHidden = 0;
        let truncated = false;
        let providerReference: string | null = null;
        let label: string | null = null;
        let pageToken: string | null = null;
        for (let page = 0; window.endMs > window.startMs; page++) {
          if (page >= this.limits.maxPages) {
            truncated = true;
            break;
          }
          const result = await this.withRetry(userId, (signal) =>
            this.provider.listEvents({
              composioUserId,
              connectionId: row.connection_id,
              timeMin: rfc3339Local(window.startMs, window.timeZone),
              timeMax: rfc3339Local(window.endMs, window.timeZone),
              timeZone: window.timeZone,
              pageSize: this.limits.pageSize,
              pageToken,
              signal,
            }),
          );
          providerReference = result.providerReference ?? providerReference;
          const normalized = normalizePage(result.raw, window, capability.resultBounds.maxTitleLength);
          events.push(...normalized.events);
          cancelledHidden += normalized.cancelled;
          label = label ?? normalized.calendarSummary;
          pageToken = normalized.nextPageToken;
          if (pageToken === null) break;
        }
        const maxEvents = Math.min(this.limits.maxEvents, capability.resultBounds.maxEvents);
        const sorted = sortEvents(events);
        if (sorted.length > maxEvents) truncated = true;
        const shown = sorted.slice(0, maxEvents);
        if (row.status === "error") await this.store.updateConnectionStatus(userId, PROVIDER, "connected", null, this.now());
        const accountLabel = maskLabel(label) ?? row.account_label;
        if (accountLabel !== row.account_label) await this.store.setAccountLabel(userId, PROVIDER, accountLabel);

        const retrievedAt = this.now();
        const summary =
          `${shown.length} event${shown.length === 1 ? "" : "s"} for ${request.date} (${request.timeZone})` +
          (truncated ? ", list shortened" : "") +
          (cancelledHidden > 0 ? `, ${cancelledHidden} cancelled hidden` : "");
        const receipt = await this.receipt(userId, "read", "succeeded", summary, null, providerReference, accountLabel);
        return {
          mode: this.mode,
          source: { provider: PROVIDER, calendar: "primary", label: accountLabel },
          window: {
            date: window.date,
            timeZone: window.timeZone,
            start: rfc3339Local(window.startMs, window.timeZone),
            end: rfc3339Local(window.endMs, window.timeZone),
          },
          events: shown,
          cancelledHidden,
          truncated,
          retrievedAt: iso(retrievedAt),
          expiresAt: iso(retrievedAt + RESULT_TTL_MS),
          receipt,
        };
      });
    } catch (error) {
      if (error instanceof AppError && error.code !== "busy") {
        const appError = error.options.receipt
          ? error
          : new AppError(error.code, { ...error.options, receipt: await this.receipt(userId, "read", "blocked", "Not read: a Doddy limit was reached.", error.code, null) });
        throw appError;
      }
      if (error instanceof AppError) throw error;
      const appError = toAppError(error);
      if (appError.code === "connection_expired") {
        await this.store.updateConnectionStatus(userId, PROVIDER, "expired", "revoked_or_expired", this.now());
      }
      const receipt = await this.receipt(userId, "read", "failed", "Calendar wasn't read. Nothing is shown instead.", appError.code, null);
      throw new AppError(appError.code, { ...appError.options, receipt });
    }
  }

  /** Capped exponential backoff for this safe read only; honours Retry-After; every try costs allowance. */
  private async withRetry<T>(userId: string, call: (signal: AbortSignal) => Promise<T>): Promise<T> {
    const policy = CALENDAR_LIST_EVENTS.retry;
    for (let attempt = 0; ; attempt++) {
      await this.limiter.reserveCall(userId, this.now());
      try {
        return await call(this.timeout());
      } catch (raw) {
        const error = raw instanceof ProviderError ? raw : toProviderError(raw);
        if (!error.transient || attempt >= policy.maxRetries) throw error;
        const backoff = Math.min(policy.maxDelayMs, policy.baseDelayMs * 2 ** attempt);
        const wait = error.retryAfterSeconds !== undefined ? error.retryAfterSeconds * 1000 : backoff;
        if (wait > policy.maxDelayMs) throw error; // Don't hold the request; tell the user when to retry.
        await this.sleep(wait);
      }
    }
  }

  // ---------------------------------------------------------------- disconnect

  /**
   * Blocks new reads immediately (local row removed in one transaction), then attempts remote
   * revocation/deletion. A failed remote step is reported, never hidden.
   */
  async disconnect(userId: string, body: unknown): Promise<ConnectionResult> {
    parse(EmptyRequestSchema, body);
    const hadLocal = (await this.store.getConnection(userId, PROVIDER)) !== null;
    const pendingBefore = await this.store.cleanupFor(userId, PROVIDER);
    if (!hadLocal && !pendingBefore) {
      const receipt = await this.receipt(userId, "disconnect", "succeeded", "Google Calendar was already disconnected.", null, null);
      return { connection: await this.view(userId), receipt };
    }
    const remote = await this.removeRemote(userId);
    const receipt =
      remote === "removed"
        ? await this.receipt(userId, "disconnect", "succeeded", "Disconnected. Doddy's access at Google was removed.", null, null)
        : await this.receipt(
            userId,
            "disconnect",
            "outcome_unknown",
            "Disconnected in Doddy. Removing access at Google couldn't be confirmed; try again or remove it in your Google Account.",
            "remote_cleanup_failed",
            null,
          );
    return { connection: await this.view(userId), receipt };
  }

  /**
   * Hourly (app.ts): ends attempts nobody completed in time and removes their connections at the
   * provider, then retries removals that failed earlier. Without it, a user who finished Google's
   * consent after leaving Doddy would keep a grant no one tracks once `prune` drops the attempt.
   */
  async sweepAbandoned(): Promise<void> {
    const now = this.now();
    const ended = await this.store.expireAttempts(now, [PROVIDER]);
    const retry = await this.store.cleanupsToRetry([PROVIDER], now - CLEANUP_RETRY.afterMs, CLEANUP_RETRY.maxTries, CLEANUP_RETRY.perSweep);
    await this.removeQueued([...ended, ...retry]);
  }

  /** Removes connections a failed completion left at the provider; a failure stays queued and visible. */
  private async discardRemote(userId: string, ids: (string | null)[]): Promise<void> {
    const queued: QueuedCleanup[] = [];
    for (const connectionId of new Set(ids.filter((id): id is string => !!id))) {
      await this.store.queueCleanup(connectionId, userId, PROVIDER, this.now());
      queued.push({ connectionId, userId, provider: PROVIDER });
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

  private async removeRemote(userId: string): Promise<"removed" | "failed"> {
    const removed = await this.store.removeConnectionForCleanup(userId, PROVIDER, this.now());
    const cleanup = await this.store.cleanupFor(userId, PROVIDER);
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

  // ---------------------------------------------------------------- helpers

  private requireEnabled(): void {
    if (!this.registry.isEnabled(CALENDAR_LIST_EVENTS.id, this.mode)) throw new AppError("capability_disabled");
  }

  private async applyMockScenario(userId: string, scenario: MockScenario | undefined): Promise<void> {
    if (scenario === undefined) return;
    if (!(this.provider instanceof MockCalendarProvider)) {
      throw new AppError("invalid_request", { message: "Demo scenarios exist only in mock mode." });
    }
    this.provider.setScenario(await this.store.composioUserId(userId, this.now()), scenario);
  }

  private async saveScopes(row: ConnectionRow, scopes: string[] | null): Promise<void> {
    await this.store.upsertConnection({ ...row, scopes_json: scopes ? JSON.stringify(scopes) : null, status: "connected", reason: null, last_checked_at: this.now() });
  }

  private timeout(): AbortSignal {
    return AbortSignal.timeout(Math.min(this.limits.providerTimeoutMs, CALENDAR_LIST_EVENTS.timeoutMs));
  }

  private async receipt(
    userId: string,
    operation: Receipt["operation"],
    status: ReceiptStatus,
    summary: string,
    errorCode: string | null,
    providerReference: string | null,
    accountLabel?: string | null,
  ): Promise<Receipt> {
    const receipt: Receipt = {
      operationId: randomUUID(),
      operation,
      capability: operation === "read" ? CALENDAR_LIST_EVENTS.id : `connection.${operation}`,
      provider: PROVIDER,
      accountLabel: accountLabel ?? (await this.store.getConnection(userId, PROVIDER))?.account_label ?? null,
      timestamp: iso(this.now()),
      mode: this.mode,
      status,
      summary: summary.slice(0, 200),
      errorCode,
      providerReference,
    };
    await this.store.saveReceipt(userId, receipt, this.now());
    return receipt;
  }
}

function statusForVerdict(verdict: GrantVerdict): { status: ConnectionRow["status"]; reason: ConnectionReason | null } {
  switch (verdict) {
    case "read_only":
      return { status: "connected", reason: null };
    case "missing_read_scope":
      return { status: "permission_insufficient", reason: "missing_read_scope" };
    case "not_read_only":
      return { status: "permission_insufficient", reason: "grant_not_read_only" };
    case "unverifiable":
      return { status: "permission_insufficient", reason: "grant_unverifiable" };
  }
}

function blockedSummary(verdict: GrantVerdict): string {
  switch (verdict) {
    case "not_read_only":
      return "Connected, but the access granted could change events, so Doddy won't use it. Disconnect and reconnect with read-only access.";
    case "missing_read_scope":
      return "Connected, but calendar reading wasn't allowed. Reconnect and allow reading events.";
    default:
      return "Connected, but Doddy couldn't confirm the access is read-only, so it won't use it.";
  }
}

function parse<T>(schema: { safeParse(v: unknown): { success: true; data: T } | { success: false } }, body: unknown): T {
  const result = schema.safeParse(body);
  if (!result.success) throw new AppError("invalid_request");
  return result.data;
}

function toProviderError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  return new ProviderError("provider_unavailable");
}

function toAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  const p = toProviderError(error);
  return new AppError(p.code, p.retryAfterSeconds !== undefined ? { retryAfterSeconds: p.retryAfterSeconds } : {});
}

const iso = (ms: number) => new Date(ms).toISOString();
