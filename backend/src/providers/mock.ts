import { randomBytes } from "node:crypto";
import { GOOGLE_CALENDAR_REQUESTED_SCOPE } from "../capabilities.js";
import type { MockScenario } from "../contracts.js";
import { ProviderError } from "../errors.js";
import { localDate, rfc3339Local, startOfLocalDay } from "../time.js";
import type { CalendarProvider, ListEventsCall, ListEventsPage, ProviderConnection } from "./types.js";

/**
 * Deterministic offline adapter. Makes zero network calls and never shows a sign-in page.
 * Events are synthetic and generated inside the requested local day; every value is fake.
 * A scenario (per Composio user) selects success, empty, error and permission fixtures.
 */
export class MockCalendarProvider implements CalendarProvider {
  readonly mode = "mock" as const;
  readonly authConfigId = "mock_auth_config";
  private readonly connections = new Map<string, ProviderConnection & { owner: string }>();
  private readonly scenarios = new Map<string, MockScenario>();
  /** Every adapter call, for tests that prove which calls happened (or did not). */
  readonly calls: string[] = [];

  setScenario(composioUserId: string, scenario: MockScenario): void {
    this.scenarios.set(composioUserId, scenario);
  }

  private scenario(composioUserId: string): MockScenario {
    return this.scenarios.get(composioUserId) ?? "events";
  }

  async createConnectionLink(input: { composioUserId: string }) {
    this.calls.push("createConnectionLink");
    const id = `mock_ca_${randomBytes(6).toString("hex")}`;
    this.connections.set(id, {
      id,
      owner: input.composioUserId,
      status: "pending",
      toolkitSlug: "googlecalendar",
      authConfigId: this.authConfigId,
      grantedScopes: null,
    });
    return { pendingConnectionId: id, redirectUrl: null };
  }

  async completeVerifiedAuth(): Promise<{ connectionId: string; toolkitSlug: string }> {
    throw new ProviderError("provider_unavailable");
  }

  async completeMock(input: { composioUserId: string; approve: boolean }) {
    this.calls.push("completeMock");
    const pending = [...this.connections.values()].find((c) => c.owner === input.composioUserId && c.status === "pending");
    if (!pending) return null;
    if (!input.approve) {
      pending.status = "failed";
      return null;
    }
    const scenario = this.scenario(input.composioUserId);
    pending.status = scenario === "expired" ? "expired" : "active";
    pending.grantedScopes =
      scenario === "broad_scope"
        ? ["https://www.googleapis.com/auth/calendar", GOOGLE_CALENDAR_REQUESTED_SCOPE]
        : scenario === "insufficient_scope"
          ? ["https://www.googleapis.com/auth/userinfo.email"]
          : [GOOGLE_CALENDAR_REQUESTED_SCOPE];
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

  async listEvents(call: ListEventsCall): Promise<ListEventsPage> {
    this.calls.push("listEvents");
    const c = this.connections.get(call.connectionId);
    if (!c || c.owner !== call.composioUserId) throw new ProviderError("connection_expired");
    switch (this.scenario(call.composioUserId)) {
      case "expired":
        throw new ProviderError("connection_expired");
      case "provider_error":
        return { raw: { successful: false, error: "synthetic failure", data: {} }, providerReference: null };
      case "rate_limited":
        throw new ProviderError("rate_limited", 30);
      case "timeout":
        throw new ProviderError("provider_timeout");
      case "malformed":
        return { raw: { successful: true, data: { items: [{ summary: "Broken", start: {} }] } }, providerReference: null };
      case "empty":
        return { raw: { successful: true, error: null, data: { items: [], summary: "demo.calendar@example.com" } }, providerReference: null };
      case "many":
        return { raw: this.manyPage(call), providerReference: null };
      default:
        return { raw: this.demoPage(call), providerReference: null };
    }
  }

  async removeConnection(input: { connectionId: string }) {
    this.calls.push("removeConnection");
    const c = this.connections.get(input.connectionId);
    if (c) c.status = "revoked";
    this.connections.delete(input.connectionId);
    return "removed" as const;
  }

  /** Demo day: an all-day item, a recurring stand-up, a meeting, a cancelled instance (hidden). */
  private demoPage(call: ListEventsCall) {
    const tz = call.timeZone;
    const date = localDate(Date.parse(call.timeMin), tz);
    const dayStart = startOfLocalDay(date, tz);
    const at = (h: number, m = 0) => rfc3339Local(dayStart + (h * 60 + m) * 60_000, tz);
    const next = new Date(Date.parse(`${date}T00:00:00Z`) + 86_400_000).toISOString().slice(0, 10);
    return {
      successful: true,
      error: null,
      data: {
        summary: "demo.calendar@example.com",
        items: [
          { status: "confirmed", summary: "Demo: Mum's birthday", start: { date }, end: { date: next } },
          { status: "confirmed", summary: "Demo: Team stand-up", start: { dateTime: at(9, 30) }, end: { dateTime: at(9, 45) }, recurringEventId: "demo_series" },
          { status: "confirmed", summary: "Demo: Dentist", start: { dateTime: at(14) }, end: { dateTime: at(14, 45) } },
          { status: "cancelled", summary: "Demo: Cancelled yoga", start: { dateTime: at(18) }, end: { dateTime: at(19) }, recurringEventId: "demo_yoga" },
        ],
      },
    };
  }

  /** Paged fixture: three pages of 50 one-minute events, to exercise pagination and truncation. */
  private manyPage(call: ListEventsCall) {
    const tz = call.timeZone;
    const date = localDate(Date.parse(call.timeMin), tz);
    const dayStart = startOfLocalDay(date, tz);
    const page = call.pageToken === null ? 0 : Number(call.pageToken.replace("page_", ""));
    const items = Array.from({ length: call.pageSize }, (_, i) => {
      const n = page * call.pageSize + i;
      const start = dayStart + (6 * 60 + n) * 60_000;
      return { status: "confirmed", summary: `Demo item ${n + 1}`, start: { dateTime: rfc3339Local(start, tz) }, end: { dateTime: rfc3339Local(start + 60_000, tz) } };
    });
    return { successful: true, error: null, data: { items, nextPageToken: page < 5 ? `page_${page + 1}` : undefined } };
  }
}
