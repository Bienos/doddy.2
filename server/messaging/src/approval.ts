import { createHash } from "node:crypto";

/**
 * What an approval is bound to (ADR-490, DOD-07): SHA-256 over each field, in order, written as its
 * UTF-8 byte length in decimal, a colon, then its UTF-8 bytes. Length prefixes rather than JSON, so
 * Swift and JavaScript can't disagree on escaping. Nothing is trimmed or normalised: an approval
 * covers exactly the characters the card showed. Shared test vectors:
 * contracts/phone/approval-vectors.json (the iPhone's ApprovalHash is tested against the same file).
 */
export function approvalHash(fields: readonly string[]): Buffer {
  const hash = createHash("sha256");
  for (const field of fields) {
    const bytes = Buffer.from(field, "utf8");
    hash.update(`${bytes.length}:`, "utf8");
    hash.update(bytes);
  }
  return hash.digest();
}

export const APPROVAL_VERSION = "doddy-approval-1";

/** A text from Doddy's number to `to` (E.164), with exactly `body`. */
export const textApprovalHash = (to: string, body: string) => approvalHash([APPROVAL_VERSION, "text", to, body]);

/**
 * A call Doddy places later (ADR-495): to `to` (E.164), at `at` exactly as the app wrote it
 * (YYYY-MM-DDTHH:MM:SSZ), saying `reason`, and whether the user allowed it inside quiet hours.
 */
export const callApprovalHash = (to: string, at: string, reason: string, allowQuietHours: boolean) =>
  approvalHash([APPROVAL_VERSION, "call", to, at, reason, allowQuietHours ? "1" : "0"]);
