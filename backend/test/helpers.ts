import { once } from "node:events";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { DevSessionVerifier } from "../src/auth.js";
import { defaultRegistry } from "../src/capabilities.js";
import { type Limits, testLimits } from "../src/config.js";
import { createHandler } from "../src/http.js";
import { type ComposioLike, ComposioCalendarProvider } from "../src/providers/composio.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import type { CalendarProvider } from "../src/providers/types.js";
import { ConnectedAppsService } from "../src/service.js";
import { Store } from "../src/store.js";

export const USER_A = "dev-user-a";
export const USER_B = "dev-user-b";
export const READ_SCOPE = "https://www.googleapis.com/auth/calendar.events.readonly";
/** Planted in fake provider state to prove credentials never leak into responses, receipts or logs. */
export const PLANTED_TOKEN = "FAKE-PLANTED-ACCESS-TOKEN-must-never-appear";

export class Clock {
  constructor(public ms: number) {}
  now = () => this.ms;
  advance(ms: number) {
    this.ms += ms;
  }
}

export interface Harness {
  base: string;
  service: ConnectedAppsService;
  store: Store;
  provider: CalendarProvider;
  clock: Clock;
  logs: string[];
  sleeps: number[];
  close(): Promise<void>;
  call(method: string, path: string, opts?: { token?: string | null; body?: unknown; headers?: Record<string, string> }): Promise<{ status: number; body: any; headers: Headers; text: string }>;
}

export async function harness(
  opts: {
    provider?: CalendarProvider;
    completionMode?: "verifier" | "callback" | "mock";
    limits?: Partial<Limits>;
    nowIso?: string;
  } = {},
): Promise<Harness> {
  const store = new Store(":memory:");
  const provider = opts.provider ?? new MockCalendarProvider();
  const clock = new Clock(Date.parse(opts.nowIso ?? "2026-10-09T10:00:00Z"));
  const logs: string[] = [];
  const sleeps: number[] = [];
  const service = new ConnectedAppsService({
    store,
    provider,
    registry: defaultRegistry(),
    limits: testLimits(opts.limits),
    publicBaseUrl: "https://api.doddy.test",
    appReturnUrl: "doddy-dev://connected-apps/return",
    completionMode: opts.completionMode ?? (provider.mode === "mock" ? "mock" : "callback"),
    now: clock.now,
    sleep: async (ms) => {
      sleeps.push(ms);
    },
  });
  const handler = createHandler({
    service,
    verifier: new DevSessionVerifier(),
    appReturnUrl: "doddy-dev://connected-apps/return",
    maxBodyBytes: 8 * 1024,
    now: () => new Date(clock.ms),
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const server: Server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  let closed = false;
  return {
    base,
    service,
    store,
    provider,
    clock,
    logs,
    sleeps,
    async close() {
      if (closed) return;
      closed = true;
      server.close();
      store.close();
    },
    async call(method, path, o = {}) {
      const headers: Record<string, string> = { ...(o.headers ?? {}) };
      const token = o.token === undefined ? USER_A : o.token;
      if (token !== null) headers.authorization = `Bearer ${token}`;
      let body: string | undefined;
      if (o.body !== undefined) {
        headers["content-type"] = "application/json";
        body = typeof o.body === "string" ? o.body : JSON.stringify(o.body);
      }
      const res = await fetch(`${base}${path}`, { method, headers, redirect: "manual", ...(body !== undefined ? { body } : {}) });
      const text = await res.text();
      let parsed: unknown = null;
      try {
        parsed = text ? JSON.parse(text) : null;
      } catch {
        parsed = null;
      }
      return { status: res.status, body: parsed, headers: res.headers, text };
    },
  };
}

export const CAL = "/v1/connected-apps/google-calendar";

/** Connect through the mock flow and return the result body. */
export async function connectMock(h: Harness, token = USER_A, scenario?: string) {
  const headers = scenario ? { "x-doddy-demo-scenario": scenario } : undefined;
  const start = await h.call("POST", `${CAL}/connect`, { token, body: {}, ...(headers ? { headers } : {}) });
  if (start.status !== 200) throw new Error(`connect failed ${start.status} ${start.text}`);
  const done = await h.call("POST", `${CAL}/complete`, {
    token,
    body: { attemptId: start.body.attemptId, nonce: start.body.nonce, result: { kind: "mock", outcome: "approve" } },
  });
  return { start: start.body, done };
}

// ------------------------------------------------------------------ fake Composio SDK client

interface FakeAccount {
  id: string;
  userId: string;
  authConfigId: string;
  toolkit: string;
  status: string;
  scope: string | undefined;
  isDisabled: boolean;
}

export class FakeComposio {
  readonly accounts = new Map<string, FakeAccount>();
  readonly calls: string[] = [];
  readonly executeArgs: Record<string, unknown>[] = [];
  /** Session URIs a verifier redirect would carry, mapped to the pending account they complete. */
  readonly sessions = new Map<string, string>();
  execute: (body: { arguments?: Record<string, unknown> }) => Promise<unknown> = async () => ({
    data: { items: [], summary: "owner@example.com" },
    error: null,
    successful: true,
    logId: "log_fake_123",
  });
  deleteFails = false;
  private n = 0;

  /** What happens when the user finishes Google consent in the browser. */
  activate(id: string, scope: string | null = READ_SCOPE) {
    const a = this.accounts.get(id)!;
    a.status = "ACTIVE";
    a.scope = scope ?? undefined;
  }

  /** Simulates an account created outside Doddy's attempt (e.g. another user's). */
  addAccount(account: Partial<FakeAccount> & { id: string; userId: string }) {
    this.accounts.set(account.id, {
      authConfigId: "ac_calendar",
      toolkit: "googlecalendar",
      status: "ACTIVE",
      scope: READ_SCOPE,
      isDisabled: false,
      ...account,
    });
  }

  private view(a: FakeAccount) {
    return {
      id: a.id,
      status: a.status,
      isDisabled: a.isDisabled,
      statusReason: null,
      toolkit: { slug: a.toolkit },
      authConfig: { id: a.authConfigId, isComposioManaged: true, isDisabled: false },
      state: { authScheme: "OAUTH2", val: { status: a.status, access_token: PLANTED_TOKEN, refresh_token: "PLANTED-REFRESH", scope: a.scope } },
      createdAt: "2026-10-09T00:00:00Z",
      updatedAt: "2026-10-09T00:00:00Z",
    };
  }

  private notFound() {
    const e = new Error("not found");
    e.name = "ComposioConnectedAccountNotFoundError";
    return e;
  }

  readonly connectedAccounts = {
    link: async (userId: string, authConfigId: string, options?: { callbackUrl?: string }) => {
      this.calls.push("link");
      const id = `ca_fake_${++this.n}`;
      this.accounts.set(id, { id, userId, authConfigId, toolkit: "googlecalendar", status: "INITIATED", scope: undefined, isDisabled: false });
      return { id, status: "INITIATED", redirectUrl: `https://connect.composio.dev/link/${id}?cb=${encodeURIComponent(options?.callbackUrl ?? "")}` };
    },
    completeAuth: async (params: { userId: string; sessionUri: string }) => {
      this.calls.push("completeAuth");
      const id = this.sessions.get(params.sessionUri);
      const a = id ? this.accounts.get(id) : undefined;
      if (!a || a.userId !== params.userId) {
        throw Object.assign(new Error("session not found"), { status: 404 });
      }
      this.sessions.delete(params.sessionUri);
      a.status = "ACTIVE";
      return { connectedAccountId: a.id, toolkitSlug: a.toolkit };
    },
    get: async (id: string) => {
      this.calls.push("get");
      const a = this.accounts.get(id);
      if (!a) throw this.notFound();
      return this.view(a);
    },
    list: async (q: { userIds?: string[]; authConfigIds?: string[] }) => {
      this.calls.push("list");
      const items = [...this.accounts.values()]
        .filter((a) => !q.userIds || q.userIds.includes(a.userId))
        .filter((a) => !q.authConfigIds || q.authConfigIds.includes(a.authConfigId))
        .map((a) => this.view(a));
      return { items, nextCursor: null, totalPages: 1 };
    },
    revoke: async (id: string) => {
      this.calls.push("revoke");
      const a = this.accounts.get(id);
      if (!a) throw this.notFound();
      a.status = "REVOKED";
      return { connectedAccount: { id, status: "REVOKED" }, revokedTokens: ["access_token"] };
    },
    delete: async (id: string) => {
      this.calls.push("delete");
      if (this.deleteFails) throw Object.assign(new Error("upstream"), { status: 503 });
      if (!this.accounts.delete(id)) throw this.notFound();
      return { success: true };
    },
  };

  readonly tools = {
    execute: async (slug: string, body: { userId?: string; connectedAccountId?: string; version?: string; arguments?: Record<string, unknown> }) => {
      this.calls.push(`execute:${slug}`);
      this.executeArgs.push({ slug, ...body });
      const a = body.connectedAccountId ? this.accounts.get(body.connectedAccountId) : undefined;
      if (!a || a.userId !== body.userId) throw Object.assign(new Error("account mismatch"), { status: 400 });
      return this.execute(body);
    },
  };
}

export function liveProvider(fake: FakeComposio): ComposioCalendarProvider {
  return new ComposioCalendarProvider(
    { apiKey: "unused-in-tests", authConfigId: "ac_calendar", toolkitVersion: "20250909_00", completionMode: "callback" },
    fake as unknown as ComposioLike,
  );
}

/** Tomorrow (YYYY-MM-DD) relative to the harness clock in a zone. */
export function tomorrow(h: Harness, tz = "Europe/Warsaw"): string {
  const local = new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(h.clock.ms));
  const d = new Date(`${local}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}
