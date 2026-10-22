// Studio, the app's routes (ADR-584, docs/implementation/STUDIO.md "Server API"). Every body is
// strict: approve carries only a digest, cancel and delete nothing.
import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import type { StudioContext } from "../studio/context.js";
import { isKeptFile } from "../studio/checks.js";
import { approveItem, cancelItem, createItem, deleteItem, getItem, listItems, readFile, type Refusal } from "../studio/service.js";

const idParam = z.strictObject({ id: z.uuid() });
const fileParam = z.strictObject({ id: z.uuid(), name: z.string().max(64) });
const approveBody = z.strictObject({ digest: z.string().regex(/^[0-9a-f]{64}$/) });
const empty = z.union([z.undefined(), z.null(), z.strictObject({})]);

export const studioRoutes = (deps: Deps, ctx: StudioContext | undefined): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  // Without MEMORY_ENCRYPTION_KEY nothing can be stored or read: the feature is off.
  const configured = (reply: FastifyReply): StudioContext | undefined => {
    if (!ctx) void reply.code(503).send({ error: "studio_disabled" });
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

  app.post("/v1/studio", { preHandler: auth, config: limit(30) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    const r = await createItem(c, principal(req).accountId, req.body);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(201).send(r.draft);
  });

  app.post("/v1/studio/:id/approve", { preHandler: auth, config: limit(30) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const body = p && parse(approveBody, req.body, reply);
    if (!c || !p || !body) return;
    const r = await approveItem(c, principal(req).accountId, p.id, body.digest);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(202).send(r.approved);
  });

  app.get("/v1/studio", { preHandler: auth, config: limit(1200) }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    return { items: await listItems(c, principal(req).accountId) };
  });

  app.get("/v1/studio/:id", { preHandler: auth, config: limit(1200) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const item = await getItem(c, principal(req).accountId, p.id);
    return item ?? reply.code(404).send({ error: "not_found" });
  });

  app.get("/v1/studio/:id/files/:name", { preHandler: auth, config: limit(600) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(fileParam, req.params, reply);
    if (!c || !p) return;
    if (!isKeptFile(p.name)) return reply.code(404).send({ error: "not_found" });
    const file = await readFile(c, principal(req).accountId, p.id, p.name);
    if (!file) return reply.code(404).send({ error: "not_found" });
    return reply
      .header("content-type", file.mime)
      .header("cache-control", "private, no-store")
      .header("x-content-type-options", "nosniff")
      // An SVG opened directly must not run anything, whatever is in it.
      .header("content-security-policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox")
      .header("content-disposition", `attachment; filename="${p.name}"`)
      .send(file.bytes);
  });

  app.post("/v1/studio/:id/cancel", { preHandler: auth, config: limit(120) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p || !noBody(req.body, reply)) return;
    const r = await cancelItem(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(204).send();
  });

  app.delete("/v1/studio/:id", { preHandler: auth, config: limit(240) }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const r = await deleteItem(c, principal(req).accountId, p.id);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return r;
  });
};
