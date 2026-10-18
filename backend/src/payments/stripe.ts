import {
  type ApplePayPassThrough,
  GatewayError,
  type GatewayPayment,
  type PaymentGateway,
} from "./gateway.js";

/**
 * Stripe over HTTPS (ADR-490), with Doddy's own secret key on Doddy's server. The ONLY file that
 * may name Stripe's API host (scripts/check_forbidden_capabilities.sh). No Stripe SDK: plain
 * `fetch`, form-encoded bodies with Stripe's bracket notation, the key in the Authorization header.
 *
 * Nothing here logs. Request bodies, the Apple Pay token, the BLIK code and Stripe's error
 * messages never leave this file; errors become a `GatewayError` kind and at most a short
 * `[a-z_]` decline code.
 *
 * Stripe-Version: deliberately NOT sent, so the account's default API version applies. Nothing
 * here has run against Stripe, so pinning a version string would be a guess (Stripe's BLIK guide
 * read on 2026-10-18 names `2026-09-30.endive`; that was not confirmed as an account default). What
 * this file reads has been stable across API versions since 2019-02-11: PaymentIntent `status`
 * values, `payment_method_types`, `next_action.type`, `last_payment_error.decline_code|code`. A
 * status it doesn't know (e.g. an old account's `requires_source`) is `unknown`, never paid. Decline
 * codes differ by version (older versions say `generic_decline` for BLIK failures); they are
 * informational only and never change what the user is told was charged.
 *
 * Not verified against Stripe (no network or keys in development): that `/v1/tokens` accepts
 * `pk_token…` with a secret key (Stripe's iOS SDK sends the same parameters with a publishable
 * key, StripeApplePay Token+API.swift), and that `payment_method_data[card][token]` is accepted.
 */
const STRIPE_API = "https://api.stripe.com";

/** Stripe's test card token, used only when the simulator's Apple Pay returns no token and the key is a test key. */
export const STRIPE_SIMULATOR_TOKEN = "tok_visa";

const TEST_KEY = /^(sk|rk)_test_/;
const PAYMENT_ID = /^pi_[A-Za-z0-9_]{1,255}$/;
const TOKEN_ID = /^tok_[A-Za-z0-9_]{1,255}$/;
const PURCHASE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SHORT_CODE = /^[a-z_]{1,64}$/;
/** Errors from `fetch` that prove the connection was never made, so nothing reached Stripe. */
const NEVER_CONNECTED = new Set(["ENOTFOUND", "EAI_AGAIN", "ECONNREFUSED", "ERR_INVALID_URL"]);

export interface StripeSettings {
  secretKey: string;
  timeoutMs: number;
}

type Params = [string, string][];

interface StripeAnswer {
  status: number;
  body: Record<string, unknown> | null;
}

export class StripeHttpGateway implements PaymentGateway {
  readonly mode = "test" as const;

  constructor(
    private readonly settings: StripeSettings,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  async payWithApplePay(input: {
    purchaseId: string;
    amountMinor: number;
    currency: "PLN";
    description: string;
    applePay: ApplePayPassThrough;
    idempotencyKey: string;
  }): Promise<GatewayPayment> {
    const token = await this.cardToken(input.applePay, input.idempotencyKey);
    return this.createPaymentIntent(input, [
      ["payment_method_types[]", "card"],
      ["payment_method_data[type]", "card"],
      ["payment_method_data[card][token]", token],
    ]);
  }

  async payWithBlik(input: {
    purchaseId: string;
    amountMinor: number;
    currency: "PLN";
    description: string;
    blikCode: string;
    idempotencyKey: string;
  }): Promise<GatewayPayment> {
    if (!/^\d{6}$/.test(input.blikCode)) throw new GatewayError("not_sent");
    return this.createPaymentIntent(input, [
      ["payment_method_types[]", "blik"],
      ["payment_method_data[type]", "blik"],
      ["payment_method_options[blik][code]", input.blikCode],
    ]);
  }

  async retrieve(paymentId: string): Promise<GatewayPayment> {
    if (!PAYMENT_ID.test(paymentId)) throw new GatewayError("not_sent");
    const answer = await this.request("GET", `/v1/payment_intents/${paymentId}`);
    return this.paymentIntent(this.ok(answer));
  }

  async findByPurchase(purchaseId: string): Promise<GatewayPayment | null> {
    if (!PURCHASE_ID.test(purchaseId)) throw new GatewayError("not_sent");
    // Validated UUID: nothing from a request can change the query. Stripe's search can lag writes
    // by up to a minute, so "none listed" proves nothing; the caller keeps "outcome unknown".
    const query = `metadata['purchase_id']:'${purchaseId}'`;
    const answer = await this.request("GET", `/v1/payment_intents/search?query=${encodeURIComponent(query)}`);
    const data = this.ok(answer).data;
    if (!Array.isArray(data)) throw new GatewayError("unknown");
    const match = data.find((item) => {
      const metadata = record(record(item)?.metadata);
      return metadata?.purchase_id === purchaseId;
    });
    return match === undefined ? null : this.paymentIntent(record(match));
  }

  async cancel(paymentId: string): Promise<GatewayPayment> {
    if (!PAYMENT_ID.test(paymentId)) throw new GatewayError("not_sent");
    const answer = await this.request("POST", `/v1/payment_intents/${paymentId}/cancel`, []);
    return this.paymentIntent(this.ok(answer));
  }

  // ---------------------------------------------------------------- internals

  /**
   * A card token from the Apple Pay token. Nothing is charged by this call, so any failure here,
   * a timeout included, is `not_sent`.
   */
  private async cardToken(applePay: ApplePayPassThrough, idempotencyKey: string): Promise<string> {
    if (applePay.paymentData === "") {
      // The simulator's Apple Pay sheet returns an empty token. Only a test key may stand in a test card.
      if (TEST_KEY.test(this.settings.secretKey)) return STRIPE_SIMULATOR_TOKEN;
      throw new GatewayError("not_sent");
    }
    const params: Params = [["pk_token", applePay.paymentData]];
    if (applePay.instrumentName) params.push(["pk_token_instrument_name", applePay.instrumentName]);
    if (applePay.network) params.push(["pk_token_payment_network", applePay.network]);
    if (applePay.transactionId) params.push(["pk_token_transaction_id", applePay.transactionId]);
    let answer: StripeAnswer;
    try {
      answer = await this.request("POST", "/v1/tokens", params, `${idempotencyKey}:token`);
    } catch {
      throw new GatewayError("not_sent");
    }
    const id = answer.status === 200 ? answer.body?.id : undefined;
    if (typeof id !== "string" || !TOKEN_ID.test(id)) throw new GatewayError("not_sent");
    return id;
  }

  private async createPaymentIntent(
    input: { purchaseId: string; amountMinor: number; description: string; idempotencyKey: string },
    method: Params,
  ): Promise<GatewayPayment> {
    if (!PURCHASE_ID.test(input.purchaseId) || !Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0) {
      throw new GatewayError("not_sent");
    }
    const params: Params = [
      ["amount", String(input.amountMinor)],
      ["currency", "pln"],
      ["confirm", "true"],
      ...method,
      ["description", input.description],
      ["metadata[purchase_id]", input.purchaseId],
    ];
    const answer = await this.request("POST", "/v1/payment_intents", params, input.idempotencyKey);
    return this.paymentIntent(this.ok(answer));
  }

  /**
   * One HTTPS call. A request that may have reached Stripe and got no readable answer is
   * `unknown`; one that provably never connected is `not_sent`.
   */
  private async request(method: "GET" | "POST", path: string, params?: Params, idempotencyKey?: string): Promise<StripeAnswer> {
    const headers: Record<string, string> = { authorization: `Bearer ${this.settings.secretKey}`, accept: "application/json" };
    let body: string | undefined;
    if (method === "POST") {
      headers["content-type"] = "application/x-www-form-urlencoded";
      body = new URLSearchParams(params ?? []).toString();
      if (idempotencyKey !== undefined) headers["idempotency-key"] = idempotencyKey;
    }
    let response: Response;
    try {
      response = await this.fetchImpl(`${STRIPE_API}${path}`, {
        method,
        headers,
        ...(body !== undefined ? { body } : {}),
        redirect: "error",
        signal: AbortSignal.timeout(this.settings.timeoutMs),
      });
    } catch (error) {
      throw new GatewayError(neverConnected(error) ? "not_sent" : "unknown");
    }
    let parsed: unknown = null;
    try {
      parsed = await response.json();
    } catch {
      parsed = null;
    }
    return { status: response.status, body: record(parsed) };
  }

  /**
   * HTTP status to a kind. 402: declined at Stripe. Other 4xx: Stripe refused before charging,
   * except the two idempotency answers, which mean an earlier request with the same key exists and
   * may have gone through (409: still running; 400 `idempotency_error`: sent with other
   * parameters): those are `unknown`. 5xx or an unreadable success: may have happened.
   */
  private ok(answer: StripeAnswer): Record<string, unknown> {
    const { status, body } = answer;
    if (status >= 200 && status < 300) {
      if (!body) throw new GatewayError("unknown");
      return body;
    }
    const error = record(body?.error);
    const paymentId = record(error?.payment_intent)?.id;
    const detail = {
      ...(typeof paymentId === "string" && PAYMENT_ID.test(paymentId) ? { paymentId } : {}),
      ...shortCode(error?.decline_code ?? error?.code),
    };
    if (status === 402) throw new GatewayError("rejected", detail);
    if (status === 409 || error?.type === "idempotency_error") throw new GatewayError("unknown", detail);
    if (status >= 400 && status < 500) throw new GatewayError("not_sent", detail);
    throw new GatewayError("unknown", detail);
  }

  /** Stripe's PaymentIntent to Doddy's normalized state. Anything unexpected is `unknown`. */
  private paymentIntent(pi: Record<string, unknown> | null): GatewayPayment {
    const id = pi?.id;
    if (!pi || typeof id !== "string" || !PAYMENT_ID.test(id)) throw new GatewayError("unknown");
    switch (pi.status) {
      case "succeeded":
        return { paymentId: id, state: "succeeded" };
      case "processing":
        return { paymentId: id, state: "processing" };
      case "requires_action": {
        const types = Array.isArray(pi.payment_method_types) ? pi.payment_method_types : [];
        const blik = types.includes("blik") || record(pi.next_action)?.type === "blik_authorize";
        return { paymentId: id, state: blik ? "waiting_for_bank" : "needs_card_check" };
      }
      case "requires_payment_method": {
        const error = record(pi.last_payment_error);
        return { paymentId: id, state: "declined", ...shortCode(error?.decline_code ?? error?.code) };
      }
      case "canceled":
        return { paymentId: id, state: "canceled" };
      default:
        throw new GatewayError("unknown", { paymentId: id });
    }
  }
}

function record(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function shortCode(value: unknown): { declineCode?: string } {
  return typeof value === "string" && SHORT_CODE.test(value) ? { declineCode: value } : {};
}

function neverConnected(error: unknown): boolean {
  if (!(error instanceof Error) || error.name === "AbortError" || error.name === "TimeoutError") return false;
  const code = (error as { cause?: { code?: unknown } }).cause?.code;
  return typeof code === "string" && NEVER_CONNECTED.has(code);
}
