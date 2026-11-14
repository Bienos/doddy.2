import { randomBytes } from "node:crypto";
import { sha256 } from "./crypto.js";
import type { FastifyReply, FastifyRequest, RequestPayload } from "fastify";
import type { Db } from "./db.js";
import { DAY_SECONDS, DEFAULT_DEVICE_TOKEN_POLICY, type DeviceTokenPolicy } from "./deviceTokens.js";

export interface Principal { accountId: string; deviceId: string }

declare module "fastify" {
  interface FastifyRequest { principal?: Principal }
  /** How long device tokens of Doddy accounts live on this server (set in buildApp from `Deps.deviceTokens`). */
  interface FastifyInstance { deviceTokenPolicy: DeviceTokenPolicy }
}

/** 256-bit random bearer token; only its SHA-256 is stored. */
export function newDeviceToken(): { token: string; hash: Buffer } {
  const token = randomBytes(32).toString("base64url");
  return { token, hash: hashToken(token) };
}

export const hashToken = sha256;

/** One lookup per request: the rate limiter's key and the route's token check share it. */
const lookups = new WeakMap<FastifyRequest, Promise<Principal | null>>();

/** The device whose bearer token the request carries, or null for a missing, malformed or unknown token. */
export function deviceFor(db: Db, req: FastifyRequest): Promise<Principal | null> {
  let lookup = lookups.get(req);
  if (!lookup) {
    lookup = lookUpDevice(db, req.server.deviceTokenPolicy ?? DEFAULT_DEVICE_TOKEN_POLICY, req.headers.authorization);
    lookups.set(req, lookup);
  }
  return lookup;
}

/**
 * What a query that finds a device by its token (`$1`, the hash) selects to judge it, next to the columns it wants itself: whether
 * the token is the current one, whether the account is a Doddy account, and whether the idle (`$2`) or the absolute (`$3`) lifetime,
 * in seconds, is over. Used with `devices d JOIN accounts a`. The comparison is made on the database's clock, the one that wrote
 * the times.
 */
export const TOKEN_STATE_COLUMNS = `
  d.token_hash = $1 AS current,
  a.auth_subject IS NOT NULL AS doddy_account,
  d.last_seen_at <= now() - make_interval(secs => $2::double precision) AS idle_over,
  d.token_issued_at <= now() - make_interval(secs => $3::double precision) AS too_old`;

/** The device a token belongs to: as its current holder or, until `previous_valid_until`, as the token a rotation replaced. */
export const TOKEN_MATCH = "(d.token_hash = $1 OR (d.previous_token_hash = $1 AND d.previous_valid_until > now()))";

const DEVICE_BY_TOKEN = `
  SELECT d.id, d.account_id, ${TOKEN_STATE_COLUMNS},
         d.last_seen_at < now() - interval '1 hour' AS stale
    FROM devices d JOIN accounts a ON a.id = d.account_id
   WHERE ${TOKEN_MATCH}`;

/**
 * True when the device's token has run out under `policy`: only for the current token of a Doddy account (an anonymous account's
 * token never expires; a token a rotation replaced is judged by its overlap alone, which the query already checked).
 */
export function tokenRunOut(policy: DeviceTokenPolicy, row: { current: boolean; doddy_account: boolean; idle_over: boolean; too_old: boolean }): boolean {
  return policy.enforce && row.current && row.doddy_account && (row.idle_over || row.too_old);
}

/** The lifetimes in seconds the query above takes as `$2` and `$3`. */
export const lifetimeSeconds = (policy: DeviceTokenPolicy): [number, number] => [policy.idleDays * DAY_SECONDS, policy.maxAgeDays * DAY_SECONDS];

async function lookUpDevice(db: Db, policy: DeviceTokenPolicy, authorization: string | undefined): Promise<Principal | null> {
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(authorization ?? "");
  if (!match?.[1]) return null;
  const { rows } = await db.query<{
    id: string; account_id: string; current: boolean; doddy_account: boolean; idle_over: boolean; too_old: boolean; stale: boolean;
  }>(DEVICE_BY_TOKEN, [hashToken(match[1]), ...lifetimeSeconds(policy)]);
  const row = rows[0];
  if (!row) return null;
  // A token that has run out is refused like an unknown one, and is not marked seen: being refused is not being used.
  if (tokenRunOut(policy, row)) return null;
  // Hour precision is enough for 60 days, and spares a write on every request.
  if (row.stale) await db.query("UPDATE devices SET last_seen_at = now() WHERE id = $1 AND last_seen_at < now() - interval '1 hour'", [row.id]);
  return { accountId: row.account_id, deviceId: row.id };
}

/** The hooks below, so app.ts can tell which routes are signed in (default rate limit, large-body check). */
const deviceHooks = new WeakSet<object>();
export const isDeviceHook = (hook: unknown): boolean => typeof hook === "function" && deviceHooks.has(hook);

/** preHandler for signed-in routes: 401 `{error: "unauthorized"}` without a known device token. */
export function requireDevice(db: Db) {
  const hook = async (req: FastifyRequest, reply: FastifyReply) => {
    const device = await deviceFor(db, req);
    if (!device) return reply.code(401).send({ error: "unauthorized" });
    req.principal = device;
  };
  deviceHooks.add(hook);
  return hook;
}

/**
 * requireDevice for routes whose bodyLimit is above the server's default: a preParsing hook, so a request
 * without a known device token gets the same 401 before its body is read or parsed. It runs after the rate
 * limiter (onRequest), so refused requests are still counted (by address, `rateLimitKey`).
 */
export function requireDeviceBeforeBody(db: Db) {
  const check = requireDevice(db);
  const hook = async (req: FastifyRequest, reply: FastifyReply, payload: RequestPayload) => {
    await check(req, reply);
    return payload;
  };
  deviceHooks.add(hook);
  return hook;
}

/** Rate-limit key for routes that never take a device token: the client's address. */
export const byIp = (req: FastifyRequest): string => "ip:" + req.ip;

/**
 * The default rate-limit key. A request whose bearer token belongs to a device is counted per token; one with
 * no token, a malformed one or an unknown one is counted by the client's address, so made-up tokens don't
 * each get a fresh count.
 */
export function rateLimitKey(db: Db) {
  return async (req: FastifyRequest): Promise<string> => {
    const authorization = req.headers.authorization;
    if (authorization && await deviceFor(db, req)) return "auth:" + sha256(authorization).toString("hex");
    return byIp(req);
  };
}

/**
 * True when the account belongs to a Doddy account (signed in with Apple, Google or a code by email, `accounts.auth_subject`,
 * decision 2026-11-08-required-account); false for an anonymous account from before, or one that is gone.
 */
export async function hasDoddyAccount(db: Pick<Db, "query">, accountId: string): Promise<boolean> {
  const { rows } = await db.query<{ signed_in: boolean }>(
    "SELECT auth_subject IS NOT NULL AS signed_in FROM accounts WHERE id = $1", [accountId]);
  return rows[0]?.signed_in ?? false;
}

export function principal(req: FastifyRequest): Principal {
  if (!req.principal) throw new Error("route is missing requireDevice");
  return req.principal;
}
