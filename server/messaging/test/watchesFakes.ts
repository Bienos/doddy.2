// Stand-ins for the price-watch tests: a fake shop (a PageFetcher serving prepared outcomes, recording when it
// was asked) and helpers that build product pages with schema.org data. Nothing here reaches the network.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { TextCipher } from "../src/crypto.js";
import type { FetchOutcome, PageFetcher } from "../src/shopping/pagecheck.js";
import { contentAad } from "../src/watches/context.js";
import { blobJson, contentDigest, type WatchContent } from "../src/watches/schema.js";
import type { Claimed } from "../src/watches/worker.js";

const here = path.dirname(fileURLToPath(import.meta.url));
export const watchFixture = JSON.parse(readFileSync(path.resolve(here, "../../../../schemas/fixtures/watch_create_v1.json"), "utf8")) as {
  request: WatchContent; canonical: string; digest: string; preview: Record<string, unknown>; summaries: Record<string, Record<string, unknown>>;
};

export const FX_URL = watchFixture.request.url;
export const FX_HOST = new URL(FX_URL).hostname;

/** A shop page publishing one Product with one Offer, the way shops publish it for search engines. */
export function productPage(price: number | string, o: { currency?: string; availability?: string; finalUrl?: string } = {}): FetchOutcome {
  const offer: Record<string, unknown> = { "@type": "Offer", price, priceCurrency: o.currency ?? "PLN" };
  if (o.availability) offer.availability = `https://schema.org/${o.availability}`;
  const ld = { "@context": "https://schema.org", "@type": "Product", name: "Zmywarka testowa", offers: offer };
  return {
    kind: "ok", status: 200, contentType: "text/html; charset=utf-8", finalUrl: o.finalUrl ?? FX_URL,
    body: Buffer.from(`<html><head><script type="application/ld+json">${JSON.stringify(ld)}</script></head><body>Cena 1 zł!</body></html>`),
  };
}
export const blocked: FetchOutcome = { kind: "blocked", reason: "http_403" };
export const disallowed: FetchOutcome = { kind: "disallowed", reason: "robots" };
export const failedRead: FetchOutcome = { kind: "failed", reason: "network" };
/** A readable HTML page that publishes no structured price (its prose says "Cena 1 zł!", which is never parsed). */
export const noPricePage: FetchOutcome = {
  kind: "ok", status: 200, contentType: "text/html", finalUrl: FX_URL, body: Buffer.from("<html><body>Cena 1 zł!</body></html>"),
};
export const pdfPage: FetchOutcome = { kind: "ok", status: 200, contentType: "application/pdf", finalUrl: FX_URL, body: Buffer.from("%PDF") };

type Page = FetchOutcome | (() => FetchOutcome | Promise<FetchOutcome>);

/** A fetcher serving what the test set per address (anything else: a failed read), recording each request. */
export class FakeShop implements PageFetcher {
  readonly calls: { url: string; at: number }[] = [];
  private readonly pages = new Map<string, Page>();
  constructor(private readonly clock: () => number = () => 0) {}
  set(url: string, page: Page): this { this.pages.set(url, page); return this; }
  has(url: string): boolean { return this.pages.has(url); }
  count(url?: string): number { return url ? this.calls.filter((c) => c.url === url).length : this.calls.length; }
  async fetchPage(url: string): Promise<FetchOutcome> {
    this.calls.push({ url, at: this.clock() });
    const p = this.pages.get(url) ?? failedRead;
    return typeof p === "function" ? p() : p;
  }
}

/** A promise a test settles from outside: holds a fake shop's answer while the test acts. */
export function gate<T = void>(): { promise: Promise<T>; open: (v: T) => void } {
  let open!: (v: T) => void;
  const promise = new Promise<T>((resolve) => { open = resolve; });
  return { promise, open };
}

/** A claim row for the worker as the database would hand it out, for tests that don't need a database. */
export function claimedFor(cipher: TextCipher, content: WatchContent, over: Partial<Claimed> = {}): Claimed {
  const id = over.id ?? "7d6c1f0e-2b8a-4c55-9a0e-3f4d5b6a7c81";
  const accountId = over.account_id ?? "0b9e8d7c-6a5f-4e3d-8c2b-1a0f9e8d7c6b";
  const due = new Date("2026-10-24T18:02:30.000Z");
  return {
    id, account_id: accountId, language: content.language,
    content_ciphertext: cipher.encrypt(blobJson({ language: content.language, shop: content.shop, title: content.title, url: content.url }), contentAad(accountId, id)),
    payload_digest: contentDigest(content), threshold_minor: String(content.thresholdMinor), currency: content.currency,
    due_at: due, lease: new Date(due.getTime() + 15 * 60_000), ...over,
  };
}
