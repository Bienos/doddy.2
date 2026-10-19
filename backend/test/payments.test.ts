import assert from "node:assert/strict";
import { once } from "node:events";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { DevSessionVerifier } from "../src/auth.js";
import { defaultRegistry } from "../src/capabilities.js";
import { type Limits, testLimits } from "../src/config.js";
import { ErrorResponseSchema } from "../src/contracts.js";
import { createHandler } from "../src/http.js";
import {
  checkoutTarget,
  formatPln,
  HandoffResultSchema,
  PrepareResultSchema,
  PurchaseResultSchema,
  PurchasesListSchema,
} from "../src/payments/contracts.js";
import {
  type ApplePayPassThrough,
  GatewayError,
  type GatewayPayment,
  MockPaymentGateway,
  type PaymentGateway,
} from "../src/payments/gateway.js";
import { NATIVE_PAYEE, PaymentsService } from "../src/payments/service.js";
import { STRIPE_CALL_CAP_MS, StripeHttpGateway } from "../src/payments/stripe.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { ConnectedAppsService } from "../src/service.js";
import { Store } from "../src/store.js";
import { Clock, USER_A, USER_B } from "./helpers.js";

/**
 * Purchases (ADR-530): the contract's shapes, the approval rules (single use, bound to the stored
 * purchase), the limits, every native outcome, the checkout hand-off, and the Stripe adapter's
 * request encoding and error mapping against a fake fetch. Nothing here reaches Stripe.
 */

const FIXTURES = join(process.cwd(), "..", "contracts", "purchases");
const fixture = (name: string) => JSON.parse(readFileSync(join(FIXTURES, `${name}.json`), "utf8")) as Record<string, any>;

/** Short fakes: a key that matches the config rule but not the guard's secret pattern. */
const TEST_KEY = "sk_test_fakefake";
const LIVE_LOOKING_KEY = "sk_live_fakefake";

// ------------------------------------------------------------------ rig

/** Wraps a gateway to count calls and optionally replace answers. Never sees more than the gateway does. */
class SpyGateway implements PaymentGateway {
  readonly calls: { op: string; idempotencyKey?: string; amountMinor?: number; description?: string; purchaseId?: string; applePay?: ApplePayPassThrough; blikCode?: string }[] = [];
  pay: ((op: "apple_pay" | "blik") => Promise<GatewayPayment>) | null = null;
  retrieveWith: ((id: string) => Promise<GatewayPayment>) | null = null;
  findWith: ((purchaseId: string) => Promise<GatewayPayment | null>) | null = null;
  cancelWith: ((id: string) => Promise<GatewayPayment>) | null = null;

  /** `mode` lets a test drive the mock's behaviour while the service runs as "test" (Stripe) mode. */
  constructor(readonly inner: PaymentGateway, readonly mode: "mock" | "test" = inner.mode) {}
  count(op: string) {
    return this.calls.filter((c) => c.op === op).length;
  }
  async payWithApplePay(input: Parameters<PaymentGateway["payWithApplePay"]>[0]) {
    this.calls.push({ op: "apple_pay", idempotencyKey: input.idempotencyKey, amountMinor: input.amountMinor, description: input.description, purchaseId: input.purchaseId, applePay: input.applePay });
    return this.pay ? this.pay("apple_pay") : this.inner.payWithApplePay(input);
  }
  async payWithBlik(input: Parameters<PaymentGateway["payWithBlik"]>[0]) {
    this.calls.push({ op: "blik", idempotencyKey: input.idempotencyKey, amountMinor: input.amountMinor, purchaseId: input.purchaseId, blikCode: input.blikCode });
    return this.pay ? this.pay("blik") : this.inner.payWithBlik(input);
  }
  async retrieve(id: string) {
    this.calls.push({ op: "retrieve" });
    return this.retrieveWith ? this.retrieveWith(id) : this.inner.retrieve(id);
  }
  async findByPurchase(purchaseId: string) {
    this.calls.push({ op: "find", purchaseId });
    return this.findWith ? this.findWith(purchaseId) : this.inner.findByPurchase(purchaseId);
  }
  async cancel(id: string) {
    this.calls.push({ op: "cancel" });
    return this.cancelWith ? this.cancelWith(id) : this.inner.cancel(id);
  }
}

interface Rig {
  call(method: string, path: string, o?: { token?: string | null; body?: unknown; raw?: string }): Promise<{ status: number; body: any; text: string }>;
  gateway: SpyGateway | null;
  payments: PaymentsService;
  store: Store;
  clock: Clock;
  logs: string[];
  close(): Promise<void>;
}

let rig: Rig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

async function start(o: { limits?: Partial<Limits>; gateway?: PaymentGateway | null; mode?: "mock" | "test"; checkoutHosts?: string[]; nowIso?: string } = {}): Promise<Rig> {
  const store = await Store.memory();
  const clock = new Clock(Date.parse(o.nowIso ?? "2026-10-18T10:00:00.000Z"));
  const limits = testLimits(o.limits);
  const mode = o.mode ?? "mock";
  const gateway =
    o.gateway === undefined ? new SpyGateway(new MockPaymentGateway(clock.now), mode) : o.gateway ? new SpyGateway(o.gateway) : null;
  const payments = new PaymentsService({ store, gateway, mode, limits, checkoutHosts: o.checkoutHosts ?? [], now: clock.now });
  const service = new ConnectedAppsService({
    store, provider: new MockCalendarProvider(), registry: defaultRegistry(), limits, publicBaseUrl: "https://api.doddy.test",
    appReturnUrl: "doddy-dev://connected-apps/return", completionMode: "mock", now: clock.now,
  });
  const logs: string[] = [];
  const handler = createHandler({
    service, payments, verifier: new DevSessionVerifier(), appReturnUrl: "doddy-dev://connected-apps/return", maxBodyBytes: 8 * 1024,
    now: () => new Date(clock.ms), log: (line) => logs.push(JSON.stringify(line)),
  });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  let closed = false;
  return {
    gateway, payments, store, clock, logs,
    async close() {
      if (closed) return;
      closed = true;
      server.close();
      await store.close();
    },
    async call(method, path, c = {}) {
      const headers: Record<string, string> = {};
      const token = c.token === undefined ? USER_A : c.token;
      if (token !== null) headers.authorization = `Bearer ${token}`;
      let body: string | undefined = c.raw;
      if (c.body !== undefined) body = JSON.stringify(c.body);
      if (body !== undefined) headers["content-type"] = "application/json";
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

const NATIVE = { kind: "native", merchantName: "Kino Muranów", description: "2 tickets, Friday 19:30", amountMinor: 5600, currency: "PLN" };
const CHECKOUT = { kind: "checkout", merchantName: "Pyszne Bistro", description: "Pad thai and spring rolls, delivery to home", amountMinor: 7450, currency: "PLN", checkoutUrl: "https://shop.example.pl/checkout?cart=abc123" };
const APPLE_PAY = { paymentData: '{"version":"EC_v1","data":"ZmFrZQ=="}', network: "Visa", instrumentName: "Visa 1234", transactionId: "abc123" };

const prepare = (r: Rig, body: Record<string, unknown>, token = USER_A) => r.call("POST", "/v1/purchases/prepare", { token, body });
const payApple = (r: Rig, p: any, token = USER_A, applePay: Record<string, unknown> = APPLE_PAY) =>
  r.call("POST", "/v1/purchases/pay", { token, body: { purchaseId: p.purchase.id, approvalId: p.approvalId, method: "apple_pay", applePay } });
const payBlik = (r: Rig, p: any, code: string, token = USER_A) =>
  r.call("POST", "/v1/purchases/pay", { token, body: { purchaseId: p.purchase.id, approvalId: p.approvalId, method: "blik", blikCode: code } });
const status = (r: Rig, id: string, token = USER_A) => r.call("POST", "/v1/purchases/status", { token, body: { purchaseId: id } });
const cancel = (r: Rig, id: string, token = USER_A) => r.call("POST", "/v1/purchases/cancel", { token, body: { purchaseId: id } });

async function prepared(r: Rig, body: Record<string, unknown> = NATIVE, token = USER_A) {
  const res = await prepare(r, body, token);
  assert.equal(res.status, 200, res.text);
  return res.body;
}

const keys = (value: unknown): string[] => Object.keys(value as object).sort();

// ------------------------------------------------------------------ contract fixtures (Swift decodes the same files)

test("contracts/purchases fixtures parse against the server's response schemas", () => {
  PrepareResultSchema.parse(fixture("prepare-result-native"));
  PrepareResultSchema.parse(fixture("prepare-result-checkout"));
  PurchaseResultSchema.parse(fixture("purchase-result-paid-apple-pay"));
  PurchaseResultSchema.parse(fixture("purchase-result-unknown"));
  PurchaseResultSchema.parse(fixture("purchase-result-waiting-blik"));
  HandoffResultSchema.parse(fixture("handoff-result"));
  PurchasesListSchema.parse(fixture("purchases-list"));
  ErrorResponseSchema.parse(fixture("error-confirmation-expired"));
});

test("responses have exactly the fixtures' keys, and the summaries match them word for word", async () => {
  rig = await start();
  const native = await prepared(rig);
  const want = fixture("prepare-result-native");
  assert.deepEqual(keys(native), keys(want));
  assert.deepEqual(keys(native.purchase), keys(want.purchase));
  PrepareResultSchema.parse(native);
  assert.equal(native.mode, "mock");
  assert.equal(native.payee, NATIVE_PAYEE);
  assert.equal(native.payee, want.payee);
  assert.deepEqual(native.methods, want.methods);
  assert.equal(native.purchase.summary, want.purchase.summary);
  assert.equal(native.purchase.checkoutHost, null);
  assert.equal(native.purchase.method, null);
  assert.equal(native.purchase.testMode, true);
  assert.equal(native.purchase.createdAt, "2026-10-18T10:00:00.000Z");
  assert.equal(native.expiresAt, "2026-10-18T10:05:00.000Z", "valid 5 minutes");

  const checkout = await prepared(rig, CHECKOUT);
  const wantCheckout = fixture("prepare-result-checkout");
  assert.deepEqual(keys(checkout), keys(wantCheckout));
  assert.deepEqual(keys(checkout.purchase), keys(wantCheckout.purchase));
  assert.equal(checkout.purchase.summary, wantCheckout.purchase.summary);
  assert.equal(checkout.payee, "shop.example.pl");
  assert.deepEqual(checkout.methods, []);
  assert.equal(checkout.purchase.testMode, false);

  rig.clock.advance(12_000);
  const paid = await payApple(rig, native);
  assert.equal(paid.status, 200, paid.text);
  const wantPaid = fixture("purchase-result-paid-apple-pay");
  assert.deepEqual(keys(paid.body), keys(wantPaid));
  assert.deepEqual(keys(paid.body.purchase), keys(wantPaid.purchase));
  assert.equal(paid.body.purchase.summary, wantPaid.purchase.summary);
  assert.equal(paid.body.purchase.updatedAt, wantPaid.purchase.updatedAt);

  const handed = await rig.call("POST", "/v1/purchases/handoff", { body: { purchaseId: checkout.purchase.id, approvalId: checkout.approvalId } });
  const wantHanded = fixture("handoff-result");
  assert.deepEqual(keys(handed.body), keys(wantHanded));
  assert.equal(handed.body.purchase.summary, wantHanded.purchase.summary);
  assert.equal(handed.body.checkoutUrl, wantHanded.checkoutUrl);

  const reported = await rig.call("POST", "/v1/purchases/report", { body: { purchaseId: checkout.purchase.id, paid: true } });
  const list = await rig.call("GET", "/v1/purchases");
  const wantList = fixture("purchases-list");
  assert.deepEqual(keys(list.body), keys(wantList));
  assert.deepEqual(list.body.purchases.map((p: any) => p.summary), wantList.purchases.map((p: any) => p.summary));
  assert.equal(reported.body.purchase.summary, wantList.purchases[0].summary);
  PurchasesListSchema.parse(list.body);
});

test("BLIK waiting and outcome-unknown summaries match the fixtures", async () => {
  rig = await start();
  const p = await prepared(rig);
  const waiting = await payBlik(rig, p, "123456");
  assert.equal(waiting.body.purchase.status, "waiting_for_bank");
  assert.equal(waiting.body.purchase.summary, fixture("purchase-result-waiting-blik").purchase.summary);
  assert.equal(waiting.body.purchase.method, "blik");

  const unknownRig = await start({ mode: "test" });
  try {
    unknownRig.gateway!.pay = async () => {
      throw new GatewayError("unknown");
    };
    const q = await prepared(unknownRig);
    const unsure = await payApple(unknownRig, q);
    const want = fixture("purchase-result-unknown");
    assert.deepEqual(keys(unsure.body), keys(want));
    assert.equal(unsure.body.mode, "test");
    assert.equal(unsure.body.purchase.status, "outcome_unknown");
    assert.equal(unsure.body.purchase.summary, want.purchase.summary);
  } finally {
    await unknownRig.close();
  }
});

test("the confirmation-expired error is exactly the fixture's", async () => {
  rig = await start();
  const p = await prepared(rig);
  rig.clock.advance(300_000);
  const res = await payApple(rig, p);
  const want = fixture("error-confirmation-expired");
  assert.equal(res.status, 403);
  assert.deepEqual(keys(res.body.error), keys(want.error));
  assert.equal(res.body.error.code, want.error.code);
  assert.equal(res.body.error.message, want.error.message);
});

// ------------------------------------------------------------------ access and validation

test("every purchases route needs a valid session", async () => {
  rig = await start();
  const routes: [string, string][] = [
    ["GET", "/v1/purchases"],
    ...["prepare", "pay", "status", "cancel", "handoff", "report"].map((r) => ["POST", `/v1/purchases/${r}`] as [string, string]),
  ];
  for (const [method, path] of routes) {
    for (const token of [null, "dev-user-z"]) {
      const res = await rig.call(method, path, { token, ...(method === "POST" ? { body: {} } : {}) });
      assert.equal(res.status, 401, `${method} ${path}`);
    }
  }
  assert.equal(rig.gateway!.calls.length, 0);
});

test("purchases routes exist only when the service is wired", async () => {
  const store = await Store.memory();
  const service = new ConnectedAppsService({
    store, provider: new MockCalendarProvider(), registry: defaultRegistry(), limits: testLimits(), publicBaseUrl: "https://api.doddy.test",
    appReturnUrl: "doddy-dev://connected-apps/return", completionMode: "mock",
  });
  const handler = createHandler({ service, verifier: new DevSessionVerifier(), appReturnUrl: "doddy-dev://connected-apps/return", maxBodyBytes: 8192, log: () => {} });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const res = await fetch(`http://127.0.0.1:${(server.address() as AddressInfo).port}/v1/purchases`, { headers: { authorization: `Bearer ${USER_A}` } });
    assert.equal(res.status, 404);
  } finally {
    server.close();
    await store.close();
  }
});

test("prepare refuses what the contract refuses", async () => {
  rig = await start({ checkoutHosts: [] });
  const bad: [string, Record<string, unknown>][] = [
    ["euro", { ...NATIVE, currency: "EUR" }],
    ["lowercase pln", { ...NATIVE, currency: "pln" }],
    ["native below 2 zł", { ...NATIVE, amountMinor: 199 }],
    ["fraction of a grosz", { ...NATIVE, amountMinor: 56.5 }],
    ["zero", { ...CHECKOUT, amountMinor: 0 }],
    ["native with a checkout page", { ...NATIVE, checkoutUrl: "https://shop.example.pl/checkout" }],
    ["checkout without a page", { ...CHECKOUT, checkoutUrl: undefined }],
    ["http", { ...CHECKOUT, checkoutUrl: "http://shop.example.pl/checkout" }],
    ["IPv4", { ...CHECKOUT, checkoutUrl: "https://192.168.1.10/checkout" }],
    ["IPv4 in another spelling", { ...CHECKOUT, checkoutUrl: "https://3232235786/checkout" }],
    ["IPv6", { ...CHECKOUT, checkoutUrl: "https://[::1]/checkout" }],
    ["localhost", { ...CHECKOUT, checkoutUrl: "https://localhost/checkout" }],
    ["user name", { ...CHECKOUT, checkoutUrl: "https://user@shop.example.pl/checkout" }],
    ["password", { ...CHECKOUT, checkoutUrl: "https://user:pass@shop.example.pl/checkout" }],
    ["javascript", { ...CHECKOUT, checkoutUrl: "javascript:alert(1)" }],
    ["too long", { ...CHECKOUT, checkoutUrl: `https://shop.example.pl/${"a".repeat(2048)}` }],
    ["empty merchant", { ...NATIVE, merchantName: "   " }],
    ["long merchant", { ...NATIVE, merchantName: "m".repeat(81) }],
    ["long description", { ...NATIVE, description: "d".repeat(201) }],
    ["unknown kind", { ...NATIVE, kind: "crypto" }],
    ["unknown key (user)", { ...NATIVE, userId: USER_B }],
    ["unknown key (stripe)", { ...NATIVE, paymentIntent: "pi_123" }],
  ];
  for (const [name, body] of bad) {
    const res = await prepare(rig, body);
    assert.equal(res.status, 400, `${name}: ${res.text}`);
    assert.equal(res.body.error.code, "invalid_request", name);
  }
  assert.equal((await rig.call("GET", "/v1/purchases")).body.purchases.length, 0, "nothing was kept");
  // Plain, specific messages, never an echo of the request.
  const euro = await prepare(rig, { ...NATIVE, currency: "EUR" });
  assert.match(euro.body.error.message, /złoty/);
  const ip = await prepare(rig, { ...CHECKOUT, checkoutUrl: "https://10.0.0.1/x" });
  assert.match(ip.body.error.message, /https page/);
  assert.ok(!ip.text.includes("10.0.0.1"));
  // Edges that are fine: 80 characters, trimmed, exactly 2 zł, a checkout at 1 grosz.
  assert.equal((await prepare(rig, { ...NATIVE, merchantName: ` ${"m".repeat(80)} `, amountMinor: 200 })).status, 200);
  assert.equal((await prepare(rig, { ...CHECKOUT, amountMinor: 1 })).status, 200);
});

test("the shop allowlist accepts the host and its subdomains only", async () => {
  rig = await start({ checkoutHosts: ["example.pl"] });
  assert.equal((await prepare(rig, { ...CHECKOUT, checkoutUrl: "https://example.pl/c" })).status, 200);
  assert.equal((await prepare(rig, { ...CHECKOUT, checkoutUrl: "https://shop.example.pl/c" })).status, 200);
  const other = await prepare(rig, { ...CHECKOUT, checkoutUrl: "https://notexample.pl/c" });
  assert.equal(other.status, 400);
  assert.match(other.body.error.message, /allowed shops/);
  assert.equal((await prepare(rig, { ...CHECKOUT, checkoutUrl: "https://example.pl.evil.com/c" })).status, 400);
  // The checker on its own.
  assert.deepEqual(checkoutTarget("https://SHOP.Example.PL/a?b=1", []), { ok: true, url: "https://shop.example.pl/a?b=1", host: "shop.example.pl" });
  assert.equal(checkoutTarget("https://0x7f.0.0.1/", []).ok, false);
});

test("Polish price format", () => {
  assert.equal(formatPln(5600), "56,00 zł");
  assert.equal(formatPln(7450), "74,50 zł");
  assert.equal(formatPln(123450), "1 234,50 zł");
  assert.equal(formatPln(200), "2,00 zł");
  assert.equal(formatPln(5), "0,05 zł");
  assert.equal(formatPln(100000000), "1 000 000,00 zł");
});

// ------------------------------------------------------------------ limits

test("per-purchase cap, daily total and daily count", async () => {
  rig = await start({ limits: { purchaseMaxMinor: 20_000, purchaseDailyMaxMinor: 30_000, userDailyPurchases: 3 } });
  const over = await prepare(rig, { ...NATIVE, amountMinor: 20_001 });
  assert.equal(over.status, 403);
  assert.equal(over.body.error.code, "capability_disabled");
  assert.match(over.body.error.message, /limit of 200,00 zł for one purchase\. Nothing was paid\./);

  // A prepared purchase doesn't count against the total; a paid one does.
  const first = await prepared(rig, { ...NATIVE, amountMinor: 20_000 });
  assert.equal((await payApple(rig, first)).body.purchase.status, "paid");
  const second = await prepare(rig, { ...NATIVE, amountMinor: 10_001 });
  assert.equal(second.status, 403);
  assert.match(second.body.error.message, /limit of 300,00 zł a day\. Nothing was paid\./);
  // Refused prepares are not counted: two more fit in the count of three.
  await prepared(rig, { ...CHECKOUT, amountMinor: 5_000 });
  await prepared(rig, { ...NATIVE, amountMinor: 5_000 });
  const fourth = await prepare(rig, { ...NATIVE, amountMinor: 200 });
  assert.equal(fourth.status, 429);
  assert.equal(fourth.body.error.code, "quota_exceeded");
  assert.match(fourth.body.error.message, /3 purchases a day/);
  // Another user has their own limits.
  assert.equal((await prepare(rig, { ...NATIVE, amountMinor: 20_000 }, USER_B)).status, 200);
  // A new UTC day starts again.
  rig.clock.advance(86_400_000);
  assert.equal((await prepare(rig, { ...NATIVE, amountMinor: 20_000 })).status, 200);
});

test("the daily cap is counted again at pay time, so two cards can't both go over it", async () => {
  rig = await start({ limits: { purchaseDailyMaxMinor: 30_000 } });
  const a = await prepared(rig, { ...NATIVE, amountMinor: 20_000 });
  const b = await prepared(rig, { ...NATIVE, amountMinor: 20_000 });
  assert.equal((await payApple(rig, a)).body.purchase.status, "paid");
  const refused = await payApple(rig, b);
  assert.equal(refused.status, 403);
  assert.match(refused.body.error.message, /a day\. Nothing was paid\./);
  assert.equal(rig.gateway!.count("apple_pay"), 1);
  // The approval was not burnt and the purchase is still waiting for a tap.
  assert.equal((await status(rig, b.purchase.id)).body.purchase.status, "awaiting_tap");
});

test("handed-off checkouts count against the daily total", async () => {
  rig = await start({ limits: { purchaseDailyMaxMinor: 10_000 } });
  const c = await prepared(rig, { ...CHECKOUT, amountMinor: 8_000 });
  assert.equal((await rig.call("POST", "/v1/purchases/handoff", { body: { purchaseId: c.purchase.id, approvalId: c.approvalId } })).status, 200);
  assert.equal((await prepare(rig, { ...NATIVE, amountMinor: 2_001 })).status, 403);
  assert.equal((await prepare(rig, { ...NATIVE, amountMinor: 2_000 })).status, 200);
});

test("native purchases without a payment gateway say so; checkout still works", async () => {
  rig = await start({ gateway: null, mode: "test" });
  const res = await prepare(rig, NATIVE);
  assert.equal(res.status, 503);
  assert.equal(res.body.error.code, "live_not_configured");
  assert.equal(res.body.error.message, "Payments aren't set up on this server.");
  const checkout = await prepared(rig, CHECKOUT);
  assert.equal(checkout.mode, "test");
  const health = await rig.call("GET", "/v1/health", { token: null });
  assert.deepEqual(health.body.capabilities, ["calendar.listEvents"]);
});

test("health lists payments when a gateway is set up", async () => {
  rig = await start();
  assert.deepEqual((await rig.call("GET", "/v1/health", { token: null })).body.capabilities, ["calendar.listEvents", "payments"]);
});

// ------------------------------------------------------------------ approvals

test("an approval is single-use: a second pay never charges again", async () => {
  rig = await start();
  const p = await prepared(rig);
  const first = await payApple(rig, p);
  assert.equal(first.body.purchase.status, "paid");
  const again = await payApple(rig, p);
  assert.equal(again.status, 200);
  assert.equal(again.body.purchase.status, "paid");
  assert.equal(rig.gateway!.count("apple_pay"), 1, "charged once");
  // Even switching the method doesn't make a second payment.
  const blik = await payBlik(rig, p, "123456");
  assert.equal(blik.body.purchase.status, "paid");
  assert.equal(rig.gateway!.count("blik"), 0);
  // Another approval (here: a different purchase's) gets no answer about this one.
  const other = await prepared(rig);
  const wrong = await rig.call("POST", "/v1/purchases/pay", { body: { purchaseId: p.purchase.id, approvalId: other.approvalId, method: "apple_pay", applePay: APPLE_PAY } });
  assert.equal(wrong.status, 403);
  assert.equal(rig.gateway!.count("apple_pay"), 1);
});

test("two pays racing with the same approval charge once", async () => {
  rig = await start({ mode: "test" });
  const p = await prepared(rig);
  let release: () => void = () => {};
  const gate = new Promise<void>((r) => (release = r));
  rig.gateway!.pay = async () => {
    await gate;
    return { paymentId: "pi_race_1", state: "succeeded" };
  };
  const one = payApple(rig, p);
  const two = payApple(rig, p);
  await new Promise((r) => setTimeout(r, 50));
  release();
  const answers = await Promise.all([one, two]);
  assert.equal(rig.gateway!.count("apple_pay"), 1);
  assert.deepEqual(answers.map((a) => a.status), [200, 200]);
  assert.ok(answers.some((a) => a.body.purchase.status === "paid"));
});

test("the approval is bound to the stored purchase, its owner and its kind", async () => {
  rig = await start();
  const a = await prepared(rig);
  const b = await prepared(rig, { ...NATIVE, amountMinor: 9_900 });
  // Another user's purchase is not found, whatever approval comes with it.
  const theirs = await payApple(rig, a, USER_B);
  assert.equal(theirs.status, 404);
  // A's approval can't pay B.
  const swapped = await rig.call("POST", "/v1/purchases/pay", { body: { purchaseId: b.purchase.id, approvalId: a.approvalId, method: "apple_pay", applePay: APPLE_PAY } });
  assert.equal(swapped.status, 403);
  assert.equal(swapped.body.error.message, "This purchase needs a fresh confirmation. Nothing was paid.");
  // A pay body can't carry an amount or a payee: the purchase is read from the store.
  const tampered = await rig.call("POST", "/v1/purchases/pay", { body: { purchaseId: a.purchase.id, approvalId: a.approvalId, method: "apple_pay", applePay: APPLE_PAY, amountMinor: 1 } });
  assert.equal(tampered.status, 400);
  // A checkout approval can't be used for a native pay, and vice versa.
  const c = await prepared(rig, CHECKOUT);
  assert.equal((await rig.call("POST", "/v1/purchases/pay", { body: { purchaseId: c.purchase.id, approvalId: c.approvalId, method: "blik", blikCode: "123456" } })).status, 400);
  assert.equal((await rig.call("POST", "/v1/purchases/handoff", { body: { purchaseId: a.purchase.id, approvalId: a.approvalId } })).status, 400);
  assert.equal(rig.gateway!.calls.length, 0, "nothing reached the gateway");
  // The real pay still works and charges exactly what the card showed.
  assert.equal((await payApple(rig, a)).body.purchase.status, "paid");
  assert.equal(rig.gateway!.calls[0]!.amountMinor, 5600);
  assert.equal(rig.gateway!.calls[0]!.idempotencyKey, `purchase:${a.purchase.id}:apple_pay`);
  assert.equal(rig.gateway!.calls[0]!.description, "Kino Muranów: 2 tickets, Friday 19:30");
});

test("a changed stored purchase no longer matches its approval", async () => {
  rig = await start();
  const p = await prepared(rig);
  await rig.store.db.query("UPDATE purchases SET amount_minor = 19900 WHERE purchase_id = $1", [p.purchase.id]);
  const res = await payApple(rig, p);
  assert.equal(res.status, 403);
  assert.equal(rig.gateway!.calls.length, 0);
});

test("an expired approval marks the purchase expired and pays nothing", async () => {
  rig = await start();
  const p = await prepared(rig);
  rig.clock.advance(300_000);
  const res = await payApple(rig, p);
  assert.equal(res.status, 403);
  assert.equal(res.body.error.code, "capability_disabled");
  assert.equal(rig.gateway!.calls.length, 0);
  const now = await status(rig, p.purchase.id);
  assert.equal(now.body.purchase.status, "expired");
  assert.match(now.body.purchase.summary, /ran out/);
  // And it stays refused.
  assert.equal((await payApple(rig, p)).status, 403);
});

test("an unpaid card past its expiry shows as expired in status and the list", async () => {
  rig = await start();
  const p = await prepared(rig);
  rig.clock.advance(301_000);
  assert.equal((await rig.call("GET", "/v1/purchases")).body.purchases[0].status, "expired");
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "expired");
});

// ------------------------------------------------------------------ native outcomes

test("Apple Pay success is paid, with the token passed through untouched and never stored", async () => {
  rig = await start();
  const p = await prepared(rig);
  const res = await payApple(rig, p);
  assert.equal(res.status, 200);
  assert.equal(res.body.purchase.status, "paid");
  assert.equal(res.body.purchase.method, "apple_pay");
  assert.deepEqual(rig.gateway!.calls[0]!.applePay, APPLE_PAY);
  const row = (await rig.store.getPurchase("00000000-0000-4000-8000-00000000000a", p.purchase.id))!;
  assert.equal(row.payment_id, "mock_pi_1");
  const dump = JSON.stringify((await rig.store.db.query("SELECT * FROM purchases")).rows) + JSON.stringify((await rig.store.db.query("SELECT * FROM approvals")).rows);
  assert.ok(!dump.includes("EC_v1") && !dump.includes("ZmFrZQ"), "no token in the database");
  assert.ok(!rig.logs.join("\n").includes("EC_v1"), "no token in the logs");
  // ADR-322: the approval's outcome is recorded with the payment id.
  const approval = (await rig.store.db.query("SELECT outcome, external_id FROM approvals WHERE approval_id = $1", [p.approvalId])).rows[0] as any;
  assert.deepEqual({ ...approval }, { outcome: "succeeded", external_id: "mock_pi_1" });
});

test("an Apple Pay token up to 24 KB is accepted on the pay route; bigger is refused", async () => {
  rig = await start();
  const p = await prepared(rig);
  const big = await payApple(rig, p, USER_A, { paymentData: "x".repeat(24 * 1024 + 1) });
  assert.equal(big.status, 400);
  const ok = await payApple(rig, p, USER_A, { paymentData: "x".repeat(20 * 1024) });
  assert.equal(ok.status, 200, "a 20 KB token fits the pay route's 32 KB limit");
  // Other routes keep the default limit.
  const tooBig = await rig.call("POST", "/v1/purchases/prepare", { raw: JSON.stringify({ ...NATIVE, description: "x".repeat(9_000) }) });
  assert.equal(tooBig.status, 413);
  const payTooBig = await rig.call("POST", "/v1/purchases/pay", { raw: JSON.stringify({ x: "y".repeat(33 * 1024) }) });
  assert.equal(payTooBig.status, 413);
});

test("BLIK waits for the bank, then status after 3 seconds says paid; the code is never stored", async () => {
  rig = await start();
  const p = await prepared(rig);
  const waiting = await payBlik(rig, p, "777123");
  assert.equal(waiting.body.purchase.status, "waiting_for_bank");
  rig.clock.advance(2_000);
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "waiting_for_bank");
  rig.clock.advance(1_000);
  const done = await status(rig, p.purchase.id);
  assert.equal(done.body.purchase.status, "paid");
  assert.equal(done.body.purchase.summary, "Paid 56,00 zł with BLIK (test mode, no real money).");
  const dump = JSON.stringify((await rig.store.db.query("SELECT * FROM purchases")).rows);
  assert.ok(!dump.includes("777123"), "no BLIK code in the database");
  assert.ok(!rig.logs.join("\n").includes("777123"), "no BLIK code in the logs");
  // Paid stays paid; status reads nothing more.
  const reads = rig.gateway!.count("retrieve");
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "paid");
  assert.equal(rig.gateway!.count("retrieve"), reads);
});

test("BLIK 000000 is declined: failed, nothing charged", async () => {
  rig = await start();
  const p = await prepared(rig);
  const res = await payBlik(rig, p, "000000");
  assert.equal(res.body.purchase.status, "failed");
  assert.equal(res.body.purchase.summary, "The payment of 56,00 zł was declined. Nothing was charged (test mode, no real money).");
  const approval = (await rig.store.db.query("SELECT outcome FROM approvals WHERE approval_id = $1", [p.approvalId])).rows[0] as any;
  assert.equal(approval.outcome, "failed");
  // A malformed code never reaches the gateway.
  const q = await prepared(rig);
  for (const code of ["12345", "1234567", "12 345", "abcdef"]) {
    const bad = await payBlik(rig, q, code);
    assert.equal(bad.status, 400, code);
    assert.match(bad.body.error.message, /six digits/);
  }
  assert.equal(rig.gateway!.count("blik"), 1);
});

test("unknown outcome: never paid, never retried; status keeps it unknown until Stripe has it", async () => {
  rig = await start({ mode: "test" });
  const g = rig.gateway!;
  g.pay = async () => {
    throw new GatewayError("unknown");
  };
  const p = await prepared(rig);
  const res = await payApple(rig, p);
  assert.equal(res.status, 200);
  assert.equal(res.body.purchase.status, "outcome_unknown");
  // A second pay with the same approval charges nothing; it only looks.
  assert.equal((await payApple(rig, p)).body.purchase.status, "outcome_unknown");
  assert.equal(g.count("apple_pay"), 1);
  // Stripe lists nothing (yet): still unknown.
  g.findWith = async () => null;
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "outcome_unknown");
  // Reading fails: still unknown.
  g.findWith = async () => {
    throw new GatewayError("unknown");
  };
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "outcome_unknown");
  // Stripe has it, and it succeeded.
  g.findWith = async () => ({ paymentId: "pi_found_1", state: "succeeded" });
  const found = await status(rig, p.purchase.id);
  assert.equal(found.body.purchase.status, "paid");
  assert.equal(g.count("apple_pay"), 1, "never charged again");
  assert.equal((await rig.store.getPurchase("00000000-0000-4000-8000-00000000000a", p.purchase.id))!.payment_id, "pi_found_1");
  // The approval stayed unfinished while unsure, then succeeded.
  const approval = (await rig.store.db.query("SELECT outcome, external_id FROM approvals WHERE approval_id = $1", [p.approvalId])).rows[0] as any;
  assert.deepEqual({ ...approval }, { outcome: "succeeded", external_id: "pi_found_1" });
});

test("an unexpected gateway failure (not a typed answer) is outcome_unknown, never failed", async () => {
  rig = await start({ mode: "test" });
  rig.gateway!.pay = async () => {
    throw new TypeError("boom");
  };
  const p = await prepared(rig);
  assert.equal((await payApple(rig, p)).body.purchase.status, "outcome_unknown");
});

test("not_sent and rejected are failed with nothing charged", async () => {
  rig = await start({ mode: "test" });
  const p = await prepared(rig);
  rig.gateway!.pay = async () => {
    throw new GatewayError("not_sent");
  };
  const notSent = await payApple(rig, p);
  assert.equal(notSent.body.purchase.status, "failed");
  assert.equal(notSent.body.purchase.summary, "The payment of 56,00 zł didn't go through. Nothing was charged (test mode, no real money).");
  const q = await prepared(rig);
  rig.gateway!.pay = async () => {
    throw new GatewayError("rejected", { paymentId: "pi_rej_1", declineCode: "card_declined" });
  };
  const rejected = await payApple(rig, q);
  assert.equal(rejected.body.purchase.status, "failed");
  assert.match(rejected.body.purchase.summary, /declined\. Nothing was charged/);
});

test("a card that asks for 3-D Secure is cancelled and reported as not charged", async () => {
  rig = await start({ mode: "test" });
  const g = rig.gateway!;
  g.pay = async () => ({ paymentId: "pi_3ds_1", state: "needs_card_check" });
  g.cancelWith = async (id) => ({ paymentId: id, state: "canceled" });
  const p = await prepared(rig);
  const res = await payApple(rig, p);
  assert.equal(res.body.purchase.status, "failed");
  assert.equal(res.body.purchase.summary, "Your bank asked for an extra check Doddy can't show yet. Nothing was charged; try BLIK (test mode, no real money).");
  assert.equal(g.count("cancel"), 1);
});

test("processing stays paying, and status settles it", async () => {
  rig = await start({ mode: "test" });
  const g = rig.gateway!;
  g.pay = async () => ({ paymentId: "pi_proc_1", state: "processing" });
  const p = await prepared(rig);
  assert.equal((await payApple(rig, p)).body.purchase.status, "paying");
  g.retrieveWith = async (id) => ({ paymentId: id, state: "succeeded" });
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "paid");
});

// ------------------------------------------------------------------ cancel

test("cancel before paying, and while BLIK waits for the bank", async () => {
  rig = await start();
  const a = await prepared(rig);
  const cancelled = await cancel(rig, a.purchase.id);
  assert.equal(cancelled.body.purchase.status, "cancelled");
  assert.equal((await payApple(rig, a)).status, 403, "a cancelled card can't be paid");

  const b = await prepared(rig);
  assert.equal((await payBlik(rig, b, "123456")).body.purchase.status, "waiting_for_bank");
  const stopped = await cancel(rig, b.purchase.id);
  assert.equal(stopped.body.purchase.status, "cancelled");
  assert.equal(rig.gateway!.count("cancel"), 1);
  // Even after the 3 seconds, a cancelled payment stays cancelled.
  rig.clock.advance(5_000);
  assert.equal((await status(rig, b.purchase.id)).body.purchase.status, "cancelled");

  // If the bank approved before the cancel arrived, it is paid.
  const c = await prepared(rig);
  await payBlik(rig, c, "123456");
  rig.clock.advance(3_000);
  assert.equal((await cancel(rig, c.purchase.id)).body.purchase.status, "paid");

  // Paid and other states are answered as they are.
  const before = rig.gateway!.calls.length;
  assert.equal((await cancel(rig, c.purchase.id)).body.purchase.status, "paid");
  assert.equal(rig.gateway!.calls.length, before);
  // Another user's purchase is not found.
  assert.equal((await cancel(rig, c.purchase.id, USER_B)).status, 404);
});

// ------------------------------------------------------------------ checkout

test("handoff returns the stored page and is repeatable; report records the user's word", async () => {
  rig = await start();
  const c = await prepared(rig, CHECKOUT);
  const body = { purchaseId: c.purchase.id, approvalId: c.approvalId };
  const handed = await rig.call("POST", "/v1/purchases/handoff", { body });
  assert.equal(handed.status, 200);
  assert.equal(handed.body.purchase.status, "handed_off");
  assert.equal(handed.body.checkoutUrl, CHECKOUT.checkoutUrl);
  // The phone lost the answer: the same approval answers the same.
  const again = await rig.call("POST", "/v1/purchases/handoff", { body });
  assert.equal(again.status, 200);
  assert.equal(again.body.checkoutUrl, CHECKOUT.checkoutUrl);
  // Another user can't open it or report on it.
  assert.equal((await rig.call("POST", "/v1/purchases/handoff", { token: USER_B, body })).status, 404);
  assert.equal((await rig.call("POST", "/v1/purchases/report", { token: USER_B, body: { purchaseId: c.purchase.id, paid: true } })).status, 404);
  const reported = await rig.call("POST", "/v1/purchases/report", { body: { purchaseId: c.purchase.id, paid: true } });
  assert.equal(reported.body.purchase.status, "user_reported_paid");
  assert.equal(reported.body.purchase.summary, "You said you paid at shop.example.pl. Doddy didn't see the payment itself.");
  // Repeating the same answer is fine; changing it isn't.
  assert.equal((await rig.call("POST", "/v1/purchases/report", { body: { purchaseId: c.purchase.id, paid: true } })).status, 200);
  assert.equal((await rig.call("POST", "/v1/purchases/report", { body: { purchaseId: c.purchase.id, paid: false } })).status, 400);
  assert.equal(rig.gateway!.calls.length, 0, "checkout never touches the gateway");
});

test("report before hand-off is refused; paid=false cancels", async () => {
  rig = await start();
  const c = await prepared(rig, CHECKOUT);
  assert.equal((await rig.call("POST", "/v1/purchases/report", { body: { purchaseId: c.purchase.id, paid: true } })).status, 400);
  await rig.call("POST", "/v1/purchases/handoff", { body: { purchaseId: c.purchase.id, approvalId: c.approvalId } });
  const no = await rig.call("POST", "/v1/purchases/report", { body: { purchaseId: c.purchase.id, paid: false } });
  assert.equal(no.body.purchase.status, "cancelled");
  assert.match(no.body.purchase.summary, /You said you didn't pay at shop\.example\.pl/);
});

test("handoff needs the purchase's own unexpired approval", async () => {
  rig = await start();
  const c = await prepared(rig, CHECKOUT);
  const d = await prepared(rig, CHECKOUT);
  assert.equal((await rig.call("POST", "/v1/purchases/handoff", { body: { purchaseId: c.purchase.id, approvalId: d.approvalId } })).status, 403);
  rig.clock.advance(300_000);
  const late = await rig.call("POST", "/v1/purchases/handoff", { body: { purchaseId: c.purchase.id, approvalId: c.approvalId } });
  assert.equal(late.status, 403);
  assert.equal((await status(rig, c.purchase.id)).body.purchase.status, "expired");
});

// ------------------------------------------------------------------ list and isolation

test("the list is the user's own, newest first, last 90 days, at most 50", async () => {
  rig = await start({ limits: { userDailyPurchases: 100, purchaseDailyMaxMinor: 10_000_000, purchaseMaxMinor: 10_000_000 } });
  const old = await prepared(rig, NATIVE);
  rig.clock.advance(91 * 86_400_000);
  const theirs = await prepared(rig, NATIVE, USER_B);
  for (let i = 0; i < 52; i++) {
    rig.clock.advance(1_000);
    await prepared(rig, { ...NATIVE, amountMinor: 200 + i });
  }
  const mine = (await rig.call("GET", "/v1/purchases")).body.purchases;
  assert.equal(mine.length, 50);
  assert.equal(mine[0].amountMinor, 251, "newest first");
  assert.ok(!mine.some((p: any) => p.id === old.purchase.id), "older than 90 days is not listed");
  assert.ok(!mine.some((p: any) => p.id === theirs.purchase.id), "another user's purchase is not listed");
  const b = (await rig.call("GET", "/v1/purchases", { token: USER_B })).body.purchases;
  assert.deepEqual(b.map((p: any) => p.id), [theirs.purchase.id]);
  assert.equal((await status(rig, theirs.purchase.id)).status, 404);
});

test("prune drops purchases older than 90 days", async () => {
  rig = await start();
  await prepared(rig);
  rig.clock.advance(91 * 86_400_000);
  const kept = await prepared(rig);
  const gone = await rig.store.prune(rig.clock.now());
  assert.equal(gone.purchases, 1);
  assert.deepEqual((await rig.call("GET", "/v1/purchases")).body.purchases.map((p: any) => p.id), [kept.purchase.id]);
});

test("a mock gateway can't be used with test mode, nor Stripe with mock mode", async () => {
  const store = await Store.memory();
  try {
    assert.throws(() => new PaymentsService({ store, gateway: new MockPaymentGateway(), mode: "test", limits: testLimits(), checkoutHosts: [] }));
    assert.throws(() => new PaymentsService({ store, gateway: new StripeHttpGateway({ secretKey: TEST_KEY, timeoutMs: 1000 }), mode: "mock", limits: testLimits(), checkoutHosts: [] }));
  } finally {
    await store.close();
  }
});

test("logs are content-free: route templates and codes only", async () => {
  rig = await start();
  const p = await prepared(rig);
  await payBlik(rig, p, "424242");
  const text = rig.logs.join("\n");
  for (const secret of ["424242", "Kino", "tickets", p.purchase.id, p.approvalId]) assert.ok(!text.includes(secret), secret);
});

// ------------------------------------------------------------------ Stripe adapter (fake fetch)

interface Sent {
  url: string;
  method: string;
  headers: Record<string, string>;
  form: URLSearchParams | null;
}

function fakeStripe(answers: ((req: Sent) => Response | Promise<Response>)[]) {
  const sent: Sent[] = [];
  const fetchImpl = (async (input: string | URL | Request, init?: RequestInit) => {
    const headers = Object.fromEntries(Object.entries((init?.headers ?? {}) as Record<string, string>).map(([k, v]) => [k.toLowerCase(), v]));
    const req: Sent = { url: String(input), method: init?.method ?? "GET", headers, form: typeof init?.body === "string" ? new URLSearchParams(init.body) : null };
    sent.push(req);
    const next = answers.shift();
    if (!next) throw new Error("unexpected request");
    return next(req);
  }) as typeof fetch;
  return { sent, fetchImpl };
}

const json = (status: number, body: unknown) => () => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const PID = "6f1c2b9e-3a4d-4f5e-8a7b-1c2d3e4f5a6b";
const common = { purchaseId: PID, amountMinor: 5600, currency: "PLN" as const, description: "Kino Muranów: 2 tickets, Friday 19:30", idempotencyKey: `purchase:${PID}:apple_pay` };
const stripe = (fetchImpl: typeof fetch, secretKey = TEST_KEY) => new StripeHttpGateway({ secretKey, timeoutMs: 500 }, fetchImpl);

test("Stripe Apple Pay: tokens call with Stripe's own pk_token parameters, a card PaymentMethod, then a confirmed PaymentIntent", async () => {
  const { sent, fetchImpl } = fakeStripe([
    json(200, { id: "tok_1AbC", object: "token" }),
    json(200, { id: "pm_1AbC", object: "payment_method", type: "card" }),
    json(200, { id: "pi_1AbC", object: "payment_intent", status: "succeeded", payment_method_types: ["card"] }),
  ]);
  const result = await stripe(fetchImpl).payWithApplePay({ ...common, applePay: APPLE_PAY });
  assert.deepEqual(result, { paymentId: "pi_1AbC", state: "succeeded" });
  const [token, method, pi] = sent as [Sent, Sent, Sent];
  assert.equal(token.url, "https://api.stripe.com/v1/tokens");
  assert.equal(token.method, "POST");
  assert.equal(token.headers["content-type"], "application/x-www-form-urlencoded");
  assert.equal(token.headers.authorization, `Bearer ${TEST_KEY}`);
  assert.equal(token.headers["idempotency-key"], `purchase:${PID}:apple_pay:token`);
  assert.equal(token.headers["stripe-version"], undefined, "the account's default API version applies");
  assert.deepEqual([...token.form!.entries()], [
    ["pk_token", APPLE_PAY.paymentData],
    ["pk_token_instrument_name", "Visa 1234"],
    ["pk_token_payment_network", "Visa"],
    ["pk_token_transaction_id", "abc123"],
  ]);
  assert.equal(method.url, "https://api.stripe.com/v1/payment_methods");
  assert.equal(method.method, "POST");
  assert.equal(method.headers["idempotency-key"], `purchase:${PID}:apple_pay:method`);
  assert.deepEqual([...method.form!.entries()], [["type", "card"], ["card[token]", "tok_1AbC"]]);
  // Bracket notation on the wire.
  assert.match(new URLSearchParams(method.form!).toString(), /card%5Btoken%5D=tok_1AbC/);
  assert.equal(pi.url, "https://api.stripe.com/v1/payment_intents");
  assert.equal(pi.headers["idempotency-key"], `purchase:${PID}:apple_pay`);
  assert.deepEqual(Object.fromEntries(pi.form!.entries()), {
    amount: "5600",
    currency: "pln",
    confirm: "true",
    "payment_method_types[]": "card",
    payment_method: "pm_1AbC",
    description: "Kino Muranów: 2 tickets, Friday 19:30",
    "metadata[purchase_id]": PID,
  });
});

test("Stripe Apple Pay: an empty token uses tok_visa with a test key only", async () => {
  const { sent, fetchImpl } = fakeStripe([json(200, { id: "pm_sim_1" }), json(200, { id: "pi_sim_1", status: "succeeded", payment_method_types: ["card"] })]);
  await stripe(fetchImpl).payWithApplePay({ ...common, applePay: { paymentData: "" } });
  assert.equal(sent.length, 2, "no tokens call");
  assert.equal(sent[0]!.form!.get("card[token]"), "tok_visa");
  assert.equal(sent[1]!.form!.get("payment_method"), "pm_sim_1");
  const restricted = fakeStripe([json(200, { id: "pm_sim_2" }), json(200, { id: "pi_sim_2", status: "succeeded" })]);
  await stripe(restricted.fetchImpl, "rk_test_fakefake").payWithApplePay({ ...common, applePay: { paymentData: "" } });
  assert.equal(restricted.sent[0]!.form!.get("card[token]"), "tok_visa");
});

test("Stripe gateway: only test keys, and each call at most STRIPE_CALL_CAP_MS", () => {
  const other = fakeStripe([]);
  for (const key of [LIVE_LOOKING_KEY, "rk_live_fakefake", "", "pk_test_fakefake"]) {
    assert.throws(() => stripe(other.fetchImpl, key), /test keys only/);
  }
  assert.equal(other.sent.length, 0);
  assert.equal(new StripeHttpGateway({ secretKey: TEST_KEY, timeoutMs: 60_000 }).callTimeoutMs, STRIPE_CALL_CAP_MS);
  assert.equal(new StripeHttpGateway({ secretKey: TEST_KEY, timeoutMs: 1_000 }).callTimeoutMs, 1_000);
  // Three calls in a row (token, method, payment) end before the phone's 20-second wait.
  assert.ok(3 * STRIPE_CALL_CAP_MS < 20_000);
});

test("Stripe Apple Pay: a failed PaymentMethod call is not_sent, even a timeout, and no PaymentIntent follows", async () => {
  for (const answer of [json(400, { error: { type: "invalid_request_error", message: "planted" } }), json(500, {}), json(200, { id: "card_wrong" }), () => Promise.reject(Object.assign(new Error("t"), { name: "TimeoutError" }))]) {
    const { sent, fetchImpl } = fakeStripe([json(200, { id: "tok_ok" }), answer]);
    await assert.rejects(stripe(fetchImpl).payWithApplePay({ ...common, applePay: APPLE_PAY }), (e: unknown) => e instanceof GatewayError && e.kind === "not_sent" && !e.message.includes("planted"));
    assert.equal(sent.length, 2, "no PaymentIntent after a failed PaymentMethod");
  }
});

test("Stripe Apple Pay: a failed tokens call is not_sent, even a timeout (nothing can be charged)", async () => {
  for (const answer of [json(400, { error: { type: "invalid_request_error", code: "token_invalid", message: "planted Stripe message" } }), json(500, {}), () => Promise.reject(Object.assign(new Error("t"), { name: "TimeoutError" }))]) {
    const { sent, fetchImpl } = fakeStripe([answer]);
    await assert.rejects(stripe(fetchImpl).payWithApplePay({ ...common, applePay: APPLE_PAY }), (e: unknown) => e instanceof GatewayError && e.kind === "not_sent" && !e.message.includes("planted"));
    assert.equal(sent.length, 1, "no PaymentIntent after a failed token");
  }
});

test("Stripe BLIK: a confirmed PaymentIntent with the code in payment_method_options", async () => {
  const { sent, fetchImpl } = fakeStripe([json(200, { id: "pi_blik_1", status: "requires_action", payment_method_types: ["blik"], next_action: { type: "blik_authorize" } })]);
  const result = await stripe(fetchImpl).payWithBlik({ ...common, blikCode: "123456", idempotencyKey: `purchase:${PID}:blik` });
  assert.deepEqual(result, { paymentId: "pi_blik_1", state: "waiting_for_bank" });
  assert.equal(sent[0]!.headers["idempotency-key"], `purchase:${PID}:blik`);
  assert.deepEqual(Object.fromEntries(sent[0]!.form!.entries()), {
    amount: "5600",
    currency: "pln",
    confirm: "true",
    "payment_method_types[]": "blik",
    "payment_method_data[type]": "blik",
    "payment_method_options[blik][code]": "123456",
    description: "Kino Muranów: 2 tickets, Friday 19:30",
    "metadata[purchase_id]": PID,
  });
});

test("Stripe status mapping", async () => {
  const cases: [Record<string, unknown>, GatewayPayment | "unknown"][] = [
    [{ id: "pi_a", status: "succeeded" }, { paymentId: "pi_a", state: "succeeded" }],
    [{ id: "pi_b", status: "processing" }, { paymentId: "pi_b", state: "processing" }],
    [{ id: "pi_c", status: "requires_action", payment_method_types: ["blik"] }, { paymentId: "pi_c", state: "waiting_for_bank" }],
    [{ id: "pi_d", status: "requires_action", payment_method_types: ["card"], next_action: { type: "blik_authorize" } }, { paymentId: "pi_d", state: "waiting_for_bank" }],
    [{ id: "pi_e", status: "requires_action", payment_method_types: ["card"], next_action: { type: "use_stripe_sdk" } }, { paymentId: "pi_e", state: "needs_card_check" }],
    [{ id: "pi_f", status: "requires_payment_method", last_payment_error: { decline_code: "insufficient_funds", message: "planted" } }, { paymentId: "pi_f", state: "declined", declineCode: "insufficient_funds" }],
    [{ id: "pi_g", status: "requires_payment_method", last_payment_error: { code: "Not A Code!" } }, { paymentId: "pi_g", state: "declined" }],
    [{ id: "pi_h", status: "canceled" }, { paymentId: "pi_h", state: "canceled" }],
    [{ id: "pi_i", status: "requires_capture" }, "unknown"],
    [{ id: "pi_j", status: "requires_confirmation" }, "unknown"],
    [{ status: "succeeded" }, "unknown"],
  ];
  for (const [body, want] of cases) {
    const { fetchImpl } = fakeStripe([json(200, body)]);
    const call = stripe(fetchImpl).retrieve("pi_lookup_1");
    if (want === "unknown") await assert.rejects(call, (e: unknown) => e instanceof GatewayError && e.kind === "unknown", JSON.stringify(body));
    else assert.deepEqual(await call, want, JSON.stringify(body));
  }
});

test("Stripe error mapping: 402 rejected, 4xx not_sent, 5xx/abort/network/unreadable unknown", async () => {
  const blik = (fetchImpl: typeof fetch) => stripe(fetchImpl).payWithBlik({ ...common, blikCode: "123456" });
  const kind = async (answer: (req: Sent) => Response | Promise<Response>) => {
    const { fetchImpl } = fakeStripe([answer]);
    try {
      await blik(fetchImpl);
      return "resolved";
    } catch (e) {
      assert.ok(e instanceof GatewayError);
      assert.ok(!e.message.includes("planted"), "no Stripe message in the error");
      return e.kind;
    }
  };
  assert.equal(await kind(json(402, { error: { type: "card_error", code: "card_declined", decline_code: "generic_decline", message: "planted", payment_intent: { id: "pi_x", status: "requires_payment_method" } } })), "rejected");
  assert.equal(await kind(json(400, { error: { type: "invalid_request_error", code: "parameter_invalid", message: "planted" } })), "not_sent");
  assert.equal(await kind(json(401, { error: { type: "invalid_request_error", message: "planted" } })), "not_sent");
  assert.equal(await kind(json(429, { error: { type: "rate_limit_error" } })), "not_sent");
  assert.equal(await kind(json(400, { error: { type: "idempotency_error", message: "planted" } })), "unknown");
  assert.equal(await kind(json(409, { error: { type: "invalid_request_error", code: "idempotency_key_in_use" } })), "unknown");
  assert.equal(await kind(json(500, { error: { type: "api_error" } })), "unknown");
  assert.equal(await kind(json(503, {})), "unknown");
  assert.equal(await kind(() => new Response("<html>not json</html>", { status: 200 })), "unknown");
  assert.equal(await kind(() => Promise.reject(Object.assign(new Error("aborted"), { name: "AbortError" }))), "unknown");
  assert.equal(await kind(() => Promise.reject(Object.assign(new Error("timeout"), { name: "TimeoutError" }))), "unknown");
  assert.equal(await kind(() => Promise.reject(Object.assign(new TypeError("fetch failed"), { cause: { code: "ECONNRESET" } }))), "unknown");
  assert.equal(await kind(() => Promise.reject(Object.assign(new TypeError("fetch failed"), { cause: { code: "ENOTFOUND" } }))), "not_sent");
  // 402 carries the PaymentIntent id and a short decline code only.
  const { fetchImpl } = fakeStripe([json(402, { error: { decline_code: "insufficient_funds", payment_intent: { id: "pi_402" }, message: "planted" } })]);
  await assert.rejects(blik(fetchImpl), (e: unknown) => e instanceof GatewayError && e.detail.paymentId === "pi_402" && e.detail.declineCode === "insufficient_funds");
});

test("Stripe timeout: a real AbortSignal timeout is unknown", async () => {
  const fetchImpl = ((_: unknown, init?: RequestInit) =>
    new Promise((_, reject) => {
      init?.signal?.addEventListener("abort", () => reject(init.signal!.reason));
    })) as typeof fetch;
  const gateway = new StripeHttpGateway({ secretKey: TEST_KEY, timeoutMs: 30 }, fetchImpl);
  // AbortSignal.timeout's timer doesn't hold the event loop open (a running server does); this one stands in.
  const keepAlive = setInterval(() => {}, 1_000);
  try {
    await assert.rejects(gateway.payWithBlik({ ...common, blikCode: "123456" }), (e: unknown) => e instanceof GatewayError && e.kind === "unknown");
  } finally {
    clearInterval(keepAlive);
  }
});

test("Stripe retrieve, search and cancel requests", async () => {
  const { sent, fetchImpl } = fakeStripe([
    json(200, { id: "pi_r1", status: "succeeded" }),
    json(200, { object: "search_result", data: [{ id: "pi_s1", status: "processing", metadata: { purchase_id: PID } }] }),
    json(200, { object: "search_result", data: [] }),
    json(200, { id: "pi_c1", status: "canceled" }),
  ]);
  const g = stripe(fetchImpl);
  assert.deepEqual(await g.retrieve("pi_r1"), { paymentId: "pi_r1", state: "succeeded" });
  assert.deepEqual(await g.findByPurchase(PID), { paymentId: "pi_s1", state: "processing" });
  assert.equal(await g.findByPurchase(PID), null);
  assert.deepEqual(await g.cancel("pi_c1"), { paymentId: "pi_c1", state: "canceled" });
  assert.equal(sent[0]!.url, "https://api.stripe.com/v1/payment_intents/pi_r1");
  assert.equal(sent[0]!.method, "GET");
  assert.equal(sent[0]!.headers["idempotency-key"], undefined);
  const search = new URL(sent[1]!.url);
  assert.equal(search.pathname, "/v1/payment_intents/search");
  assert.equal(search.searchParams.get("query"), `metadata['purchase_id']:'${PID}'`);
  assert.equal(sent[3]!.url, "https://api.stripe.com/v1/payment_intents/pi_c1/cancel");
  assert.equal(sent[3]!.method, "POST");
  // Ids that aren't Stripe's or a UUID never reach the URL.
  const none = fakeStripe([]);
  await assert.rejects(stripe(none.fetchImpl).retrieve("pi_x/../../v1/charges"), GatewayError);
  await assert.rejects(stripe(none.fetchImpl).findByPurchase("x' OR status:'succeeded"), GatewayError);
  await assert.rejects(stripe(none.fetchImpl).cancel("ch_123"), GatewayError);
  assert.equal(none.sent.length, 0);
});

test("the service over the Stripe adapter: unknown on timeout, then search finds it paid", async () => {
  let mode: "timeout" | "search-empty" | "search-found" = "timeout";
  const fetchImpl = (async (input: string | URL | Request) => {
    const url = String(input);
    if (url.endsWith("/v1/tokens")) return new Response(JSON.stringify({ id: "tok_svc" }), { status: 200 });
    if (url.endsWith("/v1/payment_methods")) return new Response(JSON.stringify({ id: "pm_svc" }), { status: 200 });
    if (url.endsWith("/v1/payment_intents")) throw Object.assign(new Error("t"), { name: "TimeoutError" });
    if (url.includes("/search")) {
      const data = mode === "search-found" ? [{ id: "pi_svc", status: "succeeded", metadata: { purchase_id: new URL(url).searchParams.get("query")!.split("'")[3] } }] : [];
      return new Response(JSON.stringify({ data }), { status: 200 });
    }
    throw new Error(`unexpected ${url}`);
  }) as typeof fetch;
  rig = await start({ mode: "test", gateway: new StripeHttpGateway({ secretKey: TEST_KEY, timeoutMs: 500 }, fetchImpl) });
  const p = await prepared(rig);
  assert.equal(p.mode, "test");
  assert.equal((await payApple(rig, p)).body.purchase.status, "outcome_unknown");
  mode = "search-empty";
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "outcome_unknown");
  mode = "search-found";
  assert.equal((await status(rig, p.purchase.id)).body.purchase.status, "paid");
  assert.equal(rig.gateway!.count("apple_pay"), 1);
});
