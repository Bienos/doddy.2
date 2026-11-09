import { randomUUID } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import type pg from "pg";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { hashToken, newDeviceToken, principal, requireDevice } from "../auth.js";
import { queuePhoneAgentDeletions } from "../calls.js";
import { abuseLimits } from "../config.js";
import { clientBucket, counterKey, pruneCounters, returnCounter, takeCounter } from "../dailyCounters.js";
import { inTransaction } from "../db.js";
import { AccountCheckUnavailable } from "../doddyAccount.js";
import { takeServerSlot } from "../serverUsage.js";
import type { TaskCallContext } from "../taskCalls/context.js";
import { beforeAccountDeleted } from "../taskCalls/worker.js";
import { beforeAccountDeleted as studioBeforeAccountDeleted } from "../studio/service.js";

/** At most this many iPhones per account: a new one replaces the one unseen longest (decision 2026-11-08-required-account). */
export const MAX_DEVICES_PER_ACCOUNT = 10;

const signInBody = z.object({ deviceToken: z.string().regex(/^[A-Za-z0-9_-]{43}$/).optional() }).strict();

/** True when nothing but its iPhones points at this account: an anonymous account that was never used. */
async function holdsOnlyDevices(c: pg.PoolClient, accountId: string): Promise<boolean> {
  // Every table that refers to an account, read from the database itself, so a new table can't be missed.
  const { rows } = await c.query<{ tbl: string; col: string }>(
    `SELECT con.conrelid::regclass::text AS tbl, att.attname AS col
       FROM pg_constraint con
       JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY (con.conkey)
      WHERE con.contype = 'f' AND con.confrelid = 'accounts'::regclass`);
  for (const { tbl, col } of rows) {
    if (tbl === "devices") continue;
    const hit = await c.query(`SELECT 1 FROM ${tbl} WHERE "${col.replace(/"/g, '""')}" = $1 LIMIT 1`, [accountId]);
    if (hit.rows.length > 0) return false;
  }
  return true;
}

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

  // Decision 2026-11-08-required-account: sign in with a Doddy account (Apple, Google or a code by email,
  // checked against the Supabase project's own keys). The account here is the one belonging to that Doddy
  // account, made the first time; this iPhone gets its own device token, used as before. An iPhone that
  // already has an anonymous account here sends its device token: that account is linked once, or, when
  // the Doddy account already has one here, this iPhone moves to it if its own holds nothing. Never merged.
  app.post("/v1/accounts/sign-in", {
    config: { rateLimit: { max: 30, timeWindow: "1 hour", keyGenerator: (req) => "ip:" + req.ip } },
  }, async (req, reply) => {
    if (!deps.accounts) return reply.code(503).send({ error: "not_configured" });
    const bearer = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization ?? "")?.[1];
    if (!bearer) return reply.code(401).send({ error: "unauthorized" });
    let account: { sub: string } | null;
    try {
      account = await deps.accounts.verify(bearer);
    } catch (error) {
      // "Try again", never "signed out": a 401 would send the app back to sign in.
      if (error instanceof AccountCheckUnavailable) return reply.code(503).send({ error: "account_check_unavailable" });
      throw error;
    }
    if (!account) return reply.code(401).send({ error: "unauthorized" });
    const body = parse(signInBody, req.body ?? {}, reply);
    if (!body) return;
    const subject = account.sub;
    const ipKey = counterKey(ipSecret, clientBucket(req.ip));

    const attempt = () => inTransaction(db, async (c) => {
      const mine = (await c.query<{ id: string }>("SELECT id FROM accounts WHERE auth_subject = $1", [subject])).rows[0];
      if (body.deviceToken) {
        const device = (await c.query<{ id: string; account_id: string; auth_subject: string | null }>(
          `SELECT d.id, d.account_id, a.auth_subject FROM devices d JOIN accounts a ON a.id = d.account_id
            WHERE d.token_hash = $1 FOR UPDATE OF a`, [hashToken(body.deviceToken)])).rows[0];
        if (device) {
          if (device.auth_subject === subject) return { accountId: device.account_id, deviceToken: body.deviceToken };
          if (device.auth_subject !== null) return "signed_in_elsewhere" as const;
          if (!mine) {
            await c.query("UPDATE accounts SET auth_subject = $1 WHERE id = $2", [subject, device.account_id]);
            return { accountId: device.account_id, deviceToken: body.deviceToken };
          }
          if (!(await holdsOnlyDevices(c, device.account_id))) return "has_data" as const;
          await c.query("UPDATE devices SET account_id = $1 WHERE id = $2", [mine.id, device.id]);
          await c.query("DELETE FROM accounts WHERE id = $1", [device.account_id]);
          return { accountId: mine.id, deviceToken: body.deviceToken };
        }
      }
      let accountId = mine?.id;
      if (!accountId) {
        // A new account here counts against the same daily caps as an anonymous one (ADR-702).
        if (!(await takeCounter(c, "signup_ip", ipKey, limits.accountsPerIpDay))) return "rate_limited" as const;
        if (!(await takeServerSlot(c, "accounts", limits.accountsPerServerDay))) {
          await returnCounter(c, "signup_ip", ipKey);
          return "rate_limited" as const;
        }
        accountId = randomUUID();
        await c.query("INSERT INTO accounts (id, auth_subject) VALUES ($1, $2)", [accountId, subject]);
        await pruneCounters(c);
      }
      // Room for this iPhone: past the newest MAX - 1, the ones unseen longest go (their call-case
      // approvals keep the record, with no device, ON DELETE SET NULL).
      await c.query(
        `DELETE FROM devices WHERE id IN (
           SELECT id FROM devices WHERE account_id = $1 ORDER BY last_seen_at DESC, created_at DESC OFFSET $2)`,
        [accountId, MAX_DEVICES_PER_ACCOUNT - 1]);
      const { token, hash } = newDeviceToken();
      await c.query("INSERT INTO devices (id, account_id, token_hash) VALUES ($1, $2, $3)", [randomUUID(), accountId, hash]);
      return { accountId, deviceToken: token };
    });

    let outcome;
    try {
      outcome = await attempt();
    } catch (error) {
      // Two first sign-ins of one Doddy account at once: the unique key let one make the account; this one uses it.
      if ((error as { code?: string }).code !== "23505") throw error;
      outcome = await attempt();
    }
    if (outcome === "rate_limited") return reply.code(429).send({ error: "rate_limited" });
    if (outcome === "signed_in_elsewhere") return reply.code(409).send({ error: "account_conflict", reason: "device_signed_in_to_another_account" });
    if (outcome === "has_data") return reply.code(409).send({ error: "account_conflict", reason: "device_account_has_data" });
    return reply.code(200).send(outcome);
  });

  // Erases the account and everything tied to it (devices, phone number, queued and past messages).
  app.delete("/v1/account", { preHandler: auth }, async (req, reply) => {
    // Calls Doddy is making for this account end first; their ElevenLabs copies are deleted
    // promptly by jobs that outlive the account (call cases, ADR-506).
    if (taskCtx) await beforeAccountDeleted(taskCtx, principal(req).accountId);
    // Studio's copies at Anthropic not yet confirmed deleted outlive the account until they are (ADR-740).
    await studioBeforeAccountDeleted(db, principal(req).accountId, new Date());
    // Phone-agent conversations (incoming calls, "call me now") are queued for deletion at ElevenLabs
    // whether or not task calls are on; the delete cascade removes the rows that hold their ids.
    await inTransaction(db, async (c) => {
      await queuePhoneAgentDeletions(c, principal(req).accountId, new Date());
      await c.query("DELETE FROM accounts WHERE id = $1", [principal(req).accountId]);
    });
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

  // Signing out on this iPhone (security audit 2026-11-09, finding 1). The device row is the whole of this iPhone's
  // authority here: its token (stored as a hash) and its push binding are columns of it, so deleting it ends
  // both in one statement: the token is refused from then on, and no later push is addressed to this iPhone.
  // Other iPhones of the account are untouched. Only an iPhone of a Doddy account can do this: signing in
  // again makes a new device row, whereas the only device of an anonymous account is the only way back in.
  // A repeat with the same token is answered 401 (the token no longer exists), which the app reads as "done".
  app.delete("/v1/device", { preHandler: auth }, async (req, reply) => {
    const { rowCount } = await db.query(
      `DELETE FROM devices d USING accounts a
        WHERE d.id = $1 AND a.id = d.account_id AND a.auth_subject IS NOT NULL`,
      [principal(req).deviceId]);
    if (!rowCount) return reply.code(409).send({ error: "device_not_signed_in_to_an_account" });
    return reply.code(204).send();
  });

  app.delete("/v1/device/push-token", { preHandler: auth }, async (req, reply) => {
    await db.query("UPDATE devices SET apns_token = NULL, apns_environment = NULL WHERE id = $1", [principal(req).deviceId]);
    return reply.code(204).send();
  });
};
