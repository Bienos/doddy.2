// The countries Doddy texts and calls (SMS_ALLOWED_CALLING_CODES). Checked before a verify code is
// sent, before a text is handed to Twilio and before "call me now" dials.

/** True when the digits after "+" start with one of `codes` (E.164 country calling codes). The longest
 * codes are tried first, and only a whole listed code counts: "+42…" matches neither 420 nor 421. */
export function hasAllowedCallingCode(e164: string, codes: readonly string[]): boolean {
  if (!/^\+[1-9][0-9]{6,14}$/.test(e164)) return false;
  const digits = e164.slice(1);
  return [...codes].sort((a, b) => b.length - a.length).some((code) => digits.startsWith(code));
}
