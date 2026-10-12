import type { TransferTypedData } from "./x402.js";

/**
 * Wallet boundary for payments. A wallet can do exactly one thing: sign the EIP-3009 transfer
 * authorization that `x402.transferTypedData` built. It never receives a free-form message, a
 * transaction, a recipient chosen by anyone but the approved offer, or a way to send funds itself.
 * Nothing here returns a key.
 */
export type WalletFailureKind = "timeout" | "unavailable";

export class WalletFailure extends Error {
  constructor(readonly kind: WalletFailureKind) {
    super(kind);
    this.name = "WalletFailure";
  }
}

export interface PaymentWallet {
  /** `mock`: offline demo, signs nothing real. `coinbase_cdp`: a Coinbase Developer Platform server wallet. */
  readonly kind: "mock" | "coinbase_cdp";
  readonly mode: "mock" | "live";
  /** The account payments are drawn from (0x…, 40 hex digits). */
  readonly address: string;
  /** `idempotencyKey` makes a repeated signing request return the same signature instead of a new one. */
  signTransferAuthorization(typedData: TransferTypedData, options: { signal: AbortSignal; idempotencyKey: string }): Promise<string>;
}

/** "0x1234…abcd": enough for a person to recognise their wallet, short enough to read aloud. */
export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/**
 * Offline demo wallet. Its "signature" is a fixed placeholder that no real token contract would
 * accept, and the mock seller never checks it: nothing here can move money. Receipts made with it
 * say `mode: "mock"`, and the app labels them DEMO DATA like every other mock result.
 */
export class MockPaymentWallet implements PaymentWallet {
  readonly kind = "mock" as const;
  readonly mode = "mock" as const;
  readonly address = `0xd0dd1e${"0".repeat(33)}1`;
  readonly signed: TransferTypedData[] = [];
  /** Demo failure: make the next signing attempt fail, to exercise the "nothing was paid" path. */
  failNext: WalletFailureKind | null = null;

  async signTransferAuthorization(typedData: TransferTypedData): Promise<string> {
    if (this.failNext) {
      const kind = this.failNext;
      this.failNext = null;
      throw new WalletFailure(kind);
    }
    this.signed.push(typedData);
    return `0x${"00".repeat(65)}`;
  }
}
