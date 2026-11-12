import { mergeBookings, type ReadEmail } from "../src/travel/merge.js";
import { readTravelEmail, senderDomain, type TravelReader } from "../src/travel/reader.js";
import type { TravelBooking, TravelReading } from "../src/travel/schema.js";
import {
  BOOKING_CANCELLED_TEXT, BOOKING_STAY_TEXT, CHECKIN_REMINDER, HOST_MESSAGE, RESTAURANT, RYANAIR_HTML, RYANAIR_HTML_CHANGED, RYANAIR_UK_HTML,
} from "./travelFixtures.js";

/**
 * The shared scenario behind schemas/fixtures/travel_bookings_v1.json: eight made-up emails, read by a
 * scripted reader with faithful answers, then checked and merged by the real code. The Swift tests build
 * trips and their to-do items from the same file.
 */
const none = { stay: null, destination: null, bags: [], total: null, freeCancellationUntil: null, nonRefundable: null, payOnSite: [], deposit: null, notes: [] };

const flight = (from: [string, string], to: [string, string], number: string, date: string, iso: string, dep: string, arr: string) => ({
  carrier: null, number, from: { code: from[0], name: from[1] }, to: { code: to[0], name: to[1] },
  departDate: { iso, asWritten: date }, departTime: dep, arriveDate: null, arriveTime: arr,
});

const EMAILS: { id: string; at: string; sender: string; body: string; answer: TravelReading }[] = [
  { id: "m-lis-1", at: "2026-08-27T10:00:00Z", sender: "Itinerary@ryanair.com", body: RYANAIR_HTML, answer: { kind: "flight", status: "confirmed", provider: "Ryanair", reference: "Q7TEST", ...none,
    segments: [flight(["GDN", "Gdańsk"], ["LIS", "Lizbona"], "FR1234", "12/05/2027", "2027-05-12", "06:10", "09:35"), flight(["LIS", "Lizbona"], ["GDN", "Gdańsk"], "FR1235", "16/05/2027", "2027-05-16", "10:20", "15:55")],
    destination: { city: "Lizbona", country: null }, bags: ["Bagaż rejestrowany 10 kg"], total: { amount: "612.40", currency: "PLN", asWritten: "612.40 PLN" } } },
  { id: "m-lis-2", at: "2026-11-04T18:00:00Z", sender: "Itinerary@ryanair.com", body: RYANAIR_HTML_CHANGED, answer: { kind: "flight", status: "confirmed", provider: "Ryanair", reference: "Q7TEST", ...none,
    segments: [flight(["GDN", "Gdańsk"], ["LIS", "Lizbona"], "FR1234", "13/05/2027", "2027-05-13", "06:10", "09:35"), flight(["LIS", "Lizbona"], ["GDN", "Gdańsk"], "FR1235", "16/05/2027", "2027-05-16", "10:20", "15:55")],
    destination: { city: "Lizbona", country: null }, bags: ["Bagaż rejestrowany 10 kg"], total: { amount: "612.40", currency: "PLN", asWritten: "612.40 PLN" } } },
  { id: "m-lis-3", at: "2026-11-05T07:00:00Z", sender: "Ryanair <service@service.ryanairemail.pl>", body: CHECKIN_REMINDER, answer: { kind: "flight", status: "reminder", provider: null, reference: "Q7TEST", ...none,
    segments: [flight(["LIS", "Lizbona"], ["GDN", "Gdańsk"], "FR9999", "13 maj", "2027-05-13", "06:10", "09:35")] } },
  { id: "m-opo-1", at: "2027-03-01T10:00:00Z", sender: "noreply@booking.com", body: BOOKING_STAY_TEXT, answer: { kind: "stay", status: "confirmed", provider: "Booking.com", reference: "7001234567", ...none, segments: [],
    stay: { name: "Casa Azul : River view, AC", address: "Rua Exemplo 10, 4050-000 Porto, Portugal", city: "Porto",
      checkInDate: { iso: "2027-05-12", asWritten: "Wednesday, 12 May 2027" }, checkInTime: "15:00",
      checkOutDate: { iso: "2027-05-16", asWritten: "Sunday, 16 May 2027" }, checkOutTime: "11:00", guests: "2 adults" },
    destination: { city: "Porto", country: "Portugal" }, total: { amount: "350.00", currency: "EUR", asWritten: "€ 350.00" },
    freeCancellationUntil: { date: { iso: "2027-05-05", asWritten: "5 May 2027" }, time: "23:59" }, nonRefundable: false,
    payOnSite: [{ what: "City tax", money: { amount: "8.00", currency: "EUR", asWritten: "€ 8.00" } }],
    deposit: { money: { amount: "200", currency: "EUR", asWritten: "EUR 200" }, when: "The host charges this 7 days before arrival." },
    notes: ["Both studios are on the 4th floor without elevator"] } },
  { id: "m-opo-2", at: "2027-05-12T09:00:00Z", sender: "noreply@booking.com", body: HOST_MESSAGE, answer: { kind: "stay", status: "message", provider: "Booking.com", reference: "7001234567", ...none, segments: [] } },
  { id: "m-opo-x", at: "2027-02-28T09:00:00Z", sender: "noreply@booking.com", body: BOOKING_CANCELLED_TEXT, answer: { kind: "stay", status: "cancelled", provider: "Booking.com", reference: "7009999999", ...none, segments: [] } },
  { id: "m-brs-1", at: "2026-11-04T18:48:00Z", sender: "Itinerary@ryanair.com", body: RYANAIR_UK_HTML, answer: { kind: "flight", status: "confirmed", provider: "Ryanair", reference: "Z9FAKE", ...none,
    segments: [flight(["KRK", "Kraków"], ["BRS", "Bristol"], "FR5500", "08/12/2026", "2026-12-08", "14:00", "15:40"), flight(["BRS", "Bristol"], ["WMI", "Warszawa (Modlin)"], "FR1500", "12/12/2026", "2026-12-12", "08:05", "11:45")],
    destination: { city: "Bristol", country: null }, bags: ["Bagaż rejestrowany 10 kg"], total: { amount: "296.50", currency: "PLN", asWritten: "296.50 PLN" } } },
  { id: "m-food", at: "2026-08-09T14:00:00Z", sender: "reserve-noreply@google.com", body: RESTAURANT, answer: { kind: "not_travel", status: "confirmed", provider: null, reference: null, ...none, segments: [] } },
];

class Scripted implements TravelReader {
  constructor(private readonly answer: TravelReading) {}
  async read() { return this.answer; }
}

export async function scenarioBookings(): Promise<TravelBooking[]> {
  const read: ReadEmail[] = [];
  for (const e of EMAILS) {
    const out = await readTravelEmail({ messageId: e.id, receivedAt: e.at, sender: e.sender, subject: "", body: e.body }, new Scripted(e.answer));
    if (out.kind !== "read") throw new Error(`${e.id} was not read`);
    read.push({ messageId: e.id, receivedAt: e.at, senderDomain: senderDomain(e.sender), reading: out.reading });
  }
  return mergeBookings(read);
}
