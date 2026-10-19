import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { DevSessionVerifier } from "../src/auth.js";
import { testLimits } from "../src/config.js";
import { createHandler } from "../src/http.js";
import { ConnectedAppsService } from "../src/service.js";
import { defaultRegistry } from "../src/capabilities.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { Store } from "../src/store.js";
import { MockToolsProvider, type ToolsMockScenario } from "../src/tools/mock.js";
import { cloudTool } from "../src/tools/catalog.js";
import { CloudToolsService } from "../src/tools/service.js";
import { MockWebSearchProvider, type WebSearchProvider } from "../src/tools/websearch.js";
import { Clock, USER_A } from "./helpers.js";

/** A running server with the mock tools provider, for tests and for fixture generation. */
export interface Rig {
  call(method: string, path: string, o?: { token?: string | null; body?: unknown; scenario?: ToolsMockScenario }): Promise<{ status: number; body: any; text: string }>;
  provider: MockToolsProvider;
  tools: CloudToolsService;
  /** The offline demo search (null when the rig was started without web search). */
  webSearch: MockWebSearchProvider | null;
  store: Store;
  logs: string[];
  clock: Clock;
  close(): Promise<void>;
}

export async function start(limits: Parameters<typeof testLimits>[0] = {}, o: { webSearch?: WebSearchProvider | null } = {}): Promise<Rig> {
  const store = await Store.memory();
  const clock = new Clock(Date.parse("2026-10-10T10:00:00Z"));
  const provider = new MockToolsProvider();
  const logs: string[] = [];
  const common = { store, limits: testLimits(limits), publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return", now: clock.now, sleep: async () => {} };
  const webSearch = o.webSearch === undefined ? new MockWebSearchProvider() : o.webSearch;
  const tools = new CloudToolsService({ ...common, provider, webSearch, completionMode: "mock", log: (line) => logs.push(JSON.stringify(line)) });
  const service = new ConnectedAppsService({ ...common, provider: new MockCalendarProvider(), registry: defaultRegistry(), completionMode: "mock" });
  const handler = createHandler({
    service,
    tools,
    verifier: new DevSessionVerifier(),
    appReturnUrl: common.appReturnUrl,
    maxBodyBytes: 8 * 1024,
    now: () => new Date(clock.ms),
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  let closed = false;
  return {
    provider,
    tools,
    webSearch: webSearch instanceof MockWebSearchProvider ? webSearch : null,
    store,
    logs,
    clock,
    async close() {
      if (closed) return;
      closed = true;
      server.close();
      (await store.close());
    },
    async call(method, path, o = {}) {
      const headers: Record<string, string> = {};
      const token = o.token === undefined ? USER_A : o.token;
      if (token !== null) headers.authorization = `Bearer ${token}`;
      if (o.scenario) headers["x-doddy-tools-scenario"] = o.scenario;
      let body: string | undefined;
      if (o.body !== undefined) {
        headers["content-type"] = "application/json";
        body = JSON.stringify(o.body);
      }
      const res = await fetch(`${base}${path}`, { method, headers, ...(body !== undefined ? { body } : {}) });
      const text = await res.text();
      let parsed: unknown = null;
      try {
        parsed = text ? JSON.parse(text) : null;
      } catch {
        parsed = null;
      }
      return { status: res.status, body: parsed, text };
    },
  };
}

export async function connect(r: Rig, toolkit: string, token = USER_A, scenario?: ToolsMockScenario) {
  const begin = await r.call("POST", `/v1/tools/${toolkit}/connect`, { token, body: {}, ...(scenario ? { scenario } : {}) });
  assert.equal(begin.status, 200, begin.text);
  return r.call("POST", `/v1/tools/${toolkit}/complete`, {
    token,
    body: { attemptId: begin.body.attemptId, nonce: begin.body.nonce, result: { kind: "mock", outcome: "approve" } },
  });
}

export const on = (r: Rig, tool: string, token = USER_A) => r.call("PUT", "/v1/tools/switch", { token, body: { tool, enabled: true } });
/** A run exactly as sent: no approval unless `extra` has one. ASK-01 tests use this. */
export const runRaw = (r: Rig, tool: string, args: Record<string, unknown>, extra: Record<string, unknown> = {}, token = USER_A) =>
  r.call("POST", "/v1/tools/run", { token, body: { tool, arguments: args, timeZone: "Europe/Warsaw", ...extra } });

const isRead = (tool: string) => tool === "web_search" || cloudTool(tool)?.risk === "read";

/**
 * The app's flow for a read (ASK-01): ask (prepare: the card), the user says yes, then run with
 * that approval. A refused ask is returned as it is. Writes are sent as given: their tests make
 * and pass their own approvals.
 */
export async function run(r: Rig, tool: string, args: Record<string, unknown>, extra: Record<string, unknown> = {}, token = USER_A) {
  if (!isRead(tool) || "approvalId" in extra) return runRaw(r, tool, args, extra, token);
  const asked = await r.call("POST", "/v1/tools/prepare", { token, body: { tool, arguments: args } });
  if (asked.status !== 200) return asked;
  return runRaw(r, tool, args, { ...extra, approvalId: asked.body.approvalId }, token);
}

export async function ready(r: Rig, toolkit: string, tool: string, token = USER_A) {
  assert.equal((await connect(r, toolkit, token)).status, 200);
  assert.equal((await on(r, tool, token)).status, 200);
}

