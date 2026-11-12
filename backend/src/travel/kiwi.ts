import { z } from "zod";

/**
 * Flights for the trip planner (decision 2026-11-11-travel-agent-plan, stage 2; owner, 12 Nov 2026: Kiwi.com
 * "od razu dla wszystkich"). Kiwi.com's public MCP server (https://mcp.kiwi.com, tool `search-flight`, no
 * key) answers with live itineraries, a total price for the party with the bags asked for, and a booking
 * link on kiwi.com. Doddy only searches and links out: the person books and pays on Kiwi.com.
 *
 * Read on 12 Nov 2026 from this session: `initialize` and `tools/list` over JSON-RPC (Streamable HTTP,
 * answers as `data:` lines); a search for GDN–LIS returned 15 itineraries in EUR, one for GDN–BCN with
 * 2 adults, one checked bag, PLN and no stops returned prices in PLN with the bag counted.
 * Their terms for use inside another company's app are not published; the owner chose to go ahead
 * (owner queue: ask Kiwi).
 */

export const KIWI_MCP_URL = "https://mcp.kiwi.com";
export const KIWI_TIMEOUT_MS = 15_000;

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

const SearchAnswer = z.object({
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

const kiwiDate = (iso: string) => {
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
};

/** The tool arguments for a query. Exported for tests. */
export function kiwiArguments(q: FlightQuery): Record<string, unknown> {
  const args: Record<string, unknown> = {
    flyFrom: q.from,
    flyTo: q.to,
    departureDate: kiwiDate(q.departFrom),
    adults: q.adults,
    currency: q.currency,
    locale: "pl",
    sort: "price",
  };
  if (q.departTo !== q.departFrom) args.departureDateTo = kiwiDate(q.departTo);
  if (q.nightsMin !== null && q.nightsMax !== null) {
    args.nights_in_dst_from = q.nightsMin;
    args.nights_in_dst_to = q.nightsMax;
  }
  if (q.children > 0) args.children = q.children;
  if (q.adultBags.some((b) => b > 0)) args.adults_hold_bags = q.adultBags;
  if (q.directOnly) args.max_sector_stopovers = 0;
  return args;
}

/** The `data:` payload of a Streamable HTTP answer (or the body itself when it is plain JSON). */
export function parseRpcBody(body: string): unknown {
  const data = body.split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()).join("");
  return JSON.parse(data || body);
}

export class KiwiFlightSearch implements FlightSearch {
  constructor(private readonly url = KIWI_MCP_URL, private readonly fetcher: typeof fetch = fetch) {}

  async search(query: FlightQuery, signal: AbortSignal) {
    let res: Response;
    try {
      res = await this.fetcher(this.url, {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json, text/event-stream" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "search-flight", arguments: kiwiArguments(query) } }),
        signal,
        redirect: "error",
      });
    } catch {
      throw new FlightSearchError("unavailable");
    }
    if (!res.ok) throw new FlightSearchError(res.status === 429 || res.status === 403 ? "refused" : "unavailable");
    let rpc: unknown;
    try {
      rpc = parseRpcBody((await res.text()).slice(0, 2_000_000));
    } catch {
      throw new FlightSearchError("malformed");
    }
    const result = (rpc as { result?: { content?: { type?: string; text?: string }[]; isError?: boolean } }).result;
    const text = result?.content?.find((c) => c.type === "text")?.text;
    if (!result || result.isError || typeof text !== "string") throw new FlightSearchError(result?.isError ? "refused" : "malformed");
    let parsed: z.infer<typeof SearchAnswer>;
    try {
      parsed = SearchAnswer.parse(JSON.parse(text));
    } catch {
      throw new FlightSearchError("malformed");
    }
    // Only links to Kiwi.com itself are passed on.
    const itineraries = parsed.itineraries.filter((i) => /^https:\/\/(www\.)?kiwi\.com\//.test(i.bookingUrl));
    return { currency: parsed.currency, itineraries };
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
