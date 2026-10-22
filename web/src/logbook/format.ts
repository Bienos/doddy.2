import type { Language, MessageKey } from "../i18n/messages.js";

/**
 * Dates, durations and language names for Logbook, in the page's language. Days are written
 * "2026-10-21" and are the iPhone's own local days, so they are formatted as UTC calendar days
 * and never shifted by the browser's time zone.
 */

type T = (key: MessageKey, values?: Record<string, string | number>) => string;

export interface Formats {
  /** "21 Oct" / "21 paź" */
  dayShort(iso: string): string;
  /** "Wednesday 21 October" / "środa, 21 października" */
  dayLong(iso: string): string;
  /** "Wed" / "śr." */
  weekdayShort(iso: string): string;
  weekdayShortByIndex(index: number): string;
  weekdayLongByIndex(index: number): string;
  /** "12–18 October 2026", "28 Sep – 4 Oct" */
  range(first: string, last: string, withYear?: boolean): string;
  /** "1 h 28 min", "52 min" */
  minutes(seconds: number): string;
  /** "3 min 08 s" */
  average(seconds: number): string;
  language(code: string): string;
  /** "08:00" */
  hour(hour: number): string;
  /** "08:00 to 09:00" */
  hourRange(hour: number): string;
}

const pad2 = (n: number) => String(n).padStart(2, "0");

// A Monday, to name weekdays by index.
const MONDAY = "2026-10-19";

export function makeFormats(language: Language, t: T): Formats {
  const locale = language === "pl" ? "pl-PL" : "en-GB";
  const utc = { timeZone: "UTC" } as const;
  const dayMonth = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", ...utc });
  const dayMonthLong = new Intl.DateTimeFormat(locale, { day: "numeric", month: "long", ...utc });
  const dayLongFmt = new Intl.DateTimeFormat(locale, { weekday: "long", day: "numeric", month: "long", ...utc });
  const weekdayShortFmt = new Intl.DateTimeFormat(locale, { weekday: "short", ...utc });
  const weekdayLongFmt = new Intl.DateTimeFormat(locale, { weekday: "long", ...utc });
  const dateOf = (iso: string) => new Date(`${iso}T00:00:00Z`);
  const byIndex = (index: number) => {
    const d = dateOf(MONDAY);
    d.setUTCDate(d.getUTCDate() + index);
    return d;
  };
  // The month in the form that goes after a day number ("października", not "październik").
  const monthAfterDay = (d: Date) => dayMonthLong.formatToParts(d).find((p) => p.type === "month")?.value ?? "";
  let names: Intl.DisplayNames | null = null;
  try {
    names = new Intl.DisplayNames([locale], { type: "language", fallback: "code" });
  } catch {
    names = null;
  }

  return {
    dayShort: (iso) => dayMonth.format(dateOf(iso)),
    dayLong: (iso) => dayLongFmt.format(dateOf(iso)),
    weekdayShort: (iso) => weekdayShortFmt.format(dateOf(iso)),
    weekdayShortByIndex: (index) => weekdayShortFmt.format(byIndex(index)),
    weekdayLongByIndex: (index) => weekdayLongFmt.format(byIndex(index)),
    range(first, last, withYear = false) {
      const a = dateOf(first);
      const b = dateOf(last);
      const tail = withYear ? ` ${b.getUTCFullYear()}` : "";
      if (first === last) return `${dayMonth.format(a)}${tail}`;
      if (a.getUTCMonth() === b.getUTCMonth() && a.getUTCFullYear() === b.getUTCFullYear()) {
        return `${a.getUTCDate()}–${b.getUTCDate()} ${monthAfterDay(b)}${tail}`;
      }
      return `${dayMonth.format(a)} – ${dayMonth.format(b)}${tail}`;
    },
    minutes(seconds) {
      const m = Math.round(seconds / 60);
      if (m < 60) return t("logbook.fmt.minutes", { m });
      return t("logbook.fmt.hoursMinutes", { h: Math.floor(m / 60), m: pad2(m % 60) });
    },
    average(seconds) {
      const r = Math.round(seconds);
      if (r < 60) return t("logbook.fmt.seconds", { s: r });
      return t("logbook.fmt.minSec", { m: Math.floor(r / 60), s: pad2(r % 60) });
    },
    language(code) {
      const name = names?.of(code);
      if (!name || name === code) return code;
      return name.charAt(0).toLocaleUpperCase(locale) + name.slice(1);
    },
    hour: (hour) => `${pad2(hour)}:00`,
    hourRange: (hour) => `${pad2(hour)}:00–${pad2((hour + 1) % 24)}:00`,
  };
}
