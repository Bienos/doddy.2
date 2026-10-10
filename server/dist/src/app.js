import Fastify from "fastify";
import formbody from "@fastify/formbody";
import rateLimit from "@fastify/rate-limit";
import { callRoutes } from "./routes/calls.js";
import { elevenLabsRoutes } from "./routes/elevenlabs.js";
import { newsRoutes } from "./routes/news.js";
import { accountRoutes } from "./routes/account.js";
import { phoneRoutes } from "./routes/phone.js";
import { updateRoutes } from "./routes/updates.js";
import { voiceRoutes } from "./routes/voice.js";
import { twilioWebhookRoutes } from "./routes/twilioWebhooks.js";
export async function buildApp(deps) {
    const app = Fastify({
        // Render terminates TLS and sets X-Forwarded-For.
        trustProxy: true,
        bodyLimit: 16 * 1024,
        logger: deps.logger === false ? false : {
            level: "info",
            // Never log bearer tokens or signatures. Request bodies are not logged at all.
            redact: ["req.headers.authorization", 'req.headers["x-twilio-signature"]',
                'req.headers["x-doddy-tool-secret"]', 'req.headers["x-doddy-session"]'],
        },
    });
    await app.register(formbody);
    await app.register(rateLimit, {
        global: false,
        keyGenerator: (req) => req.headers.authorization ?? req.ip,
    });
    app.setErrorHandler((err, req, reply) => {
        if (err.statusCode && err.statusCode < 500) {
            return reply.code(err.statusCode).send({ error: err.statusCode === 429 ? "rate_limited" : "bad_request" });
        }
        req.log.error({ err: { message: err.message, code: err.code } }, "request failed");
        return reply.code(500).send({ error: "internal" });
    });
    app.get("/healthz", async (_req, reply) => {
        try {
            await deps.db.query("SELECT 1");
            return { ok: true };
        }
        catch {
            return reply.code(503).send({ ok: false });
        }
    });
    await app.register(accountRoutes(deps));
    await app.register(phoneRoutes(deps));
    await app.register(updateRoutes(deps));
    await app.register(voiceRoutes(deps));
    await app.register(twilioWebhookRoutes(deps));
    await app.register(callRoutes(deps));
    await app.register(elevenLabsRoutes(deps));
    await app.register(newsRoutes(deps));
    return app;
}
/** Parses with zod; on failure sends 400 with the failing field paths (never the values). */
export function parse(schema, data, reply) {
    const r = schema.safeParse(data);
    if (r.success)
        return r.data;
    void reply.code(400).send({ error: "invalid_request", fields: r.error.issues.map((i) => i.path.join(".")) });
    return undefined;
}
//# sourceMappingURL=app.js.map