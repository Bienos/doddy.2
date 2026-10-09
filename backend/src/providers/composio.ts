import { Composio } from "@composio/core";
import { EVENT_FIELDS } from "../calendar.js";
import type { ComposioSettings } from "../config.js";
import { ProviderError } from "../errors.js";
import type { CalendarProvider, ListEventsCall, ListEventsPage, ProviderConnection, ProviderConnectionStatus } from "./types.js";

/**
 * Composio adapter, written against @composio/core 0.22.0 declarations (see
 * docs/integrations/COMPOSIO_INTEGRATION_PLAN.md for the evidence table):
 *  - connectedAccounts.link()          hosted Connect Link (initiate() is retired for managed OAuth)
 *  - connectedAccounts.completeAuth()  OAuth callback-verifier redemption
 *  - connectedAccounts.get()/list()    authoritative status, auth config, ownership by userIds filter
 *  - connectedAccounts.revoke()/delete() remote cleanup
 *  - tools.execute(GOOGLECALENDAR_EVENTS_LIST) with a pinned toolkit version and explicit account
 * Only this file names a Composio tool slug. Credentials in `state` are read for the scope list
 * only and never leave this function.
 */
export const GOOGLE_CALENDAR_TOOLKIT = "googlecalendar";
export const EVENTS_LIST_TOOL = "GOOGLECALENDAR_EVENTS_LIST";
/** The SDK's documented default API origin (@composio/core 0.22.0). */
const COMPOSIO_API_BASE_URL = "https://backend.composio.dev";

/** The subset of the SDK this adapter uses; lets tests inject a fake without network access. */
export type ComposioLike = Pick<Composio, "connectedAccounts" | "tools">;

export class ComposioCalendarProvider implements CalendarProvider {
  readonly mode = "live" as const;
  readonly authConfigId: string;
  private readonly client: ComposioLike;
  private readonly toolkitVersion: string;

  constructor(settings: ComposioSettings, client?: ComposioLike) {
    this.authConfigId = settings.authConfigId;
    this.toolkitVersion = settings.toolkitVersion;
    this.client =
      client ??
      new Composio({
        apiKey: settings.apiKey,
        // Pinned so neither COMPOSIO_BASE_URL nor a ~/.composio user file can redirect the project key.
        baseURL: COMPOSIO_API_BASE_URL,
        allowTracking: false,
        // The SDK otherwise contacts registry.npmjs.org at start-up to look for upgrades.
        disableVersionCheck: true,
        toolkitVersions: { [GOOGLE_CALENDAR_TOOLKIT]: settings.toolkitVersion },
      });
  }

  async createConnectionLink(input: { composioUserId: string; callbackUrl: string; signal: AbortSignal }) {
    const request = await guard(() =>
      this.client.connectedAccounts.link(
        input.composioUserId,
        this.authConfigId,
        { callbackUrl: input.callbackUrl, allowMultiple: false },
        { signal: input.signal },
      ),
    );
    if (!request.redirectUrl) throw new ProviderError("provider_unavailable");
    return { pendingConnectionId: request.id, redirectUrl: request.redirectUrl };
  }

  async completeVerifiedAuth(input: { composioUserId: string; sessionUri: string; signal: AbortSignal }) {
    const result = await guard(() =>
      this.client.connectedAccounts.completeAuth(
        { userId: input.composioUserId, sessionUri: input.sessionUri },
        { signal: input.signal },
      ),
    );
    return { connectionId: result.connectedAccountId, toolkitSlug: result.toolkitSlug };
  }

  async completeMock(): Promise<{ connectionId: string } | null> {
    throw new ProviderError("provider_unavailable");
  }

  async getConnection(input: { connectionId: string; signal: AbortSignal }): Promise<ProviderConnection> {
    const account = await guard(() => this.client.connectedAccounts.get(input.connectionId, { signal: input.signal }));
    return {
      id: account.id,
      status: mapStatus(account.status, account.isDisabled),
      toolkitSlug: account.toolkit.slug,
      authConfigId: account.authConfig.id,
      grantedScopes: extractScopes(account.state),
    };
  }

  async isOwnedBy(input: { connectionId: string; composioUserId: string; signal: AbortSignal }): Promise<boolean> {
    // The retrieve response carries no user ID, so ownership is checked with the server-side userIds filter.
    const page = await guard(() =>
      this.client.connectedAccounts.list(
        {
          userIds: [input.composioUserId],
          authConfigIds: [this.authConfigId],
          toolkitSlugs: [GOOGLE_CALENDAR_TOOLKIT],
          limit: 20,
        },
        { signal: input.signal },
      ),
    );
    return page.items.some((item) => item.id === input.connectionId);
  }

  async listEvents(call: ListEventsCall): Promise<ListEventsPage> {
    const args: Record<string, unknown> = {
      calendarId: "primary",
      timeMin: call.timeMin,
      timeMax: call.timeMax,
      timeZone: call.timeZone,
      singleEvents: true,
      orderBy: "startTime",
      showDeleted: false,
      maxResults: call.pageSize,
      fields: EVENT_FIELDS,
    };
    if (call.pageToken !== null) args.pageToken = call.pageToken;
    const response = await guard(() =>
      this.client.tools.execute(
        EVENTS_LIST_TOOL,
        {
          userId: call.composioUserId,
          connectedAccountId: call.connectionId,
          version: this.toolkitVersion,
          arguments: args,
        },
        { signal: call.signal },
      ),
    );
    return {
      raw: { successful: response.successful, error: response.error, data: response.data },
      providerReference: response.logId ?? null,
    };
  }

  async removeConnection(input: { connectionId: string; signal: AbortSignal }) {
    try {
      await this.client.connectedAccounts.revoke(input.connectionId, { signal: input.signal });
    } catch (error) {
      // Not supported / not revokable / already gone: still delete the Composio connection below.
      if (isCancel(error)) return "failed" as const;
    }
    try {
      await this.client.connectedAccounts.delete(input.connectionId, { signal: input.signal });
      return "removed" as const;
    } catch (error) {
      return errorName(error) === "ComposioConnectedAccountNotFoundError" ? ("removed" as const) : ("failed" as const);
    }
  }
}

function mapStatus(status: string, isDisabled: boolean): ProviderConnectionStatus {
  if (isDisabled) return "disabled";
  switch (status) {
    case "ACTIVE":
      return "active";
    case "INITIALIZING":
    case "INITIATED":
      return "pending";
    case "EXPIRED":
      return "expired";
    case "REVOKED":
    case "INACTIVE":
      return "revoked";
    default:
      return "failed";
  }
}

/** Reads only the granted scope list from connection state; returns null when it is not exposed. */
export function extractScopes(state: unknown): string[] | null {
  if (typeof state !== "object" || state === null) return null;
  const val = (state as { val?: unknown }).val;
  if (typeof val !== "object" || val === null) return null;
  const scope = (val as { scope?: unknown }).scope;
  if (typeof scope === "string") {
    const list = scope.split(/[\s,]+/).filter(Boolean);
    return list.length > 0 ? list : null;
  }
  if (Array.isArray(scope) && scope.every((s) => typeof s === "string")) {
    return scope.length > 0 ? [...scope] : null;
  }
  return null;
}

function errorName(error: unknown): string {
  return error instanceof Error ? error.name : "";
}

function isCancel(error: unknown): boolean {
  return errorName(error) === "ComposioRequestCancelledError" || errorName(error) === "AbortError" || errorName(error) === "TimeoutError";
}

function httpStatus(error: unknown): { status: number | null; retryAfter: number | undefined } {
  for (let e: unknown = error, depth = 0; e && depth < 4; e = (e as { cause?: unknown }).cause, depth++) {
    const status = (e as { status?: unknown }).status;
    if (typeof status === "number") {
      const headers = (e as { headers?: unknown }).headers;
      let raw: string | null = null;
      if (headers instanceof Headers) raw = headers.get("retry-after");
      else if (headers && typeof headers === "object") {
        const v = (headers as Record<string, unknown>)["retry-after"];
        raw = typeof v === "string" ? v : null;
      }
      const seconds = raw !== null && /^\d{1,5}$/.test(raw) ? Number(raw) : undefined;
      return { status, retryAfter: seconds };
    }
  }
  return { status: null, retryAfter: undefined };
}

/** Maps SDK/HTTP failures to safe codes. Provider messages are dropped, never logged or returned. */
export function mapProviderError(error: unknown): ProviderError {
  if (error instanceof ProviderError) return error;
  if (isCancel(error)) return new ProviderError("provider_timeout");
  if (errorName(error) === "ComposioConnectedAccountNotFoundError") return new ProviderError("connection_expired");
  const { status, retryAfter } = httpStatus(error);
  if (status === 429) return new ProviderError("rate_limited", retryAfter);
  // 401/403 from Composio means Doddy's own project key or config is wrong, not the user's grant;
  // a bad key must surface as an error, never as "reconnect" or as demo data.
  if (status === 404 || status === 410) return new ProviderError("connection_expired");
  return new ProviderError("provider_unavailable");
}

async function guard<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    throw mapProviderError(error);
  }
}
