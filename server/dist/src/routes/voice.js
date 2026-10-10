import { requireDevice } from "../auth.js";
import { ProviderError } from "../providers/types.js";
export const voiceRoutes = (deps) => async (app) => {
    // Short-lived ElevenLabs conversation token so the app never ships an API key (ADR-034).
    app.get("/v1/voice/token", {
        preHandler: requireDevice(deps.db),
        config: { rateLimit: { max: 30, timeWindow: "1 hour" } },
    }, async (_req, reply) => {
        if (!deps.voice)
            return reply.code(503).send({ error: "not_configured" });
        try {
            return { token: await deps.voice.conversationToken() };
        }
        catch (err) {
            if (err instanceof ProviderError)
                return reply.code(502).send({ error: "provider_unavailable" });
            throw err;
        }
    });
};
//# sourceMappingURL=voice.js.map