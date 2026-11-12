import assert from "node:assert/strict";
import { test } from "node:test";
import {
  JakdojadePartnerClient, JakdojadePartnerError,
  type PartnerFetch,
} from "../src/integrations/jakdojade.js";

const AUTH = { licenseKey: "test-licence", secret: "test-secret" };
const ROUTES = `<?xml version="1.0" encoding="utf-8"?>
<ROUTE_SEARCH_RESULT cityName="Warszawa">
  <routes>
    <route startDate="20.11.26 08:05" finishDate="20.11.26 08:43">
      <lines>
        <line name="M2" vehicleType="subway" direction="Bródno">
          <stops>
            <stop name="Rondo ONZ" departureTime="08:10"/>
            <stop name="Świętokrzyska" arrivalTime="08:13" departureTime="08:14"/>
          </stops>
        </line>
        <line name="walk" vehicleType="walk">
          <stops><stop name="Metro"/><stop name="Cel" arrivalTime="08:43"/></stops>
        </line>
      </lines>
    </route>
  </routes>
</ROUTE_SEARCH_RESULT>`;
const LOCATIONS = `<LOCATIONS_MATCH_RESULT resultCount="1">
  <locations>
    <location type="stop"><coordinate>52.232:21.012</coordinate><name>Świętokrzyska</name><stopCode>1011-01</stopCode></location>
  </locations>
</LOCATIONS_MATCH_RESULT>`;

const start = { latitude: 52.23232, longitude: 21.01599 };
const end = { latitude: 52.26289, longitude: 20.98983 };

test("real partner route builder: only fixed HTTPS endpoint and authenticated GET", async () => {
  const calls: { url: URL; init: RequestInit }[] = [];
  const fetcher: PartnerFetch = async (url, init) => {
    calls.push({ url, init });
    return new Response(ROUTES, { status: 200, headers: { "content-type": "application/xml" } });
  };
  const client = new JakdojadePartnerClient(async () => AUTH, fetcher);
  const routes = await client.routes({
    from: start, to: end, day: "20.11.26", hour: "08:50",
    arriving: true, mode: "convenient", avoidBuses: true, avoidTransfers: true,
  });
  assert.equal(calls.length, 1);
  const { url, init } = calls[0]!;
  assert.equal(url.origin, "https://jakdojade.pl");
  assert.equal(url.pathname, "/api/rest/v2/routes");
  assert.equal(init.method, "GET");
  assert.equal(init.redirect, "error");
  const qs = url.searchParams;
  assert.equal(qs.get("fc"), "52.232320:21.015990");
  assert.equal(qs.get("tc"), "52.262890:20.989830");
  assert.equal(qs.get("rc"), "3");
  assert.equal(qs.get("ia"), "true");
  assert.equal(qs.get("h"), "08:50");
  assert.equal(qs.get("t"), "convenient");
  assert.equal(qs.get("aac"), "true");
  assert.equal(qs.get("aab"), "true");
  assert.equal(qs.get("output"), "xml");
  assert.equal(qs.get("test"), null);
  assert.equal((init.headers as Record<string, string>).authorization,
    `Basic ${Buffer.from("test-licence:test-secret").toString("base64")}`);
  assert.equal(routes.length, 1);
  assert.equal(routes[0]?.startLocal, "20.11.26 08:05");
  assert.equal(routes[0]?.finishLocal, "20.11.26 08:43");
  assert.equal(routes[0]?.segments[0]?.line, "M2");
  assert.equal(routes[0]?.segments[0]?.stops[0]?.name, "Rondo ONZ");
  assert.equal(routes[0]?.segments[1]?.vehicleType, "walk");
});

test("location matcher returns verified candidates, never silently chooses a destination", async () => {
  const client = new JakdojadePartnerClient(async () => AUTH, async (url, init) => {
    assert.equal(url.pathname, "/api/rest/v1/locationmatcher");
    assert.equal(url.searchParams.get("agg"), "WARSZAWA");
    assert.equal(url.searchParams.get("text"), "Świętokrzyska");
    assert.equal(init.method, "GET");
    return new Response(LOCATIONS);
  });
  const results = await client.locations("warszawa", "Świętokrzyska");
  assert.deepEqual(results, [{
    name: "Świętokrzyska",
    type: "stop",
    coordinate: { latitude: 52.232, longitude: 21.012 },
    stopCode: "1011-01",
  }]);
});

test("no partner licence NEVER sends requests or shows sample routes", async () => {
  let calls = 0;
  const client = new JakdojadePartnerClient(async () => null, async () => {
    calls += 1;
    return new Response(ROUTES);
  });
  await assert.rejects(() => client.routes({ from: start, to: end }),
    (err) => err instanceof JakdojadePartnerError && err.code === "not_configured");
  assert.equal(calls, 0);
});

test("coordinates, city and date are validated before the provider can be contacted", async () => {
  let calls = 0;
  const client = new JakdojadePartnerClient(async () => AUTH, async () => {
    calls += 1;
    return new Response(ROUTES);
  });
  const bad = [
    { from: { latitude: 91, longitude: 21 }, to: end },
    { from: start, to: { latitude: Infinity, longitude: 22 } },
    { from: start, to: end, day: "bad" },
    { from: start, to: end, hour: "now" },
  ];
  for (const request of bad) {
    await assert.rejects(() => client.routes(request),
      (err) => err instanceof JakdojadePartnerError && err.code === "invalid_request");
  }
  await assert.rejects(() => client.locations("WARSZAWA&foo=bar", "street"),
    (err) => err instanceof JakdojadePartnerError && err.code === "invalid_request");
  assert.equal(calls, 0);
});

test("HTTP auth, limits, and invalid upstream XML fail explicitly", async () => {
  for (const [status, reason] of [
    [401, "unauthorized"], [403, "forbidden"], [429, "rate_limited"], [503, "unavailable"],
  ] as const) {
    const client = new JakdojadePartnerClient(async () => AUTH, async () => new Response("", { status }));
    await assert.rejects(() => client.routes({ from: start, to: end }),
      (err) => err instanceof JakdojadePartnerError && err.code === reason);
  }
  const html = new JakdojadePartnerClient(async () => AUTH,
    async () => new Response("<!DOCTYPE html><html>Not routes</html>"));
  await assert.rejects(() => html.routes({ from: start, to: end }),
    (err) => err instanceof JakdojadePartnerError && err.code === "invalid_response");

  const tooLarge = new JakdojadePartnerClient(async () => AUTH,
    async () => new Response(ROUTES, { headers: { "content-length": "700000" } }));
  await assert.rejects(() => tooLarge.routes({ from: start, to: end }),
    (err) => err instanceof JakdojadePartnerError && err.code === "invalid_response");
});

test("empty official route list returns zero, never fabricated departures or tickets", async () => {
  const client = new JakdojadePartnerClient(async () => AUTH,
    async () => new Response("<ROUTE_SEARCH_RESULT cityName=\"Warszawa\"/>"));
  const routes = await client.routes({ from: start, to: end });
  assert.deepEqual(routes, []);
});
