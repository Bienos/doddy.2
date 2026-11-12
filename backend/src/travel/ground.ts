import { appearsIn, groundDate, groundMoney, groundTime } from "./evidence.js";
import type { GroundedReading, GroundedSegment, GroundedStay, TravelReading } from "./schema.js";

const CANCEL_WORDS = /cancel|anulow|odwołan|storn/i;
const FAILED_WORDS = /fail|didn.t go through|could ?n.t book|nie powiodł|nieudan|nie udało/i;

/**
 * Keep only what the email says (DOD-02). Every name, code and reference must appear in the email's text;
 * every date, time and amount must appear as written and mean the value given. What fails is set to null
 * (or left out of a list) and its path is recorded in `dropped`. Kind and status are closed lists and are
 * kept, but a "confirmed" reading whose reference isn't in the email is treated as "other": the app never
 * shows a booking as made on the reader's word alone (DOD-08).
 */
export function groundReading(reading: TravelReading, text: string, emailYear: number): GroundedReading {
  const dropped: string[] = [];
  const keep = (path: string, value: string | null): string | null => {
    if (value === null) return null;
    if (appearsIn(text, value)) return value.trim();
    dropped.push(path);
    return null;
  };
  const date = (path: string, ev: Parameters<typeof groundDate>[1]) => {
    if (!ev) return null;
    const v = groundDate(text, ev, emailYear);
    if (v === null) dropped.push(path);
    return v;
  };
  const time = (path: string, value: string | null) => {
    if (value === null) return null;
    const v = groundTime(text, value);
    if (v === null) dropped.push(path);
    return v;
  };
  const money = (path: string, ev: Parameters<typeof groundMoney>[1]) => {
    if (!ev) return null;
    const v = groundMoney(text, ev);
    if (v === null) dropped.push(path);
    return v;
  };
  const code = (path: string, value: string | null) => {
    if (value === null) return null;
    const upper = value.toUpperCase();
    // An airport code counts only as a whole word ("KRK", "(BRS)"), never inside another word.
    if (new RegExp(`(^|[^A-Za-z])${upper}($|[^A-Za-z])`).test(text)) return upper;
    dropped.push(path);
    return null;
  };

  const segments: GroundedSegment[] = reading.segments.map((s, i) => {
    const p = `segments.${i}`;
    return {
      carrier: keep(`${p}.carrier`, s.carrier),
      number: keep(`${p}.number`, s.number),
      from: { code: code(`${p}.from.code`, s.from.code), name: keep(`${p}.from.name`, s.from.name) },
      to: { code: code(`${p}.to.code`, s.to.code), name: keep(`${p}.to.name`, s.to.name) },
      departDate: date(`${p}.departDate`, s.departDate),
      departTime: time(`${p}.departTime`, s.departTime),
      arriveDate: date(`${p}.arriveDate`, s.arriveDate),
      arriveTime: time(`${p}.arriveTime`, s.arriveTime),
    };
  });

  const stay: GroundedStay | null = reading.stay
    ? {
        name: keep("stay.name", reading.stay.name),
        address: keep("stay.address", reading.stay.address),
        city: keep("stay.city", reading.stay.city),
        checkInDate: date("stay.checkInDate", reading.stay.checkInDate),
        checkInTime: time("stay.checkInTime", reading.stay.checkInTime),
        checkOutDate: date("stay.checkOutDate", reading.stay.checkOutDate),
        checkOutTime: time("stay.checkOutTime", reading.stay.checkOutTime),
        guests: keep("stay.guests", reading.stay.guests),
      }
    : null;

  const reference = keep("reference", reading.reference);
  let status = reading.status;
  if ((status === "confirmed" || status === "changed") && reference === null) {
    dropped.push("status");
    status = "other";
  }
  // Ending a booking takes the email's own words for it. This doesn't stop a host's message that quotes
  // such words (a known gap, TRAVEL_EMAILS.md); the app shows a cancelled booking with its email to check.
  if (status === "cancelled" && !CANCEL_WORDS.test(text)) { dropped.push("status"); status = "other"; }
  if (status === "failed" && !FAILED_WORDS.test(text)) { dropped.push("status"); status = "other"; }

  const freeDate = reading.freeCancellationUntil ? date("freeCancellationUntil.date", reading.freeCancellationUntil.date) : null;
  const deposit = reading.deposit ? money("deposit.money", reading.deposit.money) : null;

  return {
    kind: reading.kind,
    status,
    provider: keep("provider", reading.provider),
    reference,
    segments,
    stay,
    destination: reading.destination
      ? { city: keep("destination.city", reading.destination.city), country: keep("destination.country", reading.destination.country) }
      : null,
    bags: reading.bags.filter((b, i) => keep(`bags.${i}`, b) !== null),
    total: money("total", reading.total),
    freeCancellationUntil: freeDate && reading.freeCancellationUntil
      ? { date: freeDate, time: time("freeCancellationUntil.time", reading.freeCancellationUntil.time) }
      : null,
    // A yes/no can't be found word for word; it is kept only next to words that say it.
    nonRefundable: reading.nonRefundable === true && !/non-?refundable|bezzwrotn|nie podlega zwrotowi|no refund/i.test(text)
      ? (dropped.push("nonRefundable"), null)
      : reading.nonRefundable,
    payOnSite: reading.payOnSite.flatMap((item, i) => {
      const m = money(`payOnSite.${i}.money`, item.money);
      const what = keep(`payOnSite.${i}.what`, item.what);
      return m && what ? [{ what, amount: m.amount, currency: m.currency }] : [];
    }),
    deposit: deposit && reading.deposit ? { ...deposit, when: keep("deposit.when", reading.deposit.when) } : null,
    notes: reading.notes.filter((n, i) => keep(`notes.${i}`, n) !== null),
    dropped,
  };
}
