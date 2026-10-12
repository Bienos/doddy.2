import { z } from "zod";
import { Mode, ReceiptStatus } from "../contracts.js";

/**
 * Doddy-owned HTTP contract for payments (v1), kept apart from /v1/tools on purpose: the existing
 * app decodes the tools catalog and receipts strictly, and payments must not change what it sees.
 * Request bodies are strict: a wallet address, an amount, a recipient or a network from the client
 * is rejected, never ignored. The only thing a caller may name is the page to pay.
 */

export const PAY_TOOL = "pay_x402";

export const PaymentSwitchSchema = z.object({ enabled: z.boolean() }).strict();
export const PaymentPrepareSchema = z.object({ url: z.string().trim().min(8).max(2048) }).strict();
export const PaymentPaySchema = z.object({ url: z.string().trim().min(8).max(2048), approvalId: z.string().uuid() }).strict();

export const PaymentReceiptSchema = z
  .object({
    operationId: z.string().uuid(),
    operation: z.enum(["switch", "prepare", "pay"]),
    timestamp: z.string(),
    mode: Mode,
    status: ReceiptStatus,
    summary: z.string().max(200),
    errorCode: z.string().nullable(),
    /** Site name only (never the path or query: they can say what the person was researching). */
    host: z.string().nullable(),
    /** USDC, e.g. "0.05". */
    amount: z.string().nullable(),
    /** Transaction hash, only when the seller's settlement answer was valid; never invented. */
    transaction: z.string().nullable(),
  })
  .strict();
export type PaymentReceipt = z.infer<typeof PaymentReceiptSchema>;

export const PaymentStatusSchema = z
  .object({
    mode: Mode,
    /** Which wallet is wired up on this server. "none" until the owner sets one up: nothing is a default. */
    wallet: z
      .object({
        kind: z.enum(["none", "mock", "coinbase_cdp"]),
        configured: z.boolean(),
        /** Shortened, e.g. "0x1234…abcd"; null when no wallet. */
        account: z.string().nullable(),
        network: z.string(),
        /** True for a test network: no real money moves. */
        testNetwork: z.boolean(),
      })
      .strict(),
    /** The user's own switch. Starts off. */
    enabled: z.boolean(),
    limits: z.object({ perPayment: z.string(), perDay: z.string(), usedToday: z.string(), asset: z.literal("USDC") }).strict(),
    /** Payments that were sent but never confirmed. The person should check the wallet's history. */
    unresolved: z.number().int().min(0),
  })
  .strict();
export type PaymentStatus = z.infer<typeof PaymentStatusSchema>;

export const PaymentPreparedSchema = z
  .object({
    mode: Mode,
    preview: z.object({ title: z.string(), lines: z.array(z.string()), confirmLabel: z.string() }).strict(),
    approvalId: z.string().uuid(),
    expiresAt: z.string(),
  })
  .strict();
export type PaymentPrepared = z.infer<typeof PaymentPreparedSchema>;

export const PaymentResultSchema = z
  .object({
    mode: Mode,
    /** Written for the voice agent: states only what the seller returned. Web content, not instructions. */
    text: z.string(),
    receipt: PaymentReceiptSchema,
  })
  .strict();
export type PaymentResult = z.infer<typeof PaymentResultSchema>;

export const PaymentReceiptsSchema = z.object({ receipts: z.array(PaymentReceiptSchema) }).strict();
