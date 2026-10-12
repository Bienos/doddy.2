import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { test } from "node:test";
import { buildApp } from "../src/app.js";
import { ConfigError, loadConfig } from "../src/config.js";
import { MockPaymentWallet } from "../src/payments/wallet.js";

/** A live environment that is valid without any payment setting at all. */
const live = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "signed",
  DODDY_SESSION_SIGNING_KEY: Buffer.alloc(32, 7).toString("base64"),
  COMPOSIO_API_KEY: "k",
  COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID: "ac_cal",
  COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: "20250909_00",
};

/** Fresh keys on every run: no key material is ever written into the repository. */
function cdpEnv() {
  const ed = generateKeyPairSync("ed25519");
  const der = ed.privateKey.export({ format: "der", type: "pkcs8" });
  const publicRaw = Buffer.from(ed.publicKey.export({ format: "jwk" }).x as string, "base64url");
  const ec = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return {
    DODDY_PAYMENTS_WALLET: "coinbase_cdp",
    CDP_API_KEY_ID: "key-id",
    CDP_API_KEY_SECRET: Buffer.concat([der.subarray(der.length - 32), publicRaw]).toString("base64"),
    CDP_WALLET_SECRET: ec.privateKey.export({ format: "der", type: "pkcs8" }).toString("base64"),
    CDP_PAYMENT_ACCOUNT_ADDRESS: "0x1111111111111111111111111111111111111111",
  };
}

const problems = (env: Record<string, string>) => {
  try {
    loadConfig(env);
    return null;
  } catch (error) {
    assert.ok(error instanceof ConfigError);
    return error;
  }
};

test("by default no wallet is set up, the network is the test network, and the limits are small", () => {
  for (const env of [{}, live]) {
    const p = loadConfig(env).payments;
    assert.equal(p.wallet, "none", "the Coinbase wallet is never a default");
    assert.equal(p.cdp, null);
    assert.equal(p.network, "base-sepolia");
    assert.equal(p.maxPerPayment, 250_000);
    assert.equal(p.userDaily, 1_000_000);
    assert.equal(p.serviceDaily, 5_000_000);
    assert.deepEqual(p.allowedHosts, []);
  }
});

test("choosing the Coinbase wallet in live mode needs all four settings and valid keys", () => {
  const ok = loadConfig({ ...live, ...cdpEnv() }).payments;
  assert.equal(ok.wallet, "coinbase_cdp");
  assert.equal(ok.cdp?.accountAddress, "0x1111111111111111111111111111111111111111");

  for (const name of ["CDP_API_KEY_ID", "CDP_API_KEY_SECRET", "CDP_WALLET_SECRET", "CDP_PAYMENT_ACCOUNT_ADDRESS"]) {
    const env: Record<string, string> = { ...live, ...cdpEnv() };
    delete env[name];
    assert.match(problems(env)!.message, new RegExp(`${name} is required when DODDY_PAYMENTS_WALLET=coinbase_cdp`), name);
  }
  assert.match(problems({ ...live, ...cdpEnv(), CDP_API_KEY_SECRET: Buffer.alloc(12).toString("base64") })!.message, /CDP_API_KEY_SECRET is invalid/);
  assert.match(problems({ ...live, ...cdpEnv(), CDP_WALLET_SECRET: "AAAA" })!.message, /CDP_WALLET_SECRET is invalid/);
  assert.match(problems({ ...live, ...cdpEnv(), CDP_PAYMENT_ACCOUNT_ADDRESS: "0xabc" })!.message, /CDP_PAYMENT_ACCOUNT_ADDRESS is invalid/);
});

test("settings and key values never appear in configuration errors", () => {
  const env = { ...live, ...cdpEnv(), CDP_PAYMENT_ACCOUNT_ADDRESS: "0xabc", DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC: "hunter2" };
  const message = problems(env)!.message;
  for (const secret of [env.CDP_API_KEY_SECRET, env.CDP_WALLET_SECRET, "hunter2"]) assert.ok(!message.includes(secret));
});

test("mock mode ignores live wallet settings and never builds a Coinbase wallet", () => {
  const p = loadConfig({ ...cdpEnv(), CDP_API_KEY_SECRET: "garbage" }).payments;
  assert.equal(p.cdp, null, "mock never reads them, so garbage there is not an error");
});

test("limits must be sensible amounts and ordered", () => {
  assert.equal(loadConfig({ DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC: "1", DODDY_PAYMENTS_USER_DAILY_USDC: "5", DODDY_PAYMENTS_SERVICE_DAILY_USDC: "20" }).payments.maxPerPayment, 1_000_000);
  for (const bad of ["abc", "-1", "0", "0.001", "1e2", "20000", ""]) {
    assert.match(problems({ DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC: bad })!.message, /DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC must be an amount/, bad);
  }
  assert.match(problems({ DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC: "2", DODDY_PAYMENTS_USER_DAILY_USDC: "1" })!.message, /MAX_PER_PAYMENT_USDC must not exceed DODDY_PAYMENTS_USER_DAILY_USDC/);
  assert.match(problems({ DODDY_PAYMENTS_USER_DAILY_USDC: "9", DODDY_PAYMENTS_SERVICE_DAILY_USDC: "5" })!.message, /USER_DAILY_USDC must not exceed DODDY_PAYMENTS_SERVICE_DAILY_USDC/);
});

test("real money needs an explicit network choice, and only known networks are accepted", () => {
  assert.equal(loadConfig({ DODDY_PAYMENTS_NETWORK: "base" }).payments.network, "base");
  assert.throws(() => loadConfig({ DODDY_PAYMENTS_NETWORK: "ethereum" }), ConfigError);
  assert.throws(() => loadConfig({ DODDY_PAYMENTS_WALLET: "metamask" }), ConfigError);
});

test("the allow-list is parsed and validated", () => {
  assert.deepEqual(loadConfig({ DODDY_PAYMENTS_ALLOWED_HOSTS: " Shop.Example , api.other.test " }).payments.allowedHosts, ["shop.example", "api.other.test"]);
  assert.match(problems({ DODDY_PAYMENTS_ALLOWED_HOSTS: "https://shop.example/x" })!.message, /ALLOWED_HOSTS must be comma-separated host names/);
  assert.match(problems({ DODDY_PAYMENTS_ALLOWED_HOSTS: "localhost" })!.message, /ALLOWED_HOSTS/);
});

test("the composition root: mock mode wires the demo wallet, live without a wallet wires none", () => {
  const mock = buildApp({ ...loadConfig({ DODDY_DB_PATH: ":memory:" }) });
  try {
    assert.equal(mock.payments.status("u").wallet.kind, "mock");
    assert.equal(mock.payments.status("u").enabled, false, "even the demo wallet starts off");
  } finally {
    mock.store.close();
  }
  const liveNone = buildApp(loadConfig({ ...live, DODDY_DB_PATH: ":memory:" }));
  try {
    const status = liveNone.payments.status("u");
    assert.deepEqual([status.wallet.kind, status.wallet.configured, status.enabled], ["none", false, false]);
  } finally {
    liveNone.store.close();
  }
  const withCoinbase = buildApp({ ...loadConfig({ ...live, ...cdpEnv(), DODDY_DB_PATH: ":memory:" }) });
  try {
    const status = withCoinbase.payments.status("u");
    assert.deepEqual([status.wallet.kind, status.wallet.configured, status.wallet.account, status.enabled], ["coinbase_cdp", true, "0x1111…1111", false]);
  } finally {
    withCoinbase.store.close();
  }
  const override = buildApp(loadConfig({ DODDY_DB_PATH: ":memory:" }), { paymentWallet: null });
  try {
    assert.equal(override.payments.status("u").wallet.kind, "none");
  } finally {
    override.store.close();
  }
  assert.ok(new MockPaymentWallet().address.startsWith("0xd0dd1e"));
});
