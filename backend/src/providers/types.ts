/**
 * Provider boundary for the Google Calendar connection. The service only talks to this
 * interface; mock and Composio adapters implement it. Nothing here returns credentials:
 * adapters must reduce provider objects to these fields.
 */

export type ProviderConnectionStatus = "pending" | "active" | "failed" | "expired" | "revoked" | "disabled";

export interface ProviderConnection {
  id: string;
  status: ProviderConnectionStatus;
  toolkitSlug: string;
  authConfigId: string;
  /** Scopes the provider reports as granted; null when the provider does not expose them. */
  grantedScopes: string[] | null;
}

export interface ListEventsCall {
  composioUserId: string;
  connectionId: string;
  timeMin: string;
  timeMax: string;
  timeZone: string;
  pageSize: number;
  pageToken: string | null;
  signal: AbortSignal;
}

export interface ListEventsPage {
  /** Raw tool output; validated by the normalizer, never forwarded. */
  raw: unknown;
  /** Execution reference the provider returned (Composio log ID), if any. */
  providerReference: string | null;
}

export type RemoteCleanupResult = "removed" | "failed";

export interface CalendarProvider {
  readonly mode: "mock" | "live";
  readonly authConfigId: string;

  /** Hosted connection link for this user. `redirectUrl` is null in mock mode. */
  createConnectionLink(input: {
    composioUserId: string;
    callbackUrl: string;
    signal: AbortSignal;
  }): Promise<{ pendingConnectionId: string | null; redirectUrl: string | null }>;

  /** Redeems a callback-verifier session for this user (verifier completion mode only). */
  completeVerifiedAuth(input: { composioUserId: string; sessionUri: string; signal: AbortSignal }): Promise<{ connectionId: string; toolkitSlug: string }>;

  /** Mock-only completion (the demo never shows a sign-in page). Live adapters throw. */
  completeMock(input: { composioUserId: string; approve: boolean }): Promise<{ connectionId: string } | null>;

  getConnection(input: { connectionId: string; signal: AbortSignal }): Promise<ProviderConnection>;

  /** Authoritative ownership check: the connection belongs to this Composio user and auth config. */
  isOwnedBy(input: { connectionId: string; composioUserId: string; signal: AbortSignal }): Promise<boolean>;

  listEvents(call: ListEventsCall): Promise<ListEventsPage>;

  /** Revoke at Google where supported, then delete the Composio connection. */
  removeConnection(input: { connectionId: string; signal: AbortSignal }): Promise<RemoteCleanupResult>;
}
