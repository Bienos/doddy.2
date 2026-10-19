import type { ProviderConnection } from "../providers/types.js";
import type { ToolkitId } from "./catalog.js";

/**
 * Provider boundary for online accounts (Gmail, Drive, Notion, Todoist). The service only talks to
 * this interface; the mock and Composio adapters implement it. Nothing here returns credentials.
 */
export interface ExecuteCall {
  toolkit: ToolkitId;
  slug: string;
  composioUserId: string;
  connectionId: string;
  arguments: Record<string, unknown>;
  signal: AbortSignal;
}

export interface ExecuteResult {
  /** Raw tool envelope; validated by the tool's normalizer, never forwarded. */
  raw: unknown;
  providerReference: string | null;
}

export interface ToolsProvider {
  readonly mode: "mock" | "live";
  /** Toolkits this server can connect (live: those with settings; mock: all). */
  isConfigured(toolkit: ToolkitId): boolean;
  /** The account's full sign-in. */
  authConfigId(toolkit: ToolkitId): string;
  /** The smaller first sign-in (ADR-511), or null when this server hasn't set one up. */
  narrowAuthConfigId(toolkit: ToolkitId): string | null;

  createConnectionLink(input: {
    toolkit: ToolkitId;
    /** One of this toolkit's auth configs (`authConfigId` or `narrowAuthConfigId`), chosen by the service. */
    authConfigId: string;
    composioUserId: string;
    callbackUrl: string;
    signal: AbortSignal;
  }): Promise<{ pendingConnectionId: string | null; redirectUrl: string | null }>;

  completeVerifiedAuth(input: { composioUserId: string; sessionUri: string; signal: AbortSignal }): Promise<{ connectionId: string; toolkitSlug: string }>;

  /** Mock-only completion (no fake sign-in page is ever shown). Live adapters throw. */
  completeMock(input: { toolkit: ToolkitId; composioUserId: string; approve: boolean }): Promise<{ connectionId: string } | null>;

  getConnection(input: { connectionId: string; signal: AbortSignal }): Promise<ProviderConnection>;

  /** Authoritative ownership check: the connection belongs to this Composio user and auth config. */
  isOwnedBy(input: { toolkit: ToolkitId; authConfigId: string; connectionId: string; composioUserId: string; signal: AbortSignal }): Promise<boolean>;

  execute(call: ExecuteCall): Promise<ExecuteResult>;

  removeConnection(input: { connectionId: string; signal: AbortSignal }): Promise<"removed" | "failed">;
}
