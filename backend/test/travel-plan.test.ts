import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import type { ClaudeProvider, StructuredInput } from "../src/tools/claude.js";
import { FlightSearchError, type FlightQuery, kiwiArguments, KiwiFlightSearch, MockFlightSearch, parseRpcBody } from "../src/travel/kiwi.js";
import { assumptions, cleanBrief, EMPTY_BRIEF, missing, pickOptions, stayLinks, toQuery, traps, type TripBrief } from "../src/travel/plan.js";
import { USER_A } from "./helpers.js";
import { type Rig, start } from "./toolsRig.js";

/**
 * The trip planner (decision 2026-11-11-travel-agent-plan, stage 2; TRAVEL_PLANNER.md). Kiwi.com and Claude
 * are stand-ins here: nothing in these tests reached the real Kiwi.com or a real model.
 */
let rig: Rig;
afterEach(async () => rig?.close());

const TODAY = "2026-11-12";
const brief = (over: Partial<TripBrief> = {}): TripBrief => ({ ...EMPTY_BRIEF, ...over });
const full = brief({ from: "Gdańsk", to: "Lisbon", departFrom: "2027-02-12", departTo: "2027-02-12", nightsMin: 4, nightsMax: 4, adults: 2 });

// ---------------------------------------------------------------- the brief

test("what can't be right is dropped and asked again", () => {
  assert.equal(cleanBrief(brief({ departFrom: "2026-11-01", departTo: "2026-11-03" }), TODAY).departFrom, null, "in the past");
  assert.equal(cleanBrief(brief({ departFrom: "2028-06-01" }), TODAY).departFrom, null, "too far ahead");
  assert.equal(cleanBrief(brief({ departFrom: "2027-02-12", departTo: "2027-02-01" }), TODAY).departTo, "2027-02-12", "a window back to front becomes the day");
  assert.equal(cleanBrief(brief({ departFrom: "2027-02-01", departTo: "2027-04-01" }), TODAY).departTo, "2027-02-01", "a window longer than a month becomes the day");
  assert.deepEqual([cleanBrief(brief({ nightsMin: 6, nightsMax: 3 }), TODAY).nightsMin], [null]);
  assert.equal(cleanBrief(brief({ nightsMin: 5 }), TODAY).nightsMax, 5);
  assert.equal(cleanBrief(brief({ from: "Gdańsk", to: "gdańsk" }), TODAY).to, null, "a trip to where it starts");
});

test("what is missing comes in the order Doddy asks, and what isn't said is assumed out loud", () => {
  assert.deepEqual(missing(EMPTY_BRIEF), ["to", "from", "when", "nights", "who"]);
  assert.deepEqual(missing(brief({ to: "Lisbon", adults: 2 })), ["from", "when", "nights"]);
  assert.deepEqual(missing(full), []);
  assert.deepEqual(assumptions(full), ["no_checked_bag", "stops_allowed", "no_children", "exact_day"]);
  assert.deepEqual(assumptions({ ...full, checkedBagPerAdult: true, directOnly: true, children: 0, departTo: "2027-02-14" }), []);
  assert.equal(toQuery(brief({ to: "Lisbon" })), null, "no search until the brief is complete");
});

test("a complete brief becomes Kiwi.com's arguments: day first, bags per adult, no stops when asked", () => {
  const q = toQuery({ ...full, departTo: "2027-02-15", checkedBagPerAdult: true, directOnly: true, children: 1 })!;
  assert.deepEqual(kiwiArguments(q), {
    flyFrom: "Gdańsk", flyTo: "Lisbon", departureDate: "12/02/2027", departureDateTo: "15/02/2027", adults: 2, children: 1,
    currency: "PLN", locale: "pl", sort: "price", nights_in_dst_from: 4, nights_in_dst_to: 4, adults_hold_bags: [1, 1], max_sector_stopovers: 0,
  });
  assert.equal(kiwiArguments(toQuery(full)!).adults_hold_bags, undefined, "no bags asked: none sent");
});

// ---------------------------------------------------------------- Kiwi.com

const rpc = (payload: unknown) => `event: message\ndata: ${JSON.stringify({ jsonrpc: "2.0", id: 1, result: { content: [{ type: "text", text: JSON.stringify(payload) }] } })}\n\n`;

test("Kiwi.com's answer is read from its data line; a link that isn't Kiwi.com's is dropped", async () => {
  const mock = await new MockFlightSearch().search(toQuery(full)!);
  const odd = { ...mock.itineraries[0]!, id: "x", bookingUrl: "https://evil.example/pay" };
  let sent: unknown;
  const kiwi = new KiwiFlightSearch("https://mcp.kiwi.com", (async (_url: unknown, init?: RequestInit) => {
    sent = JSON.parse(String(init?.body));
    return new Response(rpc({ currency: "PLN", itineraries: [...mock.itineraries, odd] }), { status: 200 });
  }) as typeof fetch);
  const out = await kiwi.search(toQuery(full)!, AbortSignal.timeout(1000));
  assert.equal(out.itineraries.length, 3);
  assert.equal((sent as any).params.name, "search-flight");
  assert.equal((sent as any).params.arguments.departureDate, "12/02/2027");
  assert.deepEqual(parseRpcBody('{"a":1}'), { a: 1 });
});

test("a refusal, an error answer or a broken one is an error, never an empty list", async () => {
  const kiwi = (body: string, status = 200) => new KiwiFlightSearch("https://mcp.kiwi.com", (async () => new Response(body, { status })) as typeof fetch);
  const q = toQuery(full)!, s = AbortSignal.timeout(1000);
  await assert.rejects(kiwi("", 429).search(q, s), (e: unknown) => e instanceof FlightSearchError && e.reason === "refused");
  await assert.rejects(kiwi(`data: ${JSON.stringify({ jsonrpc: "2.0", id: 1, result: { isError: true, content: [{ type: "text", text: "bad" }] } })}`).search(q, s),
    (e: unknown) => e instanceof FlightSearchError && e.reason === "refused");
  await assert.rejects(kiwi("data: {not json").search(q, s), (e: unknown) => e instanceof FlightSearchError && e.reason === "malformed");
  await assert.rejects(kiwi(rpc({ currency: "PLN", itineraries: [{ id: 1 }] })).search(q, s), (e: unknown) => e instanceof FlightSearchError && e.reason === "malformed");
});

// ---------------------------------------------------------------- options

test("three honest labels and the warnings worked out from the flights", async () => {
  const { itineraries } = await new MockFlightSearch().search(toQuery(full)!);
  const byId = Object.fromEntries(itineraries.map((i) => [i.id, i]));
  assert.deepEqual(traps(byId["demo-cheap"]!).sort(), ["airport_change", "different_airlines", "late_arrival"]);
  assert.deepEqual(traps(byId["demo-early"]!), ["early_departure"]);
  assert.deepEqual(traps(byId["demo-direct"]!), []);

  const options = pickOptions(itineraries, "PLN", 800);
  assert.deepEqual(options.map((o) => [o.pick, o.price]), [["cheapest", 742], ["fastest", 901], ["easiest", 958]]);
  assert.deepEqual(options.map((o) => o.overBudget), [false, true, true]);
  assert.equal(options[0]!.outbound.stops, 1);
  assert.deepEqual(options[0]!.outbound.airlines, ["Ryanair", "easyJet"]);
  assert.equal(options[2]!.outbound.toCountry, "Portugal");

  assert.deepEqual(pickOptions([byId["demo-direct"]!], "PLN", null).map((o) => o.pick), ["cheapest"], "one flight is not also 'fastest' and 'easiest'");
  assert.deepEqual(pickOptions([], "PLN", null), []);
});

test("stay links carry the place, the nights and the party; packages only when asked", async () => {
  const { itineraries } = await new MockFlightSearch().search(toQuery(full)!);
  const option = pickOptions(itineraries, "PLN", null)[0]!;
  const links = stayLinks(option, full);
  const booking = new URL(links.booking);
  assert.equal(booking.hostname, "www.booking.com");
  assert.equal(booking.searchParams.get("ss"), "Lisbon");
  assert.equal(booking.searchParams.get("checkin"), "2027-02-12");
  assert.equal(booking.searchParams.get("checkout"), "2027-02-16");
  assert.equal(booking.searchParams.get("group_adults"), "2");
  assert.match(links.airbnb, /^https:\/\/www\.airbnb\.com\/s\/Lisbon\/homes\?checkin=2027-02-12&checkout=2027-02-16&adults=2$/);
  assert.equal(links.packages, null);
  assert.equal(stayLinks(option, { ...full, package: true }).packages, "https://www.wakacje.pl/wczasy/portugalia/?od-2027-02-12,do-2027-02-16,2dorosle");
});

// ---------------------------------------------------------------- the routes

class Scripted implements ClaudeProvider {
  readonly mode = "live" as const;
  readonly calls: StructuredInput[] = [];
  constructor(private readonly answer: unknown) {}
  isConfigured() { return true; }
  async ask(): Promise<{ text: string }> { throw new Error("unused"); }
  async makeDocument(): Promise<never> { throw new Error("unused"); }
  async structured(input: StructuredInput) { this.calls.push(input); return { value: this.answer, usage: { inputTokens: 1, outputTokens: 1 } }; }
}

const post = (r: Rig, path: string, body: unknown) => r.call("POST", path, { token: USER_A, body });

test("understand: the model fills the brief, code says what's missing and what's assumed", async () => {
  const claude = new Scripted({ ...EMPTY_BRIEF, to: "Lisbon", departFrom: "2027-02-12", departTo: "2027-02-12", adults: 2, budget: 2000 });
  rig = await start({}, { claude });
  const res = await post(rig, "/v1/travel/plan/understand", { words: "Lizbona 12 lutego, we dwoje, do 2 tys.", today: TODAY });
  assert.equal(res.status, 200, res.text);
  assert.deepEqual(res.body.missing, ["from", "nights"]);
  assert.equal(res.body.brief.to, "Lisbon");
  assert.ok(res.body.assumptions.includes("no_checked_bag"));
  const sent = JSON.parse(claude.calls[0]!.user);
  assert.equal(sent.newWords, "Lizbona 12 lutego, we dwoje, do 2 tys.");
  assert.equal(sent.today, TODAY);
});

test("understand: an answer of the wrong shape keeps the brief as it was", async () => {
  rig = await start({}, { claude: new Scripted({ to: 42 }) });
  const res = await post(rig, "/v1/travel/plan/understand", { words: "z Gdańska", brief: brief({ to: "Lisbon" }), today: TODAY });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.brief.to, "Lisbon");
  assert.equal(res.body.brief.from, null);
});

test("search: refused until the brief is complete, then three options with links from the mock flights", async () => {
  rig = await start();
  const early = await post(rig, "/v1/travel/plan/search", { brief: brief({ to: "Lisbon" }), today: TODAY });
  assert.equal(early.status, 400);
  const res = await post(rig, "/v1/travel/plan/search", { brief: full, today: TODAY });
  assert.equal(res.status, 200, res.text);
  assert.equal(res.body.source, "Kiwi.com");
  assert.deepEqual(res.body.options.map((o: any) => o.pick), ["cheapest", "fastest", "easiest"]);
  assert.match(res.body.options[0].links.booking, /^https:\/\/www\.booking\.com\//);
  assert.match(res.body.options[0].bookingUrl, /^https:\/\/kiwi\.com\//);
  const line = rig.logs.find((l) => l.includes('"trip_search"'));
  assert.ok(line);
  assert.doesNotMatch(line!, /Lisbon|Gdańsk/);
});

test("search: Kiwi.com unreachable is said plainly, not as 'no flights'", async () => {
  const failing = { async search(_q: FlightQuery) { throw new FlightSearchError("unavailable"); } };
  rig = await start({}, { flightSearch: failing });
  const res = await post(rig, "/v1/travel/plan/search", { brief: full, today: TODAY });
  assert.equal(res.status, 502);
  assert.equal(res.body.error.code, "provider_unavailable");
});

test("the shared planner fixture is what the search route answers for the demo flights", async () => {
  const { readFileSync, writeFileSync } = await import("node:fs");
  const { join } = await import("node:path");
  rig = await start();
  const res = await post(rig, "/v1/travel/plan/search", { brief: { ...full, checkedBagPerAdult: true, package: true }, today: TODAY });
  assert.equal(res.status, 200, res.text);
  const file = join(process.cwd(), "..", "schemas", "fixtures", "travel_plan_v1.json");
  if (process.env.WRITE_TRAVEL_FIXTURE === "1") writeFileSync(file, `${JSON.stringify(res.body, null, 2)}\n`);
  assert.deepEqual(JSON.parse(readFileSync(file, "utf8")), res.body);
});
