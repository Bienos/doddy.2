// Errands, the app's routes (ADR-563, docs/implementation/ERRANDS.md "Server API"). Every body is
// strict: approve and ack carry only a digest, cancel and delete nothing.
import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import type { ErrandContext } from "../errands/context.js";
import {
  ackErrand, approveErrand, cancelErrand, createErrand, deleteErrand, getErrand, listErrands, type Refusal,
} from "../errands/service.js";

const idParam = z.strictObject({ id: z.uuid() });
const hex64 = z.string().regex(/^[0-9a-f]{64}$/);
const approveBody = z.strictObject({ digest: hex64 });
const ackBody = z.strictObject({ resultDigest: hex64 });
const empty = z.union([z.undefined(), z.null(), z.strictObject({})]);

export const errandRoutes = (deps: Deps, ctx: ErrandContext | undefined): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  // Without MEMORY_ENCRYPTION_KEY nothing can be stored or read: the feature is off.
  const configured = (reply: FastifyReply): ErrandContext | undefined => {
    if (!ctx) void reply.code(503).send({ error: "errands_disabled" });
    return ctx;
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

  app.post("/v1/errands", { preHandler: auth, config: limit(30) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    const r = await createErrand(c, principal(req).accountId, req.body);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(201).send(r.draft);
  });

  app.post("/v1/errands/:id/approve", { preHandler: auth, config: limit(30) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const body = p && parse(approveBody, req.body, reply);
    if (!c || !p || !body) return;
    const r = await approveErrand(c, principal(req).accountId, p.id, body.digest);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(202).send(r.approved);
  });

  app.get("/v1/errands", { preHandler: auth, config: limit(1200) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    return { errands: await listErrands(c, principal(req).accountId) };
  });

  app.get("/v1/errands/:id", { preHandler: auth, config: limit(1200) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const e = await getErrand(c, principal(req).accountId, p.id);
    return e ?? reply.code(404).send({ error: "not_found" });
  });

  app.post("/v1/errands/:id/cancel", { preHandler: auth, config: limit(120) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p || !noBody(req.body, reply)) return;
    const r = await cancelErrand(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(204).send();
  });

  // The app saved the result on the iPhone: the server deletes its copy and says what it deleted.
  app.post("/v1/errands/:id/ack", { preHandler: auth, config: limit(240) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const body = p && parse(ackBody, req.body, reply);
    if (!c || !p || !body) return;
    const r = await ackErrand(c, principal(req).accountId, p.id, body.resultDigest);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return r;
  });

  app.delete("/v1/errands/:id", { preHandler: auth, config: limit(240) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const r = await deleteErrand(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(204).send();
  });
};
