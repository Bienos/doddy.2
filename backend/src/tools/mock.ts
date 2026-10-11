import { randomBytes } from "node:crypto";
import { ProviderError } from "../errors.js";
import type { ProviderConnection } from "../providers/types.js";
import { type ToolkitId, TOOLKITS } from "./catalog.js";
import type { ExecuteCall, ExecuteResult, ToolsProvider } from "./provider.js";

/**
 * Deterministic offline adapter. Makes zero network calls and shows no sign-in page. Every value
 * is synthetic. It returns the same envelope shapes Composio documents, so the real normalizers
 * run in tests. Scenario switches let tests produce failures and over-broad grants.
 */
export type ToolsMockScenario =
  | "normal" | "empty" | "malformed" | "provider_error" | "rate_limited" | "expired" | "broad_scope" | "missing_scope"
  /** A write goes through, then its answer is lost (a timeout): the case ADR-303 settles. */
  | "lost_answer";

export class MockToolsProvider implements ToolsProvider {
  readonly mode = "mock" as const;
  private readonly connections = new Map<string, ProviderConnection & { owner: string }>();
  private readonly scenarios = new Map<string, ToolsMockScenario>();
  /** Every adapter call, for tests that prove what did (not) happen. */
  readonly calls: string[] = [];
  /** Arguments of every execute call, to prove what would be sent to Composio. */
  readonly executed: { slug: string; arguments: Record<string, unknown> }[] = [];
  /** Todoist tasks made through this adapter, per Composio user, listed after the demo ones. */
  private readonly madeTasks = new Map<string, { id: string; content: string }[]>();

  setScenario(composioUserId: string, scenario: ToolsMockScenario): void {
    this.scenarios.set(composioUserId, scenario);
  }

  private scenario(composioUserId: string): ToolsMockScenario {
    return this.scenarios.get(composioUserId) ?? "normal";
  }

  isConfigured(): boolean {
    return true;
  }

  authConfigId(toolkit: ToolkitId): string {
    return `mock_auth_${toolkit}`;
  }

  async createConnectionLink(input: { toolkit: ToolkitId; composioUserId: string }) {
    this.calls.push(`createConnectionLink:${input.toolkit}`);
    const id = `mock_ca_${randomBytes(6).toString("hex")}`;
    this.connections.set(id, {
      id,
      owner: input.composioUserId,
      status: "pending",
      toolkitSlug: TOOLKITS[input.toolkit].composioToolkit,
      authConfigId: this.authConfigId(input.toolkit),
      grantedScopes: null,
    });
    return { pendingConnectionId: id, redirectUrl: null };
  }

  async completeVerifiedAuth(): Promise<{ connectionId: string; toolkitSlug: string }> {
    throw new ProviderError("provider_unavailable");
  }

  async completeMock(input: { toolkit: ToolkitId; composioUserId: string; approve: boolean }) {
    this.calls.push(`completeMock:${input.toolkit}`);
    const pending = [...this.connections.values()].find(
      (c) => c.owner === input.composioUserId && c.status === "pending" && c.toolkitSlug === TOOLKITS[input.toolkit].composioToolkit,
    );
    if (!pending) return null;
    if (!input.approve) {
      pending.status = "failed";
      return null;
    }
    const scenario = this.scenario(input.composioUserId);
    pending.status = scenario === "expired" ? "expired" : "active";
    const toolkit = TOOLKITS[input.toolkit];
    pending.grantedScopes =
      toolkit.allowedGrants === null
        ? null
        : scenario === "broad_scope"
          ? [...toolkit.requestedScopes, "https://mail.google.com/"]
          : scenario === "missing_scope"
            ? ["https://www.googleapis.com/auth/userinfo.email"]
            : [...toolkit.requestedScopes];
    return { connectionId: pending.id };
  }

  async getConnection(input: { connectionId: string }): Promise<ProviderConnection> {
    this.calls.push("getConnection");
    const c = this.connections.get(input.connectionId);
    if (!c) throw new ProviderError("connection_expired");
    if (c.status === "active" && this.scenario(c.owner) === "expired") c.status = "expired";
    const { owner: _owner, ...view } = c;
    return { ...view, grantedScopes: c.grantedScopes ? [...c.grantedScopes] : null };
  }

  async isOwnedBy(input: { connectionId: string; composioUserId: string }): Promise<boolean> {
    this.calls.push("isOwnedBy");
    return this.connections.get(input.connectionId)?.owner === input.composioUserId;
  }

  async execute(call: ExecuteCall): Promise<ExecuteResult> {
    this.calls.push(`execute:${call.slug}`);
    this.executed.push({ slug: call.slug, arguments: call.arguments });
    const connection = this.connections.get(call.connectionId);
    if (!connection || connection.owner !== call.composioUserId) throw new ProviderError("connection_expired");
    const scenario = this.scenario(call.composioUserId);
    if (scenario === "provider_error") throw new ProviderError("provider_unavailable");
    if (scenario === "rate_limited") throw new ProviderError("rate_limited", 1);
    if (scenario === "expired") throw new ProviderError("connection_expired");
    if (scenario === "malformed") return { raw: { successful: true, data: { messages: "not a list", files: "x", results: 5, tasks: {} } }, providerReference: null };
    const made = this.madeTasks.get(call.composioUserId) ?? [];
    const raw = envelope(call.slug, call.arguments, scenario === "empty", made);
    if (call.slug === "TODOIST_CREATE_TASK") {
      made.push({ id: `task_demo_${made.length + 1}`, content: String(call.arguments.content) });
      this.madeTasks.set(call.composioUserId, made);
      if (scenario === "lost_answer") throw new ProviderError("provider_timeout");
    }
    if (call.slug === "GMAIL_CREATE_EMAIL_DRAFT" && scenario === "lost_answer") throw new ProviderError("provider_timeout");
    return { raw, providerReference: `mock_log_${randomBytes(4).toString("hex")}` };
  }

  async removeConnection(input: { connectionId: string }) {
    this.calls.push("removeConnection");
    this.connections.delete(input.connectionId);
    return "removed" as const;
  }
}

const ok = (data: unknown) => ({ successful: true, data, error: null });

function envelope(slug: string, args: Record<string, unknown>, empty: boolean, made: { id: string; content: string }[]): unknown {
  switch (slug) {
    case "GMAIL_FETCH_EMAILS":
      return ok({
        // Deliberately unsorted, as Composio documents.
        messages: empty
          ? []
          : [
              { messageId: "m1", threadId: "t1", sender: "Demo Bank <noreply@demo.example>", subject: "Your statement is ready", messageTimestamp: "2026-10-08T07:00:00Z", preview: { body: "Your September statement is now available." } },
              { messageId: "m2", threadId: "t2", sender: "Anna Demo <anna@demo.example>", subject: "Lunch on Friday?", messageTimestamp: "2026-10-09T09:30:00Z", preview: { body: "Are you free around 1pm? There's a new place near the office." } },
            ],
        nextPageToken: "",
        resultSizeEstimate: empty ? 0 : 2,
      });
    case "GMAIL_CREATE_EMAIL_DRAFT":
      return ok({ id: "draft_demo_1", message: { id: "msg_demo_1", threadId: "t_demo" } });
    case "GOOGLEDRIVE_FIND_FILE":
      return ok({
        files: empty
          ? []
          : [
              { id: "f1", name: `Demo ${String(args.q).includes("budget") ? "budget" : "notes"} 2026`, mimeType: "application/vnd.google-apps.spreadsheet", modifiedTime: "2026-10-07T12:00:00Z" },
              { id: "f2", name: "Demo contract.pdf", mimeType: "application/pdf", modifiedTime: "2026-09-30T08:15:00Z" },
            ],
      });
    case "NOTION_SEARCH_NOTION_PAGE":
      return ok({
        object: "list",
        has_more: false,
        results: empty
          ? []
          : [
              { object: "page", id: "p1", archived: false, in_trash: false, last_edited_time: "2026-10-05T10:00:00Z", properties: { Name: { id: "title", type: "title", title: [{ plain_text: "Demo trip plan" }] } } },
              { object: "page", id: "p2", archived: true, in_trash: false, last_edited_time: "2026-01-01T10:00:00Z", properties: { Name: { id: "title", type: "title", title: [{ plain_text: "Demo archived page" }] } } },
            ],
      });
    case "TODOIST_GET_ALL_TASKS":
      return ok({
        tasks: empty
          ? []
          : [
              { id: "t1", content: "Demo: renew passport", priority: 4, due: { date: "2026-10-10", string: "today", is_recurring: false } },
              { id: "t2", content: "Demo: buy milk", priority: 1 },
              ...made.map((t) => ({ id: t.id, content: t.content, priority: 1 })),
            ],
      });
    case "TODOIST_CREATE_TASK":
      return ok({ id: `task_demo_${made.length + 1}`, content: String(args.content), priority: 1, ...(args.due_string ? { due: { date: "2026-10-11", string: String(args.due_string), is_recurring: false } } : {}) });
    default:
      throw new ProviderError("provider_unavailable");
  }
}
