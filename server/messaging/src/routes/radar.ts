import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { canPush } from "../outbox.js";
import { markSeen, radarBody, radarState, saveAlerts } from "../news/radar.js";

// On my radar alerts (decision 2026-11-10-radar-alerts). The iPhone sends the whole list of follows the person
// let Doddy's server check, and the server keeps exactly that list. Behind RADAR_ALERTS_ENABLED: while it is off
// nothing new can be stored, but an empty list is always accepted, so turning checks off and deleting them
// works whatever the switch says.

const seenBody = z.object({ ids: z.array(z.string().uuid()).max(100).optional() });

export const radarRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const available = deps.radar?.enabled === true && !!deps.news;

  const state = async (accountId: string) => ({
    available,
    // A notification can reach this account now: the server can send pushes and the iPhone gave a token.
    push: !!deps.push && await canPush(db, accountId),
    ...(await radarState(db, accountId)),
  });

  app.get("/v1/news/radar", { preHandler: auth }, async (req) => state(principal(req).accountId));

  app.put("/v1/news/radar", { preHandler: auth, config: { rateLimit: { max: 30, timeWindow: "1 hour" } } }, async (req, reply) => {
    const body = parse(radarBody, req.body, reply);
    if (!body) return;
    if (!available && body.alerts.length > 0) return reply.code(503).send({ error: "radar_disabled" });
    const { accountId } = principal(req);
    await saveAlerts(db, accountId, body, new Date());
    return state(accountId);
  });

  app.post("/v1/news/radar/seen", { preHandler: auth }, async (req, reply) => {
    const body = parse(seenBody, req.body ?? {}, reply);
    if (!body) return;
    const marked = await markSeen(db, principal(req).accountId, body.ids, new Date());
    return { marked };
  });
};
