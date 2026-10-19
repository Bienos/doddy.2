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

// Payments (ADR-530). Short fakes only: the guard script refuses anything that looks like a real key.
test("payments: live mode takes a Stripe test key, and refuses live and malformed keys by name only", () => {
  assert.equal(loadConfig(live).payments, null, "no key: native purchases say not set up");
  assert.deepEqual(loadConfig({ ...live, STRIPE_SECRET_KEY: "sk_test_fakefake" }).payments, { stripeSecretKey: "sk_test_fakefake" });
  assert.deepEqual(loadConfig({ ...live, STRIPE_SECRET_KEY: "rk_test_fakefake" }).payments, { stripeSecretKey: "rk_test_fakefake" });
  for (const key of ["sk_live_fakefake", "rk_live_fakefake"]) {
    const p = problems({ ...live, STRIPE_SECRET_KEY: key });
    assert.deepEqual(p, ["STRIPE_SECRET_KEY must be a test key; live payments are blocked until ADR-530's legal review"]);
    assert.ok(!p.join(" ").includes(key));
  }
  for (const key of ["sk_test_short", "pk_test_fakefake", "sk_test_fake-fake!", "whsec_fakefake"]) {
    const p = problems({ ...live, STRIPE_SECRET_KEY: key });
    assert.ok(p.some((x) => x.includes("STRIPE_SECRET_KEY")), key);
    assert.ok(!p.join(" ").includes(key), key);
  }
});

test("payments: Stripe alone doesn't make a live server; Composio or Monid is still required", () => {
  const p = problems({ DODDY_MODE: "live", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: KEY, DODDY_PUBLIC_BASE_URL: "https://doddy-dev.example.com", STRIPE_SECRET_KEY: "sk_test_fakefake" });
  assert.ok(p.some((x) => x.includes("needs Composio")));
});

test("payments: mock mode ignores any Stripe key, even a live one", () => {
  assert.equal(loadConfig({ STRIPE_SECRET_KEY: "sk_live_fakefake" }).payments, null);
  assert.equal(loadConfig({ STRIPE_SECRET_KEY: "sk_test_fakefake" }).payments, null);
});

test("payments: limits default to the contract's and the checkout allowlist is validated", () => {
  const c = loadConfig({});
  assert.equal(c.limits.purchaseMaxMinor, 20_000);
  assert.equal(c.limits.purchaseDailyMaxMinor, 50_000);
  assert.equal(c.limits.userDailyPurchases, 10);
  assert.deepEqual(c.checkoutHosts, []);
  assert.deepEqual(loadConfig({ DODDY_CHECKOUT_HOSTS: " Shop.Example.PL, pyszne.pl ,," }).checkoutHosts, ["shop.example.pl", "pyszne.pl"]);
  for (const bad of ["https://shop.example.pl", "shop.example.pl/checkout", "10.0.0.1", "localhost", "shop.example.pl:443", "*.example.pl"]) {
    assert.ok(problems({ DODDY_CHECKOUT_HOSTS: bad }).some((x) => x.includes("DODDY_CHECKOUT_HOSTS")), bad);
  }
  assert.ok(problems({ DODDY_PURCHASE_MAX_MINOR: "199" }).length > 0, "below Stripe's PLN minimum");
  assert.ok(problems({ DODDY_PURCHASE_MAX_MINOR: "30000", DODDY_PURCHASE_DAILY_MAX_MINOR: "20000" }).some((x) => x.includes("DODDY_PURCHASE_DAILY_MAX_MINOR")));
  const set = loadConfig({ DODDY_PURCHASE_MAX_MINOR: "1000", DODDY_PURCHASE_DAILY_MAX_MINOR: "3000", DODDY_LIMIT_USER_DAILY_PURCHASES: "2" });
  assert.deepEqual([set.limits.purchaseMaxMinor, set.limits.purchaseDailyMaxMinor, set.limits.userDailyPurchases], [1000, 3000, 2]);
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
