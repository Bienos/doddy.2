import { z } from "zod";

/**
 * Flights for the trip planner (decision 2026-11-11-travel-agent-plan, stage 2; owner, 12 Nov 2026: Kiwi.com
 * "od razu dla wszystkich"). Kiwi.com's public MCP server (called only from flights/kiwi.ts, no key) answers with live itineraries, a total price for the party with the bags asked for, and a booking
 * link on kiwi.com. Doddy only searches and links out: the person books and pays on Kiwi.com.
 *
 * Read on 12 Nov 2026 from this session: `initialize` and `tools/list` over JSON-RPC (Streamable HTTP,
 * answers as `data:` lines); a search for GDN–LIS returned 15 itineraries in EUR, one for GDN–BCN with
 * 2 adults, one checked bag, PLN and no stops returned prices in PLN with the bag counted.
 * Their terms for use inside another company's app are not published; the owner chose to go ahead
 * (owner queue: ask Kiwi).
 */


/** What the planner asks for. Dates are YYYY-MM-DD; Kiwi wants dd/mm/yyyy, converted here. */
export interface FlightQuery {
  from: string;
  to: string;
  departFrom: string;
  departTo: string;
  nightsMin: number | null;
  nightsMax: number | null;
  adults: number;
  children: number;
  /** Checked bags per adult, one entry per adult (Kiwi's `adults_hold_bags`). */
  adultBags: number[];
  directOnly: boolean;
  currency: "PLN" | "EUR";
}

const Segment = z.object({
  from: z.string(), to: z.string(),
  fromCity: z.string().optional(), toCity: z.string().optional(),
  fromName: z.string().optional(), toName: z.string().optional(),
  departureTime: z.string(), arrivalTime: z.string(),
  carrier: z.string().optional(), carrierName: z.string().optional(), flightNumber: z.string().optional(),
}).passthrough();

const Leg = z.object({
  from: z.string(), to: z.string(),
  departureTime: z.string(), arrivalTime: z.string(),
  durationSeconds: z.number(), stops: z.number(),
  segments: z.array(Segment).min(1),
}).passthrough();

const Itinerary = z.object({
  id: z.string(),
  price: z.number(),
  bookingUrl: z.string().url(),
  totalDurationSeconds: z.number().optional(),
  baggage: z.object({ personalItem: z.number().optional(), cabinBag: z.number().optional(), checkedBag: z.number().optional() }).partial().optional(),
  outbound: Leg,
  inbound: Leg.nullable().optional(),
}).passthrough();

export const SearchAnswer = z.object({
  currency: z.string(),
  itineraries: z.array(Itinerary),
  error: z.unknown().optional(),
}).passthrough();

export type KiwiItinerary = z.infer<typeof Itinerary>;
export type KiwiLeg = z.infer<typeof Leg>;

export interface FlightSearch {
  search(query: FlightQuery, signal: AbortSignal): Promise<{ currency: string; itineraries: KiwiItinerary[] }>;
}

export class FlightSearchError extends Error {
  constructor(readonly reason: "unavailable" | "malformed" | "refused") {
    super(`flight search ${reason}`);
  }
}

// ---------------------------------------------------------------- mock

const seg = (from: string, to: string, fromCity: string, toCity: string, toCountry: string, dep: string, arr: string, carrier: string, carrierName: string, flightNumber: string) =>
  ({ from, to, fromCity, toCity, toCountry, departureTime: dep, arrivalTime: arr, carrier, carrierName, flightNumber });

/** Mock mode and tests: four made-up itineraries with the shapes Kiwi.com returns, one of each trap. */
export class MockFlightSearch implements FlightSearch {
  readonly queries: FlightQuery[] = [];
  async search(query: FlightQuery) {
    this.queries.push(query);
    const d = query.departFrom;
    const back = (() => {
      const t = new Date(`${d}T00:00:00Z`);
      t.setUTCDate(t.getUTCDate() + (query.nightsMin ?? 4));
      return t.toISOString().slice(0, 10);
    })();
    const legOf = (segs: ReturnType<typeof seg>[]) => ({
      from: segs[0]!.from, to: segs[segs.length - 1]!.to, departureTime: segs[0]!.departureTime, arrivalTime: segs[segs.length - 1]!.arrivalTime,
      durationSeconds: (Date.parse(segs[segs.length - 1]!.arrivalTime) - Date.parse(segs[0]!.departureTime)) / 1000, stops: segs.length - 1, segments: segs,
    });
    const home = seg("LIS", "GDN", "Lisbon", "Gdańsk", "Poland", `${back}T10:20:00`, `${back}T15:55:00`, "FR", "Ryanair", "FR1235");
    const itineraries = [
      { id: "demo-cheap", price: 742.4, bookingUrl: "https://kiwi.com/u/demo1", baggage: { checkedBag: 0 },
        outbound: legOf([seg("GDN", "BGY", "Gdańsk", "Milan", "Italy", `${d}T14:15:00`, `${d}T16:25:00`, "FR", "Ryanair", "FR3279"),
          seg("MXP", "LIS", "Milan", "Lisbon", "Portugal", `${d}T21:10:00`, `${d}T23:05:00`, "U2", "easyJet", "U27698")]),
        inbound: legOf([home]) },
      { id: "demo-direct", price: 958, bookingUrl: "https://kiwi.com/u/demo2", baggage: { checkedBag: 0 },
        outbound: legOf([seg("GDN", "LIS", "Gdańsk", "Lisbon", "Portugal", `${d}T06:10:00`, `${d}T09:35:00`, "FR", "Ryanair", "FR1234")]),
        inbound: legOf([home]) },
      { id: "demo-early", price: 901, bookingUrl: "https://kiwi.com/u/demo3", baggage: { checkedBag: 0 },
        outbound: legOf([seg("GDN", "LIS", "Gdańsk", "Lisbon", "Portugal", `${d}T05:20:00`, `${d}T08:45:00`, "W6", "Wizz Air", "W61702")]),
        inbound: legOf([home]) },
    ];
    return { currency: query.currency, itineraries: itineraries as unknown as KiwiItinerary[] };
  }
}
