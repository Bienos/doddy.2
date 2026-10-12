import assert from "node:assert/strict";
import { createHash, createPublicKey, generateKeyPairSync, type KeyObject, verify } from "node:crypto";
import { test } from "node:test";
import { buildApiKeyJwt, buildWalletAuthJwt, CDP_HOST, CdpKeyError, CoinbaseCdpWallet, type CdpSettings, loadCdpKeys } from "../src/payments/coinbase.js";
import { canonicalJson } from "../src/policy.js";
import { WalletFailure } from "../src/payments/wallet.js";
import { buildAuthorization, chooseRequirement, NETWORKS, transferTypedData } from "../src/payments/x402.js";

/**
 * Keys are generated fresh in every run, so no key material lives in the repository. These tests
 * verify the JWT structure and signatures against Coinbase's published scheme and the request the
 * wallet sends to a fake server. They do NOT prove the real Coinbase service accepts the request:
 * that needs a funded test account and is a manual step (docs/integrations/PAYMENTS_X402.md).
 */

const ADDRESS = "0x1111111111111111111111111111111111111111";

function makeSettings(): { settings: CdpSettings; apiPublic: KeyObject; walletPublic: KeyObject } {
  const ed = generateKeyPairSync("ed25519");
  const der = ed.privateKey.export({ format: "der", type: "pkcs8" });
  const seed = der.subarray(der.length - 32);
  const publicRaw = Buffer.from(ed.publicKey.export({ format: "jwk" }).x as string, "base64url");
  const ec = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return {
    settings: {
      apiKeyId: "test-key-id",
      apiKeySecret: Buffer.concat([seed, publicRaw]).toString("base64"),
      walletSecret: ec.privateKey.export({ format: "der", type: "pkcs8" }).toString("base64"),
      accountAddress: ADDRESS,
    },
    apiPublic: ed.publicKey,
    walletPublic: createPublicKey(ec.privateKey),
  };
}

function decodeJwt(token: string) {
  const [h, p, s] = token.split(".") as [string, string, string];
  return {
    header: JSON.parse(Buffer.from(h, "base64url").toString()),
    claims: JSON.parse(Buffer.from(p, "base64url").toString()),
    signingInput: Buffer.from(`${h}.${p}`),
    signature: Buffer.from(s, "base64url"),
  };
}

const typed = () => {
  const acc = chooseRequirement(
    [{ scheme: "exact", network: "eip155:84532", amount: "50000", asset: NETWORKS["base-sepolia"].usdc, payTo: "0x00000000000000000000000000000000000d0d01", maxTimeoutSeconds: 60, extra: { name: "USDC", version: "2" } }],
    { network: "base-sepolia", maxAmount: 250_000 },
  );
  assert.ok(acc.ok);
  return transferTypedData("base-sepolia", acc.accepted, buildAuthorization({ from: ADDRESS, accepted: acc.accepted, nowMs: 1_800_000_000_000, nonce: `0x${"ab".repeat(32)}` }));
};

test("keys load, and a bad one is named by variable, never by value", () => {
  const { settings } = makeSettings();
  assert.doesNotThrow(() => loadCdpKeys(settings));
  const problem = (over: Partial<CdpSettings>) => {
    try {
      loadCdpKeys({ ...settings, ...over });
      return "ok";
    } catch (error) {
      assert.ok(error instanceof CdpKeyError);
      assert.doesNotMatch(error.message, /[A-Za-z0-9+/]{20,}/);
      return error.variable;
    }
  };
  assert.equal(problem({ apiKeySecret: Buffer.alloc(32).toString("base64") }), "CDP_API_KEY_SECRET");
  assert.equal(problem({ apiKeySecret: "not base64 at all!!" }), "CDP_API_KEY_SECRET");
  assert.equal(problem({ walletSecret: "AAAA" }), "CDP_WALLET_SECRET");
  // An Ed25519 key is not a wallet secret (it must be P-256), and the reverse.
  const ed = generateKeyPairSync("ed25519").privateKey.export({ format: "der", type: "pkcs8" }).toString("base64");
  assert.equal(problem({ walletSecret: ed }), "CDP_WALLET_SECRET");
  assert.equal(problem({ accountAddress: "0x123" }), "CDP_PAYMENT_ACCOUNT_ADDRESS");
});

test("the API-key JWT is EdDSA, names the request in `uris`, and expires in two minutes", () => {
  const { settings, apiPublic } = makeSettings();
  const keys = loadCdpKeys(settings);
  const path = `/platform/v2/evm/accounts/${ADDRESS}/sign/typed-data`;
  const token = buildApiKeyJwt({ apiKeyId: settings.apiKeyId, key: keys.apiKey, method: "POST", path, nowSec: 1_800_000_000, nonce: "0123456789abcdef0123456789abcdef" });
  const jwt = decodeJwt(token);
  assert.deepEqual(jwt.header, { alg: "EdDSA", kid: "test-key-id", typ: "JWT", nonce: "0123456789abcdef0123456789abcdef" });
  assert.deepEqual(jwt.claims, {
    sub: "test-key-id", iss: "cdp", aud: ["cdp_service"], nbf: 1_800_000_000, iat: 1_800_000_000, exp: 1_800_000_120, uris: [`POST ${CDP_HOST}${path}`],
  });
  assert.equal(verify(null, jwt.signingInput, apiPublic, jwt.signature), true);
  // Tampering with a claim breaks the signature.
  const [h, , s] = token.split(".");
  const forged = `${h}.${Buffer.from(JSON.stringify({ ...jwt.claims, uris: [`POST ${CDP_HOST}/platform/v2/other`] })).toString("base64url")}.${s}`;
  const f = decodeJwt(forged);
  assert.equal(verify(null, f.signingInput, apiPublic, f.signature), false);
});

test("the wallet JWT is ES256 and binds the exact request body through reqHash", () => {
  const { settings, walletPublic } = makeSettings();
  const keys = loadCdpKeys(settings);
  const path = `/platform/v2/evm/accounts/${ADDRESS}/sign/typed-data`;
  const body = { b: 2, a: { d: [3, 1], c: "x" } };
  const jwt = decodeJwt(buildWalletAuthJwt({ key: keys.walletKey, method: "POST", path, body, nowSec: 1_800_000_000, jti: "jti-1" }));
  assert.deepEqual(jwt.header, { alg: "ES256", typ: "JWT" });
  assert.deepEqual(jwt.claims, {
    uris: [`POST ${CDP_HOST}${path}`], iat: 1_800_000_000, nbf: 1_800_000_000, jti: "jti-1",
    reqHash: createHash("sha256").update('{"a":{"c":"x","d":[3,1]},"b":2}').digest("hex"),
  });
  assert.equal(jwt.signature.length, 64); // raw r||s, as JWS ES256 requires
  assert.equal(verify("sha256", jwt.signingInput, { key: walletPublic, dsaEncoding: "ieee-p1363" }, jwt.signature), true);
});

test("signing sends one POST with both auth headers and the sorted body, and returns the signature", async () => {
  const { settings, apiPublic, walletPublic } = makeSettings();
  const seen: { url: string; init: RequestInit }[] = [];
  const signature = `0x${"cd".repeat(65)}`;
  const fake: typeof fetch = async (url, init) => {
    seen.push({ url: String(url), init: init! });
    return new Response(JSON.stringify({ signature }), { status: 200 });
  };
  const wallet = new CoinbaseCdpWallet(settings, fake, () => 1_800_000_000_000);
  assert.equal(wallet.kind, "coinbase_cdp");
  assert.equal(wallet.address, ADDRESS);

  const data = typed();
  const result = await wallet.signTransferAuthorization(data, { signal: AbortSignal.timeout(1000), idempotencyKey: "pay-1" });
  assert.equal(result, signature);
  assert.equal(seen.length, 1);
  const { url, init } = seen[0]!;
  const path = `/platform/v2/evm/accounts/${ADDRESS}/sign/typed-data`;
  assert.equal(url, `https://${CDP_HOST}${path}`);
  assert.equal(init.method, "POST");
  const headers = init.headers as Record<string, string>;
  assert.equal(headers["x-idempotency-key"], "pay-1");
  assert.equal(headers["content-type"], "application/json");
  assert.equal(init.body, canonicalJson(data));

  const api = decodeJwt(headers.authorization!.replace(/^Bearer /, ""));
  assert.equal(verify(null, api.signingInput, apiPublic, api.signature), true);
  assert.deepEqual(api.claims.uris, [`POST ${CDP_HOST}${path}`]);
  const wal = decodeJwt(headers["x-wallet-auth"]!);
  assert.equal(verify("sha256", wal.signingInput, { key: walletPublic, dsaEncoding: "ieee-p1363" }, wal.signature), true);
  // The hash covers the very bytes that were sent.
  assert.equal(wal.claims.reqHash, createHash("sha256").update(init.body as string).digest("hex"));
  // The domain pins Doddy's token and chain.
  assert.equal(JSON.parse(init.body as string).domain.verifyingContract, NETWORKS["base-sepolia"].usdc);
});

test("every way signing can fail is a WalletFailure, and none leaks provider text", async () => {
  const { settings } = makeSettings();
  const failure = async (fake: typeof fetch) => {
    const wallet = new CoinbaseCdpWallet(settings, fake);
    try {
      await wallet.signTransferAuthorization(typed(), { signal: AbortSignal.timeout(1000), idempotencyKey: "k" });
      return "signed";
    } catch (error) {
      assert.ok(error instanceof WalletFailure);
      assert.doesNotMatch(error.message, /secret|leak/i);
      return error.kind;
    }
  };
  assert.equal(await failure(async () => new Response(JSON.stringify({ errorType: "unauthorized", errorMessage: "secret leak" }), { status: 401 })), "unavailable");
  assert.equal(await failure(async () => new Response("<html>bad gateway</html>", { status: 502 })), "unavailable");
  assert.equal(await failure(async () => new Response("not json", { status: 200 })), "unavailable");
  assert.equal(await failure(async () => new Response(JSON.stringify({}), { status: 200 })), "unavailable");
  assert.equal(await failure(async () => new Response(JSON.stringify({ signature: "0x12" }), { status: 200 })), "unavailable");
  assert.equal(await failure(async () => { throw Object.assign(new Error("boom"), { name: "TimeoutError" }); }), "timeout");
  assert.equal(await failure(async () => { throw new Error("connection reset"); }), "unavailable");
});
