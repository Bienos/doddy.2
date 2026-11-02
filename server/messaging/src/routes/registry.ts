// Company registers (ADR-683): GET /v1/registry/ceidg?nip=… Bearer: the account's device token. Off unless
// CEIDG_API_TOKEN is set (503 registry_disabled). The iPhone asks the Ministry of Finance's VAT register itself
// (no key); this route exists because CEIDG needs a token that must stay on the server. Only the NIP comes in;
// the answer is CEIDG's entry cut to name, status and business address. Nothing is stored; the log holds the
// outcome and timing, never the NIP.
import type { FastifyPluginAsync } from "fastify";
import { requireDevice } from "../auth.js";
import type { Db } from "../db.js";
import { type CeidgClient, isValidNip } from "../registry/ceidg.js";

export const registryRoutes = (deps: { db: Db; ceidg?: CeidgClient }): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);

  app.get("/v1/registry/ceidg", {
    preHandler: auth,
    config: { rateLimit: { max: 30, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    if (!deps.ceidg) return reply.code(503).send({ error: "registry_disabled" });
    const nip = (req.query as { nip?: unknown })?.nip;
    if (typeof nip !== "string" || !isValidNip(nip)) return reply.code(400).send({ error: "invalid_request", fields: ["nip"] });
    const started = Date.now();
    const answer = await deps.ceidg.lookup(nip);
    req.log.info({ outcome: answer.kind, status: answer.kind === "unavailable" ? answer.status : undefined, ms: Date.now() - started }, "ceidg looked up");
    switch (answer.kind) {
      case "found": return { firma: answer.firma };
      case "not_found": return reply.code(404).send({ error: "not_found" });
      case "busy": return reply.code(429).send({ error: "busy" });
      case "unavailable": return reply.code(502).send({ error: "upstream_unavailable" });
    }
  });
};
