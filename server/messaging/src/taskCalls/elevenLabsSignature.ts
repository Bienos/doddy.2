// ElevenLabs webhook signature: header `ElevenLabs-Signature: t=<unix seconds>,v0=<hex>` where hex is
// HMAC-SHA256(secret, `${t}.${rawBody}`) (the official JS SDK's constructEvent). Checked on the raw
// bytes before anything is parsed. Stricter than the SDK: constant-time comparison, and a future
// timestamp is refused too.
import { hmacSha256, sameBytes } from "../crypto.js";

export const SIGNATURE_TOLERANCE_SECS = 30 * 60;
const FUTURE_SKEW_SECS = 5 * 60;

export function isValidElevenLabsSignature(secret: string, header: string | undefined, rawBody: Buffer, nowMs = Date.now()): boolean {
  if (!header || header.length > 512) return false;
  const parts = header.split(",").map((p) => p.trim());
  const t = parts.find((p) => p.startsWith("t="))?.slice(2);
  const v0 = parts.find((p) => p.startsWith("v0="))?.slice(3);
  if (!t || !/^\d{1,12}$/.test(t) || !v0 || !/^[0-9a-f]{64}$/.test(v0)) return false;
  const age = nowMs / 1000 - Number(t);
  if (age > SIGNATURE_TOLERANCE_SECS || age < -FUTURE_SKEW_SECS) return false;
  const expected = hmacSha256(Buffer.from(secret, "utf8"), Buffer.concat([Buffer.from(`${t}.`, "utf8"), rawBody]));
  return sameBytes(expected, Buffer.from(v0, "hex"));
}

/** For tests and the harness: the header ElevenLabs would send. */
export function signElevenLabs(secret: string, rawBody: string, nowMs = Date.now()): string {
  const t = Math.floor(nowMs / 1000);
  return `t=${t},v0=${hmacSha256(Buffer.from(secret, "utf8"), `${t}.${rawBody}`).toString("hex")}`;
}
