// Price watches, the app's routes (docs/implementation/SHOPPING_WATCH.md section 3). Bearer: the account's
// device token. Every body is strict: approve carries only a digest, stop and delete nothing. Off unless
// WATCHES_ENABLED=1 and MEMORY_ENCRYPTION_KEY is set: every route then answers 503 watches_disabled.
import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import type { WatchContext } from "../watches/context.js";
import { approveWatch, createWatch, deleteWatch, getWatch, listWatches, stopWatch, type Refusal } from "../watches/service.js";

const idParam = z.strictObject({ id: z.uuid() });
const hex64 = z.string().regex(/^[0-9a-f]{64}$/);
const approveBody = z.strictObject({ digest: hex64 });
const empty = z.union([z.undefined(), z.null(), z.strictObject({})]);

export const watchRoutes = (deps: Deps, ctx: WatchContext | undefined): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  // Without the key, the switch or a fetcher nothing can be stored or read: the feature is off.
  const configured = (reply: FastifyReply): WatchContext | undefined => {
    if (!ctx?.enabled) void reply.code(503).send({ error: "watches_disabled" });
    return ctx?.enabled ? ctx : undefined;
  };
  const refusal = (reply: FastifyReply, r: Refusal) => {
    const { status, ...body } = r;
    return reply.code(status).send(body);
  };
  const noBody = (body: unknown, reply: FastifyReply) => {
    if (empty.safeParse(body).success) return true;
    void reply.code(400).send({ error: "invalid_request", fields: [] });
    return false;
  };
  const limit = (max: number) => ({ rateLimit: { max, timeWindow: "1 hour" } });

  app.post("/v1/watches", { preHandler: auth, config: limit(30) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    // When the app closes the connection nobody is waiting for the card: the page read stops.
    const controller = new AbortController();
    reply.raw.once("close", () => { if (!reply.raw.writableFinished) controller.abort(); });
    const r = await createWatch(c, principal(req).accountId, req.body, controller.signal);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(201).send(r.draft);
  });

  app.post("/v1/watches/:id/approve", { preHandler: auth, config: limit(30) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const body = p && parse(approveBody, req.body, reply);
    if (!c || !p || !body) return;
    const r = await approveWatch(c, principal(req).accountId, p.id, body.digest);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(202).send(r.approved);
  });

  app.get("/v1/watches", { preHandler: auth, config: limit(1200) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    return { watches: await listWatches(c, principal(req).accountId) };
  });

  app.get("/v1/watches/:id", { preHandler: auth, config: limit(1200) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const w = await getWatch(c, principal(req).accountId, p.id);
    return w ?? reply.code(404).send({ error: "not_found" });
  });

  app.post("/v1/watches/:id/stop", { preHandler: auth, config: limit(120) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p || !noBody(req.body, reply)) return;
    const r = await stopWatch(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(204).send();
  });

  app.delete("/v1/watches/:id", { preHandler: auth, config: limit(240) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const r = await deleteWatch(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(204).send();
  });
};
