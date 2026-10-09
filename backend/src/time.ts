/**
 * Local calendar-day boundaries in an explicit IANA time zone.
 *
 * "Tomorrow" is the next local calendar date, from its local start of day to the next local
 * start of day — never "now + 24 h". Days can be 23 h or 25 h long (DST), can start at 01:00
 * when midnight is skipped, and can even be skipped entirely (Pacific/Apia, 30 Dec 2011).
 */

/**
 * IANA names only ("Europe/Warsaw", "UTC"). Offsets ("+02:00") and abbreviations ("PST", "CEST")
 * are refused even where the runtime would accept them, so the zone is always explicit.
 */
export function isSupportedTimeZone(tz: string): boolean {
  if (tz !== "UTC" && !/^[A-Za-z]+(?:\/[A-Za-z0-9_+-]+){1,2}$/.test(tz)) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

const DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

export function isValidDateString(date: string): boolean {
  const m = DATE.exec(date);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const t = new Date(Date.UTC(y, mo - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === mo - 1 && t.getUTCDate() === d;
}

const formatters = new Map<string, Intl.DateTimeFormat>();
function formatter(tz: string): Intl.DateTimeFormat {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
    formatters.set(tz, f);
  }
  return f;
}

/** Local wall-clock time of an instant, expressed as if it were UTC milliseconds. */
function wallClockMs(instantMs: number, tz: string): number {
  const parts: Record<string, number> = {};
  for (const p of formatter(tz).formatToParts(new Date(instantMs))) {
    if (p.type !== "literal") parts[p.type] = Number(p.value);
  }
  return Date.UTC(parts.year!, parts.month! - 1, parts.day!, parts.hour!, parts.minute!, parts.second!);
}

/** Offset of the zone from UTC at an instant, in milliseconds (local = UTC + offset). */
export function offsetMs(instantMs: number, tz: string): number {
  const whole = Math.floor(instantMs / 1000) * 1000;
  return wallClockMs(whole, tz) - whole;
}

export function localDate(instantMs: number, tz: string): string {
  return new Date(wallClockMs(instantMs, tz)).toISOString().slice(0, 10);
}

export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split("-").map(Number) as [number, number, number];
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

const HOUR = 3_600_000;

/** First instant whose local date is `date` or later. */
export function startOfLocalDay(date: string, tz: string): number {
  const [y, m, d] = date.split("-").map(Number) as [number, number, number];
  const wall = Date.UTC(y, m - 1, d);
  // Midnight exists: one of the surrounding offsets maps it back to itself. Take the earliest match.
  const offsets = new Set([offsetMs(wall - 36 * HOUR, tz), offsetMs(wall, tz), offsetMs(wall + 36 * HOUR, tz)]);
  const matches = [...offsets].map((o) => wall - o).filter((t) => wallClockMs(t, tz) === wall);
  if (matches.length > 0) return Math.min(...matches);
  // Midnight was skipped (DST gap at 00:00, or a whole skipped date): find the transition instant.
  let lo = wall - 30 * HOUR;
  let hi = wall + 30 * HOUR;
  while (hi - lo > 1000) {
    const mid = lo + Math.floor((hi - lo) / 2000) * 1000;
    if (localDate(mid, tz) >= date) hi = mid;
    else lo = mid;
  }
  return hi;
}

export interface DayWindow {
  date: string;
  timeZone: string;
  startMs: number;
  endMs: number;
}

export function localDayWindow(date: string, tz: string): DayWindow {
  return { date, timeZone: tz, startMs: startOfLocalDay(date, tz), endMs: startOfLocalDay(addDays(date, 1), tz) };
}

/** RFC 3339 with the zone's offset at that instant, e.g. 2026-10-10T00:00:00+02:00. */
export function rfc3339Local(instantMs: number, tz: string): string {
  const offset = offsetMs(instantMs, tz);
  const local = new Date(instantMs + offset).toISOString().slice(0, 19);
  const sign = offset < 0 ? "-" : "+";
  const abs = Math.abs(offset) / 60_000;
  const hh = String(Math.floor(abs / 60)).padStart(2, "0");
  const mm = String(abs % 60).padStart(2, "0");
  return `${local}${sign}${hh}:${mm}`;
}
