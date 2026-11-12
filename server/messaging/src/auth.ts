import { randomBytes } from "node:crypto";
import { sha256 } from "./crypto.js";
import type { FastifyReply, FastifyRequest } from "fastify";
import type { Db } from "./db.js";

export interface Principal { accountId: string; deviceId: string }

declare module "fastify" {
  interface FastifyRequest { principal?: Principal }
}

/** 256-bit random bearer token; only its SHA-256 is stored. */
export function newDeviceToken(): { token: string; hash: Buffer } {
  const token = randomBytes(32).toString("base64url");
  return { token, hash: hashToken(token) };
}

export const hashToken = sha256;

export function requireDevice(db: Db) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization ?? "");
    if (!match?.[1]) return reply.code(401).send({ error: "unauthorized" });
    const { rows } = await db.query<{ id: string; account_id: string; stale: boolean }>(
      "SELECT id, account_id, last_seen_at < now() - interval '1 hour' AS stale FROM devices WHERE token_hash = $1",
      [hashToken(match[1])]);
    const row = rows[0];
    if (!row) return reply.code(401).send({ error: "unauthorized" });
    // Hour precision is enough, and spares a write on every request.
    if (row.stale) await db.query("UPDATE devices SET last_seen_at = now() WHERE id = $1", [row.id]);
    req.principal = { accountId: row.account_id, deviceId: row.id };
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
