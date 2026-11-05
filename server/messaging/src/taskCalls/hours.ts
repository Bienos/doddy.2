// Calling hours: the whole call (ringing + approved maximum + the goodbye margin) must fit inside
// 8:00–23:00 Warsaw time on one day, so nobody picks up only to be cut off at 23:00. Every day of
// the week for now (open question in docs/decisions/calls.md). Uses the IANA zone, so the
// daylight-saving changes are handled by the runtime's time-zone data.

export const CALL_ZONE = "Europe/Warsaw";
export const DAY_START_MINUTES = 8 * 60;
export const DAY_END_MINUTES = 23 * 60;
/** "08:00"-style text of a minute-of-day, for the availability answer. */
export const clockText = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
/** How long the phone rings before Twilio gives up. */
export const RING_SECS = 25;
/** Room after the approved maximum for the goodbye; also Twilio's backstop margin. */
export const GRACE_SECS = 20;

const parts = new Intl.DateTimeFormat("en-GB", {
  timeZone: CALL_ZONE, year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
});

/** Local calendar day and seconds since local midnight in Warsaw. */
export function warsawClock(at: Date): { day: string; seconds: number } {
  const p = Object.fromEntries(parts.formatToParts(at).map((x) => [x.type, x.value]));
  return { day: `${p.year}-${p.month}-${p.day}`, seconds: Number(p.hour) * 3600 + Number(p.minute) * 60 + Number(p.second) };
}

/** True when a call dialled at `start` and lasting at most `maxDurationSecs` stays inside the hours. */
export function callFits(start: Date, maxDurationSecs: number, ringSecs = RING_SECS): boolean {
  const end = new Date(start.getTime() + (ringSecs + maxDurationSecs + GRACE_SECS) * 1000);
  const a = warsawClock(start);
  const b = warsawClock(end);
  return a.day === b.day && a.seconds >= DAY_START_MINUTES * 60 && b.seconds <= DAY_END_MINUTES * 60;
}
