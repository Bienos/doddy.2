import { z } from "zod";

/**
 * Doddy-owned purchases contract (ADR-530, contracts/purchases/README.md). Request bodies are
 * strict: a user ID, a Stripe ID, a provider name or any unknown field is rejected, not ignored.
 * The response schemas are the exact shapes the iPhone decodes; the backend tests parse the JSON
 * fixtures in contracts/purchases/ against them.
 */

export const PurchaseKindSchema = z.enum(["native", "checkout"]);
export type PurchaseKind = z.infer<typeof PurchaseKindSchema>;

export const PurchaseMethodSchema = z.enum(["apple_pay", "blik"]);
export type PurchaseMethod = z.infer<typeof PurchaseMethodSchema>;

export const PurchaseStatusSchema = z.enum([
  "awaiting_tap",
  "paying",
  "waiting_for_bank",
  "paid",
  "failed",
  "outcome_unknown",
  "cancelled",
  "expired",
  "handed_off",
  "user_reported_paid",
]);
export type PurchaseStatus = z.infer<typeof PurchaseStatusSchema>;

/** `mock`: the server's demo mode, nothing reaches Stripe. `test`: Stripe on test keys (or no Stripe at all). */
export const PaymentsModeSchema = z.enum(["mock", "test"]);
export type PaymentsMode = z.infer<typeof PaymentsModeSchema>;

export const PURCHASE_RULES = {
  merchantNameLength: 80,
  descriptionLength: 200,
  /** Stripe's smallest PLN charge (2 zł). */
  nativeMinimumMinor: 200,
  checkoutUrlLength: 2048,
  /** Everything in `applePay` together (the token is a few KB in practice). */
  applePayMaxBytes: 24 * 1024,
  /** Body limit for POST /v1/purchases/pay only; every other route keeps the server's default. */
  payMaxBodyBytes: 32 * 1024,
  currency: "PLN",
} as const;

/** A refusal the client may show. Fixed text only, never an echo of what was sent. */
function refuse(ctx: z.RefinementCtx, message: string): void {
  ctx.addIssue({ code: z.ZodIssueCode.custom, message, params: { userMessage: true } });
}

const uuid = z
  .string()
  .uuid()
  .transform((s) => s.toLowerCase());

// ---------------------------------------------------------------- requests

export const PrepareRequestSchema = z
  .object({
    kind: PurchaseKindSchema,
    merchantName: z.string().trim().min(1).max(PURCHASE_RULES.merchantNameLength),
    description: z.string().trim().min(1).max(PURCHASE_RULES.descriptionLength),
    amountMinor: z.number().int().min(1).max(Number.MAX_SAFE_INTEGER),
    currency: z.string(),
    /** Checkout only; checked further (https, host, allowlist) by `checkoutTarget`. */
    checkoutUrl: z.string().optional(),
  })
  .strict()
  .superRefine((value, ctx) => {
    if (value.currency !== PURCHASE_RULES.currency) refuse(ctx, "Doddy can only pay in złoty (PLN) for now.");
    if (value.kind === "native") {
      if (value.checkoutUrl !== undefined) refuse(ctx, "A purchase paid inside Doddy doesn't take a checkout page.");
      if (value.amountMinor < PURCHASE_RULES.nativeMinimumMinor) refuse(ctx, "Payments inside Doddy start at 2,00 zł.");
    } else if (value.checkoutUrl === undefined) {
      refuse(ctx, "A checkout purchase needs the shop's checkout page.");
    }
  });
export type PrepareRequest = z.infer<typeof PrepareRequestSchema>;

/** `PKPaymentToken` as the phone passed it on, untouched. Never stored or logged. */
export const ApplePayTokenSchema = z
  .object({
    /** `PKPaymentToken.paymentData` as a UTF-8 string. Empty only in the simulator (test keys). */
    paymentData: z.string(),
    network: z.string().optional(),
    instrumentName: z.string().optional(),
    transactionId: z.string().optional(),
  })
  .strict()
  .superRefine((value, ctx) => {
    const bytes = [value.paymentData, value.network, value.instrumentName, value.transactionId].reduce(
      (sum, s) => sum + (s === undefined ? 0 : Buffer.byteLength(s, "utf8")),
      0,
    );
    if (bytes > PURCHASE_RULES.applePayMaxBytes) refuse(ctx, "The Apple Pay answer was too large.");
  });
export type ApplePayToken = z.infer<typeof ApplePayTokenSchema>;

const blikCode = z.string().superRefine((value, ctx) => {
  if (!/^\d{6}$/.test(value)) refuse(ctx, "A BLIK code is the six digits from your bank app.");
});

export const PayRequestSchema = z.discriminatedUnion("method", [
  z.object({ purchaseId: uuid, approvalId: uuid, method: z.literal("apple_pay"), applePay: ApplePayTokenSchema }).strict(),
  /** The code is sent to Stripe once and never stored or logged. */
  z.object({ purchaseId: uuid, approvalId: uuid, method: z.literal("blik"), blikCode }).strict(),
]);
export type PayRequest = z.infer<typeof PayRequestSchema>;

export const PurchaseIdRequestSchema = z.object({ purchaseId: uuid }).strict();
export const HandoffRequestSchema = z.object({ purchaseId: uuid, approvalId: uuid }).strict();
export const ReportRequestSchema = z.object({ purchaseId: uuid, paid: z.boolean() }).strict();

// ---------------------------------------------------------------- responses

const isoMillis = z.string().datetime({ precision: 3 });

export const PurchaseViewSchema = z
  .object({
    id: z.string().uuid(),
    kind: PurchaseKindSchema,
    merchantName: z.string(),
    description: z.string(),
    amountMinor: z.number().int().positive(),
    currency: z.literal(PURCHASE_RULES.currency),
    /** Checkout only: the host of the page that opens. */
    checkoutHost: z.string().nullable(),
    status: PurchaseStatusSchema,
    method: PurchaseMethodSchema.nullable(),
    /** Native purchases on Stripe test keys or in mock mode. */
    testMode: z.boolean(),
    summary: z.string(),
    createdAt: isoMillis,
    updatedAt: isoMillis,
  })
  .strict();
export type PurchaseView = z.infer<typeof PurchaseViewSchema>;

export const PrepareResultSchema = z
  .object({
    mode: PaymentsModeSchema,
    purchase: PurchaseViewSchema,
    approvalId: z.string().uuid(),
    expiresAt: isoMillis,
    methods: z.array(PurchaseMethodSchema),
    /** Native: the name on the Apple Pay sheet (who is really paid). Checkout: the page's host. */
    payee: z.string(),
  })
  .strict();
export type PrepareResult = z.infer<typeof PrepareResultSchema>;

export const PurchaseResultSchema = z.object({ mode: PaymentsModeSchema, purchase: PurchaseViewSchema }).strict();
export type PurchaseResult = z.infer<typeof PurchaseResultSchema>;

export const HandoffResultSchema = z
  .object({ mode: PaymentsModeSchema, purchase: PurchaseViewSchema, checkoutUrl: z.string().url() })
  .strict();
export type HandoffResult = z.infer<typeof HandoffResultSchema>;

export const PurchasesListSchema = z.object({ purchases: z.array(PurchaseViewSchema) }).strict();
export type PurchasesList = z.infer<typeof PurchasesListSchema>;

// ---------------------------------------------------------------- checkout pages

const CHECKOUT_REFUSED = "The checkout must be the shop's own https page, without a user name, password or IP address.";
const CHECKOUT_NOT_ALLOWED = "That shop's checkout isn't on this server's list of allowed shops.";

export type CheckoutTarget = { ok: true; url: string; host: string } | { ok: false; message: string };

/**
 * A host name a shop's page can live at: at least two labels of letters, digits and hyphens. No IP
 * literal (the URL parser already rewrites forms like 0x7f.1 or 2130706433 to dotted IPv4) and no
 * localhost. Also used to validate DODDY_CHECKOUT_HOSTS.
 */
export function isShopHost(host: string): boolean {
  if (host === "localhost" || host.endsWith(".localhost")) return false;
  if (host.includes(":") || host.startsWith("[")) return false; // IPv6 literal
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) return false; // IPv4 literal
  if (host.length > 253) return false;
  const labels = host.split(".");
  return labels.length >= 2 && labels.every((label) => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label));
}

/**
 * The page a checkout purchase opens: https only, at most 2048 characters, no user name or
 * password, a real host name (no IP, no localhost) and, when the server has an allowlist, that
 * host or a subdomain of it. Doddy's server never fetches it; the phone opens it in Safari's view.
 */
export function checkoutTarget(raw: string, allowedHosts: readonly string[]): CheckoutTarget {
  const refused = { ok: false, message: CHECKOUT_REFUSED } as const;
  if (raw.length > PURCHASE_RULES.checkoutUrlLength) return refused;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return refused;
  }
  if (url.protocol !== "https:" || url.username !== "" || url.password !== "") return refused;
  const host = url.hostname.toLowerCase();
  if (!isShopHost(host) || url.href.length > PURCHASE_RULES.checkoutUrlLength) return refused;
  if (allowedHosts.length > 0 && !allowedHosts.some((allowed) => host === allowed || host.endsWith(`.${allowed}`))) {
    return { ok: false, message: CHECKOUT_NOT_ALLOWED };
  }
  return { ok: true, url: url.href, host };
}

// ---------------------------------------------------------------- money

/** "56,00 zł", "1 234,50 zł": how Polish shops write prices (same rule as DoddyCore's PurchaseMoney). */
export function formatPln(minor: number): string {
  const sign = minor < 0 ? "-" : "";
  const value = Math.abs(Math.trunc(minor));
  const whole = String(Math.floor(value / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  const fraction = String(value % 100).padStart(2, "0");
  return `${sign}${whole},${fraction} zł`;
}
