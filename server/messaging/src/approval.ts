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
