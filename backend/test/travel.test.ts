import assert from "node:assert/strict";
import { test } from "node:test";
import { emailToText, MAX_TRAVEL_TEXT_CHARS, redactSecrets, travelReadableText } from "../src/travel/emailText.js";
import { appearsIn, groundDate, groundMoney, groundTime, readAmount, readDate } from "../src/travel/evidence.js";
import { groundReading } from "../src/travel/ground.js";
import { mergeBookings, type ReadEmail } from "../src/travel/merge.js";
import { readTravelEmail, senderDomain, type TravelReader } from "../src/travel/reader.js";
import type { TravelReading } from "../src/travel/schema.js";
import {
  BOOKING_STAY_TEXT, CHECKIN_REMINDER, HOST_MESSAGE, RESTAURANT, RYANAIR_HTML, RYANAIR_HTML_CHANGED, WIZZ_CHANGE_MARKDOWN,
} from "./travelFixtures.js";

// ---------------------------------------------------------------- cleaning

test("HTML becomes plain lines: no style, no tags, no links", () => {
  const text = emailToText(RYANAIR_HTML);
  assert.match(text, /Nr rezerwacji:/);
  assert.match(text, /Q7TEST/);
  assert.match(text, /\(GDN\) -\n\(LIS\)/);
  assert.doesNotMatch(text, /<|>|margin|https?:|token=abc/);
});

test("markdown tables and tracking links become words only", () => {
  const text = emailToText(WIZZ_CHANGE_MARKDOWN);
  assert.match(text, /Flight number: 1350/);
  assert.match(text, /02\/Jun\/2027/);
  assert.doesNotMatch(text, /track\.example|https?:|\||---/);
});

test("PINs, card endings and card numbers are removed, also when the digits are on the next line", () => {
  const ryanair = travelReadableText(RYANAIR_HTML).text;
  assert.doesNotMatch(ryanair, /4321/);
  const stay = travelReadableText(BOOKING_STAY_TEXT);
  assert.doesNotMatch(stay.text, /8642/, "the PIN, in the header and in the link");
  assert.doesNotMatch(stay.text, /1111/, "the card ending");
  assert.match(stay.text, /7001234567/, "the confirmation number stays");
  assert.match(stay.text, /\+351 900 000 000/, "a phone number is not a card number");
  assert.ok(stay.removed >= 2);
  for (const [input, secret] of [
    ["Card 4111 1111 1111 1111 was charged", "4111"],
    ["Paid with card ending in 9988", "9988"],
    ["kod PIN 1234 do zmiany rezerwacji", "1234"],
    ["CVV: 321", "321"],
    ["XXXX-XXXX-XXXX-5566", "5566"],
  ] as const) {
    assert.doesNotMatch(redactSecrets(input).text, new RegExp(secret), input);
  }
});

test("the text read is capped", () => {
  const long = travelReadableText("a ".repeat(MAX_TRAVEL_TEXT_CHARS));
  assert.equal(long.text.length, MAX_TRAVEL_TEXT_CHARS);
  assert.equal(long.truncated, true);
});

// ---------------------------------------------------------------- evidence

test("dates are read the way the emails write them, day first", () => {
  assert.deepEqual(readDate("08/12/2026", 2026), ["2026-12-08"]);
  assert.deepEqual(readDate("Fri, 30 Oct 26", 2026), ["2026-10-30"]);
  assert.deepEqual(readDate("02/Apr/2026", 2026), ["2026-04-02"]);
  assert.deepEqual(readDate("Sunday, 29 March 2026", 2026), ["2026-03-29"]);
  assert.deepEqual(readDate("12 maja 2027", 2026), ["2027-05-12"]);
  assert.deepEqual(readDate("1 lis", 2026), ["2026-11-01", "2027-11-01"]);
  assert.deepEqual(readDate("30 paź", 2026), ["2026-10-30", "2027-10-30"]);
  assert.deepEqual(readDate("2027-05-12", 2026), ["2027-05-12"]);
  assert.deepEqual(readDate("31/02/2027", 2026), [], "no such day");
  assert.deepEqual(readDate("soon", 2026), []);
});

test("a date is kept only when its words are in the email and mean it", () => {
  const text = "Lot 08/12/2026 o 14:00";
  assert.equal(groundDate(text, { iso: "2026-12-08", asWritten: "08/12/2026" }, 2026), "2026-12-08");
  assert.equal(groundDate(text, { iso: "2026-08-12", asWritten: "08/12/2026" }, 2026), null, "month first is refused");
  assert.equal(groundDate(text, { iso: "2026-12-09", asWritten: "09/12/2026" }, 2026), null, "words not in the email");
});

test("times must be in the email, as a whole number", () => {
  assert.equal(groundTime("Czas wylotu - 6:10", "06:10"), "06:10");
  assert.equal(groundTime("Departure 2:30 PM", "14:30"), "14:30");
  assert.equal(groundTime("Departure 14:30", "14:00"), null);
  assert.equal(groundTime("ref 114:005", "14:00"), null);
  assert.equal(groundTime("anything", "25:00"), null);
});

test("amounts and currencies are read from their words", () => {
  assert.equal(readAmount("€ 292.21"), "292.21");
  assert.equal(readAmount("296.50 PLN"), "296.50");
  assert.equal(readAmount("1 234,50 zł"), "1234.50");
  assert.equal(readAmount("€ 1,234.50"), "1234.50");
  assert.equal(readAmount("€ 55"), "55.00");
  assert.equal(readAmount("2 x 20"), null, "two numbers");
  const text = "Total price € 350.00";
  assert.deepEqual(groundMoney(text, { amount: "350", currency: "EUR", asWritten: "€ 350.00" }), { amount: "350.00", currency: "EUR" });
  assert.equal(groundMoney(text, { amount: "350", currency: "PLN", asWritten: "€ 350.00" }), null, "wrong currency");
  assert.equal(groundMoney(text, { amount: "35", currency: "EUR", asWritten: "€ 350.00" }), null, "wrong amount");
  assert.equal(groundMoney(text, { amount: "400", currency: "EUR", asWritten: "€ 400.00" }), null, "not in the email");
});

test("searching ignores case and line breaks", () => {
  assert.ok(appearsIn("Gdańsk -\nLizbona", "gdańsk - lizbona"));
  assert.ok(!appearsIn("Gdańsk", ""));
});

// ---------------------------------------------------------------- one email

const segment = (over: Partial<TravelReading["segments"][number]> = {}): TravelReading["segments"][number] => ({
  carrier: "Ryanair", number: "FR1234", from: { code: "GDN", name: "Gdańsk" }, to: { code: "LIS", name: "Lizbona" },
  departDate: { iso: "2027-05-12", asWritten: "12/05/2027" }, departTime: "06:10",
  arriveDate: null, arriveTime: "09:35", ...over,
});

const reading = (over: Partial<TravelReading> = {}): TravelReading => ({
  kind: "flight", status: "confirmed", provider: "Ryanair", reference: "Q7TEST",
  segments: [
    segment(),
    segment({ number: "FR1235", from: { code: "LIS", name: "Lizbona" }, to: { code: "GDN", name: "Gdańsk" },
      departDate: { iso: "2027-05-16", asWritten: "16/05/2027" }, departTime: "10:20", arriveTime: "15:55" }),
  ],
  stay: null, destination: { city: "Lizbona", country: null }, bags: ["Bagaż rejestrowany 10 kg"],
  total: { amount: "612.40", currency: "PLN", asWritten: "612.40 PLN" },
  freeCancellationUntil: null, nonRefundable: null, payOnSite: [], deposit: null, notes: [], ...over,
});

test("a faithful reading of the Ryanair layout keeps everything", () => {
  const text = travelReadableText(RYANAIR_HTML).text;
  const g = groundReading(reading(), text, 2026);
  assert.deepEqual(g.dropped, []);
  assert.equal(g.status, "confirmed");
  assert.equal(g.segments[0]!.departDate, "2027-05-12");
  assert.equal(g.segments[1]!.arriveTime, "15:55");
  assert.deepEqual(g.total, { amount: "612.40", currency: "PLN" });
});

test("invented values are dropped, and a booking without its reference in the email is not 'confirmed'", () => {
  const text = travelReadableText(WIZZ_CHANGE_MARKDOWN).text;
  const g = groundReading(reading({
    kind: "flight", status: "changed", provider: "Wizz Air", reference: "XYZ999",
    segments: [segment({
      carrier: "Wizz Air", number: "W6 1350", from: { code: "LIS", name: "Lisbon Humberto Delgado Airport" },
      to: { code: "WAW", name: "Warsaw Chopin Airport" },
      departDate: { iso: "2027-06-02", asWritten: "02/Jun/2027" }, departTime: "21:00", arriveTime: "23:25",
    })],
    destination: null, bags: [], total: null, notes: ["Free drinks on board"],
  }), text, 2027);
  assert.equal(g.reference, null);
  assert.equal(g.status, "other");
  assert.equal(g.segments[0]!.number, null, "'W6' is not in the email");
  assert.equal(g.segments[0]!.departDate, "2027-06-02");
  assert.deepEqual(g.notes, []);
  assert.ok(g.dropped.includes("reference") && g.dropped.includes("segments.0.number") && g.dropped.includes("notes.0"));
});

test("an airport code counts only as a whole word", () => {
  const g = groundReading(reading({ segments: [segment({ to: { code: "ISB", name: null } })] }), "LISBON (LIS) Q7TEST Ryanair", 2027);
  assert.equal(g.segments[0]!.to.code, null);
});

test("'non-refundable' is kept only next to words that say it", () => {
  assert.equal(groundReading(reading({ nonRefundable: true }), "Q7TEST Ryanair", 2027).nonRefundable, null);
  assert.equal(groundReading(reading({ nonRefundable: true }), "Q7TEST Ryanair. This booking is non-refundable.", 2027).nonRefundable, true);
});

test("the stay layout: dates, cancellation, what is paid there, the deposit and the stairs", () => {
  const text = travelReadableText(BOOKING_STAY_TEXT).text;
  const g = groundReading({
    kind: "stay", status: "confirmed", provider: "Booking.com", reference: "7001234567", segments: [],
    stay: {
      name: "Casa Azul : River view, AC", address: "Rua Exemplo 10, 4050-000 Porto, Portugal", city: "Porto",
      checkInDate: { iso: "2027-05-12", asWritten: "Wednesday, 12 May 2027" }, checkInTime: "15:00",
      checkOutDate: { iso: "2027-05-16", asWritten: "Sunday, 16 May 2027" }, checkOutTime: "11:00", guests: "2 adults",
    },
    destination: { city: "Porto", country: "Portugal" }, bags: [],
    total: { amount: "350.00", currency: "EUR", asWritten: "€ 350.00" },
    freeCancellationUntil: { date: { iso: "2027-05-05", asWritten: "5 May 2027" }, time: "23:59" },
    nonRefundable: false,
    payOnSite: [{ what: "City tax", money: { amount: "8.00", currency: "EUR", asWritten: "€ 8.00" } }],
    deposit: { money: { amount: "200", currency: "EUR", asWritten: "EUR 200" }, when: "The host charges this 7 days before arrival." },
    notes: ["Both studios are on the 4th floor without elevator"],
  }, text, 2026);
  assert.deepEqual(g.dropped, []);
  assert.deepEqual(g.freeCancellationUntil, { date: "2027-05-05", time: "23:59" });
  assert.deepEqual(g.payOnSite, [{ what: "City tax", amount: "8.00", currency: "EUR" }]);
  assert.deepEqual(g.deposit, { amount: "200.00", currency: "EUR", when: "The host charges this 7 days before arrival." });
});

class FakeReader implements TravelReader {
  seen: { text: string; subject: string }[] = [];
  constructor(private readonly answer: unknown | (() => never)) {}
  async read(input: { system: string; text: string; subject: string; sender: string }) {
    this.seen.push({ text: input.text, subject: input.subject });
    if (typeof this.answer === "function") return (this.answer as () => never)();
    return this.answer;
  }
}

test("the reader never sees a link, a PIN or a card ending", async () => {
  const reader = new FakeReader(reading());
  const out = await readTravelEmail(
    { messageId: "m1", receivedAt: "2026-11-04T18:48:28Z", sender: "Itinerary@ryanair.com", subject: "Potwierdzenie rezerwacji Ryanair", body: BOOKING_STAY_TEXT + RYANAIR_HTML },
    reader,
  );
  assert.equal(out.kind, "read");
  const seen = reader.seen[0]!.text;
  assert.doesNotMatch(seen, /https?:|8642|1111|4321|token/);
});

test("an answer of the wrong shape, or a reader that fails, gives 'unreadable' and no booking", async () => {
  const email = { messageId: "m2", receivedAt: "2026-11-04T00:00:00Z", sender: "a@b.pl", subject: "x", body: "y" };
  assert.deepEqual(await readTravelEmail(email, new FakeReader({ kind: "flight" })), { kind: "unreadable", messageId: "m2", reason: "invalid_answer" });
  assert.deepEqual(await readTravelEmail(email, new FakeReader({ ...reading(), kind: "spaceship" })), { kind: "unreadable", messageId: "m2", reason: "invalid_answer" });
  assert.deepEqual(await readTravelEmail(email, new FakeReader(() => { throw new Error("timeout"); })), { kind: "unreadable", messageId: "m2", reason: "reader_failed" });
});

test("sender domains", () => {
  assert.equal(senderDomain("Itinerary@ryanair.com"), "ryanair.com");
  assert.equal(senderDomain("Ryanair <service@service.ryanairemail.pl>"), "ryanairemail.pl");
  assert.equal(senderDomain("no address"), "");
});

// ---------------------------------------------------------------- many emails

async function read(id: string, at: string, sender: string, body: string, answer: TravelReading): Promise<ReadEmail> {
  const out = await readTravelEmail({ messageId: id, receivedAt: at, sender, subject: "", body }, new FakeReader(answer));
  assert.equal(out.kind, "read", id);
  if (out.kind !== "read") throw new Error("unreachable");
  return { messageId: id, receivedAt: at, senderDomain: senderDomain(sender), reading: out.reading };
}

test("one booking from many emails: the newest confirmation's facts, reminders and messages change nothing", async () => {
  const first = await read("r1", "2026-08-27T10:00:00Z", "Itinerary@ryanair.com", RYANAIR_HTML, reading());
  const second = await read("r2", "2026-11-04T18:00:00Z", "Itinerary@ryanair.com", RYANAIR_HTML_CHANGED,
    reading({ segments: [segment({ departDate: { iso: "2027-05-13", asWritten: "13/05/2027" } })] }));
  const reminder = await read("r3", "2027-05-10T07:00:00Z", "service@service.ryanairemail.pl", CHECKIN_REMINDER,
    reading({ status: "reminder", segments: [segment({ departDate: { iso: "2027-05-13", asWritten: "13 maj" } })], total: null, bags: [] }));
  const restaurant = await read("x1", "2026-08-09T14:00:00Z", "reserve-noreply@google.com", RESTAURANT,
    reading({ kind: "not_travel", reference: null, provider: null, segments: [], total: null, bags: [], destination: null }));

  const bookings = mergeBookings([reminder, second, restaurant, first]);
  assert.equal(bookings.length, 1);
  const b = bookings[0]!;
  assert.equal(b.state, "booked");
  assert.equal(b.facts.segments[0]!.departDate, "2027-05-13", "the newer confirmation wins");
  assert.deepEqual(b.sources.map((s) => [s.messageId, s.status]), [["r1", "confirmed"], ["r2", "confirmed"], ["r3", "reminder"]]);
  assert.equal(b.sources[2]!.senderDomain, "ryanairemail.pl");
});

test("waiting, failed and cancelled are told apart, and a host's message alone is no booking", async () => {
  const stay = (status: TravelReading["status"]): TravelReading => ({
    kind: "stay", status, provider: "Booking.com", reference: "7001234567", segments: [], stay: null, destination: null,
    bags: [], total: null, freeCancellationUntil: null, nonRefundable: null, payOnSite: [], deposit: null, notes: [],
  });
  const host = await read("h1", "2027-05-12T09:00:00Z", "noreply@booking.com", HOST_MESSAGE, stay("message"));
  assert.deepEqual(mergeBookings([host]), [], "a message without a confirmation is not a booking");

  const confirmed = await read("s1", "2027-03-01T10:00:00Z", "noreply@booking.com", BOOKING_STAY_TEXT, stay("confirmed"));
  const cancelled = await read("s2", "2027-03-02T10:00:00Z", "noreply@booking.com", BOOKING_STAY_TEXT, stay("cancelled"));
  assert.equal(mergeBookings([confirmed, host]).at(0)?.state, "booked", "the host's later message changes nothing");
  assert.equal(mergeBookings([confirmed, cancelled, host]).at(0)?.state, "cancelled");

  const waiting = await read("p1", "2027-02-12T15:49:00Z", "noreply@booking.com", BOOKING_STAY_TEXT, stay("pending"));
  const failed = await read("p2", "2027-02-12T17:01:00Z", "noreply@booking.com",
    "Sorry, we couldn't book your stay. Booking.com reference 7001234567. Your booking didn't go through.", stay("failed"));
  assert.equal(mergeBookings([waiting]).at(0)?.state, "waiting");
  assert.equal(mergeBookings([waiting, failed]).at(0)?.state, "failed");
});

test("'cancelled' and 'failed' need words that say so in the email", () => {
  const base = reading({ status: "cancelled" });
  assert.equal(groundReading(base, "Q7TEST Ryanair FR1234", 2027).status, "other");
  assert.equal(groundReading(base, "Q7TEST Ryanair: your booking was cancelled", 2027).status, "cancelled");
  assert.equal(groundReading(reading({ status: "failed" }), "Q7TEST Ryanair: rezerwacja nie powiodła się", 2027).status, "failed");
  assert.equal(groundReading(reading({ status: "failed" }), "Q7TEST Ryanair", 2027).status, "other");
});

test("the shared fixture is exactly what the real code makes of the scenario's emails", async () => {
  const { readFileSync, writeFileSync } = await import("node:fs");
  const { join } = await import("node:path");
  const { scenarioBookings } = await import("./travelScenario.js");
  const file = join(process.cwd(), "..", "schemas", "fixtures", "travel_bookings_v1.json");
  const made = { version: 1, bookings: await scenarioBookings() };
  if (process.env.WRITE_TRAVEL_FIXTURE === "1") writeFileSync(file, `${JSON.stringify(made, null, 2)}\n`);
  assert.deepEqual(JSON.parse(readFileSync(file, "utf8")), made);
  // What the scenario is for: one changed flight, a stay with its extras, a cancelled stay, a UK trip,
  // and nothing from the restaurant table or the host's message alone.
  assert.deepEqual(made.bookings.map((b) => [b.reference, b.state]), [
    ["Z9FAKE", "booked"], ["7001234567", "booked"], ["Q7TEST", "booked"], ["7009999999", "cancelled"],
  ]);
});
