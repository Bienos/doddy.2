import { randomUUID } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { newDeviceToken, principal, requireDevice } from "../auth.js";
import { abuseLimits } from "../config.js";
import { clientBucket, counterKey, pruneCounters, returnCounter, takeCounter } from "../dailyCounters.js";
import { inTransaction } from "../db.js";
import { takeServerSlot } from "../serverUsage.js";
import type { TaskCallContext } from "../taskCalls/context.js";
import { beforeAccountDeleted } from "../taskCalls/worker.js";

const pushToken = z.object({
  token: z.string().regex(/^[0-9a-f]{64,200}$/),
  environment: z.enum(["sandbox", "production"]),
});

export const accountRoutes = (deps: Deps, taskCtx?: TaskCallContext): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const limits = abuseLimits(deps.limits);
  // The address is stored only as a keyed hash (HMAC under a key derived from MEMORY_ENCRYPTION_KEY when there is one).
  const ipSecret = deps.cipher?.derivedKey("client-address");

  // Anonymous account: no email, no name. The app keeps the returned token in the Keychain.
  // Limited per client IP only: no Authorization header can buy a fresh bucket here (ADR-175).
  // On top of 10 an hour per address (counted in memory), accounts per UTC day are capped per address and for the whole
  // server, counted in the database in the same transaction that makes the account (ADR-702): accounts cost nothing,
  // so without a daily cap a script could make as many as it liked and spend every paid feature's server-wide day.
  app.post("/v1/accounts", {
    config: { rateLimit: { max: 10, timeWindow: "1 hour", keyGenerator: (req) => "ip:" + req.ip } },
  }, async (req, reply) => {
    const accountId = randomUUID();
    const deviceId = randomUUID();
    const { token, hash } = newDeviceToken();
    const ipKey = counterKey(ipSecret, clientBucket(req.ip));
    const made = await inTransaction(db, async (c) => {
      if (!(await takeCounter(c, "signup_ip", ipKey, limits.accountsPerIpDay))) return false;
      if (!(await takeServerSlot(c, "accounts", limits.accountsPerServerDay))) {
        await returnCounter(c, "signup_ip", ipKey);
        return false;
      }
      await c.query("INSERT INTO accounts (id) VALUES ($1)", [accountId]);
      await c.query("INSERT INTO devices (id, account_id, token_hash) VALUES ($1, $2, $3)", [deviceId, accountId, hash]);
      await pruneCounters(c);
      return true;
    });
    // The same answer as the hourly limit, so a client treats both alike.
    if (!made) return reply.code(429).send({ error: "rate_limited" });
    return reply.code(201).send({ accountId, deviceToken: token });
  });

  // Erases the account and everything tied to it (devices, phone number, queued and past messages).
  app.delete("/v1/account", { preHandler: auth }, async (req, reply) => {
    // Calls Doddy is making for this account end first; their ElevenLabs copies are deleted
    // promptly by jobs that outlive the account (call cases, ADR-506).
    if (taskCtx) await beforeAccountDeleted(taskCtx, principal(req).accountId);
    await db.query("DELETE FROM accounts WHERE id = $1", [principal(req).accountId]);
    return reply.code(204).send();
  });

  app.put("/v1/device/push-token", { preHandler: auth }, async (req, reply) => {
    const body = parse(pushToken, req.body, reply);
    if (!body) return;
    const { deviceId } = principal(req);
    await inTransaction(db, async (c) => {
      // A reinstall gets a new device row but may keep the APNs token: move it.
      await c.query(
        "UPDATE devices SET apns_token = NULL, apns_environment = NULL WHERE apns_token = $1 AND id <> $2",
        [body.token, deviceId]);
      await c.query(
        `UPDATE devices SET apns_token = $2, apns_environment = $3, apns_token_invalid_at = NULL WHERE id = $1`,
        [deviceId, body.token, body.environment]);
    });
    return reply.code(204).send();
  });

  app.delete("/v1/device/push-token", { preHandler: auth }, async (req, reply) => {
    await db.query("UPDATE devices SET apns_token = NULL, apns_environment = NULL WHERE id = $1", [principal(req).deviceId]);
    return reply.code(204).send();
  });
};
