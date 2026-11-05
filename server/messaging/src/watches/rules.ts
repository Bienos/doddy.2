// The decisions of a price watch's check, as pure functions (no database, no clock, no network), so the
// rules can be tested alone. SHOPPING_WATCH.md section 2:
//   - "dropped" is only said after a confirmed read: a check that fails or can't read a price is a failed
//     check, never a price;
//   - a page that says out of stock never triggers; a price in another currency never triggers;
//   - the first confirmed in-stock read at or below the user's number triggers, once, and ends the watch;
//   - 8 failed checks in a row end it as `failed`; 30 days end it as `expired` (the last check comes first).
import type { PageCheck } from "../shopping/pagecheck.js";
import { MAX_FAILURES } from "./schema.js";

export type Verdict =
  /** A confirmed read in the user's currency, in stock, at or below the user's number. */
  | { kind: "triggered"; priceMinor: number }
  /** A confirmed read in the user's currency, in stock, above the user's number. */
  | { kind: "above"; priceMinor: number }
  /** The page was read and says out of stock: no trigger, and no price is recorded. */
  | { kind: "unavailable" }
  /** The page was read in another currency: no trigger, and no price is recorded. */
  | { kind: "other_currency" }
  /** Nothing usable was read (blocked, not allowed, no price, not HTML, network, or content that can't be opened). */
  | { kind: "failed"; cause: string };

export function judge(check: PageCheck, thresholdMinor: number, currency: string): Verdict {
  if (check.kind !== "ok") return { kind: "failed", cause: check.kind };
  const { price, availability } = check.offer;
  if (price.currency !== currency) return { kind: "other_currency" };
  if (availability === "out_of_stock") return { kind: "unavailable" };
  if (!Number.isSafeInteger(price.minor) || price.minor <= 0) return { kind: "failed", cause: "bad_price" };
  return price.minor <= thresholdMinor ? { kind: "triggered", priceMinor: price.minor } : { kind: "above", priceMinor: price.minor };
}

export interface Progress { checksDone: number; consecutiveFailures: number; endsAt: Date }

export interface Decision {
  state: "active" | "triggered" | "failed" | "expired";
  checksDone: number;
  consecutiveFailures: number;
  /** Set only by a confirmed read in stock: it becomes the watch's last (and, when triggered, triggered) price. */
  priceMinor?: number;
  /** Active only: when the next check is due. */
  nextCheckAt?: Date;
  /** The one push this check queues, if any. */
  push?: "triggered" | "failed";
}

/**
 * What one finished check does to a watch. A drop wins over everything; then 8 failures in a row; then the
 * end of the 30 days. Otherwise the next check is due one interval (and a small shift) later, but no later
 * than the end of the 30 days, so the last check comes first and only then the watch expires.
 */
export function decide(p: Progress, v: Verdict, now: Date, intervalMs: number, jitterMs: number): Decision {
  const checksDone = p.checksDone + 1;
  if (v.kind === "triggered") return { state: "triggered", checksDone, consecutiveFailures: 0, priceMinor: v.priceMinor, push: "triggered" };
  const consecutiveFailures = v.kind === "failed" ? p.consecutiveFailures + 1 : 0;
  const priceMinor = v.kind === "above" ? v.priceMinor : undefined;
  if (consecutiveFailures >= MAX_FAILURES) return { state: "failed", checksDone, consecutiveFailures, push: "failed" };
  if (now.getTime() >= p.endsAt.getTime()) return { state: "expired", checksDone, consecutiveFailures, ...(priceMinor !== undefined ? { priceMinor } : {}) };
  const next = Math.min(now.getTime() + intervalMs + jitterMs, p.endsAt.getTime());
  return { state: "active", checksDone, consecutiveFailures, ...(priceMinor !== undefined ? { priceMinor } : {}), nextCheckAt: new Date(next) };
}

/**
 * The push words (SHOPPING_WATCH.md section 2). Never a product word, a shop, an address or a price: the
 * app shows the details when it is opened. The failure line says only that the price can no longer be read.
 */
export const PUSH_TEXT = {
  triggered: { pl: "Cena, której pilnujesz, spadła.", en: "A price you're watching dropped." },
  failed: { pl: "Nie mogę już odczytać ceny, której pilnujesz.", en: "Doddy can no longer read a price you're watching." },
} as const;
export const pushText = (kind: "triggered" | "failed", language: string): string => (language === "pl" ? PUSH_TEXT[kind].pl : PUSH_TEXT[kind].en);
