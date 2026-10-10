import { createHash, randomBytes } from "node:crypto";
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

export function hashToken(token: string): Buffer {
  return createHash("sha256").update(token).digest();
}

export function requireDevice(db: Db) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization ?? "");
    if (!match?.[1]) return reply.code(401).send({ error: "unauthorized" });
    const { rows } = await db.query<{ id: string; account_id: string }>(
      "UPDATE devices SET last_seen_at = now() WHERE token_hash = $1 RETURNING id, account_id",
      [hashToken(match[1])]);
    const row = rows[0];
    if (!row) return reply.code(401).send({ error: "unauthorized" });
    req.principal = { accountId: row.account_id, deviceId: row.id };
  };
}

export function principal(req: FastifyRequest): Principal {
  if (!req.principal) throw new Error("route is missing requireDevice");
  return req.principal;
}
