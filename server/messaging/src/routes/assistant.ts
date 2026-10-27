// Messages, the app's typed conversation (ADR-585, ADR-586): POST /v1/assistant/ask. The wire is the Ask
// gateway's, so the app reads the reply the same way: { schemaVersion, requestId, text, citedMemoryIDs,
// usage } on success, { schemaVersion, requestId?, error: { code, message, retryAfterSeconds? } } on failure.
// Claude answers in text only: no tools, so nothing here can search, fetch, send or change anything (ASK-01). It may
// offer a file as `proposal` (ADR-606) or a training plan as `plan` (ADR-626); nothing is made until the person taps, and a plan's
// safety questions are asked on the app's screen, never here.
// Nothing the person wrote is stored or logged: the database holds counts per account and day, the log
// holds ids, counts and codes.
import Anthropic from "@anthropic-ai/sdk";
import type { FastifyPluginAsync } from "fastify";
import type { Deps } from "../app.js";
import { principal, requireDevice } from "../auth.js";
import { AssistRequest, LIMITS, WIRE_MESSAGE, WIRE_STATUS, type WireCode } from "../assistant/request.js";
import { addTokens, reserve } from "../assistant/usage.js";

export const assistantRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const auth = requireDevice(deps.db);
  const assistant = deps.assistant;

  app.post("/v1/assistant/ask", {
    preHandler: auth,
    bodyLimit: LIMITS.bodyBytes,
    config: { rateLimit: { max: 60, timeWindow: "1 hour" } },
  }, async (req, reply) => {
    const fail = (code: WireCode, requestId?: string) => reply.code(WIRE_STATUS[code]).send({
      schemaVersion: 1, ...(requestId ? { requestId } : {}), error: { code, message: WIRE_MESSAGE[code] },
    });

    const responder = assistant?.responder;
    if (!assistant || !assistant.settings.enabled || !responder) return fail("notConfigured");

    const parsed = AssistRequest.safeParse(req.body);
    if (!parsed.success) return fail("invalidRequest");
    const body = parsed.data;

    const reservation = await reserve(deps.db, principal(req).accountId, {
      perAccount: assistant.settings.dailyPerAccount, perServer: assistant.settings.dailyPerServer,
    });
    if (reservation !== "ok") {
      req.log.warn({ cap: reservation }, "assistant daily cap reached");
      return fail("dailyLimitReached", body.requestId);
    }

    // The model call ends when it takes too long, and when the person stops the question (the app
    // closes the connection), so a question nobody is waiting for stops costing.
    const controller = new AbortController();
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; controller.abort(); }, assistant.timeoutMs ?? 45_000);
    reply.raw.once("close", () => { if (!reply.raw.writableFinished) controller.abort(); });

    try {
      const outcome = await responder.answer(body, controller.signal);
      if (outcome.kind !== "ok") {
        if (outcome.usage) await addTokens(deps.db, principal(req).accountId, outcome.usage).catch(() => {});
        req.log.warn({ model: responder.model, outcome: outcome.kind }, "assistant gave no answer");
        return fail(outcome.kind === "refused" ? "refused" : "providerUnavailable", body.requestId);
      }
      await addTokens(deps.db, principal(req).accountId, outcome.usage).catch(() => {});
      req.log.info({
        model: responder.model, notes: body.memories.length, turns: body.turns.length, cited: outcome.sources.length, proposed: outcome.proposal?.kind, planned: outcome.plan?.goal,
        inputTokens: outcome.usage.inputTokens, outputTokens: outcome.usage.outputTokens,
      }, "assistant answered");
      return {
        schemaVersion: 1, requestId: body.requestId, text: outcome.answer,
        citedMemoryIDs: outcome.sources.map((id) => id.toLowerCase()), usage: outcome.usage,
        ...(outcome.proposal ? { proposal: outcome.proposal } : {}),
        ...(outcome.plan ? { plan: outcome.plan } : {}),
      };
    } catch (err) {
      if (timedOut) return fail("timeout", body.requestId);
      if (controller.signal.aborted) return reply; // the person stopped it; nobody is listening
      const e = err as { status?: unknown; name?: unknown };
      req.log.error({ status: typeof e.status === "number" ? e.status : undefined, kind: err instanceof Anthropic.APIError ? "api" : String(e.name) },
        "assistant provider error");
      return fail("providerUnavailable", body.requestId);
    } finally {
      clearTimeout(timer);
    }
  });
};
