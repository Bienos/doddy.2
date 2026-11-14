import { z } from "zod";

/**
 * What the reader of one booking email must answer (TravelReading), and what is left after every value has
 * been checked against the email's own words (TravelBooking). Contract: docs/implementation/TRAVEL_EMAILS.md.
 *
 * The reader proposes; `ground.ts` keeps only what the email says. Kind and status are closed lists, so a
 * reading can't invent a new kind of thing for the app to act on.
 */

const Text = (max: number) => z.string().trim().min(1).max(max);
const NullableText = (max: number) => Text(max).nullable();

/** A date as an ISO value plus the exact words in the email it comes from. */
export const DateEvidence = z.object({ iso: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), asWritten: Text(40) }).strict();
/** An amount plus the exact words ("€ 292.21", "296.50 PLN"). */
export const MoneyEvidence = z.object({ amount: Text(20), currency: z.string().regex(/^[A-Za-z]{3}$/), asWritten: Text(40) }).strict();
const Time = z.string().regex(/^\d{1,2}:\d{2}$/).nullable();

export const BOOKING_KINDS = ["flight", "stay", "package", "train", "bus", "car_rental", "not_travel"] as const;
/**
 * confirmed: the booking is made. changed: the seller changed it (schedule change). cancelled. pending: paid,
 * waiting for the seller ("awaiting confirmation"). failed: the booking didn't go through. reminder: check-in
 * or "pack your bags" for a booking made earlier. message: a host's or the seller's message about one.
 * other: travel-related but none of these (a refund, an offer).
 */
export const BOOKING_STATUSES = ["confirmed", "changed", "cancelled", "pending", "failed", "reminder", "message", "other"] as const;

const Place = z.object({ code: z.string().regex(/^[A-Za-z]{3}$/).nullable(), name: NullableText(80) }).strict();

export const Segment = z
  .object({
    carrier: NullableText(60),
    number: NullableText(12),
    from: Place,
    to: Place,
    departDate: DateEvidence.nullable(),
    departTime: Time,
    arriveDate: DateEvidence.nullable(),
    arriveTime: Time,
  })
  .strict();

export const Stay = z
  .object({
    name: NullableText(120),
    address: NullableText(200),
    city: NullableText(80),
    checkInDate: DateEvidence.nullable(),
    checkInTime: Time,
    checkOutDate: DateEvidence.nullable(),
    checkOutTime: Time,
    guests: NullableText(80),
  })
  .strict();

export const TravelReading = z
  .object({
    kind: z.enum(BOOKING_KINDS),
    status: z.enum(BOOKING_STATUSES),
    provider: NullableText(60),
    reference: NullableText(40),
    segments: z.array(Segment).max(8),
    stay: Stay.nullable(),
    destination: z.object({ city: NullableText(80), country: NullableText(80) }).strict().nullable(),
    bags: z.array(Text(80)).max(6),
    total: MoneyEvidence.nullable(),
    freeCancellationUntil: z.object({ date: DateEvidence, time: Time }).strict().nullable(),
    nonRefundable: z.boolean().nullable(),
    payOnSite: z.array(z.object({ what: Text(60), money: MoneyEvidence }).strict()).max(6),
    deposit: z.object({ money: MoneyEvidence, when: NullableText(120) }).strict().nullable(),
    notes: z.array(Text(160)).max(6),
  })
  .strict();
export type TravelReading = z.infer<typeof TravelReading>;

// ---------------------------------------------------------------- after the checks

const Money = z.object({ amount: z.string(), currency: z.string() }).strict();

export interface GroundedSegment {
  carrier: string | null;
  number: string | null;
  from: { code: string | null; name: string | null };
  to: { code: string | null; name: string | null };
  departDate: string | null;
  departTime: string | null;
  arriveDate: string | null;
  arriveTime: string | null;
}

export interface GroundedStay {
  name: string | null;
  address: string | null;
  city: string | null;
  checkInDate: string | null;
  checkInTime: string | null;
  checkOutDate: string | null;
  checkOutTime: string | null;
  guests: string | null;
}

/** One email's reading after the checks: every value in it is in the email. */
export interface GroundedReading {
  kind: (typeof BOOKING_KINDS)[number];
  status: (typeof BOOKING_STATUSES)[number];
  provider: string | null;
  reference: string | null;
  segments: GroundedSegment[];
  stay: GroundedStay | null;
  destination: { city: string | null; country: string | null } | null;
  bags: string[];
  total: z.infer<typeof Money> | null;
  freeCancellationUntil: { date: string; time: string | null } | null;
  nonRefundable: boolean | null;
  payOnSite: { what: string; amount: string; currency: string }[];
  deposit: { amount: string; currency: string; when: string | null } | null;
  notes: string[];
  /** Which values were read but not found in the email, by path ("segments.0.departDate"). Shown nowhere; counted. */
  dropped: string[];
}

/** Where one booking's facts came from: the email, never its words. */
export interface BookingSource {
  messageId: string;
  receivedAt: string;
  /** The sender's domain ("ryanair.com"), shown as "z maila od …". */
  senderDomain: string;
  status: GroundedReading["status"];
}

/**
 * One booking as the app receives it (schemas/fixtures/travel_bookings_v1.json). `state` is decided by the
 * newest email about the same reference; `facts` come from the newest email that confirmed or changed it.
 */
export interface TravelBooking {
  id: string;
  kind: Exclude<GroundedReading["kind"], "not_travel">;
  state: "booked" | "changed" | "cancelled" | "waiting" | "failed";
  provider: string | null;
  reference: string | null;
  facts: Omit<GroundedReading, "kind" | "status" | "provider" | "reference" | "dropped">;
  sources: BookingSource[];
}
