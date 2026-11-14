import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { JakdojadePartnerClient } from "../src/integrations/jakdojade.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

const XML = `<ROUTE_SEARCH_RESULT cityName="Warszawa"><routes><route startDate="20.11.26 08:05" finishDate="20.11.26 08:43"><lines><line name="M2" vehicleType="subway"><stops><stop name="Rondo ONZ" departureTime="08:10"/><stop name="Świętokrzyska" arrivalTime="08:43"/></stops></line></lines></route></routes></ROUTE_SEARCH_RESULT>`;
const placeXML = `<LOCATIONS_MATCH_RESULT resultCount="1"><locations><location type="stop"><coordinate>52.232:21.012</coordinate><name>Świętokrzyska</name></location></locations></LOCATIONS_MATCH_RESULT>`;
const trip = {
  from: { latitude: 52.23232, longitude: 21.01599 },
  to: { latitude: 52.26289, longitude: 20.98983 },
  day: "20.11.26", hour: "08:50", arriving: true,
};

describe("Jakdojade signed-in phone gateway", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  async function world(enabled = false) {
    let upstreamCalls = 0;
    const partner = enabled
      ? new JakdojadePartnerClient(async () => ({ licenseKey: "licence", secret: "private-secret" }), async (url) => {
        upstreamCalls += 1;
        return new Response(url.pathname.includes("locationmatcher") ? placeXML : XML, { headers: { "content-type": "application/xml" } });
      })
      : undefined;
    const world = await testApp(db, { jakdojade: partner });
    const account = await world.app.inject({ method: "POST", url: "/v1/accounts" });
    assert.equal(account.statusCode, 201);
    const { deviceToken } = account.json() as { deviceToken: string };
    const authorization = { authorization: `Bearer ${deviceToken}` };
    const post = async (path: string, body: object, headers = authorization) =>
      await world.app.inject({
        method: "POST", url: path, payload: JSON.stringify(body),
        headers: { ...headers, "content-type": "application/json" },
      });
    return { ...world, authorization, post, upstreamCalls: () => upstreamCalls };
  }

  test("disabled integration: authenticated status says unavailable; never calls partner", async () => {
    const w = await world();
    const status = await w.app.inject({ method: "GET", url: "/v1/journeys/provider", headers: w.authorization });
    assert.equal(status.statusCode, 200);
    assert.deepEqual(status.json(), {
      provider: "jakdojade", available: false, capabilities: [], tickets: false, realtime: false,
    });
    const result = await w.post("/v1/journeys/routes", trip);
    assert.equal(result.statusCode, 503);
    assert.deepEqual(result.json(), { error: "jakdojade_not_configured" });
    assert.equal(w.upstreamCalls(), 0);
    await w.app.close();
  });

  test("all journey routes require a real signed-in device", async () => {
    const w = await world(true);
    for(const [method, url] of [
      ["GET", "/v1/journeys/provider"], ["POST", "/v1/journeys/places"], ["POST", "/v1/journeys/routes"]
    ] as const) {
      const result = await w.app.inject({ method, url, payload: method === "POST" ? {} : undefined });
      assert.equal(result.statusCode, 401);
    }
    assert.equal(w.upstreamCalls(), 0);
    await w.app.close();
  });

  test("valid request obtains real source structure; invalid request cannot contact partner", async () => {
    const w = await world(true);
    const status = await w.app.inject({ method: "GET", url: "/v1/journeys/provider", headers: w.authorization });
    assert.equal(status.json().available, true);
    const invalid = await w.post("/v1/journeys/routes", { ...trip, from: { latitude: 123, longitude: 12 } });
    assert.equal(invalid.statusCode, 400);
    assert.equal(w.upstreamCalls(), 0);
    const forbidden = await w.post("/v1/journeys/routes", { ...trip, purchaseTicket: true });
    assert.equal(forbidden.statusCode, 400);
    assert.equal(w.upstreamCalls(), 0);
    const result = await w.post("/v1/journeys/routes", trip);
    assert.equal(result.statusCode, 200);
    const body = result.json();
    assert.equal(body.source, "Jakdojade");
    assert.equal(body.realtime, false);
    assert.equal(body.tickets, false);
    assert.equal(body.routes[0].segments[0].line, "M2");
    assert.equal(w.upstreamCalls(), 1);
    const missingCity = await w.post("/v1/journeys/places", { city: "WARSZAWA", query: "Świętokrzyska" });
    assert.equal(missingCity.statusCode, 200);
    assert.equal(missingCity.json().locations[0].name, "Świętokrzyska");
    await w.app.close();
  });
});
