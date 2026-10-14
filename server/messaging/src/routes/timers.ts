import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { cancelTimer, MAX_TIMER_SECONDS, scheduleTimer } from "../liveActivity.js";

const timerBody = z.object({
  activityToken: z.string().regex(/^[0-9a-f]{64,200}$/),
  environment: z.enum(["sandbox", "production"]),
  endsAt: z.iso.datetime(),
  label: z.string().trim().min(1).max(60).optional(),
});

/** Timers whose Live Activity the server updates when they end (ADR-483). Device-authenticated. */
export const timerRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);

  app.post("/v1/timers", { preHandler: auth }, async (req, reply) => {
    const body = parse(timerBody, req.body, reply);
    if (!body) return;
    const endsAt = new Date(body.endsAt);
    const seconds = (endsAt.getTime() - Date.now()) / 1000;
    if (!(seconds > 0 && seconds <= MAX_TIMER_SECONDS)) {
      return reply.code(400).send({ error: "timer_out_of_range" });
    }
    const id = await scheduleTimer(db, principal(req).accountId, {
      activityToken: body.activityToken, environment: body.environment, endsAt, label: body.label,
    });
    return reply.code(201).send({ id });
  });

  app.delete<{ Params: { id: string } }>("/v1/timers/:id", { preHandler: auth }, async (req, reply) => {
    const id = z.uuid().safeParse(req.params.id);
    if (!id.success) return reply.code(404).send({ error: "not_found" });
    // Same answer whether it was cancelled, already sent or belongs to someone else.
    await cancelTimer(db, principal(req).accountId, id.data);
    return reply.code(204).send();
  });
};
