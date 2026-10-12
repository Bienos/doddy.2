import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buildAuthorization,
  chooseRequirement,
  confirmSettlement,
  formatUsdc,
  NETWORKS,
  parsePaymentRequired,
  parseUsdc,
  paymentSignatureHeader,
  type Requirement,
  transferTypedData,
} from "../src/payments/x402.js";

const USDC = NETWORKS["base-sepolia"].usdc;
const PAY_TO = "0x00000000000000000000000000000000000d0d01";
const FROM = `0xd0dd1e${"0".repeat(33)}1`;
const NONCE = `0x${"11".repeat(32)}`;

const offer = (over: Partial<Requirement> = {}): Requirement => ({
  scheme: "exact",
  network: "eip155:84532",
  amount: "50000",
  asset: USDC,
  payTo: PAY_TO,
  maxTimeoutSeconds: 60,
  extra: { name: "USDC", version: "2" },
  ...over,
});
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64");
const required = (accepts: unknown[], over: Record<string, unknown> = {}) => ({ x402Version: 2, resource: { url: "https://shop.example/a" }, accepts, ...over });

// ------------------------------------------------------------------ amounts

test("USDC amounts parse and format without floating point", () => {
  assert.equal(parseUsdc("0.25"), 250_000);
  assert.equal(parseUsdc("1"), 1_000_000);
  assert.equal(parseUsdc("0.000001"), 1);
  assert.equal(parseUsdc("10000"), 10_000_000_000);
  for (const bad of ["", "-1", "1e3", "0.1234567", "1,5", "abc", "1.", ".5", "1000000000000"]) assert.equal(parseUsdc(bad), null, bad);
  assert.equal(formatUsdc(50_000), "0.05");
  assert.equal(formatUsdc(250_000), "0.25");
  assert.equal(formatUsdc(1_000_000), "1.00");
  assert.equal(formatUsdc(1), "0.000001");
  assert.equal(formatUsdc(123_456_789n), "123.456789");
});

// ------------------------------------------------------------------ reading a 402

test("a 402 is read from the base64 header, or from the body when there is no header", () => {
  const fromHeader = parsePaymentRequired({ headers: { "payment-required": b64(required([offer()])) }, body: "" });
  assert.equal(fromHeader.ok && fromHeader.value.accepts.length, 1);
  const fromBody = parsePaymentRequired({ headers: {}, body: JSON.stringify(required([offer()])) });
  assert.equal(fromBody.ok, true);
});

test("version 1, junk, and offers without a usable entry are refused, not guessed at", () => {
  assert.deepEqual(parsePaymentRequired({ headers: {}, body: JSON.stringify({ x402Version: 1, accepts: [offer()] }) }), { ok: false, reason: "unsupported_version" });
  assert.deepEqual(parsePaymentRequired({ headers: { "payment-required": "%%%not base64 json%%%" }, body: "" }), { ok: false, reason: "malformed" });
  assert.deepEqual(parsePaymentRequired({ headers: {}, body: "" }), { ok: false, reason: "malformed" });
  assert.deepEqual(parsePaymentRequired({ headers: {}, body: JSON.stringify(required([{ scheme: "exact" }])) }), { ok: false, reason: "malformed" });
  assert.deepEqual(parsePaymentRequired({ headers: {}, body: JSON.stringify(required([], {})) }), { ok: false, reason: "malformed" });
  // A huge header is dropped unread.
  assert.deepEqual(parsePaymentRequired({ headers: { "payment-required": "A".repeat(20_000) }, body: "" }), { ok: false, reason: "malformed" });
  // Entries that are not objects are skipped one by one; a good one next to them still counts.
  const mixed = parsePaymentRequired({ headers: {}, body: JSON.stringify(required(["x", 7, offer()])) });
  assert.equal(mixed.ok && mixed.value.accepts.length, 1);
});

// ------------------------------------------------------------------ Doddy's policy

const policy = { network: "base-sepolia" as const, maxAmount: 250_000 };

test("the cheapest acceptable offer is chosen", () => {
  const chosen = chooseRequirement([offer({ amount: "200000" }), offer({ amount: "50000" }), offer({ amount: "100000" })], policy);
  assert.equal(chosen.ok && chosen.accepted.amount, 50_000);
});

test("only exact / this network / the pinned USDC / a real address / EIP-3009 offers qualify", () => {
  const refusal = (o: Requirement[]) => {
    const r = chooseRequirement(o, policy);
    return r.ok ? "ok" : r.reason;
  };
  assert.equal(refusal([offer({ scheme: "upto" })]), "unsupported_scheme");
  assert.equal(refusal([offer({ network: "eip155:8453" })]), "unsupported_network");
  assert.equal(refusal([offer({ asset: "0x000000000000000000000000000000000000a11e" })]), "unsupported_asset");
  assert.equal(refusal([offer({ extra: { name: "USDC", version: "2", assetTransferMethod: "permit2" } })]), "unsupported_asset");
  assert.equal(refusal([offer({ payTo: "merchant" })]), "unsupported_recipient");
  assert.equal(refusal([offer({ payTo: `0x${"0".repeat(40)}` })]), "unsupported_recipient");
  assert.equal(refusal([offer({ extra: {} })]), "malformed");
  assert.equal(refusal([offer({ extra: { name: "U".repeat(40), version: "2" } })]), "malformed");
  assert.equal(refusal([offer({ amount: "0" })]), "malformed");
  assert.equal(refusal([offer({ amount: "-5" })]), "malformed");
  assert.equal(refusal([offer({ amount: "1e6" })]), "malformed");
  assert.equal(refusal([offer({ amount: "999999999999999999999" })]), "malformed");
  assert.equal(refusal([offer()]), "ok");
});

test("the token address is matched case-insensitively but only against the pinned contract", () => {
  assert.equal(chooseRequirement([offer({ asset: USDC.toLowerCase() })], policy).ok, true);
  assert.equal(chooseRequirement([offer({ asset: USDC.toUpperCase().replace("0X", "0x") })], policy).ok, true);
});

test("an offer over the per-payment cap is refused with its price", () => {
  const result = chooseRequirement([offer({ amount: "250001" })], policy);
  assert.deepEqual(result, { ok: false, reason: "too_expensive", amount: 250_001 });
  assert.equal(chooseRequirement([offer({ amount: "250000" })], policy).ok, true);
});

test("a mainnet offer is not accepted on the test network, and the reverse", () => {
  assert.equal(chooseRequirement([offer({ network: NETWORKS.base.caip2, asset: NETWORKS.base.usdc })], policy).ok, false);
  assert.equal(chooseRequirement([offer({ network: NETWORKS.base.caip2, asset: NETWORKS.base.usdc })], { network: "base", maxAmount: 250_000 }).ok, true);
  assert.equal(chooseRequirement([offer()], { network: "base", maxAmount: 250_000 }).ok, false);
});

// ------------------------------------------------------------------ what is signed and sent

function accepted() {
  const r = chooseRequirement([offer()], policy);
  assert.ok(r.ok);
  return r.accepted;
}

test("the authorization is for exactly the offer, valid for at most two minutes", () => {
  const nowMs = Date.parse("2026-10-12T10:00:00Z");
  const a = buildAuthorization({ from: FROM, accepted: accepted(), nowMs, nonce: NONCE });
  const now = nowMs / 1000;
  assert.deepEqual(a, { from: FROM, to: PAY_TO, value: "50000", validAfter: String(now - 60), validBefore: String(now + 60), nonce: NONCE });
  // The seller's own (long) timeout never stretches it past two minutes.
  const long = chooseRequirement([offer({ maxTimeoutSeconds: 3600 })], policy);
  assert.ok(long.ok);
  assert.equal(Number(buildAuthorization({ from: FROM, accepted: long.accepted, nowMs, nonce: NONCE }).validBefore) - now, 120);
  assert.throws(() => buildAuthorization({ from: "nope", accepted: accepted(), nowMs, nonce: NONCE }));
  assert.throws(() => buildAuthorization({ from: FROM, accepted: accepted(), nowMs, nonce: "0x12" }));
});

test("the typed data is EIP-3009 on Doddy's chain and Doddy's pinned token, whatever the seller says", () => {
  const a = buildAuthorization({ from: FROM, accepted: accepted(), nowMs: 1_000_000_000_000, nonce: NONCE });
  const typed = transferTypedData("base-sepolia", accepted(), a);
  assert.deepEqual(typed.domain, { name: "USDC", version: "2", chainId: 84532, verifyingContract: USDC });
  assert.equal(typed.primaryType, "TransferWithAuthorization");
  assert.deepEqual(typed.types.TransferWithAuthorization!.map((f) => `${f.type} ${f.name}`), [
    "address from", "address to", "uint256 value", "uint256 validAfter", "uint256 validBefore", "bytes32 nonce",
  ]);
  assert.deepEqual(typed.message, a);
});

test("the PAYMENT-SIGNATURE header carries the seller's own offer and the signed authorization", () => {
  const parsed = parsePaymentRequired({ headers: {}, body: JSON.stringify(required([offer()])) });
  assert.ok(parsed.ok);
  const acc = chooseRequirement(parsed.value.accepts, policy);
  assert.ok(acc.ok);
  const a = buildAuthorization({ from: FROM, accepted: acc.accepted, nowMs: 1_000_000_000_000, nonce: NONCE });
  const header = paymentSignatureHeader({ required: parsed.value, accepted: acc.accepted, authorization: a, signature: `0x${"22".repeat(65)}` });
  const decoded = JSON.parse(Buffer.from(header, "base64").toString("utf8"));
  assert.equal(decoded.x402Version, 2);
  assert.deepEqual(decoded.accepted, offer());
  assert.deepEqual(decoded.resource, { url: "https://shop.example/a" });
  assert.deepEqual(decoded.payload, { signature: `0x${"22".repeat(65)}`, authorization: a });
});

// ------------------------------------------------------------------ the seller's receipt

const TX = `0x${"ab".repeat(32)}`;
const settle = (body: unknown, header = "payment-response") => confirmSettlement({ [header]: b64(body) }, { network: "base-sepolia", from: FROM });

test("only a successful, well-formed settlement for this network and wallet counts as paid", () => {
  const good = { success: true, transaction: TX, network: "eip155:84532" };
  assert.deepEqual(settle(good), { transaction: TX, payer: null });
  assert.deepEqual(settle({ ...good, payer: FROM.toUpperCase().replace("0X", "0x") }), { transaction: TX, payer: FROM.toUpperCase().replace("0X", "0x") });
  assert.deepEqual(settle(good, "x-payment-response"), { transaction: TX, payer: null });

  assert.equal(settle({ ...good, success: false }), null);
  assert.equal(settle({ ...good, success: "true" }), null);
  assert.equal(settle({ ...good, transaction: "" }), null);
  assert.equal(settle({ ...good, transaction: "0x1234" }), null);
  assert.equal(settle({ ...good, network: "eip155:8453" }), null);
  assert.equal(settle({ ...good, network: undefined }), null);
  assert.equal(settle({ ...good, payer: "0x1111111111111111111111111111111111111111" }), null);
  assert.equal(confirmSettlement({}, { network: "base-sepolia", from: FROM }), null);
  assert.equal(confirmSettlement({ "payment-response": "garbage" }, { network: "base-sepolia", from: FROM }), null);
});
