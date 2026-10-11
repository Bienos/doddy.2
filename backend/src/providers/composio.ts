import { Composio } from "@composio/core";
import { EVENT_FIELDS } from "../calendar.js";
import type { ComposioSettings } from "../config.js";
import { ProviderError } from "../errors.js";
import { extractScopes, guard, mapStatus, removeComposioConnection } from "./composioShared.js";
import type { CalendarProvider, ListEventsCall, ListEventsPage, ProviderConnection } from "./types.js";

// Kept here for existing importers.
export { extractScopes, mapProviderError } from "./composioShared.js";

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
      { execute: true },
    );
    return {
      raw: { successful: response.successful, error: response.error, data: response.data },
      providerReference: response.logId ?? null,
    };
  }

  async removeConnection(input: { connectionId: string; signal: AbortSignal }) {
    return removeComposioConnection(this.client, input.connectionId, input.signal);
  }

}
