/**
 * The payment provider boundary (ADR-530). The service only ever sees this normalized shape, never
 * a provider object, error message or token. Two implementations: `MockPaymentGateway` (demo mode,
 * nothing leaves the process) and `StripeHttpGateway` in ./stripe.ts (Stripe on test keys).
 */

export type GatewayState =
  /** The provider confirmed the money moved. The only state the service calls paid. */
  | "succeeded"
  /** Accepted, the provider hasn't finished; ask again. */
  | "processing"
  /** BLIK: the user approves in the bank app. */
  | "waiting_for_bank"
  /** A card payment asked for 3-D Secure, which Doddy can't show yet. Nothing charged. */
  | "needs_card_check"
  /** Declined. Nothing charged. */
  | "declined"
  | "canceled";

export interface GatewayPayment {
  /** The provider's own id for this payment (e.g. a Stripe PaymentIntent id), when there is one. */
  paymentId: string | null;
  state: GatewayState;
  /** Short `[a-z_]` code only; never the provider's message. */
  declineCode?: string;
}

/**
 * - `not_sent`: provably never reached the provider, or it refused before charging (an invalid request).
 * - `unknown`: the request may have reached the provider (timeout, connection lost after sending, 5xx,
 *   an answer Doddy couldn't read). Never treated as paid or as failed, and never retried by itself.
 * - `rejected`: the provider declined the card or BLIK code. Nothing charged.
 */
export type GatewayErrorKind = "not_sent" | "unknown" | "rejected";

export class GatewayError extends Error {
  constructor(
    readonly kind: GatewayErrorKind,
    readonly detail: { paymentId?: string; declineCode?: string } = {},
  ) {
    super(kind); // content-free: the kind only
    this.name = "GatewayError";
  }
}

export interface ApplePayPassThrough {
  /** `PKPaymentToken.paymentData` as a UTF-8 string. Empty only in the simulator. */
  paymentData: string;
  network?: string | undefined;
  instrumentName?: string | undefined;
  transactionId?: string | undefined;
}

interface PaymentCommon {
  purchaseId: string;
  amountMinor: number;
  currency: "PLN";
  /** What the user's bank or card statement shows. */
  description: string;
  /** Same key for the same purchase and method: a resend can never create a second payment. */
  idempotencyKey: string;
}

export interface PaymentGateway {
  readonly mode: "mock" | "test";
  payWithApplePay(input: PaymentCommon & { applePay: ApplePayPassThrough }): Promise<GatewayPayment>;
  payWithBlik(input: PaymentCommon & { blikCode: string }): Promise<GatewayPayment>;
  retrieve(paymentId: string): Promise<GatewayPayment>;
  /** The payment made for this purchase, or null when the provider lists none (which proves nothing). */
  findByPurchase(purchaseId: string): Promise<GatewayPayment | null>;
  cancel(paymentId: string): Promise<GatewayPayment>;
}

// ------------------------------------------------------------------ mock

interface MockPayment {
  id: string;
  purchaseId: string;
  state: GatewayState;
  declineCode?: string;
  createdAt: number;
}

/** BLIK code the demo declines. Any other six digits wait for "the bank" and then succeed. */
export const MOCK_DECLINED_BLIK_CODE = "000000";
/** How long the demo's bank takes to approve a BLIK payment. */
export const MOCK_BLIK_APPROVAL_MS = 3_000;

/**
 * Demo payments (DODDY_MODE=mock). Deterministic and offline: Apple Pay always succeeds, BLIK
 * code 000000 is declined, any other code waits for the bank and succeeds once 3 seconds have
 * passed on the injected clock. Like Stripe, the same idempotency key gives back the same payment.
 */
export class MockPaymentGateway implements PaymentGateway {
  readonly mode = "mock" as const;
  /** What was asked, for tests. Never the token or the code. */
  readonly calls: string[] = [];
  private readonly payments = new Map<string, MockPayment>();
  private readonly byKey = new Map<string, string>();
  private n = 0;

  constructor(private readonly now: () => number = Date.now) {}

  async payWithApplePay(input: PaymentCommon & { applePay: ApplePayPassThrough }): Promise<GatewayPayment> {
    this.calls.push("apple_pay");
    return this.create(input, "succeeded");
  }

  async payWithBlik(input: PaymentCommon & { blikCode: string }): Promise<GatewayPayment> {
    this.calls.push("blik");
    return input.blikCode === MOCK_DECLINED_BLIK_CODE ? this.create(input, "declined", "generic_decline") : this.create(input, "waiting_for_bank");
  }

  async retrieve(paymentId: string): Promise<GatewayPayment> {
    this.calls.push("retrieve");
    const payment = this.payments.get(paymentId);
    if (!payment) throw new GatewayError("not_sent");
    return this.view(this.advance(payment));
  }

  async findByPurchase(purchaseId: string): Promise<GatewayPayment | null> {
    this.calls.push("find");
    const found = [...this.payments.values()].filter((p) => p.purchaseId === purchaseId).at(-1);
    return found ? this.view(this.advance(found)) : null;
  }

  async cancel(paymentId: string): Promise<GatewayPayment> {
    this.calls.push("cancel");
    const payment = this.payments.get(paymentId);
    if (!payment) throw new GatewayError("not_sent");
    this.advance(payment);
    if (payment.state === "waiting_for_bank" || payment.state === "processing" || payment.state === "needs_card_check") payment.state = "canceled";
    return this.view(payment);
  }

  private create(input: PaymentCommon, state: GatewayState, declineCode?: string): GatewayPayment {
    const existing = this.byKey.get(input.idempotencyKey);
    if (existing) return this.view(this.advance(this.payments.get(existing)!));
    const payment: MockPayment = { id: `mock_pi_${++this.n}`, purchaseId: input.purchaseId, state, createdAt: this.now(), ...(declineCode ? { declineCode } : {}) };
    this.payments.set(payment.id, payment);
    this.byKey.set(input.idempotencyKey, payment.id);
    return this.view(payment);
  }

  private advance(payment: MockPayment): MockPayment {
    if (payment.state === "waiting_for_bank" && this.now() - payment.createdAt >= MOCK_BLIK_APPROVAL_MS) payment.state = "succeeded";
    return payment;
  }

  private view(payment: MockPayment): GatewayPayment {
    return { paymentId: payment.id, state: payment.state, ...(payment.declineCode ? { declineCode: payment.declineCode } : {}) };
  }
}
