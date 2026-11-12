/**
 * Licensed Jakdojade partner routes for DODDY's signed-in iPhone clients.
 * Disabled by default. No public proxy, account scraping or ticket operations.
 * Location names and coordinates are request-scoped; nothing is retained.
 */
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { requireDevice } from "../auth.js";
import { parse } from "../app.js";
import type { Db } from "../db.js";
import {
  JakdojadePartnerClient,
  JakdojadePartnerError,
  type PartnerRouteSearch,
} from "../integrations/jakdojade.js";

const coordinate = z.strictObject({
  latitude: z.number().finite().min(-90).max(90),
  longitude: z.number().finite().min(-180).max(180),
});
const city = z.string().trim().min(2).max(40).regex(/^[A-Z_]+$/);
const placesBody = z.strictObject({
  city: city,
  query: z.string().trim().min(2).max(100),
});
const routesBody = z.strictObject({
  from: coordinate,
  to: coordinate,
  day: z.string().regex(/^\d{2}\.\d{2}\.\d{2}$/).optional(),
  hour: z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/).optional(),
  arriving: z.boolean().optional(),
  mode: z.enum(["optimal", "convenient", "hurry"]).optional(),
  avoidBuses: z.boolean().optional(),
  avoidTransfers: z.boolean().optional(),
});

function failure(err: unknown): { status: number; code: string } {
  if (!(err instanceof JakdojadePartnerError)) return { status: 502, code: "upstream_unavailable" };
  switch (err.code) {
  case "not_configured": return { status: 503, code: "jakdojade_not_configured" };
  case "invalid_request": return { status: 400, code: "invalid_request" };
  case "unauthorized":
  case "forbidden": return { status: 503, code: "jakdojade_not_configured" };
  case "rate_limited": return { status: 429, code: "provider_busy" };
  case "unavailable": return { status: 502, code: "upstream_unavailable" };
  case "invalid_response": return { status: 502, code: "invalid_provider_response" };
  }
}

export const jakdojadeRoutes = (
  deps: { db: Db; jakdojade?: JakdojadePartnerClient },
): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);

  app.get("/v1/journeys/provider", {
    preHandler: auth,
    config: { rateLimit: { max: 40, timeWindow: "1 hour" } },
  }, async () => ({
    provider: "jakdojade",
    available: Boolean(deps.jakdojade),
    capabilities: deps.jakdojade ? ["locations", "routes"] : [],
    tickets: false,
    realtime: false,
  }));

  app.post("/v1/journeys/places", {
    preHandler: auth,
    config: { rateLimit: { max: 20, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    if (!deps.jakdojade) return reply.code(503).send({ error: "jakdojade_not_configured" });
    const body = parse(placesBody, req.body, reply);
    if (!body) return;
    try {
      const locations = await deps.jakdojade.locations(body.city, body.query);
      return { source: "Jakdojade", fetchedAt: new Date().toISOString(), locations };
    } catch (error) {
      const fault = failure(error);
      return reply.code(fault.status).send({ error: fault.code });
    }
  });

  app.post("/v1/journeys/routes", {
    preHandler: auth,
    config: { rateLimit: { max: 20, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    if (!deps.jakdojade) return reply.code(503).send({ error: "jakdojade_not_configured" });
    const body = parse(routesBody, req.body, reply);
    if (!body) return;
    try {
      const results = await deps.jakdojade.routes(body as PartnerRouteSearch);
      return { source: "Jakdojade", fetchedAt: new Date().toISOString(), routes: results,
        realtime: false, tickets: false };
    } catch (error) {
      const fault = failure(error);
      return reply.code(fault.status).send({ error: fault.code });
    }
  });
};
