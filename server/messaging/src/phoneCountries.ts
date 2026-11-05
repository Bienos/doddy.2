// Which countries' phone numbers may be verified, texted and called (security review 4 Nov 2026, ADR-704).
// Without a list, anyone could verify a premium-rate number abroad and have Doddy text and call it from many
// accounts (SMS pumping, toll fraud). The list is calling codes without the "+", set by PHONE_ALLOWED_COUNTRY_CODES.

/** Poland, the rest of the EU and EEA, the UK and Switzerland. The owner can change it (env), see ADR-704. */
export const DEFAULT_ALLOWED_COUNTRY_CODES: readonly string[] = [
  "30", "31", "32", "33", "34", "351", "352", "353", "354", "356", "357", "358", "359", "36", "370", "371", "372",
  "385", "386", "39", "40", "41", "420", "421", "423", "43", "44", "45", "46", "47", "48", "49",
];

const CODE = /^[1-9][0-9]{0,2}$/;

/**
 * Reads "48,49,351" into calling codes. Throws on anything that is not a calling code, and on a list in which one
 * entry begins another ("42" next to "420"): real calling codes never do, so such a list holds a typo that would
 * let a whole range of countries through.
 */
export function parseCountryCodes(raw: string): string[] {
  const codes = raw.split(",").map((c) => c.trim().replace(/^\+/, "")).filter(Boolean);
  if (codes.length === 0) throw new Error("PHONE_ALLOWED_COUNTRY_CODES needs at least one calling code");
  for (const c of codes) {
    if (!CODE.test(c)) throw new Error(`PHONE_ALLOWED_COUNTRY_CODES: "${c}" is not a calling code (1 to 3 digits, no leading 0)`);
  }
  const unique = [...new Set(codes)];
  for (const a of unique) {
    for (const b of unique) {
      if (a !== b && b.startsWith(a)) throw new Error(`PHONE_ALLOWED_COUNTRY_CODES: "${a}" is the start of "${b}"; calling codes never overlap`);
    }
  }
  return unique;
}

/**
 * True when the E.164 number starts with one of the allowed calling codes. Calling codes are prefix-free, so a
 * number has one calling code and only that code decides: +3598... is Bulgaria (359), +4251... is nothing
 * (no 425, and 42 is not a code), +380... is Ukraine and not Croatia or Slovenia (385, 386).
 */
export function isAllowedNumber(e164: string, allowed: readonly string[]): boolean {
  if (!/^\+[1-9][0-9]{6,14}$/.test(e164)) return false;
  const digits = e164.slice(1);
  // parseCountryCodes refuses a list where one code begins another, so at most one entry can match.
  return [1, 2, 3].some((len) => allowed.includes(digits.slice(0, len)));
}
