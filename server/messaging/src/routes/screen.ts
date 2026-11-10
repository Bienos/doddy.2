// POST /v1/screen/look (decision 2026-11-09-doddy-looks-at-the-screen): one frame of the shared screen and
// the person's question, answered by Claude. Counted against the same daily caps as Messages (one budget for
// Claude questions, `assistant_usage`), so it adds no table. The frame and the question are never stored or
// logged: the log has the model, the outcome, the frame's age and the tokens.
import Anthropic from "@anthropic-ai/sdk";
import type { FastifyPluginAsync } from "fastify";
import type { Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { WIRE_MESSAGE, WIRE_STATUS, type WireCode } from "../assistant/request.js";
import { addTokens, reserve } from "../assistant/usage.js";
import { SCREEN_LIMITS, ScreenLookRequest } from "../screen/look.js";

export const screenRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  const assistant = deps.assistant;

  app.post("/v1/screen/look", {
    preHandler: auth,
    bodyLimit: SCREEN_LIMITS.bodyBytes,
    config: { rateLimit: { max: 120, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    const fail = (code: WireCode, requestId?: string) => reply.code(WIRE_STATUS[code]).send({
      schemaVersion: 1, ...(requestId ? { requestId } : {}), error: { code, message: WIRE_MESSAGE[code] },
    });

    const looker = assistant?.screen;
    if (!assistant || !assistant.settings.enabled || !looker) return fail("notConfigured");

    const parsed = ScreenLookRequest.safeParse(req.body);
    if (!parsed.success) return fail("invalidRequest");
    const body = parsed.data;

    const reservation = await reserve(deps.db, principal(req).accountId, {
      perAccount: assistant.settings.dailyPerAccount, perServer: assistant.settings.dailyPerServer,
      newAccountPool: assistant.settings.dailyForNewAccounts, newAccountHours: assistant.settings.newAccountHours,
    });
    if (reservation !== "ok") {
      req.log.warn({ cap: reservation }, "screen look daily cap reached");
      return fail("dailyLimitReached", body.requestId);
    }

    // The person is waiting in a voice conversation: a short limit, and the call stops when the app gives up.
    const controller = new AbortController();
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, assistant.screenTimeoutMs ?? 20_000);
    reply.raw.once("close", () => { if (!reply.raw.writableFinished) controller.abort(); });

    try {
      const outcome = await looker.look(body, controller.signal);
      if (outcome.usage) await addTokens(deps.db, principal(req).accountId, outcome.usage).catch(() => {});
      if (outcome.kind !== "ok") {
        req.log.warn({ model: looker.model, outcome: outcome.kind }, "screen look gave no answer");
        return fail(outcome.kind === "refused" ? "refused" : "providerUnavailable", body.requestId);
      }
      req.log.info({
        model: looker.model, frameAgeSeconds: Math.round(body.frameAgeSeconds),
        inputTokens: outcome.usage.inputTokens, outputTokens: outcome.usage.outputTokens,
      }, "screen look answered");
      return { schemaVersion: 1, requestId: body.requestId, text: outcome.answer, usage: outcome.usage };
    } catch (err) {
      if (timedOut) return fail("timeout", body.requestId);
      if (controller.signal.aborted) return reply; // the person stopped it; nobody is listening
      const e = err as { status?: unknown; name?: unknown };
      req.log.error({ status: typeof e.status === "number" ? e.status : undefined, kind: err instanceof Anthropic.APIError ? "api" : String(e.name) },
        "screen look provider error");
      return fail("providerUnavailable", body.requestId);
    } finally {
      clearTimeout(timer);
    }
  });
};
