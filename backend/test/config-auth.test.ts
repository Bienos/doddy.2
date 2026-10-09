import assert from "node:assert/strict";
import { test } from "node:test";
import { DevSessionVerifier, SignedSessionVerifier } from "../src/auth.js";
import { ConfigError, loadConfig } from "../src/config.js";

const KEY = Buffer.alloc(32, 7).toString("base64");
const live = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "signed",
  DODDY_SESSION_SIGNING_KEY: KEY,
  DODDY_PUBLIC_BASE_URL: "https://doddy-dev.example.com",
  COMPOSIO_API_KEY: "ak_secret_value_123",
  COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID: "ac_123",
  COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: "20250909_00",
};

const problems = (env: Record<string, string>) => {
  try {
    loadConfig(env);
    return [];
  } catch (e) {
    assert.ok(e instanceof ConfigError);
    return e.problems;
  }
};

test("mock mode runs with no secrets at all", () => {
  const c = loadConfig({});
  assert.equal(c.mode, "mock");
  assert.equal(c.composio, null);
  assert.equal(c.authMode, "dev");
});

test("valid live development config loads", () => {
  const c = loadConfig(live);
  assert.equal(c.mode, "live");
  assert.equal(c.composio?.completionMode, "verifier");
});

test("live mode fails closed, naming missing variables but never their values", () => {
  const p = problems({ DODDY_MODE: "live", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: KEY, COMPOSIO_API_KEY: "ak_secret_value_123" });
  assert.ok(p.some((x) => x.includes("COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID")));
  assert.ok(p.some((x) => x.includes("COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION")));
  assert.ok(!p.join(" ").includes("ak_secret_value_123"));
});

test("test identities can never be used with live mode, production or a public host", () => {
  assert.ok(problems({ ...live, DODDY_AUTH_MODE: "dev" }).length > 0);
  assert.ok(problems({ DODDY_ENV: "production" }).some((x) => x.includes("DODDY_AUTH_MODE=dev")));
  assert.ok(problems({ DODDY_HOST: "0.0.0.0" }).some((x) => x.includes("loopback")));
});

test("production live mode is blocked until real sign-in exists", () => {
  assert.ok(problems({ ...live, DODDY_ENV: "production" }).some((x) => x.includes("production")));
});

test("toolkit version must be pinned and callback completion is development-only", () => {
  assert.ok(problems({ ...live, COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: "latest" }).length > 0);
  assert.ok(problems({ ...live, DODDY_ENV: "test", COMPOSIO_COMPLETION_MODE: "callback" }).some((x) => x.includes("callback")));
});

test("TLS outside loopback; return URL is allowlisted (scheme, no query)", () => {
  assert.ok(problems({ ...live, DODDY_PUBLIC_BASE_URL: "http://doddy-dev.example.com" }).length > 0);
  assert.ok(problems({ DODDY_APP_RETURN_URL: "http://evil.example/cb" }).length > 0);
  assert.ok(problems({ DODDY_APP_RETURN_URL: "doddy-dev://connected-apps/return?next=https://evil.example" }).length > 0);
  assert.ok(problems({ DODDY_APP_RETURN_URL: "javascript://x" }).length > 0);
});

test("signing key must be strong", () => {
  assert.ok(problems({ ...live, DODDY_SESSION_SIGNING_KEY: Buffer.alloc(8).toString("base64") }).length > 0);
});

test("signed sessions: valid, expired, tampered, wrong key, malformed", () => {
  const now = new Date("2026-10-09T10:00:00Z");
  const v = new SignedSessionVerifier(Buffer.alloc(32, 1));
  const user = "3f1c2a8e-1b2c-4d3e-8f90-123456789abc";
  const token = v.mint(user, now, 3600);
  assert.deepEqual(v.verify(`Bearer ${token}`, now), { userId: user });
  assert.equal(v.verify(`Bearer ${token}`, new Date(now.getTime() + 3601_000)), null);
  const [p, payload, sig] = token.split(".") as [string, string, string];
  const forged = Buffer.from(JSON.stringify({ v: 1, sub: "00000000-0000-4000-8000-00000000000b", iat: 0, exp: 9e9 })).toString("base64url");
  assert.equal(v.verify(`Bearer ${p}.${forged}.${sig}`, now), null);
  assert.equal(v.verify(`Bearer ${p}.${payload}.${sig.slice(0, -2)}AA`, now), null);
  assert.equal(new SignedSessionVerifier(Buffer.alloc(32, 2)).verify(`Bearer ${token}`, now), null);
  for (const bad of [undefined, "", "Basic abc", `Bearer ${token} extra`, "Bearer x"]) assert.equal(v.verify(bad, now), null);
  assert.throws(() => v.mint("alice@example.com", now, 60));
});

test("dev verifier only knows its two loopback identities", () => {
  const v = new DevSessionVerifier();
  assert.ok(v.verify("Bearer dev-user-a"));
  assert.equal(v.verify("Bearer dev-user-c"), null);
  assert.equal(v.verify("Bearer constructor"), null);
  assert.equal(v.verify("Bearer __proto__"), null);
});
