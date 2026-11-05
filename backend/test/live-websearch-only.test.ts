import assert from "node:assert/strict";
import { once } from "node:events";
import type { AddressInfo } from "node:net";
import { after, before, test } from "node:test";
import { buildApp } from "../src/app.js";
import { SignedSessionVerifier } from "../src/auth.js";
import { ConfigError, loadConfig } from "../src/config.js";
import { MonidWebSearchProvider } from "../src/tools/websearch.js";

/**
 * A live server with only a Monid key (no Composio): web search works, every account says
 * "Not set up", and nothing falls back to demo data.
 */
const KEY = Buffer.alloc(32, 9).toString("base64");
const base = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "signed",
  DODDY_SESSION_SIGNING_KEY: KEY,
  DODDY_PUBLIC_BASE_URL: "https://doddy.onrender.com",
  DODDY_DB_PATH: ":memory:",
};

test("config: live mode starts with Monid alone, and needs Composio or Monid", () => {
  const config = loadConfig({ ...base, MONID_API_KEY: "monid_live_abcdefgh123" });
  assert.equal(config.mode, "live");
  assert.equal(config.composio, null);
  assert.notEqual(config.monid, null);
  assert.throws(() => loadConfig(base), (e: unknown) => e instanceof ConfigError && /needs Composio .* or MONID_API_KEY/.test(e.message));
});

test("config: half a Composio setup is still refused", () => {
  assert.throws(
    () => loadConfig({ ...base, MONID_API_KEY: "monid_live_abcdefgh123", COMPOSIO_API_KEY: "ak_x" }),
    (e: unknown) => e instanceof ConfigError && /COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID is required/.test(e.message),
  );
  assert.throws(
    () => loadConfig({ ...base, MONID_API_KEY: "monid_live_abcdefgh123", COMPOSIO_GMAIL_AUTH_CONFIG_ID: "ac_g", COMPOSIO_GMAIL_TOOLKIT_VERSION: "20260101_00" }),
    /COMPOSIO_API_KEY is required/,
  );
});

let url = "";
let token = "";
let close: () => void = () => {};
const monidCalls: string[] = [];

before(async () => {
  const config = loadConfig({ ...base, MONID_API_KEY: "monid_live_abcdefgh123" });
  const fakeMonid = (async (input: string | URL | Request) => {
    monidCalls.push(String(input));
    return new Response(
      JSON.stringify({ runId: "r1", status: "COMPLETED", providerResponse: { httpStatus: 200 }, output: { results: [{ title: "Real-looking result", link: "https://example.org/a", snippet: "Open until 18:00." }] } }),
      { status: 200 },
    );
  }) as typeof fetch;
  const { server, store } = await buildApp(config, { webSearch: new MonidWebSearchProvider(config.monid!, fakeMonid) });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  url = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  token = new SignedSessionVerifier(Buffer.from(KEY, "base64")).mint("00000000-0000-4000-8000-0000000000aa", new Date(), 3600);
  close = async () => {
    server.close();
    void (await store.close());
  };
});
after(() => close());

const call = async (method: string, path: string, body?: unknown) => {
  const res = await fetch(`${url}${path}`, {
    method,
    headers: { authorization: `Bearer ${token}`, ...(body !== undefined ? { "content-type": "application/json" } : {}) },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  return { status: res.status, body: (await res.json()) as any };
};

test("health says live", async () => {
  const res = await fetch(`${url}/v1/health`);
  assert.equal(((await res.json()) as any).mode, "live");
});

test("accounts are not set up; web search is ready and runs against Monid", async () => {
  const catalog = (await call("GET", "/v1/tools")).body;
  assert.equal(catalog.mode, "live");
  for (const section of catalog.toolkits) {
    assert.equal(section.status, section.id === "websearch" ? "connected" : "unavailable", section.id);
  }
  assert.equal((await call("PUT", "/v1/tools/switch", { tool: "check_email", enabled: true })).status, 503);
  assert.equal((await call("POST", "/v1/tools/gmail/connect", {})).status, 503);

  assert.equal((await call("PUT", "/v1/tools/switch", { tool: "web_search", enabled: true })).status, 200);
  // ASK-01: without the user's yes nothing reaches Monid; with it, exactly one search.
  const unasked = await call("POST", "/v1/tools/run", { tool: "web_search", arguments: { query: "cafe hours" }, timeZone: "Europe/Warsaw" });
  assert.equal(unasked.status, 403);
  assert.deepEqual(monidCalls, []);
  const asked = await call("POST", "/v1/tools/prepare", { tool: "web_search", arguments: { query: "cafe hours" } });
  assert.equal(asked.status, 200);
  const search = await call("POST", "/v1/tools/run", { tool: "web_search", arguments: { query: "cafe hours" }, timeZone: "Europe/Warsaw", approvalId: asked.body.approvalId });
  assert.equal(search.status, 200);
  assert.equal(search.body.mode, "live", "live results are never labelled as demo");
  assert.match(search.body.text, /Real-looking result/);
  assert.deepEqual(monidCalls, ["https://api.monid.ai/v1/run"]);
});

test("Google Calendar says not set up instead of showing demo data", async () => {
  const connect = await call("POST", "/v1/connected-apps/google-calendar/connect", {});
  assert.equal(connect.status, 503);
  assert.equal(connect.body.error.code, "live_not_configured");
  assert.match(connect.body.error.message, /Google Calendar isn't set up on this server/);
  const events = await call("POST", "/v1/connected-apps/google-calendar/events", { date: "2026-10-11", timeZone: "Europe/Warsaw" });
  assert.notEqual(events.status, 200);
});
