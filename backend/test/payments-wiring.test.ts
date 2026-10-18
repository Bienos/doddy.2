import assert from "node:assert/strict";
import { once } from "node:events";
import type { AddressInfo } from "node:net";
import { test } from "node:test";
import { buildApp } from "../src/app.js";
import { SignedSessionVerifier } from "../src/auth.js";
import { loadConfig } from "../src/config.js";
import { MockPaymentGateway } from "../src/payments/gateway.js";
import { StripeHttpGateway } from "../src/payments/stripe.js";

/**
 * buildApp picks the payment gateway strictly from validated config (ADR-530): mock mode uses the
 * demo gateway, live mode uses Stripe only with a test key and otherwise none. Mock never stands in.
 */
const KEY = Buffer.alloc(32, 5).toString("base64");
const live = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "signed",
  DODDY_SESSION_SIGNING_KEY: KEY,
  DODDY_PUBLIC_BASE_URL: "https://doddy.onrender.com",
  DODDY_DB_PATH: ":memory:",
  MONID_API_KEY: "monid_live_abcdefgh123",
};

async function serve(env: Record<string, string>) {
  const app = buildApp(loadConfig(env));
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const url = `http://127.0.0.1:${(app.server.address() as AddressInfo).port}`;
  return {
    app,
    url,
    close: () => {
      app.server.close();
      app.store.close();
    },
  };
}

test("mock mode: the demo gateway, mock mode on every answer", async () => {
  const s = await serve({ DODDY_DB_PATH: ":memory:", STRIPE_SECRET_KEY: "sk_live_fakefake" });
  try {
    assert.equal(s.app.payments.mode, "mock");
    assert.ok((s.app.payments as unknown as { gateway: unknown }).gateway instanceof MockPaymentGateway);
    const res = await fetch(`${s.url}/v1/purchases/prepare`, {
      method: "POST",
      headers: { authorization: "Bearer dev-user-a", "content-type": "application/json" },
      body: JSON.stringify({ kind: "native", merchantName: "Doddy Café", description: "Coffee", amountMinor: 1000, currency: "PLN" }),
    });
    const body = (await res.json()) as any;
    assert.equal(res.status, 200);
    assert.equal(body.mode, "mock");
    assert.equal(body.purchase.testMode, true);
  } finally {
    s.close();
  }
});

test("live mode with a test key: Stripe over HTTPS, test mode", async () => {
  const s = await serve({ ...live, STRIPE_SECRET_KEY: "sk_test_fakefake" });
  try {
    assert.equal(s.app.payments.mode, "test");
    assert.ok((s.app.payments as unknown as { gateway: unknown }).gateway instanceof StripeHttpGateway);
    const health = (await (await fetch(`${s.url}/v1/health`)).json()) as any;
    assert.deepEqual(health.capabilities, ["calendar.listEvents", "payments"]);
  } finally {
    s.close();
  }
});

test("live mode without a key: native purchases are not set up, never the demo", async () => {
  const s = await serve(live);
  try {
    assert.equal(s.app.payments.mode, "test");
    assert.equal(s.app.payments.nativeConfigured, false);
    const token = new SignedSessionVerifier(Buffer.from(KEY, "base64")).mint("00000000-0000-4000-8000-0000000000ab", new Date(), 3600);
    const res = await fetch(`${s.url}/v1/purchases/prepare`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ kind: "native", merchantName: "Doddy Café", description: "Coffee", amountMinor: 1000, currency: "PLN" }),
    });
    assert.equal(res.status, 503);
    assert.equal(((await res.json()) as any).error.code, "live_not_configured");
    const health = (await (await fetch(`${s.url}/v1/health`)).json()) as any;
    assert.deepEqual(health.capabilities, ["calendar.listEvents"]);
  } finally {
    s.close();
  }
});
