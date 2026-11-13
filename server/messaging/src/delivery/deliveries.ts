import type { TextCipher } from "../crypto.js";
import type { Db } from "../db.js";
import type { DeliveryProvider, UberAddress, UberDelivery, UberItem } from "./uberDirect.js";

// Deliveries through Uber Direct (decision 2026-11-12-uber-direct-deliveries). A quote is priced and
// shown on a card; Uber is asked to deliver only after the tap that card's lines are bound to
// (deliveryApprovalHash, DOD-07). Uber bills the account these credentials belong to, so every
// delivery is capped per account, per server per day and by price (DeliveryLimits).

export interface DeliveryLimits {
  /** Highest quoted price Doddy will confirm, in the currency's minor units. */
  maxFee: number;
  /** Confirmed deliveries per account per rolling 24 hours. */
  perAccountDaily: number;
  /** Confirmed deliveries for the whole server per rolling 24 hours. */
  perServerDaily: number;
}

/** Proposal until the owner decides who pays (OWNER_QUEUE): 60 zł, 2 a day each, 5 a day in all. */
export const DEFAULT_DELIVERY_LIMITS: DeliveryLimits = { maxFee: 6000, perAccountDaily: 2, perServerDaily: 5 };

export interface DeliveryDeps {
  provider: DeliveryProvider;
  mode: "test" | "live";
  limits: DeliveryLimits;
}

/** What the user asked to send, kept encrypted until the delivery is over. */
export interface DeliveryPayload {
  pickup: { name: string; address: UberAddress; phone: string };
  dropoff: { name: string; address: UberAddress; phone: string };
  items: UberItem[];
  note: string;
  card: DeliveryCard;
}

/** The card's lines, written here once; the iPhone shows them as they are and hashes them for the tap. */
export interface DeliveryCard { pickup: string; dropoff: string; dropoffPhone: string; items: string; note: string }

export function addressLine(a: UberAddress): string {
  return `${a.street}${a.apartment ? ` ${a.apartment}` : ""}, ${a.postcode} ${a.city}, ${a.country}`;
}

export function deliveryCard(p: Omit<DeliveryPayload, "card">): DeliveryCard {
  return {
    pickup: `${p.pickup.name}, ${addressLine(p.pickup.address)}`,
    dropoff: `${p.dropoff.name}, ${addressLine(p.dropoff.address)}`,
    dropoffPhone: p.dropoff.phone,
    items: p.items.map((i) => `${i.quantity}× ${i.name} (${i.size})`).join(", "),
    note: p.note,
  };
}

export const payloadAad = (accountId: string, id: string) => `${accountId}:delivery:${id}`;

export const sealPayload = (cipher: TextCipher, accountId: string, id: string, p: DeliveryPayload) =>
  cipher.encrypt(JSON.stringify(p), payloadAad(accountId, id));

/** The payload, or undefined when it was erased or can't be read any more (a key change). */
export function openPayload(cipher: TextCipher, accountId: string, id: string, blob: Buffer | null): DeliveryPayload | undefined {
  if (!blob) return undefined;
  try {
    return JSON.parse(cipher.decrypt(blob, payloadAad(accountId, id))) as DeliveryPayload;
  } catch {
    return undefined;
  }
}

export type DeliveryState =
  'quoted' | 'creating' | 'created' | 'unknown' | 'delivered' | 'cancelled' | 'returned' | 'failed' | 'expired';

/** Over: the payload is erased and nothing more is asked of Uber. */
export const FINISHED: readonly DeliveryState[] = ["delivered", "cancelled", "returned", "failed", "expired"];

/** Our state for Uber's status (pending, pickup, pickup_complete, dropoff, ongoing, delivered, canceled, returned). */
export function stateFor(uberStatus: string): DeliveryState {
  switch (uberStatus) {
    case "delivered": return "delivered";
    case "canceled": case "cancelled": return "cancelled";
    case "returned": return "returned";
    default: return "created";
  }
}

/**
 * Records what Uber said about a delivery: its id, status, tracking link and whether it is live. A
 * finished one loses its payload. In test mode a delivery Uber marks live is a real one made by
 * mistake (production credentials in a test setup): it is cancelled at once and recorded as failed.
 */
export async function recordUberDelivery(db: Pick<Db, "query">, deps: DeliveryDeps, accountId: string, id: string,
  d: UberDelivery): Promise<DeliveryState> {
  let state = stateFor(d.status);
  let error: string | null = null;
  if (deps.mode === "test" && d.liveMode === true && !FINISHED.includes(state)) {
    const cancelled = await deps.provider.cancel(d.id);
    state = cancelled.kind === "ok" ? "failed" : "unknown";
    error = cancelled.kind === "ok" ? "live_delivery_in_test_mode" : "live_delivery_cancel_unclear";
  }
  const done = FINISHED.includes(state);
  await db.query(
    `UPDATE deliveries SET state = $3, error_code = COALESCE($4, error_code), uber_delivery_id = $5, uber_status = $6,
       tracking_url = COALESCE($7, tracking_url), live_mode = COALESCE($8, live_mode),
       payload_ciphertext = CASE WHEN $9 THEN NULL ELSE payload_ciphertext END,
       payload_key_version = CASE WHEN $9 THEN NULL ELSE payload_key_version END, updated_at = now()
     WHERE id = $1 AND account_id = $2`,
    [id, accountId, state, error, d.id, d.status, d.trackingUrl, d.liveMode, done]);
  return state;
}

/**
 * Erases what isn't needed any more: quotes never tapped (expired 10 minutes ago or more) and the
 * payload of finished deliveries. Run by the worker loop. Returns how many rows changed.
 */
export async function pruneDeliveries(db: Pick<Db, "query">, now = new Date()): Promise<number> {
  const lapsed = await db.query(
    `UPDATE deliveries SET state = 'expired', payload_ciphertext = NULL, payload_key_version = NULL, updated_at = now()
     WHERE state = 'quoted' AND quote_expires_at < $1::timestamptz - interval '10 minutes'`, [now]);
  const finished = await db.query(
    `UPDATE deliveries SET payload_ciphertext = NULL, payload_key_version = NULL, updated_at = now()
     WHERE payload_ciphertext IS NOT NULL AND state IN ('delivered', 'cancelled', 'returned', 'failed', 'expired')`);
  return (lapsed.rowCount ?? 0) + (finished.rowCount ?? 0);
}
