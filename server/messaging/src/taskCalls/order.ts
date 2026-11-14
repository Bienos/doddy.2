// A food order Doddy may place on a call (decision docs/decisions/2026-11-12-food-by-phone.md). The
// person approves these exact details on the card; every sentence that names them is built here, in
// code, so the model never phrases what is ordered. The order agent may accept exactly this order by
// saying `orderConfirmLine` and nothing else; result.ts checks that it did and that it said no other
// commitment. Payment is on delivery or at pickup only: no payment detail is ever part of an order.
import { z } from "zod";
import { clean } from "./clean.js";

const NAME = /^[\p{L}][\p{L}\p{M} '’.\-]{0,59}$/u;
const text = (max: number, min = 1) => z.string().min(min).max(max * 2).transform(clean).pipe(z.string().min(min).max(max));

/** One line of the order: "2 × pizza margherita", optionally "bez cebuli". */
export const orderLineSchema = z.strictObject({
  quantity: z.number().int().min(1).max(20),
  name: text(80),
  note: text(60).optional(),
});

/** Where it goes: typed on the card for this one call, never saved as a home address. */
export const deliverySchema = z.strictObject({
  street: text(80),
  apartment: text(20).optional(),
  postcode: z.string().regex(/^\d{2}-\d{3}$/),
  city: text(60),
  /**
   * The number the courier may call: a Polish number, 9 digits, kept as "600 000 000" (a "+48" typed before it is
   * dropped, so Doddy never says an 11-digit number, which the call audit reads as a PESEL).
   */
  phone: z.string().max(24).transform((p) => p.replace(/[\s\-]/g, "").replace(/^(\+48|0048)/, ""))
    .pipe(z.string().regex(/^\d{9}$/)).transform((p) => `${p.slice(0, 3)} ${p.slice(3, 6)} ${p.slice(6)}`),
});

export const MAX_ORDER_LINES = 8;
/** Highest total the person can set on a card, in zł; the card's default. */
export const MAX_TOTAL_PLN = 500;
export const DEFAULT_TOTAL_PLN = 150;

export const orderSchema = z.strictObject({
  /** The name the order is under ("Anna Kowalska"). */
  name: text(60).pipe(z.string().regex(NAME)),
  lines: z.array(orderLineSchema).min(1).max(MAX_ORDER_LINES),
  /** Delivery to this address, or exactly one of `pickup`. */
  delivery: deliverySchema.optional(),
  pickup: z.literal(true).optional(),
  /** The most the person will pay, in whole zł. Doddy never accepts a higher total. */
  maxTotalPln: z.number().int().min(10).max(MAX_TOTAL_PLN).default(DEFAULT_TOTAL_PLN),
}).refine((o) => (o.delivery !== undefined) !== (o.pickup === true), { message: "delivery_xor_pickup", path: ["delivery"] });

export type Order = z.infer<typeof orderSchema>;

const PAYMENT = "płatność gotówką lub kartą przy odbiorze";

/** "2 × pizza margherita (bez cebuli), 1 × cola". */
export function orderItems(o: Order): string {
  return o.lines.map((l) => `${l.quantity} × ${l.name}${l.note ? ` (${l.note})` : ""}`).join(", ");
}

/** "ul. Długa 5 m. 12, 00-001 Warszawa" (the street as typed). */
export function deliveryAddress(d: NonNullable<Order["delivery"]>): string {
  return `${d.street}${d.apartment ? ` m. ${d.apartment}` : ""}, ${d.postcode} ${d.city}`;
}

/** "dostawa na …" or "odbiór osobisty". */
export function orderHow(o: Order): string {
  return o.delivery ? `dostawa na ${deliveryAddress(o.delivery)}` : "odbiór osobisty";
}

/** The question asked word for word after the AI disclosure. No address, no name: those come after they agree. */
export function orderQuestion(o: Order): string {
  return `Czy mogą Państwo przyjąć zamówienie ${o.delivery ? "z dostawą" : "na odbiór osobisty"}?`;
}

/** The only sentence that accepts the order. Said at most once, and only when they can take exactly this. */
export function orderConfirmLine(o: Order): string {
  return `Dobrze, proszę o zamówienie: ${orderItems(o)}, ${orderHow(o)}, ${PAYMENT}, na nazwisko ${o.name}.`;
}

/** The order as the agent reads it, one detail per line. */
export function orderLines(o: Order): string {
  return [
    `- Zamówienie: ${orderItems(o)}`,
    `- ${o.delivery ? `Dostawa na adres: ${deliveryAddress(o.delivery)}` : "Odbiór osobisty"}`,
    ...(o.delivery ? [`- Telefon dla kuriera: ${o.delivery.phone}`] : []),
    `- Płatność: ${PAYMENT.replace("płatność ", "")}`,
    `- Najwyższa łączna kwota: ${o.maxTotalPln} zł`,
    `- Na nazwisko: ${o.name}`,
  ].join("\n");
}

/** What the card's "never" list says the call may accept. */
export function orderSummary(o: Order): string {
  return `${orderItems(o)}, ${orderHow(o)}, na nazwisko ${o.name}`;
}
