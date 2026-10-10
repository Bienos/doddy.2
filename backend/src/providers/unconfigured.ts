import { AppError } from "../errors.js";
import type { ToolkitId } from "../tools/catalog.js";
import type { ExecuteCall, ExecuteResult, ToolsProvider } from "../tools/provider.js";
import type { CalendarProvider, ListEventsCall, ListEventsPage, ProviderConnection, RemoteCleanupResult } from "./types.js";

/**
 * Live mode without Composio (e.g. a server that only runs web search). These adapters never
 * call anyone and never invent data: every provider operation answers "not set up on this server",
 * so the app shows the accounts as unavailable instead of falling back to demo data.
 */
const notSetUp = (what: string) => new AppError("live_not_configured", { message: `${what} isn't set up on this server.` });

export class UnconfiguredCalendarProvider implements CalendarProvider {
  readonly mode = "live" as const;
  readonly authConfigId = "";

  async createConnectionLink(): Promise<{ pendingConnectionId: string | null; redirectUrl: string | null }> {
    throw notSetUp("Google Calendar");
  }
  async completeVerifiedAuth(): Promise<{ connectionId: string; toolkitSlug: string }> {
    throw notSetUp("Google Calendar");
  }
  async completeMock(): Promise<{ connectionId: string } | null> {
    throw notSetUp("Google Calendar");
  }
  async getConnection(): Promise<ProviderConnection> {
    throw notSetUp("Google Calendar");
  }
  async isOwnedBy(): Promise<boolean> {
    return false;
  }
  async listEvents(_call: ListEventsCall): Promise<ListEventsPage> {
    throw notSetUp("Google Calendar");
  }
  async removeConnection(): Promise<RemoteCleanupResult> {
    // Nothing was ever connected through this server, so there is nothing to remove.
    return "removed";
  }
}

export class UnconfiguredToolsProvider implements ToolsProvider {
  readonly mode = "live" as const;

  isConfigured(_toolkit: ToolkitId): boolean {
    return false;
  }
  authConfigId(_toolkit: ToolkitId): string {
    return "";
  }
  async createConnectionLink(): Promise<{ pendingConnectionId: string | null; redirectUrl: string | null }> {
    throw notSetUp("This account");
  }
  async completeVerifiedAuth(): Promise<{ connectionId: string; toolkitSlug: string }> {
    throw notSetUp("This account");
  }
  async completeMock(): Promise<{ connectionId: string } | null> {
    throw notSetUp("This account");
  }
  async getConnection(): Promise<ProviderConnection> {
    throw notSetUp("This account");
  }
  async isOwnedBy(): Promise<boolean> {
    return false;
  }
  async execute(_call: ExecuteCall): Promise<ExecuteResult> {
    throw notSetUp("This account");
  }
  async removeConnection(): Promise<"removed" | "failed"> {
    return "removed";
  }
}
