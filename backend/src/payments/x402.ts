import { z } from "zod";

/**
 * x402 (v2) buyer side, pure functions only: no network, no keys, no clock. Spec used:
 * x402-foundation/x402 `specs/x402-specification-v2.md` and `specs/schemes/exact/scheme_exact_evm.md`
 * (the EIP-3009 `transferWithAuthorization` method). Everything a seller sends is untrusted data:
 * it is parsed into a narrow shape and checked against Doddy's own policy before anything is signed.
 *
 * Not supported on purpose (each is refused with a plain message, never guessed at): x402 v1, any
 * scheme but `exact`, any token but the pinned USDC, any network but the one the server is set to,
 * and `payTo` role constants.
 */

export const NETWORKS = {
  "base-sepolia": {
    caip2: "eip155:84532",
    chainId: 84532,
    title: "Base Sepolia (test network, no real money)",
    // Circle's official USDC contract list (developers.circle.com/stablecoins/usdc-contract-addresses).
    usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
    testnet: true,
  },
  base: {
    caip2: "eip155:8453",
    chainId: 8453,
    title: "Base (real money)",
    // Widely used Base USDC address; confirm against Circle's list before the first mainnet run (see docs).
    usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    testnet: false,
  },
} as const;
export type NetworkId = keyof typeof NETWORKS;
export const NETWORK_IDS = Object.keys(NETWORKS) as [NetworkId, ...NetworkId[]];

export const USDC_DECIMALS = 6;
export const ADDRESS = /^0x[0-9a-fA-F]{40}$/;
const ZERO_ADDRESS = /^0x0{40}$/;
const SIGNATURE = /^0x[0-9a-fA-F]{130}$/;
const TX_HASH = /^0x[0-9a-fA-F]{64}$/;

/** Longest time a signed authorization may stay valid, whatever the seller asks for. */
export const MAX_AUTHORIZATION_SECONDS = 120;
/** How far back `validAfter` reaches, so a slightly slow clock on the seller's side still accepts it. */
const CLOCK_SKEW_SECONDS = 60;

// ------------------------------------------------------------------ amounts

/** "0.25" -> 250000. Whole USDC with up to six decimals; anything else is null. */
export function parseUsdc(text: string): number | null {
  const match = /^(\d{1,9})(?:\.(\d{1,6}))?$/.exec(text.trim());
  if (!match) return null;
  const atomic = Number(match[1]) * 10 ** USDC_DECIMALS + Number((match[2] ?? "").padEnd(USDC_DECIMALS, "0"));
  return Number.isSafeInteger(atomic) ? atomic : null;
}

/** 50000 -> "0.05". At least two decimals, at most six, no exponent. */
export function formatUsdc(atomic: number | bigint): string {
  const value = BigInt(atomic);
  const whole = value / 10n ** BigInt(USDC_DECIMALS);
  const fraction = (value % 10n ** BigInt(USDC_DECIMALS)).toString().padStart(USDC_DECIMALS, "0").replace(/0+$/, "").padEnd(2, "0");
  return `${whole}.${fraction}`;
}

// ------------------------------------------------------------------ what a seller sends

const RequirementSchema = z
  .object({
    scheme: z.string().max(32),
    network: z.string().max(64),
    amount: z.string().max(40),
    asset: z.string().max(100),
    payTo: z.string().max(100),
    maxTimeoutSeconds: z.number().int().positive().max(86_400),
    extra: z.record(z.unknown()).optional(),
  })
  .passthrough();
export type Requirement = z.infer<typeof RequirementSchema>;

const PaymentRequiredSchema = z
  .object({
    x402Version: z.literal(2),
    error: z.string().max(500).optional(),
    resource: z.object({ url: z.string().max(2048) }).passthrough(),
    accepts: z.array(z.unknown()).min(1).max(20),
  })
  .passthrough();

export interface PaymentRequired {
  resource: Record<string, unknown>;
  accepts: Requirement[];
}

export type ParseFailure = "unsupported_version" | "malformed";
const MAX_HEADER_CHARS = 16 * 1024;

function decodeBase64Json(value: string): unknown {
  if (value.length > MAX_HEADER_CHARS) return undefined;
  try {
    return JSON.parse(Buffer.from(value, "base64").toString("utf8")) as unknown;
  } catch {
    return undefined;
  }
}

/**
 * Reads a 402 answer: the base64 `PAYMENT-REQUIRED` header first, then the JSON body (some sellers
 * send only that). Entries of `accepts` that don't have the expected shape are dropped one by one.
 */
export function parsePaymentRequired(input: { headers: Record<string, string>; body: string }): { ok: true; value: PaymentRequired } | { ok: false; reason: ParseFailure } {
  const fromHeader = input.headers["payment-required"];
  let raw: unknown = fromHeader !== undefined ? decodeBase64Json(fromHeader) : undefined;
  if (raw === undefined && input.body.length > 0 && input.body.length <= MAX_HEADER_CHARS) {
    try {
      raw = JSON.parse(input.body) as unknown;
    } catch {
      raw = undefined;
    }
  }
  if (typeof raw !== "object" || raw === null) return { ok: false, reason: "malformed" };
  if ((raw as Record<string, unknown>).x402Version === 1) return { ok: false, reason: "unsupported_version" };
  const parsed = PaymentRequiredSchema.safeParse(raw);
  if (!parsed.success) return { ok: false, reason: "malformed" };
  const accepts = parsed.data.accepts.flatMap((item) => {
    const r = RequirementSchema.safeParse(item);
    return r.success ? [r.data] : [];
  });
  if (accepts.length === 0) return { ok: false, reason: "malformed" };
  return { ok: true, value: { resource: parsed.data.resource, accepts } };
}

// ------------------------------------------------------------------ Doddy's policy over a seller's offer

export type RefusalReason = "unsupported_scheme" | "unsupported_network" | "unsupported_asset" | "unsupported_recipient" | "malformed" | "too_expensive";

export interface Accepted {
  requirement: Requirement;
  /** Atomic USDC units (6 decimals). */
  amount: number;
  payTo: string;
  /** EIP-712 domain values of the token, as the seller states them (they cannot change which contract is used). */
  tokenName: string;
  tokenVersion: string;
}

/**
 * Picks the cheapest offer Doddy is willing to pay: scheme `exact`, the server's network, the pinned
 * USDC contract, EIP-3009, a real recipient address, and at most `maxAmount`. Otherwise says why not.
 */
export function chooseRequirement(accepts: Requirement[], policy: { network: NetworkId; maxAmount: number }): { ok: true; accepted: Accepted } | { ok: false; reason: RefusalReason; amount?: number } {
  const network = NETWORKS[policy.network];
  let best: Accepted | null = null;
  let failure = "unsupported_scheme" as RefusalReason; // widened: `note` reassigns it from a closure
  let tooExpensive: number | undefined;
  const rank: RefusalReason[] = ["unsupported_scheme", "unsupported_network", "unsupported_asset", "unsupported_recipient", "malformed", "too_expensive"];
  const note = (reason: RefusalReason) => {
    if (rank.indexOf(reason) > rank.indexOf(failure)) failure = reason;
  };

  for (const r of accepts) {
    if (r.scheme !== "exact") continue;
    if (r.network !== network.caip2) {
      note("unsupported_network");
      continue;
    }
    if (r.asset.toLowerCase() !== network.usdc.toLowerCase()) {
      note("unsupported_asset");
      continue;
    }
    const extra = r.extra ?? {};
    if (extra.assetTransferMethod !== undefined && extra.assetTransferMethod !== "eip3009") {
      note("unsupported_asset");
      continue;
    }
    if (!ADDRESS.test(r.payTo) || ZERO_ADDRESS.test(r.payTo)) {
      note("unsupported_recipient");
      continue;
    }
    const name = extra.name;
    const version = extra.version;
    if (typeof name !== "string" || typeof version !== "string" || name.length < 1 || name.length > 32 || version.length < 1 || version.length > 16 || !/^[\x20-\x7e]+$/.test(name + version)) {
      note("malformed");
      continue;
    }
    if (!/^[0-9]{1,15}$/.test(r.amount) || BigInt(r.amount) === 0n) {
      note("malformed");
      continue;
    }
    const amount = Number(r.amount);
    if (amount > policy.maxAmount) {
      note("too_expensive");
      tooExpensive = Math.min(tooExpensive ?? amount, amount);
      continue;
    }
    if (best === null || amount < best.amount) best = { requirement: r, amount, payTo: r.payTo, tokenName: name, tokenVersion: version };
  }
  if (best) return { ok: true, accepted: best };
  return { ok: false, reason: failure, ...(failure === "too_expensive" && tooExpensive !== undefined ? { amount: tooExpensive } : {}) };
}

// ------------------------------------------------------------------ what Doddy signs and sends

export interface Authorization {
  from: string;
  to: string;
  value: string;
  validAfter: string;
  validBefore: string;
  nonce: string;
}

/** A fresh authorization for exactly this offer. `nonce` is 32 random bytes the caller supplies. */
export function buildAuthorization(input: { from: string; accepted: Accepted; nowMs: number; nonce: string }): Authorization {
  if (!ADDRESS.test(input.from)) throw new Error("bad_from");
  if (!/^0x[0-9a-fA-F]{64}$/.test(input.nonce)) throw new Error("bad_nonce");
  const now = Math.floor(input.nowMs / 1000);
  const lifetime = Math.min(input.accepted.requirement.maxTimeoutSeconds, MAX_AUTHORIZATION_SECONDS);
  return {
    from: input.from,
    to: input.accepted.payTo,
    value: String(input.accepted.amount),
    validAfter: String(now - CLOCK_SKEW_SECONDS),
    validBefore: String(now + lifetime),
    nonce: input.nonce,
  };
}

export interface TransferTypedData {
  domain: { name: string; version: string; chainId: number; verifyingContract: string };
  types: Record<string, { name: string; type: string }[]>;
  primaryType: "TransferWithAuthorization";
  message: Authorization;
}

/** EIP-712 data for EIP-3009 `transferWithAuthorization`. The contract and chain are Doddy's, not the seller's. */
export function transferTypedData(network: NetworkId, accepted: Accepted, authorization: Authorization): TransferTypedData {
  const n = NETWORKS[network];
  return {
    domain: { name: accepted.tokenName, version: accepted.tokenVersion, chainId: n.chainId, verifyingContract: n.usdc },
    types: {
      EIP712Domain: [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" },
      ],
      TransferWithAuthorization: [
        { name: "from", type: "address" },
        { name: "to", type: "address" },
        { name: "value", type: "uint256" },
        { name: "validAfter", type: "uint256" },
        { name: "validBefore", type: "uint256" },
        { name: "nonce", type: "bytes32" },
      ],
    },
    primaryType: "TransferWithAuthorization",
    message: authorization,
  };
}

export function isSignature(value: unknown): value is string {
  return typeof value === "string" && SIGNATURE.test(value);
}

/**
 * The `PAYMENT-SIGNATURE` header value: base64 of the PaymentPayload. `accepted` is the seller's own
 * offer, unchanged, so the seller can match it to what it asked for.
 */
export function paymentSignatureHeader(input: { required: PaymentRequired; accepted: Accepted; authorization: Authorization; signature: string }): string {
  const payload = {
    x402Version: 2,
    resource: input.required.resource,
    accepted: input.accepted.requirement,
    payload: { signature: input.signature, authorization: input.authorization },
  };
  return Buffer.from(JSON.stringify(payload), "utf8").toString("base64");
}

// ------------------------------------------------------------------ the seller's receipt

export interface Settlement {
  transaction: string;
  payer: string | null;
}

/**
 * Trusted confirmation only: a settlement answer that says success, names a transaction hash, is for
 * the expected network, and (when it names a payer) is for Doddy's wallet. Anything else is not proof.
 */
export function confirmSettlement(headers: Record<string, string>, expected: { network: NetworkId; from: string }): Settlement | null {
  const header = headers["payment-response"] ?? headers["x-payment-response"];
  if (header === undefined) return null;
  const raw = decodeBase64Json(header);
  if (typeof raw !== "object" || raw === null) return null;
  const s = raw as Record<string, unknown>;
  if (s.success !== true) return null;
  if (typeof s.transaction !== "string" || !TX_HASH.test(s.transaction)) return null;
  if (s.network !== NETWORKS[expected.network].caip2) return null;
  if (s.payer !== undefined && (typeof s.payer !== "string" || s.payer.toLowerCase() !== expected.from.toLowerCase())) return null;
  return { transaction: s.transaction, payer: typeof s.payer === "string" ? s.payer : null };
}
