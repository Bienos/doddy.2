// Which numbers Doddy may call for the user (v1: Poland only). An allowlist, not a blocklist:
// a number is allowed only if it is a Polish mobile, geographic or 800 freephone number. Everything
// else, including 112/997/998/999 and every short number, premium 70x and shared-cost 80x, is
// refused. Ranges from the national numbering plan (Dz.U. 2024 poz. 1862); docs/decisions/calls.md.

export type DestinationKind = "mobile" | "geographic" | "freephone";
export type DestinationRefusal =
  | "not_a_number"   // letters, empty, or a shape that is no phone number
  | "short_number"   // emergency and service numbers: 112, 997, 998, 999, 116 xxx, 118 xx, 19 xxx...
  | "foreign"        // not +48
  | "premium"        // 70x
  | "shared_cost"    // 801, 804
  | "special"        // 39 (VoIP), 64 (paging), other 80x, government networks 26 and 47
  | "unknown_range"; // a 9-digit number in no allowed range

export type Destination =
  | { ok: true; e164: string; national: string; kind: DestinationKind }
  | { ok: false; reason: DestinationRefusal };

/** Two-digit mobile prefixes. */
export const MOBILE_PREFIXES: ReadonlySet<string> = new Set(["45", "50", "51", "53", "57", "60", "66", "69", "72", "73", "78", "79", "88"]);

/** Two-digit geographic area codes, without 26 (Ministry of Defence) and 47 (Ministry of the Interior). */
export const GEOGRAPHIC_PREFIXES: ReadonlySet<string> = new Set([
  "12", "13", "14", "15", "16", "17", "18", "22", "23", "24", "25", "29", "32", "33", "34", "41", "42", "43", "44",
  "46", "48", "52", "54", "55", "56", "58", "59", "61", "62", "63", "65", "67", "68", "71", "74", "75", "76", "77",
  "81", "82", "83", "84", "85", "86", "87", "89", "91", "94", "95",
]);

/**
 * Reads a number however the user typed it ("600 100 200", "+48 (22) 123-45-67", "0048...") and
 * says whether Doddy may call it. Never guesses: anything ambiguous is refused.
 */
export function classifyDestination(input: string): Destination {
  if (typeof input !== "string" || input.length > 40) return { ok: false, reason: "not_a_number" };
  const compact = input.trim().replace(/[\s\-.()/ ]/g, "");
  if (!/^\+?[0-9]+$/.test(compact)) return { ok: false, reason: "not_a_number" };

  let national: string;
  if (compact.startsWith("+")) {
    if (!compact.startsWith("+48")) return { ok: false, reason: "foreign" };
    national = compact.slice(3);
  } else if (compact.startsWith("00")) {
    if (!compact.startsWith("0048")) return { ok: false, reason: "foreign" };
    national = compact.slice(4);
  } else if (compact.length === 11 && compact.startsWith("48")) {
    national = compact.slice(2);
  } else {
    national = compact;
  }

  // Short numbers (emergency 112, 997, 998, 999; 116 xxx; 118 xx; 19 xxx; 986...) are shorter than
  // nine digits, whatever prefix was put in front of them.
  if (national.length < 9) return { ok: false, reason: national.length === 0 ? "not_a_number" : "short_number" };
  if (national.length > 9) return { ok: false, reason: "not_a_number" };

  const two = national.slice(0, 2);
  const three = national.slice(0, 3);
  if (three === "800") return allowed(national, "freephone");
  if (two === "70") return { ok: false, reason: "premium" };
  if (three === "801" || three === "804") return { ok: false, reason: "shared_cost" };
  if (two === "80" || two === "39" || two === "64" || two === "26" || two === "47") return { ok: false, reason: "special" };
  if (MOBILE_PREFIXES.has(two)) return allowed(national, "mobile");
  if (GEOGRAPHIC_PREFIXES.has(two)) return allowed(national, "geographic");
  return { ok: false, reason: "unknown_range" };
}

function allowed(national: string, kind: DestinationKind): Destination {
  return { ok: true, e164: `+48${national}`, national, kind };
}

/** "+48600100200" → "600 100 200" (mobile and 800) or "22 123 45 67" (geographic), for the card. */
export function formatPolish(e164: string): string {
  const n = e164.replace(/^\+48/, "");
  if (n.length !== 9) return e164;
  if (GEOGRAPHIC_PREFIXES.has(n.slice(0, 2)) && !MOBILE_PREFIXES.has(n.slice(0, 2))) {
    return `${n.slice(0, 2)} ${n.slice(2, 5)} ${n.slice(5, 7)} ${n.slice(7)}`;
  }
  return `${n.slice(0, 3)} ${n.slice(3, 6)} ${n.slice(6)}`;
}
