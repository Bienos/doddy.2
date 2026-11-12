// A booking Doddy may make on a call (decision docs/decisions/2026-11-12-book-agent.md). The person
// approves these exact details on the card; every sentence that names them is built here, in code, so
// the model never phrases what is being booked. The booking agent may accept exactly this booking by
// saying `confirmLine` and nothing else; result.ts checks that it did and that it said no other
// commitment.
import { z } from "zod";
import { clean } from "./clean.js";

const NAME = /^[\p{L}][\p{L}\p{M} '’.\-]{0,59}$/u;
const text = (max: number) => z.string().min(1).max(max * 2).transform(clean).pipe(z.string().min(1).max(max));

/** What the card shows and the call may accept. At least a service or a party size. */
export const bookingSchema = z.strictObject({
  /** The name the booking is under, as the person wants it said ("Anna Kowalska"). */
  name: text(60).pipe(z.string().regex(NAME)),
  /** The day, in Warsaw time. */
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(validDate, "invalid_date"),
  /** The start time, 24-hour, in Warsaw time. */
  time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
  /** "stolik", "strzyżenie męskie", "manicure hybrydowy"… */
  service: text(80).optional(),
  partySize: z.number().int().min(1).max(20).optional(),
}).refine((b) => b.service !== undefined || b.partySize !== undefined, { message: "service_or_party_size", path: ["service"] });

export type Booking = z.infer<typeof bookingSchema>;

/** How far ahead Doddy books: today (Warsaw) up to this many days. */
export const BOOK_DAYS_AHEAD = 60;

function validDate(value: string): boolean {
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y!, m! - 1, d!));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m! - 1 && date.getUTCDate() === d;
}

/** Today's date in Warsaw, as YYYY-MM-DD. */
export function warsawToday(now: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Warsaw", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

/** Whether the booking's day is today or later, and not more than BOOK_DAYS_AHEAD days away. */
export function bookingDateAllowed(b: Booking, now: Date): boolean {
  const today = warsawToday(now);
  if (b.date < today) return false;
  const [y, m, d] = today.split("-").map(Number);
  const last = new Date(Date.UTC(y!, m! - 1, d! + BOOK_DAYS_AHEAD)).toISOString().slice(0, 10);
  return b.date <= last;
}

const WEEKDAY = ["niedziela", "poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota"];
/** "w piątek", "we wtorek", "w środę": the day after the preposition (accusative). */
const ON_WEEKDAY = ["w niedzielę", "w poniedziałek", "we wtorek", "w środę", "w czwartek", "w piątek", "w sobotę"];
const MONTH = ["stycznia", "lutego", "marca", "kwietnia", "maja", "czerwca", "lipca", "sierpnia", "września", "października", "listopada", "grudnia"];

function parts(date: string) {
  const [y, m, d] = date.split("-").map(Number);
  const weekday = new Date(Date.UTC(y!, m! - 1, d!)).getUTCDay();
  return { year: y!, day: d!, month: MONTH[m! - 1]!, weekday };
}

/** "stolik dla 2 osób", "strzyżenie męskie", "strzyżenie dla 1 osoby". */
export function bookingWhat(b: Booking): string {
  const people = b.partySize === undefined ? "" : `dla ${b.partySize} ${b.partySize === 1 ? "osoby" : "osób"}`;
  if (b.service && people) return `${b.service} ${people}`;
  return b.service ?? `stolik ${people}`;
}

/** "piątek 14 listopada, 19:00" */
export function bookingWhen(b: Booking): string {
  const p = parts(b.date);
  return `${WEEKDAY[p.weekday]} ${p.day} ${p.month}, ${b.time}`;
}

/** The question asked word for word after the AI disclosure. */
export function bookingQuestion(b: Booking): string {
  const p = parts(b.date);
  return `Czy mogą Państwo zarezerwować ${bookingWhat(b)} ${ON_WEEKDAY[p.weekday]} ${p.day} ${p.month} o ${b.time} na nazwisko ${b.name}?`;
}

/** The only sentence that accepts the booking. Said at most once, and only when they can book exactly this. */
export function bookingConfirmLine(b: Booking): string {
  return `Dobrze, proszę o rezerwację: ${bookingWhat(b)}, ${bookingWhen(b)}, na nazwisko ${b.name}.`;
}

/** The booking as the agent reads it, one detail per line. */
export function bookingLines(b: Booking): string {
  const p = parts(b.date);
  return [
    `- Co: ${bookingWhat(b)}`,
    `- Kiedy: ${WEEKDAY[p.weekday]} ${p.day} ${p.month} ${p.year}, ${b.time}`,
    `- Na nazwisko: ${b.name}`,
  ].join("\n");
}
