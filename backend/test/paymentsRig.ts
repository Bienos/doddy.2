import { once } from "node:events";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { DevSessionVerifier } from "../src/auth.js";
import { defaultRegistry } from "../src/capabilities.js";
import { testLimits } from "../src/config.js";
import { createHandler } from "../src/http.js";
import { MockPaymentSeller } from "../src/payments/mockSeller.js";
import { type PaymentScenario, PaymentsService, type PaymentsPolicy } from "../src/payments/service.js";
import type { SellerHttp } from "../src/payments/net.js";
import { MockPaymentWallet, type PaymentWallet } from "../src/payments/wallet.js";
import { MockCalendarProvider } from "../src/providers/mock.js";
import { ConnectedAppsService } from "../src/service.js";
import { Store } from "../src/store.js";
import { MockToolsProvider } from "../src/tools/mock.js";
import { CloudToolsService } from "../src/tools/service.js";
import { Clock, USER_A } from "./helpers.js";

/** A running server with the mock wallet and the offline demo seller, for the payment tests. */
export interface PayRig {
  call(method: string, path: string, o?: { token?: string | null; body?: unknown; scenario?: PaymentScenario | string }): Promise<{ status: number; body: any; text: string }>;
  seller: SellerHttp & { requests?: { url: string; headers: Record<string, string> }[]; scenario?: string };
  wallet: PaymentWallet | null;
  payments: PaymentsService;
  store: Store;
  logs: string[];
  clock: Clock;
  close(): Promise<void>;
}

export const SHOP = "https://demo-shop.example/articles/42";
export const NONCE = `0x${"7e".repeat(32)}`;

export const defaultPolicy = (over: Partial<PaymentsPolicy> = {}): PaymentsPolicy => ({
  network: "base-sepolia",
  maxPerPayment: 250_000,
  userDaily: 1_000_000,
  serviceDaily: 5_000_000,
  allowedHosts: [],
  ...over,
});

export async function startPay(
  o: { policy?: Partial<PaymentsPolicy>; limits?: Parameters<typeof testLimits>[0]; wallet?: PaymentWallet | null; seller?: SellerHttp } = {},
): Promise<PayRig> {
  const store = new Store(":memory:");
  const clock = new Clock(Date.parse("2026-10-12T10:00:00Z"));
  const limits = testLimits(o.limits);
  const logs: string[] = [];
  const wallet = o.wallet === undefined ? new MockPaymentWallet() : o.wallet;
  const seller = o.seller ?? new MockPaymentSeller("base-sepolia");
  const payments = new PaymentsService({ store, mode: "mock", wallet, http: seller, policy: defaultPolicy(o.policy), limits, now: clock.now, nonce: () => NONCE });
  const common = { store, limits, publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return", now: clock.now, sleep: async () => {} };
  const tools = new CloudToolsService({ ...common, provider: new MockToolsProvider(), completionMode: "mock" });
  const service = new ConnectedAppsService({ ...common, provider: new MockCalendarProvider(), registry: defaultRegistry(), completionMode: "mock" });
  const handler = createHandler({
    service,
    tools,
    payments,
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
    seller: seller as PayRig["seller"],
    wallet,
    payments,
    store,
    logs,
    clock,
    async close() {
      if (closed) return;
      closed = true;
      server.close();
      store.close();
    },
    async call(method, path, c = {}) {
      const headers: Record<string, string> = {};
      const token = c.token === undefined ? USER_A : c.token;
      if (token !== null) headers.authorization = `Bearer ${token}`;
      if (c.scenario) headers["x-doddy-payments-scenario"] = c.scenario;
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
      return { status: res.status, body: parsed, text };
    },
  };
}

type Call = Parameters<PayRig["call"]>[2];
export const enable = (r: PayRig, token = USER_A) => r.call("PUT", "/v1/payments/switch", { token, body: { enabled: true } });
export const prepare = (r: PayRig, url = SHOP, o: Call = {}) => r.call("POST", "/v1/payments/prepare", { ...o, body: { url } });
export const pay = (r: PayRig, approvalId: string, url = SHOP, o: Call = {}) => r.call("POST", "/v1/payments/pay", { ...o, body: { url, approvalId } });
export const status = (r: PayRig, token = USER_A) => r.call("GET", "/v1/payments", { token });

/** Payment-signature headers the seller saw, decoded. */
export function paidRequests(r: PayRig) {
  return (r.seller.requests ?? [])
    .filter((q) => q.headers["payment-signature"] !== undefined)
    .map((q) => JSON.parse(Buffer.from(q.headers["payment-signature"]!, "base64").toString("utf8")));
}
