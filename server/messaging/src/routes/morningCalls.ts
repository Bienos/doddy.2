import { randomUUID, timingSafeEqual } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import type pg from "pg";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { morningCallApprovalHash } from "../approval.js";
import { principal, requireDevice } from "../auth.js";
import { abuseLimits, MORNING_CALLS_MAX_PER_SERVER_DEFAULT } from "../config.js";
import { inTransaction, type Db } from "../db.js";
import { isDays, isMorningTime, nextMorningCallAt } from "../morningCalls.js";
import { isAllowedNumber } from "../phoneCountries.js";
import { isValidTimeZone, minutesInQuietHours, parseClock, QUIET_HOURS_DEFAULT } from "../quietHours.js";
import { callsAvailable } from "./twilioVoice.js";

// A morning call (decision 2026-11-14-morning-call): "call me every day at 8 with the plan of the day". The card showed
// the time, the days, the zone, the number's last digits, what the call says and the quiet-hours switch; the approval
// covers exactly those (morningCallApprovalHash), and a changed field is a new approval. The worker turns it into a
// scheduled call each chosen day (morningCalls.ts) and checks it all again then. One per account; behind
// MORNING_CALLS_ENABLED (off: nothing new is stored). Stopping always works, flag or not, and at once.

const bookBody = z.object({
  time: z.string().refine(isMorningTime, "a morning call is from 05:00 to 11:59"),
  days: z.string().refine(isDays, "days are ISO weekdays, ascending, e.g. 12345"),
  timeZone: z.string().refine(isValidTimeZone, "unknown time zone"),
  allowQuietHours: z.boolean(),
  language: z.enum(["en", "pl"]),
  approvalHash: z.string().regex(/^[0-9a-f]{64}$/),
  idempotencyKey: z.string().min(1).max(128),
  // The morning call the card said this one replaces, or null when the card said there was none.
  replaces: z.uuid().nullable().default(null),
});

type Queryable = { query: Db["query"] };

interface Row {
  id: string; local_time: string; days: string; time_zone: string; allow_quiet_hours: boolean; language: string;
  state: string; stop_code: string | null; next_call_at: Date | null; approval_hash: Buffer; created_at: Date; stopped_at: Date | null;
}

const COLUMNS = "id, local_time, days, time_zone, allow_quiet_hours, language, state, stop_code, next_call_at, approval_hash, created_at, stopped_at";

const view = (r: Row) => ({
  id: r.id, time: r.local_time, days: r.days, timeZone: r.time_zone, allowQuietHours: r.allow_quiet_hours, language: r.language,
  state: r.state, stopCode: r.stop_code, nextCallAt: r.next_call_at?.toISOString() ?? null, createdAt: r.created_at.toISOString(),
});

class Refused extends Error {
  constructor(readonly status: number, readonly code: string, readonly extra: object = {}) { super(code); }
}

async function caller(db: Queryable, accountId: string): Promise<{ e164: string | null; consent: boolean }> {
  const { rows: [who] } = await db.query<{ e164: string | null; consent: boolean }>(
    `SELECT p.e164, s.outbound_consent_at IS NOT NULL AS consent FROM (SELECT $1::uuid AS account_id) a
     LEFT JOIN phone_numbers p ON p.account_id = a.account_id LEFT JOIN call_settings s ON s.account_id = a.account_id`,
    [accountId]);
  return { e164: who?.e164 ?? null, consent: who?.consent ?? false };
}

const activeOf = async (db: Queryable, accountId: string) =>
  (await db.query<Row>(`SELECT ${COLUMNS} FROM morning_calls WHERE account_id = $1 AND state = 'active'`, [accountId])).rows[0];

/**
 * Stops the account's morning call and cancels that day's call if it is still waiting, under the lock a booking and the
 * worker take, so nothing rings after this returns, unless that day's call was already being placed (`calling`).
 */
export async function stopMorningCall(c: pg.PoolClient, accountId: string, code: string): Promise<{ stopped: boolean; calling: boolean }> {
  await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [accountId]);
  const { rows: [stopped] } = await c.query<{ id: string }>(
    `UPDATE morning_calls SET state = 'stopped', stop_code = $2, stopped_at = now(), next_call_at = NULL, updated_at = now()
     WHERE account_id = $1 AND state = 'active' RETURNING id`, [accountId, code]);
  if (!stopped) return { stopped: false, calling: false };
  await c.query(
    `UPDATE scheduled_calls SET state = 'cancelled', error_code = $2, reason_ciphertext = NULL, reason_key_version = NULL,
       updated_at = now() WHERE morning_call_id = $1 AND state = 'scheduled'`,
    [stopped.id, code === "stopped_by_user" ? "cancelled_by_user" : code]);
  const { rowCount } = await c.query(
    `SELECT 1 FROM scheduled_calls WHERE morning_call_id = $1
       AND (state = 'placing' OR (state = 'placed' AND updated_at > now() - interval '15 minutes'))`, [stopped.id]);
  return { stopped: true, calling: !!rowCount };
}

export const morningCallRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const limits = abuseLimits(deps.limits);
  const quiet = deps.quietHours ?? QUIET_HOURS_DEFAULT;
  const settings = { enabled: false, maxPerServer: MORNING_CALLS_MAX_PER_SERVER_DEFAULT, ...deps.morningCalls };
  const available = () => settings.enabled && callsAvailable(deps).outbound && !!deps.cipher;

  // Whether the server makes morning calls, the active one if any, and the last days' calls.
  app.get("/v1/calls/morning", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const active = await activeOf(db, accountId);
    const { rows: days } = await db.query<{ at: string; state: string; error_code: string | null }>(
      `SELECT call_at_text AS at, state, error_code FROM scheduled_calls WHERE account_id = $1 AND kind = 'morning'
       ORDER BY call_at DESC LIMIT 7`, [accountId]);
    return {
      enabled: settings.enabled, available: available(),
      call: active ? view(active) : null,
      recent: days.map((d) => ({ at: d.at, state: d.state, errorCode: d.error_code })),
    };
  });

  app.post("/v1/calls/morning", { preHandler: auth, config: { rateLimit: { max: 30, timeWindow: "1 hour" } } }, async (req, reply) => {
    // Off: nothing is stored (the flag is checked before the body is even read as a booking).
    if (!settings.enabled) return reply.code(503).send({ error: "morning_calls_off" });
    if (!callsAvailable(deps).outbound || !deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const body = parse(bookBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    const who = await caller(db, accountId);
    if (!who.e164) return reply.code(409).send({ error: "no_verified_phone" });
    if (!who.consent) return reply.code(409).send({ error: "outbound_not_enabled" });
    if (!isAllowedNumber(who.e164, limits.allowedCountryCodes)) return reply.code(409).send({ error: "phone_not_allowed" });
    // The number, time, days, zone, quiet-hours choice and language the card showed; any difference is refused.
    const expected = morningCallApprovalHash(who.e164, body.time, body.days, body.timeZone, body.allowQuietHours, body.language);
    if (!timingSafeEqual(expected, Buffer.from(body.approvalHash, "hex"))) return reply.code(409).send({ error: "approval_mismatch" });
    // A repeat of the same tap is answered first, with what became of it.
    const earlier = await repeatOf(db, accountId, body.idempotencyKey, expected);
    if (earlier) return reply.code(earlier.status).send(earlier.body);
    if (!body.allowQuietHours && minutesInQuietHours(parseClock(body.time)!, quiet)) {
      return reply.code(409).send({ error: "quiet_hours" });
    }
    try {
      const result = await inTransaction(db, async (c) => {
        await c.query("SELECT pg_advisory_xact_lock(hashtext('outbound_calls:' || $1))", [accountId]);
        const again = await repeatOf(c, accountId, body.idempotencyKey, expected);
        if (again) return again;
        // Read again under the lock: consent or the number may have changed since.
        const now = await caller(c, accountId);
        if (!now.consent) throw new Refused(409, "outbound_not_enabled");
        if (now.e164 !== who.e164) throw new Refused(409, "approval_mismatch");
        const active = await activeOf(c, accountId);
        if (active) {
          if (active.approval_hash.equals(expected)) throw new Refused(409, "already_booked", { call: view(active) });
          // One per account: a new one only replaces the one the card said it replaces.
          if (body.replaces !== active.id) throw new Refused(409, "already_active", { call: view(active) });
        }
        // The server's cap on morning calls, each one a call a day (MORNING_CALLS_MAX_PER_SERVER); the one replaced
        // doesn't count. Under an advisory lock of its own, so two accounts can't both take the last place.
        await c.query("SELECT pg_advisory_xact_lock(hashtext('morning_calls_server'))");
        const { rows: [{ n } = { n: 0 }] } = await c.query<{ n: number }>(
          "SELECT count(*)::int AS n FROM morning_calls WHERE state = 'active' AND account_id <> $1", [accountId]);
        if (n >= settings.maxPerServer) throw new Refused(429, "server_limit");
        if (active) await stopMorningCall(c, accountId, "replaced");
        const id = randomUUID();
        const next = nextMorningCallAt(new Date(), body.time, body.days, body.timeZone);
        await c.query(
          `INSERT INTO morning_calls (id, account_id, local_time, days, time_zone, allow_quiet_hours, language, approval_hash,
             idempotency_key, state, next_call_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'active', $10)`,
          [id, accountId, body.time, body.days, body.timeZone, body.allowQuietHours, body.language, expected, body.idempotencyKey, next]);
        // The zone the iPhone is in now, for quiet hours when a day's call is due.
        await c.query(
          `INSERT INTO call_settings (account_id, time_zone) VALUES ($1, $2)
           ON CONFLICT (account_id) DO UPDATE SET time_zone = $2, updated_at = now()`, [accountId, body.timeZone]);
        return { status: 202, body: { id, time: body.time, days: body.days, timeZone: body.timeZone, state: "active", nextCallAt: next.toISOString() } };
      });
      return reply.code(result.status).send(result.body);
    } catch (err) {
      if (err instanceof Refused) return reply.code(err.status).send({ error: err.code, ...err.extra });
      throw err;
    }
  });

  // "Przestań dzwonić rano", or the Stop button: always accepted, whatever the flag or the phone line's setup.
  app.delete("/v1/calls/morning", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const r = await inTransaction(db, (c) => stopMorningCall(c, accountId, "stopped_by_user"));
    req.log.info({ event: "morning_call_stop", stopped: r.stopped }, "morning call stop");
    return r;
  });
};

/** The answer to a repeat of an earlier booking (the same idempotency key), or undefined for a new one. */
async function repeatOf(db: Queryable, accountId: string, key: string, expected: Buffer):
    Promise<{ status: number; body: object } | undefined> {
  const { rows: [again] } = await db.query<Row>(
    `SELECT ${COLUMNS} FROM morning_calls WHERE account_id = $1 AND idempotency_key = $2`, [accountId, key]);
  if (!again) return undefined;
  if (!again.approval_hash.equals(expected)) return { status: 409, body: { error: "idempotency_mismatch" } };
  if (again.state !== "active") return { status: 409, body: { error: "already_done", id: again.id, state: again.state } };
  return { status: 202, body: { id: again.id, time: again.local_time, days: again.days, timeZone: again.time_zone, state: again.state,
    nextCallAt: again.next_call_at?.toISOString() ?? null } };
}
