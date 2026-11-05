import { once } from "node:events";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DevSessionVerifier, type SessionVerifier } from "../src/auth.js";
import { defaultRegistry } from "../src/capabilities.js";
import { testLimits } from "../src/config.js";
import { DocumentLinks } from "../src/documents.js";
import { createHandler } from "../src/http.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { ConnectedAppsService } from "../src/service.js";
import { Store } from "../src/store.js";
import { type ClaudeProvider, MockClaudeProvider } from "../src/tools/claude.js";
import { MockToolsProvider } from "../src/tools/mock.js";
import { CloudToolsService } from "../src/tools/service.js";
import { MockWebSearchProvider } from "../src/tools/websearch.js";
import { MemoryChat } from "../src/memory/chat.js";
import { MemoryCipher } from "../src/memory/crypto.js";
import { MemoryService } from "../src/memory/service.js";
import { AccountContext } from "../src/web/chatContext.js";
import { WebRoutes } from "../src/web/routes.js";
import { ThreadService } from "../src/messages/service.js";
import { type RedeemLimits, WebAuth } from "../src/web/sessions.js";
import { WebStatic } from "../src/web/static.js";
import { Clock, USER_A } from "./helpers.js";

/**
 * A running server with Doddy Web on (ADR-600), the mock tools and a tiny built web app in a
 * temporary folder. "Phone" calls carry a dev Bearer token (dev-user-a / dev-user-b); "browser"
 * calls carry the session cookie, the web app's Origin and its header.
 */

export const WEB_ORIGIN = "https://app.doddy.test";
export const COOKIE = "__Host-doddy_web";

export interface WebRig {
  base: string;
  store: Store;
  tools: CloudToolsService;
  /** Kept notes and conversations (ADR-603), keyed with a throwaway test key unless the rig was started with `memoryKey: null`. */
  memory: MemoryService;
  clock: Clock;
  logs: string[];
  distDir: string;
  /** Raw request. `cookie` sends the session cookie; `browser` adds the web app's Origin and header. */
  call(
    method: string,
    path: string,
    o?: { token?: string | null; cookie?: string | null; body?: unknown; browser?: boolean; headers?: Record<string, string> },
  ): Promise<{ status: number; body: any; text: string; headers: Headers }>;
  /** The phone asks for a code. */
  code(token?: string): Promise<string>;
  /** The browser signs in with a code; returns the cookie's value. */
  signIn(code: string, userAgent?: string): Promise<string>;
  close(): Promise<void>;
}

export async function startWeb(
  o: {
    claude?: ClaudeProvider;
    /** What answers chat. Default: the demo provider. `null`: chat says "not set up". */
    chatClaude?: ClaudeProvider | null;
    /** `null`: no key, so keeping notes says "not set up". */
    memoryKey?: Buffer | null;
    /** What one person can keep (default: the real caps). */
    memoryLimits?: { conversations: number; bytes: number };
    /** Chat's daily caps (the same counters as Ask Doddy). Default: the test limits. */
    askLimits?: { userDailyAsk: number; serviceDailyAsk: number };
    /** `false`: the chat reads kept notes and conversations only, as before ADR-604. Default: it reads the account too, as the server does. */
    chatAccount?: boolean;
    origin?: string;
    withDist?: boolean;
    trustProxy?: boolean;
    limits?: RedeemLimits;
    verifier?: SessionVerifier;
  } = {},
): Promise<WebRig> {
  const store = await Store.memory();
  const clock = new Clock(Date.parse("2026-10-22T10:00:00Z"));
  const logs: string[] = [];
  const origin = o.origin ?? WEB_ORIGIN;
  const common = { store, limits: testLimits(), publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return", now: clock.now, sleep: async () => {} };
  const documentLinks = new DocumentLinks(Buffer.alloc(32, 7), common.publicBaseUrl);
  const tools = new CloudToolsService({
    ...common,
    provider: new MockToolsProvider(),
    webSearch: new MockWebSearchProvider(),
    claude: o.claude ?? new MockClaudeProvider(),
    documentLinks,
    completionMode: "mock",
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const service = new ConnectedAppsService({ ...common, provider: new MockCalendarProvider(), registry: defaultRegistry(), completionMode: "mock" });
  const verifier = o.verifier ?? new DevSessionVerifier();

  const distDir = mkdtempSync(join(tmpdir(), "doddy-web-dist-"));
  if (o.withDist !== false) {
    mkdirSync(join(distDir, "assets"));
    writeFileSync(join(distDir, "index.html"), "<!doctype html><title>Doddy</title><div id=root></div>");
    writeFileSync(join(distDir, "assets", "app-abc123.js"), "console.log('doddy')");
    writeFileSync(join(distDir, ".env"), "SECRET=never-served");
  }
  const memory = new MemoryService({
    store,
    cipher: o.memoryKey === null ? null : new MemoryCipher(o.memoryKey ?? Buffer.alloc(32, 5)),
    ...(o.memoryLimits ? { limits: o.memoryLimits } : {}),
    now: clock.now,
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const chat = new MemoryChat({
    memory,
    store,
    claude: o.chatClaude === undefined ? new MockClaudeProvider() : o.chatClaude,
    limits: o.askLimits ?? testLimits(),
    ...(o.chatAccount === false ? {} : { account: new AccountContext({ store, memory, tools }) }),
    now: clock.now,
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const thread = new ThreadService({
    store,
    cipher: o.memoryKey === null ? null : new MemoryCipher(o.memoryKey ?? Buffer.alloc(32, 5)),
    now: clock.now,
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const auth = new WebAuth(store, origin, o.trustProxy ?? false, o.limits);
  const handler = createHandler({
    service,
    tools,
    verifier,
    web: { auth, routes: new WebRoutes(auth, store, verifier, 8 * 1024, { service: memory, chat }, thread), pages: new WebStatic(o.withDist === false ? join(distDir, "missing") : distDir, origin) },
    documents: { links: documentLinks, store },
    appReturnUrl: common.appReturnUrl,
    maxBodyBytes: 8 * 1024,
    now: () => new Date(clock.ms),
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const cookieName = origin.startsWith("https:") ? COOKIE : "doddy_web";

  const rig: WebRig = {
    base,
    store,
    tools,
    memory,
    clock,
    logs,
    distDir,
    async call(method, path, c = {}) {
      const headers: Record<string, string> = { ...(c.headers ?? {}) };
      if (c.token) headers.authorization = `Bearer ${c.token}`;
      if (c.cookie) headers.cookie = `other=1; ${cookieName}=${c.cookie}`;
      if (c.browser) {
        headers.origin = origin;
        headers["x-doddy-web"] = "1";
      }
      let body: string | undefined;
      if (c.body !== undefined) {
        headers["content-type"] = "application/json";
        body = JSON.stringify(c.body);
      }
      const res = await fetch(`${base}${path}`, { method, headers, ...(body !== undefined ? { body } : {}) });
      const text = await res.text();
      let parsed: unknown = null;
      try {
        parsed = text ? JSON.parse(text) : null;
      } catch {
        parsed = null;
      }
      return { status: res.status, body: parsed, text, headers: res.headers };
    },
    async code(token = USER_A) {
      const res = await rig.call("POST", "/v1/web/link-codes", { token, body: {} });
      if (res.status !== 200) throw new Error(`code: ${res.status} ${res.text}`);
      return res.body.code as string;
    },
    async signIn(code, userAgent) {
      const res = await rig.call("POST", "/v1/web/session", { browser: true, body: { code }, ...(userAgent ? { headers: { "user-agent": userAgent } } : {}) });
      if (res.status !== 200) throw new Error(`sign-in: ${res.status} ${res.text}`);
      return cookieValue(res.headers.get("set-cookie"), cookieName)!;
    },
    async close() {
      server.close();
      await tools.settle();
      await store.close();
    },
  };
  return rig;
}

export function cookieValue(setCookie: string | null, name = COOKIE): string | null {
  if (!setCookie) return null;
  const match = new RegExp(`(?:^|,\\s*)${name.replace(/[-]/g, "\\-")}=([^;]*)`).exec(setCookie);
  return match ? match[1]! : null;
}

export const CHROME_MAC =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";
