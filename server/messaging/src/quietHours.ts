// Quiet hours (ADR-490 unit U4, ADR-495): no scheduled call rings inside them, in the user's own
// time zone, unless the user switched on "Call even in quiet hours" on that call's card. Times are
// read on the wall clock of the zone through Intl, so a day that changes between summer and
// winter time is handled by the platform's time zone data, not by arithmetic here.

/** Minutes after local midnight. A window whose start is after its end crosses midnight. */
export interface QuietHours { start: number; end: number }

/** Mirrored in docs/trust/config/doddy_rules.yaml (contact_policy.quiet_hours_default). */
export const QUIET_HOURS_DEFAULT: QuietHours = { start: 21 * 60, end: 8 * 60 };
/** Used when the iPhone hasn't told the server its zone yet. */
export const DEFAULT_TIME_ZONE = "Europe/Warsaw";

/** "HH:MM" (24-hour) to minutes after midnight; undefined for anything else. */
export function parseClock(text: string): number | undefined {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(text);
  return m ? Number(m[1]) * 60 + Number(m[2]) : undefined;
}

export const formatClock = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;

/** An IANA zone name this server's time zone data knows, such as Europe/Warsaw. */
export function isValidTimeZone(zone: string): boolean {
  if (!zone || zone.length > 64 || !/^[A-Za-z0-9_+\-/]+$/.test(zone)) return false;
  try {
    new Intl.DateTimeFormat("en-GB", { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

/** The wall-clock time of `at` in `zone`, as minutes after midnight. */
export function localMinutes(at: Date, zone: string): number {
  const parts = new Intl.DateTimeFormat("en-GB", { timeZone: zone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
    .formatToParts(at);
  const value = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? "0");
  return value("hour") * 60 + value("minute");
}

export function inQuietHours(at: Date, zone: string, quiet: QuietHours = QUIET_HOURS_DEFAULT): boolean {
  if (quiet.start === quiet.end) return false;
  const m = localMinutes(at, zone);
  return quiet.start < quiet.end ? m >= quiet.start && m < quiet.end : m >= quiet.start || m < quiet.end;
}

/** "18:05" in `zone`, for notifications about a call. */
export const localClock = (at: Date, zone: string) => formatClock(localMinutes(at, zone));
