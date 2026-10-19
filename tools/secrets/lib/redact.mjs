// Fingerprints and redaction. A fingerprint is the first 8 hex characters of the value's SHA-256:
// enough to tell two values apart in a plan, too short to be useful for guessing a long key.
import { createHash } from "node:crypto";

export function fingerprint(value) {
  return createHash("sha256").update(value, "utf8").digest("hex").slice(0, 8);
}

/** Replaces every known secret (raw, JSON-escaped and URI-encoded) in a message with [redacted]. */
export function redactor(values) {
  const forms = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length < 4) continue;
    forms.add(value);
    forms.add(JSON.stringify(value).slice(1, -1));
    forms.add(encodeURIComponent(value));
  }
  const sorted = [...forms].sort((a, b) => b.length - a.length);
  return (message) => {
    let text = String(message);
    for (const form of sorted) text = text.split(form).join("[redacted]");
    return text;
  };
}
