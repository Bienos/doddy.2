import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { loadConfig } from "../src/config.js";
import {
  ageOn,
  type BookingPayload,
  buildBooking,
  classifyOrder,
  type DuffelClient,
  type FindBookableFlightsArgs,
  HttpDuffelClient,
  type Offer,
  offerRequestBody,
  orderBody,
  type OrderOutcome,
  readOffer,
} from "../src/flights/duffel.js";
import { type FindFlightsArgs, HttpKiwiClient, kiwiArguments, kiwiLink, type KiwiClient, normalizeKiwi, parseMcpToolAnswer } from "../src/flights/kiwi.js";
import { USER_A, USER_B } from "./helpers.js";
import { type Rig, start } from "./toolsRig.js";

let rig: Rig;
afterEach(async () => rig?.close());

// ------------------------------------------------------------------ fixtures

/** The shape Kiwi's search-flight answered with on 11 Nov 2026 (WAW -> Barcelona, PLN), trimmed. */
const KIWI_ANSWER = {
  query: "WAW → Barcelona on 10/12/2026, 1 adult",
  currency: "PLN",
  resultsCount: 2,
  itineraries: [
    {
      id: "a_0",
      price: 183.0,
      bookingUrl: "https://kiwi.com/u/4gyym5w",
      outbound: {
        from: "WMI", to: "BCN", departureTime: "2026-12-10T17:10:00", arrivalTime: "2026-12-10T20:15:00", stops: 0,
        segments: [{ from: "WMI", to: "BCN", carrier: "FR", carrierName: "Ryanair", flightNumber: "FR4083" }],
      },
      inbound: null,
    },
    {
      id: "b_0",
      price: 212.0,
      bookingUrl: "https://evil.example/phish",
      outbound: {
        from: "WAW", to: "BCN", departureTime: "2026-12-10T15:05:00", arrivalTime: "2026-12-10T18:15:00", stops: 0,
        segments: [{ from: "WAW", to: "BCN", carrierName: "LOT Polish Airlines" }],
      },
      inbound: null,
    },
    { id: "broken", price: "free", outbound: null },
  ],
};

const sse = (payload: unknown) => `event: message\ndata: ${JSON.stringify(payload)}\n\n`;
const mcpAnswer = (inner: unknown) => sse({ jsonrpc: "2.0", id: 1, result: { content: [{ type: "text", text: JSON.stringify(inner) }] } });

class FakeKiwi implements KiwiClient {
  searches: FindFlightsArgs[] = [];
  answer: unknown = KIWI_ANSWER;
  isConfigured() {
    return true;
  }
  async search(input: { args: FindFlightsArgs }) {
    this.searches.push(input.args);
    return this.answer;
  }
}

const offerJson = (over: Record<string, unknown> = {}) => ({
  id: "off_0000TestOffer123456",
  total_amount: "412.30",
  total_currency: "PLN",
  expires_at: "2026-10-10T10:30:00Z",
  live_mode: false,
  owner: { name: "Duffel Airways" },
  payment_requirements: { requires_instant_payment: true },
  slices: [
    {
      segments: [
        {
          origin: { iata_code: "WAW" }, destination: { iata_code: "LHR" },
          departing_at: "2026-12-10T08:00:00", arriving_at: "2026-12-10T10:30:00",
          operating_carrier: { name: "Duffel Airways" }, marketing_carrier: { name: "Duffel Airways", iata_code: "ZZ" }, marketing_carrier_flight_number: "1234",
        },
      ],
    },
  ],
  passengers: [{ id: "pas_0000Adult", type: "adult" }],
  ...over,
});

class FakeDuffel implements DuffelClient {
  testMode = true;
  offer: Record<string, unknown> | null = offerJson();
  orders: BookingPayload[] = [];
  orderOutcome: OrderOutcome = { kind: "booked", orderId: "ord_0000Test", reference: "RZPNX8", amount: "412.30", currency: "PLN" };
  /** When set, the order waits until `release` is called. */
  hold: Promise<void> | null = null;
  searches: FindBookableFlightsArgs[] = [];
  isConfigured() {
    return true;
  }
  isTestMode() {
    return this.testMode;
  }
  async search(input: { args: FindBookableFlightsArgs }) {
    this.searches.push(input.args);
    return { data: { offers: this.offer ? [this.offer] : [] } };
  }
  async getOffer() {
    return this.offer ? readOffer(this.offer) : null;
  }
  async createOrder(input: { payload: BookingPayload }) {
    this.orders.push(input.payload);
    if (this.hold) await this.hold;
    return this.orderOutcome;
  }
}

const PASSENGER = { title: "ms", gender: "f", given_name: "Anna", family_name: "Kowalska", born_on: "1990-05-01" };
/** As the agent sends it: one array per field. */
const BOOKING = { offer_id: "off_0000TestOffer123456", titles: ["ms"], genders: ["f"], given_names: ["Anna"], family_names: ["Kowalska"], birth_dates: ["1990-05-01"], email: "anna@example.com", phone: "+48600100200" };
/** As the server reads it. */
const BOOKING_ARGS = { offer_id: BOOKING.offer_id, passengers: [PASSENGER], email: BOOKING.email, phone: BOOKING.phone };

async function flightsRig(o: { kiwi?: KiwiClient | null; duffel?: DuffelClient | null; bookingEnabled?: boolean; bookingWaitMs?: number } = {}) {
  return start({}, { flights: { kiwi: o.kiwi === undefined ? new FakeKiwi() : o.kiwi, duffel: o.duffel === undefined ? new FakeDuffel() : o.duffel, bookingEnabled: o.bookingEnabled ?? true, bookingWaitMs: o.bookingWaitMs ?? 2_000 } });
}

const prepare = (r: Rig, tool: string, args: unknown, token = USER_A) => r.call("POST", "/v1/tools/prepare", { token, body: { tool, arguments: args } });
/** A read as the app does it: the approval is asked for and used at once. */
async function run(r: Rig, tool: string, args: unknown, token = USER_A) {
  const asked = await prepare(r, tool, args, token);
  if (asked.status !== 200) return asked;
  return runWith(r, tool, args, asked.body.approvalId, token);
}
const runWith = (r: Rig, tool: string, args: unknown, approvalId: string | undefined, token = USER_A) =>
  r.call("POST", "/v1/tools/run", { token, body: { tool, arguments: args, timeZone: "Europe/Warsaw", ...(approvalId ? { approvalId } : {}) } });

// ------------------------------------------------------------------ Kiwi: request and answer

test("Kiwi gets fixed arguments built from validated input: PLN, Polish, dd/mm/yyyy", () => {
  assert.deepEqual(kiwiArguments({ from: "Warsaw", to: "Barcelona", departure_date: "2026-12-10", return_date: "2026-12-17", flex_days: 1, adults: 2, direct_only: true, max_price_pln: 900 }), {
    flyFrom: "Warsaw", flyTo: "Barcelona", departureDate: "10/12/2026", departureDateFlexDays: 1, returnDate: "17/12/2026", returnDateFlexDays: 1,
    adults: 2, children: 0, infants: 0, max_sector_stopovers: 0, price_to: 900, currency: "PLN", locale: "pl", sort: "price",
  });
});

test("an MCP answer is read from server-sent events or plain JSON; errors are provider failures", () => {
  assert.deepEqual(parseMcpToolAnswer(mcpAnswer({ ok: 1 })), { ok: 1 });
  assert.deepEqual(parseMcpToolAnswer(JSON.stringify({ jsonrpc: "2.0", id: 1, result: { content: [{ type: "text", text: "{\"ok\":2}" }] } })), { ok: 2 });
  assert.throws(() => parseMcpToolAnswer(sse({ jsonrpc: "2.0", id: 1, error: { code: -1 } })), /provider_unavailable/);
  assert.throws(() => parseMcpToolAnswer(sse({ jsonrpc: "2.0", id: 1, result: { isError: true, content: [] } })), /provider_unavailable/);
  assert.throws(() => parseMcpToolAnswer("data: not json"), /malformed_provider_result/);
});

test("Kiwi's flights are spoken without links; only kiwi.com https links reach the app", () => {
  const outcome = normalizeKiwi(KIWI_ANSWER, { from: "Warsaw", to: "Barcelona", departure_date: "2026-12-10" });
  assert.equal(outcome.count, 2);
  assert.match(outcome.text, /183 PLN, Ryanair, WMI 2026-12-10 17:10 -> BCN 2026-12-10 20:15 \(direct\)/);
  assert.match(outcome.text, /Doddy can't book these/);
  assert.doesNotMatch(outcome.text, /https?:/);
  assert.equal(outcome.flights[0]!.bookingUrl, "https://kiwi.com/u/4gyym5w");
  assert.equal(outcome.flights[1]!.bookingUrl, null);
  assert.equal(kiwiLink("https://www.kiwi.com/en/booking?x=1"), "https://www.kiwi.com/en/booking?x=1");
  assert.equal(kiwiLink("http://kiwi.com/u/1"), null);
  assert.equal(kiwiLink("https://kiwi.com.evil.example/u/1"), null);
  assert.match(normalizeKiwi({ itineraries: [] }, { from: "A", to: "B", departure_date: "2026-12-10" }).text, /found no flights.*do not guess/);
  assert.throws(() => normalizeKiwi({ itineraries: "x" }, { from: "A", to: "B", departure_date: "2026-12-10" }), /malformed_provider_result/);
});

test("the HTTP Kiwi client posts one tools/call to the MCP server", async () => {
  const seen: { url: string; body: any }[] = [];
  const fake = (async (url: string, init: RequestInit) => {
    seen.push({ url, body: JSON.parse(String(init.body)) });
    return new Response(mcpAnswer(KIWI_ANSWER), { status: 200, headers: { "content-type": "text/event-stream" } });
  }) as unknown as typeof fetch;
  const out = await new HttpKiwiClient("https://mcp.kiwi.com", fake).search({ args: { from: "WAW", to: "BCN", departure_date: "2026-12-10" }, signal: AbortSignal.timeout(1000) });
  assert.equal((out as any).currency, "PLN");
  assert.equal(seen[0]!.url, "https://mcp.kiwi.com");
  assert.equal(seen[0]!.body.method, "tools/call");
  assert.equal(seen[0]!.body.params.name, "search-flight");
});

// ------------------------------------------------------------------ Duffel: what each answer means

test("Duffel's order answers are classified exactly as its response guide says", () => {
  assert.deepEqual(classifyOrder(201, { data: { id: "ord_1", booking_reference: "ABC123", total_amount: "1.00", total_currency: "PLN" } }), {
    kind: "booked", orderId: "ord_1", reference: "ABC123", amount: "1.00", currency: "PLN",
  });
  // A 201 without a reference is not called booked.
  assert.equal(classifyOrder(201, { data: { id: "ord_1" } }).kind, "unknown");
  for (const code of ["offer_expired", "price_changed", "offer_no_longer_available", "order_not_created", "payment_declined", "insufficient_balance", "high_fraud_risk"]) {
    assert.equal(classifyOrder(422, { errors: [{ code }] }).kind, "not_booked", code);
  }
  assert.equal(classifyOrder(503, null).kind, "not_booked");
  assert.equal(classifyOrder(429, null).kind, "not_booked");
  // Never retried, never "not booked": Duffel says these may have booked.
  for (const status of [200, 202, 500, 502, 504, 400, 404]) assert.equal(classifyOrder(status, null).kind, "unknown", String(status));
  assert.equal(classifyOrder(422, { errors: [{ code: "something_new" }] }).kind, "unknown");
});

test("a network failure or timeout while ordering is unknown, not 'not booked'", async () => {
  const failing = (async () => {
    throw Object.assign(new Error("timeout"), { name: "TimeoutError" });
  }) as unknown as typeof fetch;
  const outcome = await new HttpDuffelClient("duffel_test_abc12345", "https://api.duffel.com", failing).createOrder({ payload: {} as BookingPayload, signal: AbortSignal.timeout(1000) });
  assert.deepEqual(outcome, { kind: "unknown", code: "timeout" });
});

test("the Duffel client sends v2 headers and only a test key counts as test mode", async () => {
  let headers: Record<string, string> = {};
  const fake = (async (_url: string, init: RequestInit) => {
    headers = init.headers as Record<string, string>;
    return new Response(JSON.stringify({ data: { offers: [] } }), { status: 201 });
  }) as unknown as typeof fetch;
  const client = new HttpDuffelClient("duffel_test_abc12345", "https://api.duffel.com", fake);
  await client.search({ args: { from: "WAW", to: "LHR", departure_date: "2026-12-10" }, signal: AbortSignal.timeout(1000) });
  assert.equal(headers["Duffel-Version"], "v2");
  assert.equal(headers.Authorization, "Bearer duffel_test_abc12345");
  assert.equal(client.isTestMode(), true);
  assert.equal(new HttpDuffelClient("duffel_live_abc12345").isTestMode(), false);
});

test("offer requests and orders are built from validated input; payments come from the test balance", () => {
  assert.deepEqual(offerRequestBody({ from: "WAW", to: "LHR", departure_date: "2026-12-10", return_date: "2026-12-12", adults: 1, child_ages: [7] }), {
    data: {
      slices: [{ origin: "WAW", destination: "LHR", departure_date: "2026-12-10" }, { origin: "LHR", destination: "WAW", departure_date: "2026-12-12" }],
      passengers: [{ type: "adult" }, { age: 7 }],
    },
  });
  const offer = readOffer(offerJson()) as Offer;
  const built = buildBooking(offer, BOOKING_ARGS as any, "2026-10-10");
  assert.ok("payload" in built);
  const body = orderBody(built.payload) as any;
  assert.deepEqual(body.data.payments, [{ type: "balance", currency: "PLN", amount: "412.30" }]);
  assert.deepEqual(body.data.selected_offers, ["off_0000TestOffer123456"]);
  assert.equal(body.data.passengers[0].id, "pas_0000Adult");
  assert.equal(body.data.type, "instant");
});

test("passengers must fit the offer: count, adults 18+, children the searched age", () => {
  const offer = readOffer(offerJson({ passengers: [{ id: "pas_a", type: "adult" }, { id: "pas_c", type: null, age: 7 }] })) as Offer;
  const child = { ...PASSENGER, title: "miss", given_name: "Zosia", born_on: "2019-06-01" };
  assert.ok("payload" in buildBooking(offer, { ...BOOKING_ARGS, passengers: [PASSENGER, child] } as any, "2026-10-10"));
  assert.match((buildBooking(offer, BOOKING_ARGS as any, "2026-10-10") as any).problem, /for 2 people, but 1 were given/);
  assert.match((buildBooking(offer, { ...BOOKING_ARGS, passengers: [child, PASSENGER] } as any, "2026-10-10") as any).problem, /must be an adult/);
  assert.match((buildBooking(offer, { ...BOOKING_ARGS, passengers: [PASSENGER, { ...child, born_on: "2010-01-01" }] } as any, "2026-10-10") as any).problem, /searched as 7/);
  assert.equal(ageOn("2008-12-11", "2026-12-10"), 17);
  assert.equal(ageOn("2008-12-10", "2026-12-10"), 18);
});

// ------------------------------------------------------------------ through the server

test("find_flights: asks with the route on its card, then answers from Kiwi with links for the app", async () => {
  const kiwi = new FakeKiwi();
  rig = await flightsRig({ kiwi });
  const args = { from: "Warsaw", to: "Barcelona", departure_date: "2026-12-10" };
  const asked = await prepare(rig, "find_flights", args);
  assert.equal(asked.status, 200, asked.text);
  assert.match(asked.body.preview.lines.join("\n"), /Warsaw → Barcelona, 2026-12-10/);
  assert.equal(kiwi.searches.length, 0, "nothing is searched before the run");
  const res = await runWith(rig, "find_flights", args, asked.body.approvalId);
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.count, 2);
  assert.deepEqual(res.body.links, [{ title: "183 PLN, WMI → BCN, 2026-12-10 17:10", url: "https://kiwi.com/u/4gyym5w" }]);
  assert.equal(res.body.receipt.toolkit, "flights");
  // The approval is single-use.
  assert.equal((await runWith(rig, "find_flights", args, asked.body.approvalId)).status, 403);
  // The route is kept out of receipts.
  assert.doesNotMatch(JSON.stringify((await rig.call("GET", "/v1/tools/receipts")).body), /Barcelona/);
});

test("without Kiwi or Duffel set up, every flight tool says so and nothing runs", async () => {
  rig = await flightsRig({ kiwi: null, duffel: null });
  for (const [tool, args] of [["find_flights", { from: "A1", to: "B1", departure_date: "2026-12-10" }], ["find_bookable_flights", { from: "WAW", to: "LHR", departure_date: "2026-12-10" }], ["book_flight", BOOKING]] as const) {
    const res = await prepare(rig, tool, args);
    assert.equal(res.status, 503, `${tool}: ${res.text}`);
    assert.equal(res.body.error.code, "live_not_configured");
    assert.equal(res.body.error.receipt.status, "blocked");
  }
});

test("find_bookable_flights lists Duffel offers with their ids for booking", async () => {
  rig = await flightsRig();
  const res = await run(rig, "find_bookable_flights", { from: "waw", to: "LHR", departure_date: "2026-12-10" });
  assert.equal(res.status, 200, res.text);
  assert.match(res.body.text, /offer off_0000TestOffer123456: 412\.30 PLN, Duffel Airways; WAW 2026-12-10 08:00 -> LHR 2026-12-10 10:30 \(direct; Duffel Airways\)/);
  assert.equal(res.body.links, undefined);
});

test("book_flight is off unless switched on, and only with a Duffel test key", async () => {
  rig = await flightsRig({ bookingEnabled: false });
  let res = await prepare(rig, "book_flight", BOOKING);
  assert.equal(res.status, 503);
  assert.match(res.body.error.message, /isn't switched on/);
  await rig.close();
  const live = new FakeDuffel();
  live.testMode = false;
  rig = await flightsRig({ duffel: live });
  res = await prepare(rig, "book_flight", BOOKING);
  assert.equal(res.status, 503);
  assert.match(res.body.error.message, /only with a Duffel test key/);
  assert.equal(live.orders.length, 0);
});

test("book_flight: the card shows the exact booking; a tap books it once and Duffel's reference is the receipt", async () => {
  const duffel = new FakeDuffel();
  rig = await flightsRig({ duffel });
  const card = await prepare(rig, "book_flight", BOOKING);
  assert.equal(card.status, 200, card.text);
  assert.equal(card.body.preview.title, "Book this flight for 412.30 PLN?");
  const lines = card.body.preview.lines.join("\n");
  assert.match(lines, /ZZ1234 WAW 2026-12-10 08:00 -> LHR 2026-12-10 10:30, operated by Duffel Airways/);
  assert.match(lines, /Passenger 1: MS Anna Kowalska, born 1990-05-01/);
  assert.match(lines, /test mode: no real ticket/);
  assert.equal(duffel.orders.length, 0, "nothing is booked before the tap");

  const booked = await runWith(rig, "book_flight", BOOKING, card.body.approvalId);
  assert.equal(booked.status, 200, booked.text);
  assert.match(booked.body.text, /^booked: Duffel confirmed the booking .*reference RZPNX8, Duffel order ord_0000Test/);
  assert.equal(booked.body.receipt.status, "succeeded");
  assert.equal(booked.body.receipt.providerReference, "ord_0000Test");
  assert.equal(duffel.orders.length, 1);

  // The phone lost the answer and sent the same approval again: the first answer, nothing booked again.
  const again = await runWith(rig, "book_flight", BOOKING, card.body.approvalId);
  assert.equal(again.status, 200);
  assert.equal(again.body.replayed, true);
  assert.match(again.body.text, /^booked: .*RZPNX8/);
  // A new card for the same offer is refused: it is already booked.
  const second = await prepare(rig, "book_flight", BOOKING);
  assert.equal(second.status, 403);
  assert.equal(second.body.error.receipt.errorCode, "already_booked");
  assert.equal(duffel.orders.length, 1);
  // And the check says so.
  const check = await run(rig, "check_flight_booking", { offer_id: BOOKING.offer_id });
  assert.match(check.body.text, /^booked: .*RZPNX8/);
});

test("book_flight needs one value per passenger in every list", async () => {
  const duffel = new FakeDuffel();
  rig = await flightsRig({ duffel });
  const res = await prepare(rig, "book_flight", { ...BOOKING, given_names: ["Anna", "Jan"] });
  assert.equal(res.status, 400, res.text);
  assert.match(res.body.error.message, /one title, gender, first name, last name and birth date for every passenger/);
  assert.equal(duffel.orders.length, 0);
});

test("book_flight without the card's approval, or for another user, books nothing", async () => {
  const duffel = new FakeDuffel();
  rig = await flightsRig({ duffel });
  const none = await runWith(rig, "book_flight", BOOKING, undefined);
  assert.equal(none.status, 403);
  assert.equal(none.body.error.receipt.status, "blocked");
  const card = await prepare(rig, "book_flight", BOOKING);
  const other = await runWith(rig, "book_flight", BOOKING, card.body.approvalId, USER_B);
  assert.equal(other.status, 403);
  assert.equal(duffel.orders.length, 0);
});

test("a changed price or a changed passenger after the card voids the tap", async () => {
  const duffel = new FakeDuffel();
  rig = await flightsRig({ duffel });
  const card = await prepare(rig, "book_flight", BOOKING);
  duffel.offer = offerJson({ total_amount: "499.00" });
  const res = await runWith(rig, "book_flight", BOOKING, card.body.approvalId);
  assert.equal(res.status, 403, res.text);
  assert.equal(res.body.error.receipt.errorCode, "booking_changed");
  assert.equal(res.body.error.receipt.status, "blocked");

  duffel.offer = offerJson();
  const card2 = await prepare(rig, "book_flight", BOOKING);
  const renamed = await runWith(rig, "book_flight", { ...BOOKING, family_names: ["Nowak"] }, card2.body.approvalId);
  assert.equal(renamed.status, 403);
  assert.equal(duffel.orders.length, 0);
});

test("an expired or vanished offer is refused before any card", async () => {
  const duffel = new FakeDuffel();
  rig = await flightsRig({ duffel });
  duffel.offer = offerJson({ expires_at: "2026-10-10T09:00:00Z" });
  let res = await prepare(rig, "book_flight", BOOKING);
  assert.equal(res.status, 404);
  assert.match(res.body.error.message, /expired/);
  duffel.offer = null;
  res = await prepare(rig, "book_flight", BOOKING);
  assert.match(res.body.error.message, /gone or expired/);
});

test("Duffel saying 'not booked' is failed, and the offer can be tried again", async () => {
  const duffel = new FakeDuffel();
  duffel.orderOutcome = { kind: "not_booked", code: "offer_no_longer_available", message: "The offer is no longer available. Search again." };
  rig = await flightsRig({ duffel });
  const card = await prepare(rig, "book_flight", BOOKING);
  const res = await runWith(rig, "book_flight", BOOKING, card.body.approvalId);
  assert.equal(res.status, 200);
  assert.match(res.body.text, /^failed: The offer is no longer available/);
  assert.equal(res.body.receipt.status, "failed");
  assert.equal((await prepare(rig, "book_flight", BOOKING)).status, 200, "a proven failure doesn't block another try");
});

test("an unknown answer is never retried: the offer is blocked and the check says unknown", async () => {
  const duffel = new FakeDuffel();
  duffel.orderOutcome = { kind: "unknown", code: "http_502" };
  rig = await flightsRig({ duffel });
  const card = await prepare(rig, "book_flight", BOOKING);
  const res = await runWith(rig, "book_flight", BOOKING, card.body.approvalId);
  assert.match(res.body.text, /^unknown: Duffel didn't confirm/);
  assert.equal(res.body.receipt.status, "outcome_unknown");
  const again = await prepare(rig, "book_flight", BOOKING);
  assert.equal(again.status, 403);
  assert.equal(again.body.error.receipt.status, "outcome_unknown");
  const check = await run(rig, "check_flight_booking", { offer_id: BOOKING.offer_id });
  assert.match(check.body.text, /^unknown: Duffel never confirmed/);
  assert.equal(duffel.orders.length, 1);
});

test("a slow Duffel answer: the app hears 'unknown' at once, the booking finishes and the check finds it", async () => {
  const duffel = new FakeDuffel();
  let release!: () => void;
  duffel.hold = new Promise<void>((r) => (release = r));
  rig = await flightsRig({ duffel, bookingWaitMs: 20 });
  const card = await prepare(rig, "book_flight", BOOKING);
  const res = await runWith(rig, "book_flight", BOOKING, card.body.approvalId);
  assert.match(res.body.text, /^unknown: Duffel hasn't confirmed this booking yet/);
  // While it is still running, the check says so and another booking of the offer is refused.
  assert.match((await run(rig, "check_flight_booking", { offer_id: BOOKING.offer_id })).body.text, /^unknown: Doddy is still waiting/);
  assert.equal((await prepare(rig, "book_flight", BOOKING)).status, 403);
  release();
  await rig.tools.settle();
  assert.match((await run(rig, "check_flight_booking", { offer_id: BOOKING.offer_id })).body.text, /^booked: .*RZPNX8/);
  assert.equal(duffel.orders.length, 1);
});

test("check_flight_booking for an offer never tried says nothing was booked", async () => {
  rig = await flightsRig();
  const res = await run(rig, "check_flight_booking", { offer_id: "off_0000NeverTried12" });
  assert.equal(res.status, 200, res.text);
  assert.match(res.body.text, /hasn't tried to book this offer/);
});

// ------------------------------------------------------------------ config

const live = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "signed",
  DODDY_SESSION_SIGNING_KEY: Buffer.alloc(32, 7).toString("base64"),
  COMPOSIO_API_KEY: "k",
  COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID: "ac_cal",
  COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: "20250909_00",
};

test("config: flights are off by default, each part switched on on its own, ignored in mock mode", () => {
  assert.deepEqual(loadConfig(live).flights, { kiwiUrl: null, duffelToken: null, duffelBaseUrl: "https://api.duffel.com", bookingEnabled: false });
  assert.equal(loadConfig({ ...live, FLIGHT_SEARCH_ENABLED: "1" }).flights.kiwiUrl, "https://mcp.kiwi.com");
  const duffel = loadConfig({ ...live, DUFFEL_ACCESS_TOKEN: "duffel_test_abcdefgh123", FLIGHT_BOOKING_ENABLED: "1" }).flights;
  assert.equal(duffel.duffelToken, "duffel_test_abcdefgh123");
  assert.equal(duffel.bookingEnabled, true);
  assert.throws(() => loadConfig({ ...live, DUFFEL_ACCESS_TOKEN: "sk_wrong" }), /DUFFEL_ACCESS_TOKEN must look like/);
  assert.throws(() => loadConfig({ ...live, FLIGHT_SEARCH_ENABLED: "1", KIWI_MCP_URL: "http://mcp.kiwi.com" }), /KIWI_MCP_URL must be an https origin/);
  assert.equal(loadConfig({ DUFFEL_ACCESS_TOKEN: "duffel_test_abcdefgh123", FLIGHT_SEARCH_ENABLED: "1" }).flights.duffelToken, null);
});
