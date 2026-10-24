// Leaflets (SHOPPING.md §2): POST /v1/deals/search. Bearer: the account's device token. Off unless DEALS_ENABLED=1
// (503 deals_disabled). The body is strict; a request is counted against the daily caps before anything is
// fetched (429 daily_limit). The reply is the contract's (schemas/fixtures/deals_search_v1.json). Nothing the
// person asked for is stored or logged: the database holds counts per account and day, the log holds counts,
// statuses and timings.
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import type { Db } from "../db.js";
import { searchDeals, type DealsDeps } from "../deals/service.js";
import { CHAINS } from "../deals/types.js";
import { addUsage, reserve } from "../deals/usage.js";

export const SearchBody = z.strictObject({
  items: z.array(z.string().trim().min(1).max(60)).min(1).max(12),
  chains: z.array(z.enum(CHAINS)).min(1).max(CHAINS.length * 2).optional(),
  language: z.string().regex(/^[a-z]{2}$/),
});

/** Registered with `app.register(dealsRoutes(deps))`; `deps.deals` absent or switched off answers 503. */
export const dealsRoutes = (deps: { db: Db; deals?: DealsDeps }): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  const deals = deps.deals;

  app.post("/v1/deals/search", {
    preHandler: auth,
    config: { rateLimit: { max: 60, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    if (!deals || !deals.settings.enabled) return reply.code(503).send({ error: "deals_disabled" });
    const body = parse(SearchBody, req.body, reply);
    if (!body) return;
    const accountId = principal(req).accountId;
    const reservation = await reserve(deps.db, accountId, {
      perAccount: deals.settings.dailyPerAccount, perServer: deals.settings.dailyPerServer,
    });
    if (reservation !== "ok") {
      req.log.warn({ cap: reservation }, "deals daily cap reached");
      return reply.code(429).send({ error: "daily_limit" });
    }
    // When the app closes the connection nobody is waiting: page reads stop.
    const controller = new AbortController();
    reply.raw.once("close", () => { if (!reply.raw.writableFinished) controller.abort(); });
    const { response, stats } = await searchDeals(deals, body, controller.signal);
    await addUsage(deps.db, accountId, stats).catch((err: Error) => req.log.error({ err: { message: err.message } }, "deals usage not recorded"));
    req.log.info({
      items: body.items.length, chains: stats.chains, statuses: stats.statuses, offers: stats.offers, checks: stats.checks,
      pagesRead: stats.pagesRead, inputTokens: stats.inputTokens, outputTokens: stats.outputTokens, picked: stats.picked, ms: stats.ms,
    }, "deals searched");
    if (controller.signal.aborted) return reply;
    return response;
  });
};
