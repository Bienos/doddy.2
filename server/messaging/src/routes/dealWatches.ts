// Deal watches, the app's routes (decision 2026-11-13-leaflet-results-and-deal-watches). Bearer: the account's device
// token. Bodies are strict. Off unless DEAL_WATCHES_ENABLED=1, MEMORY_ENCRYPTION_KEY is set and the leaflet catalog is
// on: every route then answers 503 deal_watches_disabled. Nothing here reads a leaflet page or asks a model: matches
// come from the catalog, in code.
import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import {
  createDealWatch, dealWatchOffers, deleteDealWatch, listDealWatches, type DealWatchContext, type Refusal,
} from "../deals/dealWatches.js";

const idParam = z.strictObject({ id: z.uuid() });

export const dealWatchRoutes = (deps: Deps, ctx: DealWatchContext | undefined): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  const configured = (reply: FastifyReply): DealWatchContext | undefined => {
    if (!ctx?.enabled) void reply.code(503).send({ error: "deal_watches_disabled" });
    return ctx?.enabled ? ctx : undefined;
  };
  const refusal = (reply: FastifyReply, r: Refusal) => {
    const { status, ...body } = r;
    return reply.code(status).send(body);
  };
  const limit = (max: number) => ({ rateLimit: { max, timeWindow: "1 hour" } });

  app.post("/v1/deal-watches", { preHandler: auth, config: limit(30) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    const r = await createDealWatch(c, principal(req).accountId, req.body);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(201).send(r);
  });

  app.get("/v1/deal-watches", { preHandler: auth, config: limit(600) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    return { watches: await listDealWatches(c, principal(req).accountId) };
  });

  app.get("/v1/deal-watches/:id/offers", { preHandler: auth, config: limit(600) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const r = await dealWatchOffers(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return r.matches;
  });

  app.delete("/v1/deal-watches/:id", { preHandler: auth, config: limit(240) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const r = await deleteDealWatch(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(204).send();
  });
};
