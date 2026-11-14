import { createHash } from "node:crypto";
import type { BookingSource, GroundedReading, TravelBooking } from "./schema.js";

/**
 * Many emails, one booking. Seen in real mail (11 Nov 2026): Ryanair sent a second confirmation for the
 * same reference with a different flight; Booking.com sent "awaiting confirmation", then "failed" and a
 * refund for one flight booking, and "confirmed" for the next; a stay was cancelled for an invalid card
 * minutes before it was booked again under a new number; hosts' messages repeat the confirmation number.
 *
 * Rules:
 *  - emails are grouped by the booking reference (case and spaces ignored), not by the seller's name: a
 *    check-in reminder often doesn't name the airline. An email without a reference that is in its text
 *    is left out (ground.ts already refuses to call it confirmed);
 *  - the state is the newest decisive email's: cancelled, failed, pending (waiting), confirmed (booked) or
 *    changed. Reminders, messages and "other" never change the state;
 *  - the facts come from the newest email that confirmed or changed the booking. Later reminders and
 *    messages don't overwrite them; a pending or failed group shows what its newest email said;
 *  - a group with no decisive email at all (only reminders or messages) is not a booking Doddy can vouch for
 *    and is left out;
 *  - "not_travel" readings (a restaurant table, a concert ticket) are left out.
 */
export interface ReadEmail {
  messageId: string;
  receivedAt: string;
  senderDomain: string;
  reading: GroundedReading;
}

const DECISIVE = new Set(["confirmed", "changed", "cancelled", "pending", "failed"]);
const STATE: Record<string, TravelBooking["state"]> = {
  confirmed: "booked", changed: "changed", cancelled: "cancelled", pending: "waiting", failed: "failed",
};

const groupKey = (r: GroundedReading) => (r.reference ?? "").toUpperCase().replace(/\s+/g, "");

export function mergeBookings(emails: readonly ReadEmail[]): TravelBooking[] {
  const groups = new Map<string, ReadEmail[]>();
  for (const e of emails) {
    if (e.reading.kind === "not_travel" || e.reading.reference === null) continue;
    const key = groupKey(e.reading);
    groups.set(key, [...(groups.get(key) ?? []), e]);
  }

  const out: TravelBooking[] = [];
  for (const [key, group] of groups) {
    const byTime = [...group].sort((a, b) => a.receivedAt.localeCompare(b.receivedAt) || a.messageId.localeCompare(b.messageId));
    const decisive = byTime.filter((e) => DECISIVE.has(e.reading.status));
    const last = decisive.at(-1);
    if (!last) continue;
    const factSource = [...byTime].reverse().find((e) => e.reading.status === "confirmed" || e.reading.status === "changed") ?? last;
    const r = factSource.reading;
    const provider = [...byTime].reverse().map((e) => e.reading.provider).find((p) => p !== null) ?? null;
    if (r.kind === "not_travel") continue;
    const sources: BookingSource[] = byTime.map((e) => ({
      messageId: e.messageId, receivedAt: e.receivedAt, senderDomain: e.senderDomain, status: e.reading.status,
    }));
    out.push({
      id: createHash("sha256").update(key).digest("hex").slice(0, 16),
      kind: r.kind,
      state: STATE[last.reading.status]!,
      provider: r.provider ?? provider,
      reference: r.reference,
      facts: {
        segments: r.segments, stay: r.stay, destination: r.destination, bags: r.bags, total: r.total,
        freeCancellationUntil: r.freeCancellationUntil, nonRefundable: r.nonRefundable, payOnSite: r.payOnSite,
        deposit: r.deposit, notes: r.notes,
      },
      sources,
    });
  }
  return out.sort((a, b) => firstDate(a).localeCompare(firstDate(b)) || a.id.localeCompare(b.id));
}

/** The booking's first day, for ordering ("9999" when it has none). */
export function firstDate(b: TravelBooking): string {
  const dates = [
    ...b.facts.segments.map((s) => s.departDate),
    b.facts.stay?.checkInDate ?? null,
  ].filter((d): d is string => d !== null);
  return dates.sort()[0] ?? "9999-12-31";
}
