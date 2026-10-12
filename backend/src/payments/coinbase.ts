import { createHash, createPrivateKey, randomBytes, randomUUID, sign, type KeyObject } from "node:crypto";
import { canonicalJson } from "../policy.js";
import { type PaymentWallet, WalletFailure } from "./wallet.js";
import { ADDRESS, isSignature, type TransferTypedData } from "./x402.js";

/**
 * Coinbase Developer Platform (CDP) server wallet, REST only, no SDK: the one file that talks to
 * Coinbase. Doddy asks it for a single thing, an EIP-712 signature over a transfer authorization,
 * from an account the owner created in the CDP portal. Doddy never creates accounts, never moves
 * funds itself, and never sees a private key: CDP signs inside its own enclave.
 *
 * Auth follows Coinbase's published scheme (docs.cdp.coinbase.com/api-reference/v2/authentication)
 * and the behaviour of its open-source SDK:
 *  - `Authorization: Bearer <JWT>`, EdDSA over the Ed25519 API key, claims sub/iss/aud/uris/nbf/exp;
 *  - `X-Wallet-Auth: <JWT>`, ES256 over the Wallet Secret (a P-256 key), claims uris/iat/nbf/jti and
 *    `reqHash` = SHA-256 of the key-sorted compact JSON body.
 *
 * Verified offline only (JWT structure and signatures; the request shape against a fake server).
 * NOT run against the real Coinbase service from the authoring environment.
 */

export const CDP_HOST = "api.cdp.coinbase.com";

export interface CdpSettings {
  /** API key ID (the JWT `kid` and `sub`). */
  apiKeyId: string;
  /** Ed25519 secret, base64 of 64 bytes (seed + public key), as the CDP portal shows it. */
  apiKeySecret: string;
  /** Wallet Secret, base64 of a PKCS#8 DER P-256 private key. */
  walletSecret: string;
  /** The CDP EVM account payments are signed from. */
  accountAddress: string;
}

export type CdpKeyProblem = "CDP_API_KEY_SECRET" | "CDP_WALLET_SECRET" | "CDP_PAYMENT_ACCOUNT_ADDRESS";

export class CdpKeyError extends Error {
  constructor(readonly variable: CdpKeyProblem) {
    super(`${variable} is invalid`);
    this.name = "CdpKeyError";
  }
}

export interface CdpKeys {
  apiKey: KeyObject;
  walletKey: KeyObject;
}

/** Fails fast, naming the variable (never its value). */
export function loadCdpKeys(settings: CdpSettings): CdpKeys {
  if (!ADDRESS.test(settings.accountAddress)) throw new CdpKeyError("CDP_PAYMENT_ACCOUNT_ADDRESS");
  let apiKey: KeyObject;
  try {
    const raw = Buffer.from(settings.apiKeySecret, "base64");
    if (raw.length !== 64) throw new Error("length");
    // PKCS#8 wrapper for a raw Ed25519 seed (RFC 8410).
    const der = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), raw.subarray(0, 32)]);
    apiKey = createPrivateKey({ key: der, format: "der", type: "pkcs8" });
    if (apiKey.asymmetricKeyType !== "ed25519") throw new Error("type");
  } catch {
    throw new CdpKeyError("CDP_API_KEY_SECRET");
  }
  let walletKey: KeyObject;
  try {
    walletKey = createPrivateKey({ key: Buffer.from(settings.walletSecret, "base64"), format: "der", type: "pkcs8" });
    if (walletKey.asymmetricKeyType !== "ec" || walletKey.asymmetricKeyDetails?.namedCurve !== "prime256v1") throw new Error("type");
  } catch {
    throw new CdpKeyError("CDP_WALLET_SECRET");
  }
  return { apiKey, walletKey };
}

const b64url = (value: Buffer | string) => Buffer.from(value).toString("base64url");

function compactJwt(header: object, claims: object, signer: (data: Buffer) => Buffer): string {
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  return `${signingInput}.${b64url(signer(Buffer.from(signingInput)))}`;
}

/** API-key JWT for one request. Valid for two minutes; the request line is bound into `uris`. */
export function buildApiKeyJwt(input: { apiKeyId: string; key: KeyObject; method: string; path: string; nowSec: number; nonce?: string }): string {
  const header = { alg: "EdDSA", kid: input.apiKeyId, typ: "JWT", nonce: input.nonce ?? randomBytes(16).toString("hex") };
  const claims = {
    sub: input.apiKeyId,
    iss: "cdp",
    aud: ["cdp_service"],
    nbf: input.nowSec,
    iat: input.nowSec,
    exp: input.nowSec + 120,
    uris: [`${input.method} ${CDP_HOST}${input.path}`],
  };
  return compactJwt(header, claims, (data) => sign(null, data, input.key));
}

/** Wallet-auth JWT for one request: proves the Wallet Secret holder wants exactly this body. */
export function buildWalletAuthJwt(input: { key: KeyObject; method: string; path: string; body: unknown; nowSec: number; jti?: string }): string {
  const claims = {
    uris: [`${input.method} ${CDP_HOST}${input.path}`],
    iat: input.nowSec,
    nbf: input.nowSec,
    jti: input.jti ?? randomBytes(16).toString("hex"),
    reqHash: createHash("sha256").update(canonicalJson(input.body)).digest("hex"),
  };
  return compactJwt({ alg: "ES256", typ: "JWT" }, claims, (data) => sign("sha256", data, { key: input.key, dsaEncoding: "ieee-p1363" }));
}

export class CoinbaseCdpWallet implements PaymentWallet {
  readonly kind = "coinbase_cdp" as const;
  readonly mode = "live" as const;
  readonly address: string;
  private readonly keys: CdpKeys;

  constructor(
    private readonly settings: CdpSettings,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly now: () => number = Date.now,
  ) {
    this.keys = loadCdpKeys(settings);
    this.address = settings.accountAddress;
  }

  async signTransferAuthorization(typedData: TransferTypedData, options: { signal: AbortSignal; idempotencyKey?: string }): Promise<string> {
    const path = `/platform/v2/evm/accounts/${this.address}/sign/typed-data`;
    // Sorted and compact, byte for byte what the wallet JWT hashes.
    const body = canonicalJson(typedData);
    const nowSec = Math.floor(this.now() / 1000);
    let response: Response;
    try {
      response = await this.fetchImpl(`https://${CDP_HOST}${path}`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${buildApiKeyJwt({ apiKeyId: this.settings.apiKeyId, key: this.keys.apiKey, method: "POST", path, nowSec })}`,
          "x-wallet-auth": buildWalletAuthJwt({ key: this.keys.walletKey, method: "POST", path, body: typedData, nowSec }),
          "x-idempotency-key": options.idempotencyKey ?? randomUUID(),
          "content-type": "application/json",
        },
        body,
        signal: options.signal,
      });
    } catch (error) {
      throw new WalletFailure(error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError") ? "timeout" : "unavailable");
    }
    if (!response.ok) throw new WalletFailure("unavailable");
    let parsed: unknown;
    try {
      parsed = await response.json();
    } catch {
      throw new WalletFailure("unavailable");
    }
    const signature = typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>).signature : undefined;
    if (!isSignature(signature)) throw new WalletFailure("unavailable");
    return signature;
  }
}
