// File-ready pushes, the app's route (owner, 9 Nov 2026). The body is strict: the file's signed link and the language the
// push is written in. Only a link on DOCUMENTS_ORIGIN is accepted.
import type { FastifyPluginAsync } from "fastify";
import { type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { registerWatch, type FileWatchContext } from "../fileWatches.js";

export const fileWatchRoutes = (deps: Deps, ctx: FileWatchContext | undefined): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  app.post("/v1/file-watches", { preHandler: auth, config: { rateLimit: { max: 60, timeWindow: "1 hour" } } }, async (req, reply) => {
    if (!ctx) return reply.code(503).send({ error: "file_watch_disabled" });
    const result = await registerWatch(ctx, principal(req).accountId, req.body);
    if (!result.ok) return reply.code(result.status).send({ error: result.error });
    return reply.code(201).send({ id: result.id });
  });
};
