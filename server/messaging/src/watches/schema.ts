// Price watches (docs/implementation/SHOPPING_WATCH.md, fixture schemas/fixtures/watch_create_v1.json):
// the request the app sends and the digest the user approves. No model is involved anywhere in this
// module: the rules are code.
import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJson } from "../taskCalls/payload.js";

export const WATCH_STATES = ["draft", "active", "triggered", "expired", "stopped", "failed"] as const;
export type WatchState = (typeof WATCH_STATES)[number];

/** The promise on the card: how long and how often. Part of the digest, so the app can't show another one. */
export const DAYS = 30;
export const CHECKS_PER_DAY = 4;
/** Failed checks in a row that end a watch (about two days at four checks a day). */
export const MAX_FAILURES = 8;

export const LIMITS = { title: 120, shop: 80, url: 2048, threshold: 1_000_000_000 } as const;

const text = (max: number) => z.string().max(max).refine((s) => s.trim().length > 0, "empty");

/** https, with a host right after the slashes, no credentials, no whitespace: the page the shop itself publishes. */
const pageUrl = z.string().max(LIMITS.url).refine((s) => {
  if (!/^https:\/\/[^/\\\s?#@]+(?:[/?#]\S*)?$/u.test(s)) return false;
  try {
    const u = new URL(s);
    return u.protocol === "https:" && u.hostname.length > 0 && !u.username && !u.password;
  } catch {
    return false;
  }
}, "not an https address");

/**
 * POST /v1/watches. The words are stored exactly as sent (never trimmed or rewritten). `thresholdMinor`
 * is the user's price in minor units (grosze).
 */
export const createBody = z.strictObject({
  title: text(LIMITS.title),
  shop: text(LIMITS.shop),
  url: pageUrl,
  thresholdMinor: z.number().int().min(1).max(LIMITS.threshold),
  currency: z.string().regex(/^[A-Z]{3}$/),
  language: z.string().regex(/^[a-z]{2}$/),
});
export type WatchContent = z.infer<typeof createBody>;

/**
 * What the user approves: SHA-256 (hex) over the canonical JSON of {checksPerDay, currency, days,
 * language, shop, thresholdMinor, title, url} with days = 30 and checksPerDay = 4: keys sorted, no
 * spaces, strings as JSON.stringify writes them, UTF-8. The price read now is not in it: it varies,
 * and the user approves the promise, not a quote.
 */
export function contentJson(c: WatchContent): string {
  return canonicalJson({
    checksPerDay: CHECKS_PER_DAY, currency: c.currency, days: DAYS, language: c.language, shop: c.shop,
    thresholdMinor: c.thresholdMinor, title: c.title, url: c.url,
  });
}
export const contentDigest = (c: WatchContent): Buffer => createHash("sha256").update(contentJson(c), "utf8").digest();

/** The part of the content that is stored encrypted: only words and the address, never the numbers. */
export const blobSchema = z.strictObject({
  language: z.string().regex(/^[a-z]{2}$/),
  shop: text(LIMITS.shop),
  title: text(LIMITS.title),
  url: pageUrl,
});
export type WatchBlob = z.infer<typeof blobSchema>;
export const blobJson = (b: WatchBlob): string => canonicalJson({ language: b.language, shop: b.shop, title: b.title, url: b.url });
