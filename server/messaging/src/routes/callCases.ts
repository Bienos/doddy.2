// Call cases, the app's side (ADR-500..507). docs/decisions/calls.md. Every body is strict: approve,
// end, takeover and ack can't carry a number, a fact or a duration, only ids and digests.
import type { FastifyPluginAsync, FastifyReply } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { ackResult, cancelCase, getCase, listCases, setLiveActivityToken } from "../taskCalls/cases.js";
import type { TaskCallContext } from "../taskCalls/context.js";
import { approve, caseOwnedBy, createCase, endCall, latestAttempt, liveView, type Refusal } from "../taskCalls/service.js";
import { startTakeover } from "../taskCalls/takeover.js";

const idParam = z.strictObject({ id: z.uuid() });
const hex64 = z.string().regex(/^[0-9a-f]{64}$/);
const approveBody = z.strictObject({ digest: hex64, at: z.iso.datetime({ offset: true }).optional() });
const ackBody = z.strictObject({ attemptId: z.uuid(), resultDigest: hex64 });
const liveQuery = z.strictObject({ after: z.string().max(40).regex(/^[0-9 :.+\-T]+$/).optional() });
const liveActivityBody = z.strictObject({ token: z.string().regex(/^[0-9a-f]{64,400}$/), environment: z.enum(["sandbox", "production"]) });
const empty = z.union([z.undefined(), z.null(), z.strictObject({})]);
/** True when the body is empty (or {}); otherwise sends 400. */
function emptyBody(body: unknown, reply: FastifyReply): boolean {
  if (empty.safeParse(body).success) return true;
  void reply.code(400).send({ error: "invalid_request", fields: [] });
  return false;
}

export const callCaseRoutes = (deps: Deps, ctx: TaskCallContext | undefined): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  const configured = (reply: FastifyReply): TaskCallContext | undefined => {
    if (!ctx) void reply.code(503).send({ error: "not_configured" });
    return ctx;
  };
  const refusal = (reply: FastifyReply, r: Refusal) => {
    const { status, ...body } = r;
    return reply.code(status).send(body);
  };

  // What the server can do now; the app shows "needs setup" or "off" instead of a form that fails.
  app.get("/v1/call-cases/availability", { preHandler: auth }, async (req) => {
    const { rows } = await deps.db.query("SELECT 1 FROM phone_numbers WHERE account_id = $1", [principal(req).accountId]);
    const agentProblems = ctx ? await ctx.drift.problems() : [];
    return {
      available: !!ctx && !ctx.settings.killSwitch && agentProblems.length === 0,
      configured: !!ctx,
      killSwitch: ctx?.settings.killSwitch ?? false,
      phoneVerified: rows.length > 0,
      recordingNotice: ctx?.settings.notice ?? "off",
      recordsAudio: false,
      maxDurationSecs: ctx?.settings.limits.maxDurationSecs ?? 300,
      hours: { zone: "Europe/Warsaw", from: "08:00", to: "20:00" },
      // Names of agent settings that differ from the spec (no values); calls are refused while any are listed.
      agentProblems,
    };
  });

  app.post("/v1/call-cases", { preHandler: auth, config: { rateLimit: { max: 20, timeWindow: "1 hour" } } }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    const r = await createCase(c, principal(req).accountId, req.body);
    if ("refusal" in r) return refusal(reply, r.refusal);
    return reply.code(201).send(r.preview);
  });

  app.get("/v1/call-cases", { preHandler: auth }, async (req, reply) => {
    const c = configured(reply);
    if (!c) return;
    return { cases: await listCases(c, principal(req).accountId) };
  });

  app.get("/v1/call-cases/:id", { preHandler: auth }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const kase = await getCase(c, principal(req).accountId, p.id);
    return kase ?? reply.code(404).send({ error: "not_found" });
  });

  app.post("/v1/call-cases/:id/approve", { preHandler: auth, config: { rateLimit: { max: 20, timeWindow: "1 hour" } } }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const body = p && parse(approveBody, req.body, reply);
    if (!c || !p || !body) return;
    const { accountId, deviceId } = principal(req);
    const r = await approve(c, accountId, deviceId, p.id, body.digest, body.at);
    if ("refusal" in r) return refusal(reply, r.refusal);
    switch (r.dial.kind) {
      case "dialing": case "scheduled": case "unknown":
        return reply.code(202).send({ attemptId: r.attemptId, state: r.dial.kind });
      case "refused":
        return reply.code(409).send({ error: "gate_refused", gate: r.dial.gate, attemptId: r.attemptId });
      case "not_placed":
        return reply.code(502).send({ error: "provider_refused", attemptId: r.attemptId });
      default:
        return reply.code(409).send({ error: "not_dialled", state: r.dial.kind, attemptId: r.attemptId });
    }
  });

  app.get("/v1/call-cases/:id/live", { preHandler: auth, config: { rateLimit: { max: 3000, timeWindow: "1 hour" } } }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const q = p && parse(liveQuery, req.query, reply);
    if (!c || !p || !q) return;
    const view = await liveView(c, principal(req).accountId, p.id, q.after);
    return view ?? reply.code(404).send({ error: "not_found" });
  });

  // "Zakończ": Doddy says goodbye and the call ends.
  app.post("/v1/call-cases/:id/end", { preHandler: auth }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p || !emptyBody(req.body, reply)) return;
    const accountId = principal(req).accountId;
    if (!(await caseOwnedBy(c.db, p.id, accountId))) return reply.code(404).send({ error: "not_found" });
    const a = await latestAttempt(c.db, p.id);
    if (!a) return reply.code(409).send({ error: "not_live" });
    const r = await endCall(c, a.id, "user_ended");
    if (r === "not_live" || r === "taken_over") return reply.code(409).send({ error: r });
    return reply.code(202).send({ state: r });
  });

  // "Przejmij": rings the user's verified phone; they press 1 to join.
  app.post("/v1/call-cases/:id/takeover", { preHandler: auth, config: { rateLimit: { max: 10, timeWindow: "1 hour" } } }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p || !emptyBody(req.body, reply)) return;
    const r = await startTakeover(c, principal(req).accountId, p.id);
    if (r.kind === "refused") {
      return reply.code(r.error === "not_found" ? 404 : r.error === "calls_disabled" ? 503 : 409).send({ error: r.error });
    }
    return reply.code(202).send({ takeoverId: r.takeoverId, state: r.state });
  });

  // The app saved the result on the iPhone: the server deletes its copy and says what it deleted.
  app.post("/v1/call-cases/:id/ack", { preHandler: auth }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const body = p && parse(ackBody, req.body, reply);
    if (!c || !p || !body) return;
    const r = await ackResult(c, principal(req).accountId, p.id, body.attemptId, body.resultDigest);
    if (r === "not_found") return reply.code(404).send({ error: "not_found" });
    if (r === "mismatch") return reply.code(409).send({ error: "result_mismatch" });
    return r;
  });

  app.post("/v1/call-cases/:id/cancel", { preHandler: auth }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p || !emptyBody(req.body, reply)) return;
    const r = await cancelCase(c, principal(req).accountId, p.id);
    if (r === "not_found") return reply.code(404).send({ error: "not_found" });
    if (r === "live") return reply.code(409).send({ error: "call_live" });
    return reply.code(204).send();
  });

  app.put("/v1/call-cases/:id/live-activity", { preHandler: auth }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    const body = p && parse(liveActivityBody, req.body, reply);
    if (!c || !p || !body) return;
    const ok = await setLiveActivityToken(c, principal(req).accountId, p.id, body.token, body.environment);
    return ok ? reply.code(204).send() : reply.code(404).send({ error: "not_found" });
  });

  app.delete("/v1/call-cases/:id/live-activity", { preHandler: auth }, async (req, reply) => {
    const c = configured(reply);
    const p = c && parse(idParam, req.params, reply);
    if (!c || !p) return;
    const ok = await setLiveActivityToken(c, principal(req).accountId, p.id, null, null);
    return ok ? reply.code(204).send() : reply.code(404).send({ error: "not_found" });
  });
};
