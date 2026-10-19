import { randomUUID } from "node:crypto";
import type { Limits } from "../config.js";
import { AppError } from "../errors.js";
import { argumentDigest } from "../policy.js";
import type { PurchaseRow, PurchaseStatusValue, Store } from "../store.js";
import {
  checkoutTarget,
  formatPln,
  HandoffRequestSchema,
  type HandoffResult,
  type PaymentsMode,
  PayRequestSchema,
  PrepareRequestSchema,
  type PrepareResult,
  PurchaseIdRequestSchema,
  type PurchaseMethod,
  type PurchaseResult,
  type PurchasesList,
  type PurchaseView,
  ReportRequestSchema,
} from "./contracts.js";
import { GatewayError, type GatewayPayment, type PaymentGateway } from "./gateway.js";

/**
 * Purchases (ADR-530). The agent only proposes; this service decides. Order for a native payment:
 * signed-in owner -> strict body -> the user's own purchase, still awaiting the tap -> not expired
 * -> payments set up -> daily cap -> the single-use approval, bound to the STORED purchase, used up
 * in the same transaction that marks it `paying` -> one gateway call -> normalized answer -> status.
 *
 * - "paid" only when the gateway confirmed it. `outcome_unknown` is never paid and never retried:
 *   a later status check only reads.
 * - Never stored or logged: the Apple Pay token, the BLIK code, card details, provider messages.
 * - The approval's outcome (ADR-322) is recorded once the payment settles (paid: succeeded;
 *   failed or cancelled: failed). While paying, waiting for the bank or unsure it stays
 *   unfinished, which the store already reads as "may or may not have gone through".
 */

export const PURCHASE_CAPABILITY = { native: "purchase.native", checkout: "purchase.checkout" } as const;
export const PURCHASE_APPROVAL_TTL_SECONDS = 300;
/**
 * The name on the Apple Pay sheet: who is really paid. The same in mock and test mode (the
 * contract fixture shows it in mock mode), so the card never names the shop as the payee.
 */
export const NATIVE_PAYEE = "Doddy (test)";
const NATIVE_METHODS: PurchaseMethod[] = ["apple_pay", "blik"];
const LIST_DAYS = 90;
const LIST_LIMIT = 50;
const DAY_MS = 86_400_000;

/** What counts against the daily cap (contract: paid, paying, waiting for the bank, unsure, handed off, reported paid). */
const COMMITTED: readonly PurchaseStatusValue[] = ["paid", "paying", "waiting_for_bank", "outcome_unknown", "handed_off", "user_reported_paid"];
/** A pay for a purchase in one of these answers with where it is, and charges nothing. */
const ALREADY_SENT: ReadonlySet<PurchaseStatusValue> = new Set(["paid", "paying", "waiting_for_bank", "outcome_unknown"]);
/** Worth reading again from the gateway. */
const UNSETTLED: ReadonlySet<PurchaseStatusValue> = new Set(["paying", "waiting_for_bank", "outcome_unknown"]);

/** Short fixed codes kept in `purchases.reason`, for the summary only. */
type Reason = "declined" | "not_sent" | "card_check" | "canceled" | "cancel_requested" | "user_reported_unpaid";

export interface PaymentsServiceDeps {
  store: Store;
  /** Null: native purchases answer "Payments aren't set up"; checkout still works. */
  gateway: PaymentGateway | null;
  mode: PaymentsMode;
  limits: Limits;
  /** DODDY_CHECKOUT_HOSTS. Empty: any valid https shop host. */
  checkoutHosts: readonly string[];
  now?: () => number;
}

export class PaymentsService {
  readonly mode: PaymentsMode;
  private readonly store: Store;
  private readonly gateway: PaymentGateway | null;
  private readonly limits: Limits;
  private readonly checkoutHosts: readonly string[];
  private readonly now: () => number;

  constructor(deps: PaymentsServiceDeps) {
    // Mock never stands in for Stripe, and Stripe never runs in the demo.
    if (deps.gateway && deps.gateway.mode !== deps.mode) throw new Error("payment gateway and payments mode must both be mock or both test");
    this.mode = deps.mode;
    this.store = deps.store;
    this.gateway = deps.gateway;
    this.limits = deps.limits;
    this.checkoutHosts = deps.checkoutHosts;
    this.now = deps.now ?? Date.now;
  }

  /** Whether native (Apple Pay, BLIK) purchases can be paid on this server. */
  get nativeConfigured(): boolean {
    return this.gateway !== null;
  }

  // ---------------------------------------------------------------- prepare

  /** Checks a proposal against the limits and keeps it with a single-use approval for exactly what the card shows. */
  async prepare(userId: string, body: unknown): Promise<PrepareResult> {
    const request = parse(PrepareRequestSchema, body);
    if (request.kind === "native" && !this.gateway) throw notSetUp();
    let checkoutUrl: string | null = null;
    let host: string | null = null;
    if (request.kind === "checkout") {
      const target = checkoutTarget(request.checkoutUrl!, this.checkoutHosts);
      if (!target.ok) throw new AppError("invalid_request", { message: target.message });
      checkoutUrl = target.url;
      host = target.host;
    }
    const now = this.now();
    const counter = { counter: `user:${userId}:purchases`, period: `day:${utcDay(now)}`, limit: this.limits.userDailyPurchases };
    if ((await this.store.usage(counter.counter, counter.period)) >= counter.limit) throw this.tooManyToday();
    if (request.amountMinor > this.limits.purchaseMaxMinor) {
      throw new AppError("capability_disabled", {
        message: `That's more than Doddy's limit of ${formatPln(this.limits.purchaseMaxMinor)} for one purchase. Nothing was paid.`,
      });
    }
    if (!(await this.withinDailyCap(userId, request.amountMinor, now))) throw this.overDailyCap();
    // Counted only when a purchase is really made, so a refused proposal costs the user nothing.
    if (!(await this.store.reserveUsage([counter], 1))) throw this.tooManyToday();

    const row = await this.store.createPurchase(
      {
        purchase_id: randomUUID(),
        user_id: userId,
        kind: request.kind,
        merchant_name: request.merchantName,
        description: request.description,
        amount_minor: request.amountMinor,
        currency: request.currency,
        checkout_url: checkoutUrl,
        status: "awaiting_tap",
        method: null,
        payment_id: null,
        reason: null,
        test_mode: request.kind === "native" ? 1 : 0,
        created_at: now,
        updated_at: now,
      },
      {
        capability: PURCHASE_CAPABILITY[request.kind],
        argsDigest: purchaseDigest({ kind: request.kind, merchant_name: request.merchantName, description: request.description, amount_minor: request.amountMinor, currency: request.currency, checkout_url: checkoutUrl }),
        ttlSeconds: PURCHASE_APPROVAL_TTL_SECONDS,
      },
    );
    return {
      mode: this.mode,
      purchase: this.view(row),
      approvalId: row.approval_id,
      expiresAt: iso(row.expires_at),
      methods: request.kind === "native" ? [...NATIVE_METHODS] : [],
      payee: request.kind === "native" ? NATIVE_PAYEE : host!,
    };
  }

  // ---------------------------------------------------------------- pay (native)

  async pay(userId: string, body: unknown): Promise<PurchaseResult> {
    const request = parse(PayRequestSchema, body);
    const row = await this.own(userId, request.purchaseId);
    if (row.kind !== "native") throw new AppError("invalid_request", { message: "This purchase opens the shop's own checkout; it isn't paid inside Doddy." });
    // Already sent with this approval (a repeated tap, or the phone lost the answer): say where it
    // is, charge nothing. The status re-read only reads.
    if (ALREADY_SENT.has(row.status)) {
      if (request.approvalId !== row.approval_id) throw freshConfirmation();
      return this.result(await this.refresh(row));
    }
    const now = this.now();
    if (row.status === "awaiting_tap" && now >= row.expires_at) {
      await this.expire(row, now);
      throw freshConfirmation();
    }
    if (row.status !== "awaiting_tap") throw freshConfirmation();
    const gateway = this.gateway;
    if (!gateway) throw notSetUp();

    // The approval is used up in the same transaction that marks the purchase `paying`, before any
    // money can move: a second request with it (a double tap, a replay) loses here and charges nothing.
    const used = await this.store.usePurchaseApproval(
      { approvalId: request.approvalId, userId, capability: PURCHASE_CAPABILITY.native, purchaseId: row.purchase_id, argsDigest: purchaseDigest(row), now },
      ["awaiting_tap"],
      { status: "paying", method: request.method },
      this.dailyCap(now),
    );
    if (used === "limit") throw this.overDailyCap();
    if (used === "refused") throw freshConfirmation();

    // Everything sent to the gateway comes from the stored purchase, never from this request.
    const common = {
      purchaseId: row.purchase_id,
      amountMinor: row.amount_minor,
      currency: "PLN" as const,
      description: `${row.merchant_name}: ${row.description}`,
      idempotencyKey: `purchase:${row.purchase_id}:${request.method}`,
    };
    let answer: GatewayPayment | GatewayError;
    try {
      answer =
        request.method === "apple_pay"
          ? await gateway.payWithApplePay({ ...common, applePay: request.applePay })
          : await gateway.payWithBlik({ ...common, blikCode: request.blikCode });
    } catch (error) {
      // Anything but a typed gateway answer happened mid-call: it may or may not have gone through.
      answer = error instanceof GatewayError ? error : new GatewayError("unknown");
    }
    const sent = (await this.store.getPurchase(userId, row.purchase_id)) ?? row;
    // A definite answer also replaces an "unsure" a status check wrote meanwhile.
    return this.result(await this.apply(sent, answer, ["paying", "outcome_unknown"]));
  }

  // ---------------------------------------------------------------- status / cancel

  /** Re-reads an unsettled native payment from the gateway. Never pays, never retries a payment. */
  async status(userId: string, body: unknown): Promise<PurchaseResult> {
    const request = parse(PurchaseIdRequestSchema, body);
    return this.result(await this.refresh(await this.own(userId, request.purchaseId)));
  }

  /** Before paying, or while BLIK waits for the bank. Anything else is answered as it is. */
  async cancel(userId: string, body: unknown): Promise<PurchaseResult> {
    const request = parse(PurchaseIdRequestSchema, body);
    const row = await this.own(userId, request.purchaseId);
    const now = this.now();
    if (row.status === "awaiting_tap") {
      await this.store.updatePurchase(userId, row.purchase_id, ["awaiting_tap"], { status: "cancelled", now });
      return this.result(await this.reload(row));
    }
    const gateway = this.gateway;
    if (row.status !== "waiting_for_bank" || row.kind !== "native" || !gateway) return this.result(row);

    // Remembered first, so a cancellation Stripe reports later reads as the user's own.
    await this.store.updatePurchase(userId, row.purchase_id, ["waiting_for_bank"], { status: "waiting_for_bank", now, reason: "cancel_requested" });
    let payment: GatewayPayment | null = null;
    try {
      const paymentId = row.payment_id ?? (await gateway.findByPurchase(row.purchase_id))?.paymentId ?? null;
      if (paymentId) {
        try {
          payment = await gateway.cancel(paymentId);
        } catch {
          payment = null; // e.g. it already succeeded and can't be cancelled: read it below
        }
        if (!payment || !SETTLED_STATES.has(payment.state)) payment = await gateway.retrieve(paymentId);
      }
    } catch {
      payment = null;
    }
    const current = await this.reload(row);
    if (!payment) return this.result(current);
    return this.result(await this.apply(current, payment, ["waiting_for_bank"]));
  }

  // ---------------------------------------------------------------- checkout

  /** Uses up the checkout's approval and returns the page to open. A repeat with the same approval answers the same. */
  async handoff(userId: string, body: unknown): Promise<HandoffResult> {
    const request = parse(HandoffRequestSchema, body);
    const row = await this.own(userId, request.purchaseId);
    if (row.kind !== "checkout" || !row.checkout_url) {
      throw new AppError("invalid_request", { message: "This purchase is paid inside Doddy; it has no checkout page." });
    }
    if (row.status === "handed_off") {
      if (request.approvalId !== row.approval_id) throw freshConfirmation();
      return this.handoffResult(row);
    }
    const now = this.now();
    if (row.status === "awaiting_tap" && now >= row.expires_at) {
      await this.expire(row, now);
      throw freshConfirmation();
    }
    if (row.status !== "awaiting_tap") throw freshConfirmation();
    const used = await this.store.usePurchaseApproval(
      { approvalId: request.approvalId, userId, capability: PURCHASE_CAPABILITY.checkout, purchaseId: row.purchase_id, argsDigest: purchaseDigest(row), now },
      ["awaiting_tap"],
      { status: "handed_off" },
      this.dailyCap(now),
    );
    if (used === "limit") throw this.overDailyCap();
    if (used === "refused") throw freshConfirmation();
    // What was approved (opening the page) happened. Whether the user paid there is theirs to say.
    await this.store.finishApproval(row.approval_id, "succeeded", null, now);
    return this.handoffResult(await this.reload(row));
  }

  /** After a hand-off: the user's own answer, recorded as theirs and never as Doddy's confirmation. */
  async report(userId: string, body: unknown): Promise<PurchaseResult> {
    const request = parse(ReportRequestSchema, body);
    const row = await this.own(userId, request.purchaseId);
    if (row.kind !== "checkout") throw new AppError("invalid_request", { message: "Doddy reads payments made inside Doddy itself; there's nothing to report." });
    const target: PurchaseStatusValue = request.paid ? "user_reported_paid" : "cancelled";
    const reason: Reason | null = request.paid ? null : "user_reported_unpaid";
    // The same answer again (the phone lost the reply) is answered the same.
    if (row.status === target && row.reason === reason) return this.result(row);
    if (row.status === "user_reported_paid" || (row.status === "cancelled" && row.reason === "user_reported_unpaid")) {
      throw new AppError("invalid_request", { message: "You already answered for this checkout." });
    }
    if (row.status !== "handed_off") throw new AppError("invalid_request", { message: "Doddy only asks about a checkout after it was opened." });
    await this.store.updatePurchase(userId, row.purchase_id, ["handed_off"], { status: target, now: this.now(), reason });
    return this.result(await this.reload(row));
  }

  // ---------------------------------------------------------------- list

  async list(userId: string): Promise<PurchasesList> {
    const now = this.now();
    const rows = await this.store.listPurchases(userId, now - LIST_DAYS * DAY_MS, LIST_LIMIT);
    const purchases: PurchaseView[] = [];
    for (const row of rows) purchases.push(this.view(await this.expireIfDue(row, now)));
    return { purchases };
  }

  // ---------------------------------------------------------------- internals

  private async own(userId: string, purchaseId: string): Promise<PurchaseRow> {
    const row = await this.store.getPurchase(userId, purchaseId);
    if (!row) throw new AppError("not_found");
    return row;
  }

  private async reload(row: PurchaseRow): Promise<PurchaseRow> {
    return (await this.store.getPurchase(row.user_id, row.purchase_id)) ?? row;
  }

  private async expire(row: PurchaseRow, now: number): Promise<PurchaseRow> {
    await this.store.updatePurchase(row.user_id, row.purchase_id, ["awaiting_tap"], { status: "expired", now });
    return this.reload(row);
  }

  private expireIfDue(row: PurchaseRow, now: number): Promise<PurchaseRow> {
    return row.status === "awaiting_tap" && now >= row.expires_at ? this.expire(row, now) : Promise.resolve(row);
  }

  /** Today's committed total (UTC day, both kinds) plus this amount stays within the daily cap. */
  private async withinDailyCap(userId: string, amountMinor: number, now: number): Promise<boolean> {
    const committed = await this.store.committedPurchaseMinor(userId, startOfUtcDay(now), COMMITTED);
    return committed + amountMinor <= this.limits.purchaseDailyMaxMinor;
  }

  /** The same cap, counted again inside the transaction that uses the approval. */
  private dailyCap(now: number) {
    return {
      since: startOfUtcDay(now),
      statuses: COMMITTED,
      allows: (purchase: PurchaseRow, committedMinor: number) => committedMinor + purchase.amount_minor <= this.limits.purchaseDailyMaxMinor,
    };
  }

  private overDailyCap(): AppError {
    return new AppError("capability_disabled", {
      message: `That would go over Doddy's limit of ${formatPln(this.limits.purchaseDailyMaxMinor)} a day. Nothing was paid.`,
    });
  }

  private tooManyToday(): AppError {
    return new AppError("quota_exceeded", {
      message: `Doddy's limit of ${this.limits.userDailyPurchases} purchases a day was reached. Try again tomorrow. Nothing was paid.`,
    });
  }

  /**
   * Reads an unsettled payment again: by the stored payment id, or by the purchase id when the
   * first answer never came. Any failure, or nothing listed, leaves the status as it was (an
   * "unsure" stays unsure). A `paying` with no answer long after the call must have ended (the
   * server stopped mid-call) becomes `outcome_unknown`.
   */
  private async refresh(row: PurchaseRow): Promise<PurchaseRow> {
    const now = this.now();
    row = await this.expireIfDue(row, now);
    const gateway = this.gateway;
    if (!UNSETTLED.has(row.status) || row.kind !== "native" || !gateway) return row;
    let payment: GatewayPayment | null;
    try {
      payment = row.payment_id ? await gateway.retrieve(row.payment_id) : await gateway.findByPurchase(row.purchase_id);
    } catch {
      return this.reload(row);
    }
    if (payment) return this.apply(await this.reload(row), payment, [row.status]);
    const stale = row.status === "paying" && row.payment_id === null && now - row.updated_at > 3 * this.limits.providerTimeoutMs;
    if (stale) await this.store.updatePurchase(row.user_id, row.purchase_id, ["paying"], { status: "outcome_unknown", now });
    return this.reload(row);
  }

  /**
   * The gateway's answer to a purchase status, written only if the purchase is still in one of
   * `from` (two requests can't both move it). A card that asks for 3-D Secure is cancelled
   * (best effort; it can't be charged without that check anyway) and reported as not charged.
   */
  private async apply(row: PurchaseRow, answer: GatewayPayment | GatewayError, from: readonly PurchaseStatusValue[]): Promise<PurchaseRow> {
    let status: PurchaseStatusValue;
    let reason: Reason | null | undefined;
    let paymentId: string | null = null;
    if (answer instanceof GatewayError) {
      paymentId = answer.detail.paymentId ?? null;
      if (answer.kind === "unknown") status = "outcome_unknown";
      else [status, reason] = ["failed", answer.kind === "rejected" ? "declined" : "not_sent"];
    } else {
      paymentId = answer.paymentId;
      switch (answer.state) {
        case "succeeded":
          status = "paid";
          break;
        case "processing":
          status = "paying";
          break;
        case "waiting_for_bank":
          status = "waiting_for_bank";
          break;
        case "declined":
          [status, reason] = ["failed", "declined"];
          break;
        case "canceled":
          [status, reason] = row.reason === "cancel_requested" ? ["cancelled", "cancel_requested"] : ["failed", "canceled"];
          break;
        case "needs_card_check": {
          let after: GatewayPayment | null = null;
          if (this.gateway && answer.paymentId) {
            try {
              after = await this.gateway.cancel(answer.paymentId);
            } catch {
              after = null;
            }
          }
          if (after?.state === "succeeded") status = "paid";
          else [status, reason] = ["failed", "card_check"];
          break;
        }
      }
    }
    const now = this.now();
    await this.store.updatePurchase(row.user_id, row.purchase_id, from, {
      status,
      now,
      ...(paymentId ? { paymentId } : {}),
      ...(reason !== undefined ? { reason } : {}),
    });
    const updated = await this.reload(row);
    if (updated.status === "paid") await this.store.finishApproval(updated.approval_id, "succeeded", updated.payment_id, now);
    else if (updated.status === "failed" || updated.status === "cancelled") await this.store.finishApproval(updated.approval_id, "failed", updated.payment_id, now);
    return updated;
  }

  private result(row: PurchaseRow): PurchaseResult {
    return { mode: this.mode, purchase: this.view(row) };
  }

  private handoffResult(row: PurchaseRow): HandoffResult {
    return { mode: this.mode, purchase: this.view(row), checkoutUrl: row.checkout_url! };
  }

  private view(row: PurchaseRow): PurchaseView {
    return {
      id: row.purchase_id,
      kind: row.kind,
      merchantName: row.merchant_name,
      description: row.description,
      amountMinor: row.amount_minor,
      currency: "PLN",
      checkoutHost: row.checkout_url ? new URL(row.checkout_url).hostname : null,
      status: row.status,
      method: row.method === "apple_pay" || row.method === "blik" ? row.method : null,
      testMode: row.test_mode === 1,
      summary: summary(row),
      createdAt: iso(row.created_at),
      updatedAt: iso(row.updated_at),
    };
  }
}

const SETTLED_STATES: ReadonlySet<GatewayPayment["state"]> = new Set(["succeeded", "canceled", "declined"]);

/** The approval's digest: exactly what the card shows, from the stored purchase. */
export function purchaseDigest(row: Pick<PurchaseRow, "kind" | "merchant_name" | "description" | "amount_minor" | "currency" | "checkout_url">): string {
  return argumentDigest({
    kind: row.kind,
    merchantName: row.merchant_name,
    description: row.description,
    amountMinor: row.amount_minor,
    currency: row.currency,
    checkoutUrl: row.checkout_url ?? null,
  });
}

/** One plain sentence for the screen and the voice agent. Matches the contract fixtures word for word. */
export function summary(row: PurchaseRow): string {
  const amount = formatPln(row.amount_minor);
  if (row.kind === "checkout") {
    const host = row.checkout_url ? new URL(row.checkout_url).hostname : "the shop";
    switch (row.status) {
      case "awaiting_tap":
        return `Ready to open the checkout at ${host}. Expected price ${amount}; the shop's page shows the real one.`;
      case "handed_off":
        return `Opened the checkout at ${host}. Doddy can't see whether you paid there.`;
      case "user_reported_paid":
        return `You said you paid at ${host}. Doddy didn't see the payment itself.`;
      case "cancelled":
        return row.reason === "user_reported_unpaid"
          ? `You said you didn't pay at ${host}. Doddy didn't see the page itself.`
          : `Cancelled. The checkout at ${host} wasn't opened and nothing was paid.`;
      case "expired":
        return `The confirmation ran out before the checkout at ${host} was opened. Nothing was paid.`;
      default:
        return `The checkout at ${host} is the shop's own page. Doddy can't see whether you paid there.`;
    }
  }
  const test = row.test_mode === 1 ? " (test mode, no real money)" : "";
  const method = row.method === "apple_pay" ? "Apple Pay" : row.method === "blik" ? "BLIK" : null;
  switch (row.status) {
    case "awaiting_tap":
      return `Waiting for your tap: ${amount} for ${row.merchant_name}${test}.`;
    case "paying":
      return `Paying ${amount}; waiting for the answer${test}.`;
    case "waiting_for_bank":
      return `Approve ${amount} in your bank app${test}.`;
    case "paid":
      return `Paid ${amount}${method ? ` with ${method}` : ""}${test}.`;
    case "outcome_unknown":
      // Fixture purchase-result-unknown.json: no test-mode note here; the card shows it.
      return `Stripe didn't answer, so Doddy can't tell yet whether ${amount} was paid. Nothing will be tried again by itself.`;
    case "failed":
      switch (row.reason) {
        case "card_check":
          return `Your bank asked for an extra check Doddy can't show yet. Nothing was charged; try BLIK${test}.`;
        case "declined":
          return `The payment of ${amount} was declined. Nothing was charged${test}.`;
        default:
          return `The payment of ${amount} didn't go through. Nothing was charged${test}.`;
      }
    case "cancelled":
      return `Cancelled: ${amount} for ${row.merchant_name} was not paid${test}.`;
    case "expired":
      return `The confirmation for ${amount} ran out before you paid. Nothing was paid${test}.`;
    default:
      return `Nothing was paid for ${row.merchant_name}${test}.`;
  }
}

function freshConfirmation(): AppError {
  return new AppError("capability_disabled", { message: "This purchase needs a fresh confirmation. Nothing was paid." });
}

function notSetUp(): AppError {
  return new AppError("live_not_configured", { message: "Payments aren't set up on this server." });
}

/** Strict parse. A refusal written for the user (see contracts.ts) keeps its text; anything else is the generic one. */
function parse<T>(schema: { safeParse(v: unknown): { success: true; data: T } | { success: false; error: { issues: { message: string; params?: Record<string, unknown> }[] } } }, body: unknown): T {
  const result = schema.safeParse(body);
  if (result.success) return result.data;
  const written = result.error.issues.find((issue) => issue.params?.userMessage === true);
  throw new AppError("invalid_request", written ? { message: written.message } : {});
}

const iso = (ms: number) => new Date(ms).toISOString();
const utcDay = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const startOfUtcDay = (ms: number) => Date.parse(`${utcDay(ms)}T00:00:00.000Z`);
