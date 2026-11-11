import { randomUUID, timingSafeEqual } from "node:crypto";
import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { parse, type Deps } from "../app.js";
import { deliveryApprovalHash } from "../approval.js";
import { principal, requireDevice } from "../auth.js";
import { abuseLimits } from "../config.js";
import { inTransaction, type Db } from "../db.js";
import {
  deliveryCard, FINISHED, openPayload, recordUberDelivery, sealPayload, type DeliveryDeps, type DeliveryPayload, type DeliveryState,
} from "../delivery/deliveries.js";
import { isAllowedNumber } from "../phoneCountries.js";

// Deliveries through Uber Direct (decision 2026-11-12-uber-direct-deliveries). Off unless the server has
// Uber's credentials and UBER_DIRECT_ENABLED=1: every route answers 503 not_configured.
//
//   POST /v1/deliveries/quotes        price it; returns the card's lines and Doddy's id
//   POST /v1/deliveries/:id/confirm   the tap: the card's hash and an idempotency key; asks Uber to deliver
//   GET  /v1/deliveries/:id           where it is now (asks Uber; settles an unknown by Doddy's id)
//   GET  /v1/deliveries               the latest 20
//   POST /v1/deliveries/:id/cancel    asks Uber to cancel; "cancelled" only when Uber says so

/** One line of text as the user typed it: no line breaks or control characters, no lone surrogates. */
const line = (max: number) => z.string().min(1).max(max)
  .refine((s) => s.trim() === s && s.length > 0 && !/[\p{Cc}\p{Cs}]/u.test(s), "not one line of text");

/** Where Doddy can send couriers. Uber Direct's coverage in Poland is unconfirmed (decision file). */
export const DELIVERY_COUNTRIES = ["PL"] as const;

const address = z.object({
  street: line(120),
  apartment: line(40).optional(),
  city: line(80),
  postcode: z.string().regex(/^[0-9A-Za-z][0-9A-Za-z -]{1,10}$/),
  country: z.enum(DELIVERY_COUNTRIES),
});

const quoteBody = z.object({
  pickup: z.object({ name: line(60), address }),
  dropoff: z.object({ name: line(60), phone: z.string().regex(/^\+[1-9][0-9]{6,14}$/), address }),
  items: z.array(z.object({ name: line(60), quantity: z.number().int().min(1).max(20), size: z.enum(["small", "medium", "large"]) }))
    .min(1).max(5),
  note: z.string().max(280).refine((s) => !/[\p{Cc}\p{Cs}]/u.test(s), "not one line of text").default(""),
});
const confirmBody = z.object({
  approvalHash: z.string().regex(/^[0-9a-f]{64}$/),
  idempotencyKey: z.string().min(1).max(128),
});
const cancelBody = z.object({ confirm: z.literal(true) });
const idParam = z.object({ id: z.uuid() });

interface Row {
  id: string; state: DeliveryState; error_code: string | null; uber_quote_id: string; fee: number; currency: string;
  quote_expires_at: Date; dropoff_eta: Date | null; payload_ciphertext: Buffer | null; approval_hash: Buffer;
  confirm_key: string | null; confirmed_at: Date | null; uber_delivery_id: string | null; uber_status: string | null;
  tracking_url: string | null; created_at: Date;
}

class Refused extends Error {
  constructor(readonly status: number, readonly code: string, readonly extra: object = {}) { super(code); }
}

async function load(db: Pick<Db, "query">, accountId: string, id: string, lock = false): Promise<Row | undefined> {
  const { rows: [row] } = await db.query<Row>(
    `SELECT * FROM deliveries WHERE id = $1 AND account_id = $2${lock ? " FOR UPDATE" : ""}`, [id, accountId]);
  return row;
}

export const deliveryRoutes = (deps: Deps): FastifyPluginAsync => async (app) => {
  const { db } = deps;
  const auth = requireDevice(db);
  const limits = abuseLimits(deps.limits);
  const available = (): DeliveryDeps | undefined => (deps.deliveries && deps.cipher ? deps.deliveries : undefined);

  const view = (accountId: string, r: Row) => {
    const payload = deps.cipher ? openPayload(deps.cipher, accountId, r.id, r.payload_ciphertext) : undefined;
    return {
      id: r.id, state: r.state, errorCode: r.error_code, fee: r.fee, currency: r.currency,
      quoteExpiresAt: r.quote_expires_at, dropoffEta: r.dropoff_eta, uberStatus: r.uber_status, trackingUrl: r.tracking_url,
      card: payload?.card ?? null, createdAt: r.created_at, confirmedAt: r.confirmed_at,
    };
  };

  /** Erases the payload and records the end, for a delivery that never reached Uber or was refused. */
  const finish = (accountId: string, id: string, state: DeliveryState, code: string) => db.query(
    `UPDATE deliveries SET state = $3, error_code = $4, payload_ciphertext = NULL, payload_key_version = NULL, updated_at = now()
     WHERE id = $1 AND account_id = $2`, [id, accountId, state, code]);

  app.post("/v1/deliveries/quotes", { preHandler: auth, config: { rateLimit: { max: 20, timeWindow: "1 hour" } } }, async (req, reply) => {
    const d = available();
    if (!d || !deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const body = parse(quoteBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    // The courier calls the sender: the number this account verified, never one typed into the card.
    const { rows: [own] } = await db.query<{ e164: string }>("SELECT e164 FROM phone_numbers WHERE account_id = $1", [accountId]);
    if (!own) return reply.code(409).send({ error: "no_verified_phone" });
    if (!isAllowedNumber(own.e164, limits.allowedCountryCodes)) return reply.code(409).send({ error: "phone_not_allowed" });
    if (!isAllowedNumber(body.dropoff.phone, limits.allowedCountryCodes)) return reply.code(409).send({ error: "recipient_phone_not_allowed" });

    const quote = await d.provider.quote({
      pickupAddress: body.pickup.address, pickupPhone: own.e164,
      dropoffAddress: body.dropoff.address, dropoffPhone: body.dropoff.phone,
    });
    if (quote.kind === "rejected") return reply.code(422).send({ error: "quote_refused", code: quote.code });
    if (quote.kind !== "ok") return reply.code(503).send({ error: "provider_unavailable", code: quote.code });
    const q = quote.value;
    // Over the cap: shown, so the user hears the price, but nothing is stored and it can't be confirmed.
    if (q.fee > d.limits.maxFee) {
      return reply.code(409).send({ error: "fee_over_limit", fee: q.fee, currency: q.currency, maxFee: d.limits.maxFee });
    }
    const id = randomUUID();
    const base = {
      pickup: { name: body.pickup.name, address: body.pickup.address, phone: own.e164 },
      dropoff: body.dropoff, items: body.items, note: body.note,
    };
    const payload: DeliveryPayload = { ...base, card: deliveryCard(base) };
    const hash = deliveryApprovalHash(id, q.fee, q.currency, payload.card);
    await db.query(
      `INSERT INTO deliveries (id, account_id, state, uber_quote_id, fee, currency, quote_expires_at, dropoff_eta,
         payload_ciphertext, payload_key_version, approval_hash)
       VALUES ($1, $2, 'quoted', $3, $4, $5, $6, $7, $8, $9, $10)`,
      [id, accountId, q.quoteId, q.fee, q.currency, q.expiresAt, q.dropoffEta,
        sealPayload(deps.cipher, accountId, id, payload), deps.cipher.keyVersion, hash]);
    return reply.code(201).send({
      id, fee: q.fee, currency: q.currency, expiresAt: q.expiresAt, dropoffEta: q.dropoffEta, card: payload.card, mode: d.mode,
    });
  });

  app.post("/v1/deliveries/:id/confirm", { preHandler: auth, config: { rateLimit: { max: 10, timeWindow: "1 hour" } } }, async (req, reply) => {
    const d = available();
    if (!d || !deps.cipher) return reply.code(503).send({ error: "not_configured" });
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    const body = parse(confirmBody, req.body, reply);
    if (!body) return;
    const { accountId } = principal(req);
    const given = Buffer.from(body.approvalHash, "hex");
    let row: Row;
    try {
      row = await inTransaction(db, async (c) => {
        // One lock for every confirmation: the server-wide daily cap counts all accounts.
        await c.query("SELECT pg_advisory_xact_lock(hashtext('deliveries'))");
        const r = await load(c, accountId, p.id, true);
        if (!r) throw new Refused(404, "not_found");
        // The same tap again (an unclear answer, Doddy reopened): what happened to the first.
        if (r.confirm_key === body.idempotencyKey) {
          if (!r.approval_hash.equals(given)) throw new Refused(409, "idempotency_mismatch");
          throw new Refused(200, "repeat");
        }
        if (r.state !== "quoted") throw new Refused(409, "already_confirmed", { state: r.state });
        // Anything the card showed that differs from what was priced voids the tap.
        if (!timingSafeEqual(r.approval_hash, given)) throw new Refused(409, "approval_mismatch");
        // Uber's quote must still hold when Uber gets the request.
        if (r.quote_expires_at.getTime() - 30_000 < Date.now()) throw new Refused(409, "quote_expired");
        if (r.fee > d.limits.maxFee) throw new Refused(409, "fee_over_limit");
        const { rows: [counts = { mine: 0, all: 0 }] } = await c.query<{ mine: number; all: number }>(
          `SELECT count(*) FILTER (WHERE account_id = $1)::int AS mine, count(*)::int AS all FROM deliveries
           WHERE confirmed_at > now() - interval '1 day' AND state NOT IN ('failed', 'expired')`, [accountId]);
        if (counts.mine >= d.limits.perAccountDaily) throw new Refused(429, "daily_limit");
        if (counts.all >= d.limits.perServerDaily) throw new Refused(429, "server_daily_limit");
        const { rows: [updated] } = await c.query<Row>(
          `UPDATE deliveries SET state = 'creating', confirm_key = $3, confirmed_at = now(), updated_at = now()
           WHERE id = $1 AND account_id = $2 RETURNING *`, [p.id, accountId, body.idempotencyKey]);
        if (!updated) throw new Refused(404, "not_found");
        return updated;
      });
    } catch (err) {
      if (!(err instanceof Refused)) throw err;
      if (err.code === "repeat") {
        const again = await load(db, accountId, p.id);
        return reply.code(200).send(view(accountId, again!));
      }
      if (err.code === "quote_expired") await finish(accountId, p.id, "expired", "quote_expired");
      return reply.code(err.status).send({ error: err.code, ...err.extra });
    }

    const payload = openPayload(deps.cipher, accountId, row.id, row.payload_ciphertext);
    if (!payload) {
      await finish(accountId, row.id, "failed", "payload_unreadable");
      return reply.code(200).send(view(accountId, (await load(db, accountId, row.id))!));
    }
    const created = await d.provider.create({
      quoteId: row.uber_quote_id,
      pickupName: payload.pickup.name, pickupAddress: payload.pickup.address, pickupPhone: payload.pickup.phone,
      dropoffName: payload.dropoff.name, dropoffAddress: payload.dropoff.address, dropoffPhone: payload.dropoff.phone,
      dropoffNotes: payload.note, items: payload.items, doddyId: row.id,
    });
    if (created.kind === "ok") {
      await recordUberDelivery(db, d, accountId, row.id, created.value);
    } else if (created.kind === "unknown") {
      // Maybe booked, maybe not: never sent again on its own. GET /v1/deliveries/:id settles it.
      await db.query("UPDATE deliveries SET state = 'unknown', error_code = $3, updated_at = now() WHERE id = $1 AND account_id = $2",
        [row.id, accountId, created.code]);
    } else {
      // Refused, or refused before Uber accepted it: nothing was booked.
      await finish(accountId, row.id, "failed", created.code);
    }
    req.log.info({ delivery: row.id, outcome: created.kind, code: created.kind === "ok" ? undefined : created.code }, "delivery confirm");
    return reply.code(200).send(view(accountId, (await load(db, accountId, row.id))!));
  });

  app.get("/v1/deliveries/:id", { preHandler: auth, config: { rateLimit: { max: 120, timeWindow: "1 hour" } } }, async (req, reply) => {
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    const { accountId } = principal(req);
    const r = await load(db, accountId, p.id);
    if (!r) return reply.code(404).send({ error: "not_found" });
    const d = available();
    // A confirmation that stopped between the tap and Uber's answer (a restart) counts as unknown after two minutes.
    const stuck = r.state === "creating" && r.confirmed_at && r.confirmed_at.getTime() < Date.now() - 120_000;
    if (d && (r.state === "created" || r.state === "unknown" || stuck)) {
      const latest = r.uber_delivery_id ? await d.provider.get(r.uber_delivery_id) : await d.provider.findByExternalId(r.id);
      if (latest.kind === "ok" && latest.value) {
        await recordUberDelivery(db, d, accountId, r.id, latest.value);
      } else if (stuck) {
        await db.query("UPDATE deliveries SET state = 'unknown', error_code = 'interrupted', updated_at = now() WHERE id = $1 AND state = 'creating'", [r.id]);
      }
    }
    return view(accountId, (await load(db, accountId, p.id))!);
  });

  app.get("/v1/deliveries", { preHandler: auth }, async (req) => {
    const { accountId } = principal(req);
    const { rows } = await db.query<Row>(
      "SELECT * FROM deliveries WHERE account_id = $1 ORDER BY created_at DESC LIMIT 20", [accountId]);
    return { deliveries: rows.map((r) => view(accountId, r)) };
  });

  app.post("/v1/deliveries/:id/cancel", { preHandler: auth, config: { rateLimit: { max: 20, timeWindow: "1 hour" } } }, async (req, reply) => {
    const p = parse(idParam, req.params, reply);
    if (!p) return;
    if (!parse(cancelBody, req.body, reply)) return;
    const { accountId } = principal(req);
    const r = await load(db, accountId, p.id);
    if (!r) return reply.code(404).send({ error: "not_found" });
    // A quote never tapped: nothing at Uber to cancel.
    if (r.state === "quoted") {
      await finish(accountId, r.id, "expired", "cancelled_before_confirm");
      return view(accountId, (await load(db, accountId, r.id))!);
    }
    if (FINISHED.includes(r.state)) return reply.code(409).send({ error: "already_over", state: r.state });
    const d = available();
    if (!d) return reply.code(503).send({ error: "not_configured" });
    if (!r.uber_delivery_id) return reply.code(409).send({ error: "not_known_at_uber_yet", state: r.state });
    const res = await d.provider.cancel(r.uber_delivery_id);
    if (res.kind === "ok") {
      await recordUberDelivery(db, d, accountId, r.id, res.value);
      return view(accountId, (await load(db, accountId, r.id))!);
    }
    if (res.kind === "rejected") return reply.code(409).send({ error: "cannot_cancel", code: res.code });
    // Unclear or busy: the state is unchanged; GET /v1/deliveries/:id says what Uber has now.
    return reply.code(503).send({ error: res.kind === "unknown" ? "cancel_unclear" : "provider_unavailable", code: res.code });
  });
};
