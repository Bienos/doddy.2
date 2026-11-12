// Shared by the brief and the booking (kept apart so neither imports the other's module while it loads).

/** Collapses whitespace and removes control and format characters (including bidi overrides). */
export function clean(value: string): string {
  return value.normalize("NFC").replace(/[\p{Cc}\p{Cf}]/gu, " ").replace(/\s+/g, " ").trim();
}
