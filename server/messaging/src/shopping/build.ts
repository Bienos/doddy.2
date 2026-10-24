// The code rules on a shopping result (docs/implementation/SHOPPING.md, "Code rules"). The model's
// card refers to offers by id; this file writes every price, shop, link and time from the registry,
// computes what can be computed (over budget, which pick is really the cheapest), drops model-written
// sentences that state an amount it can't back, and fills the research card's generic fields so older
// apps and check_errands keep working.
import { z } from "zod";
import { shorten } from "../news/writer.js";
import {
  ErrandResultSchema, LIMITS, PICK_ROLES, SHOPPING_LIMITS,
  type ErrandResult, type ShoppingResult,
} from "../errands/schema.js";
import { formatMoney, moneyMentions, type Money } from "./money.js";
import type { OfferRegistry, RegisteredOffer } from "./offers.js";

/** What the card writer returns: every field present (null when empty), lengths clamped by code. */
export const ShoppingCardOutput = z.object({
  picks: z.array(z.object({
    role: z.enum(PICK_ROLES).describe("best: your pick by the person's priorities; cheapest: the cheapest offer that fits; premium: better on the top priority even if dearer; alternative: another worth seeing."),
    offerId: z.string().describe("An offer id from the offers list, e.g. o3. Never a price."),
    why: z.string().describe("One short sentence: why this one, by the person's priorities. No prices: the app shows them."),
    tradeoff: z.string().nullable().describe("One short sentence on what it gives up, or null."),
  })).describe(`One best pick, then at most ${SHOPPING_LIMITS.picks - 1} more.`),
  offerNotes: z.array(z.object({
    offerId: z.string(),
    notes: z.string().describe("Short facts from the pages you read, e.g. '42 dB · 10 kompletów · klasa C'. No prices."),
  })),
  budget: z.object({
    amount: z.number().nullable().describe("The person's budget as a number in their currency (e.g. 2000), only if they gave one."),
  }),
  recommendation: z.string().nullable().describe("One or two sentences, no prices, or null."),
  howChosen: z.array(z.string()).describe(`At most ${SHOPPING_LIMITS.howChosen} short lines: how you filtered and ordered.`),
  watchOuts: z.array(z.string()).describe(`At most ${SHOPPING_LIMITS.watchOuts}: costs or catches to know about.`),
  unknowns: z.array(z.string()).describe(`At most ${SHOPPING_LIMITS.unknowns}: what you couldn't confirm.`),
  rejected: z.array(z.string()).describe(`At most ${SHOPPING_LIMITS.rejected}: what you left out and why.`),
  next: z.array(z.string()).describe(`At most ${LIMITS.next} short follow-ups the person might ask next.`),
});
export type ShoppingCardOutput = z.infer<typeof ShoppingCardOutput>;

export interface ShoppingContent { words: string; brief: string; language: string; priorities: string[] }
export interface ShoppingBuildStats { droppedPicks: number; droppedSentences: number; relabelled: number }

type Role = (typeof PICK_ROLES)[number];
const ROLE_LABEL: Record<Role, { pl: string; en: string }> = {
  best: { pl: "Mój wybór", en: "My pick" },
  cheapest: { pl: "Najtańsza", en: "Cheapest" },
  premium: { pl: "Bez kompromisów", en: "No compromise" },
  alternative: { pl: "Inna opcja", en: "Another option" },
};
const EVIDENCE_LABEL = {
  shop_page: { pl: "Cena sprawdzona na stronie sklepu", en: "Price checked on the shop's page" },
  listing: { pl: "Cena z listy Google Shopping", en: "Price from the Google Shopping list" },
} as const;
const pick = <T extends { pl: string; en: string }>(l: T, language: string) => (language === "pl" ? l.pl : l.en);

/** Is the budget the model read actually in the person's words (or Doddy's brief)? */
export function budgetBacked(minor: number, words: string, brief: string): boolean {
  if (minor % 100 !== 0) return false;
  const whole = minor / 100;
  const text = `${words} ${brief}`;
  const compact = text.replace(/[\s  .]/gu, "");
  if (new RegExp(String.raw`(^|\D)${whole}(\D|$)`, "u").test(compact)) return true;
  if (whole % 1000 === 0) {
    const k = whole / 1000;
    if (new RegExp(String.raw`(^|\D)${k}\s*(tys|k\b|tysi)`, "iu").test(text)) return true;
  }
  return false;
}

/** Keeps the sentences whose money amounts are all in `allowed`; counts the dropped ones. */
export function keepBackedSentences(text: string, allowed: ReadonlySet<number>, onDrop: () => void): string | undefined {
  const sentences = text.trim().split(/(?<=[.!?])\s+/u);
  const kept = sentences.filter((s) => {
    const ok = moneyMentions(s).every((a) => allowed.has(a));
    if (!ok) onDrop();
    return ok;
  });
  const out = kept.join(" ").trim();
  return out || undefined;
}

/** Confirmed: the code read this price on the shop's own page. Only these can be picked, priced or shown (ADR-611). */
export const isConfirmed = (o: RegisteredOffer): boolean => o.evidence === "shop_page";

/** One line, written by the code, naming the shops whose offers were found only in Google's list (no prices). */
export function unconfirmedLine(leads: readonly RegisteredOffer[], lang: string): string | undefined {
  if (!leads.length) return undefined;
  const shops = [...new Set(leads.map((o) => o.shop))];
  const shown = shops.slice(0, 3).join(", ") + (shops.length > 3 ? (lang === "pl" ? " i inne" : " and others") : "");
  return shorten(lang === "pl"
    ? `Oferty z listy Google Shopping bez potwierdzenia na stronie sklepu (nie podaję ich cen): ${shown}.`
    : `Offers from the Google Shopping list not confirmed on the shop's page (prices not shown): ${shown}.`, SHOPPING_LIMITS.line);
}

/**
 * The result when no price could be confirmed on a shop's own page: an honest research-style card with no
 * `shopping` block and no price anywhere (ADR-611: "only confirmed prices, and say so when there are none").
 * Offers found only in Google's list appear by name and shop, never with a price or a link.
 */
export function buildUnconfirmedResult(registry: OfferRegistry, content: { language: string }, now: Date): ErrandResult | undefined {
  const pl = content.language === "pl";
  const leads = registry.list().filter((o) => !isConfirmed(o));
  const items = leads.slice(0, LIMITS.items).map((o) => ({
    title: shorten(o.title, LIMITS.itemTitle),
    detail: shorten(pl ? `${o.shop} · cena niepotwierdzona na stronie sklepu, więc bez ceny` : `${o.shop} · price not confirmed on the shop's page, so none shown`, LIMITS.detail),
  }));
  const answer = pl
    ? "Nie udało mi się potwierdzić ceny na stronie żadnego sklepu, więc nie podaję żadnych cen."
      + (leads.length ? " Znalazłem tylko oferty z listy Google Shopping." : " Nie znalazłem też żadnej oferty z odczytywalną ceną.")
    : "I couldn't confirm a price on any shop's own page, so I'm not giving any prices."
      + (leads.length ? " I only found offers from the Google Shopping list." : " I also found no offer with a readable price.");
  const draft = {
    answer,
    sections: items.length ? [{ heading: pl ? "Bez potwierdzonej ceny" : "Not confirmed", kind: "brief" as const, items }] : [],
    next: [pl ? "Spróbuj jeszcze raz za jakiś czas albo opisz dokładniej, czego szukasz." : "Try again later, or describe more exactly what you're looking for."],
    sources: [],
    checkedAt: now.toISOString(),
  };
  const parsed = ErrandResultSchema.safeParse(draft);
  return parsed.success ? parsed.data : undefined;
}

/**
 * Builds the stored result. Returns undefined (the errand fails as unreadable_result) when no `best`
 * pick names an offer confirmed on a shop's page. Offers known only from Google's list are never picked,
 * priced or shown; one code-written line says so.
 */
export function buildShoppingResult(card: ShoppingCardOutput, registry: OfferRegistry, content: ShoppingContent, now: Date,
  affiliate?: { link(pageUrl: string): string | undefined }):
  { result: ErrandResult; stats: ShoppingBuildStats } | undefined {
  const lang = content.language;
  const stats: ShoppingBuildStats = { droppedPicks: 0, droppedSentences: 0, relabelled: 0 };

  // Picks: known ids only, one per offer, one each of best/cheapest/premium, at most 4.
  type P = { role: Role; offer: RegisteredOffer; why: string; tradeoff?: string };
  const picks: P[] = [];
  for (const p of card.picks) {
    const offer = registry.get(p.offerId.trim());
    const dupRole = p.role !== "alternative" && picks.some((x) => x.role === p.role);
    if (!offer || !isConfirmed(offer) || dupRole || picks.some((x) => x.offer.id === offer.id) || picks.length >= SHOPPING_LIMITS.picks) {
      stats.droppedPicks++;
      continue;
    }
    picks.push({ role: p.role, offer, why: p.why, tradeoff: p.tradeoff ?? undefined });
  }
  const best = picks.find((p) => p.role === "best");
  if (!best) return undefined;
  // "Cheapest" must be true among the picks.
  for (const p of picks) {
    if (p.role !== "cheapest") continue;
    const cheaper = picks.some((x) => x !== p && x.offer.price.currency === p.offer.price.currency && x.offer.price.minor < p.offer.price.minor);
    if (cheaper) { p.role = "alternative"; stats.relabelled++; }
  }
  // best first, then cheapest, premium, alternatives in the model's order (the sort is stable).
  const order: Record<Role, number> = { best: 0, cheapest: 1, premium: 2, alternative: 3 };
  picks.sort((a, b) => order[a.role] - order[b.role]);

  // Budget: only a number that is in the person's words.
  let budget: Money | undefined;
  const amount = card.budget.amount;
  if (typeof amount === "number" && Number.isFinite(amount) && amount > 0 && amount < 1e9) {
    const minor = Math.round(amount * 100);
    if (budgetBacked(minor, content.words, content.brief)) budget = { minor, currency: best.offer.price.currency };
  }
  const over = (o: RegisteredOffer): Money | undefined =>
    budget && o.price.currency === budget.currency && o.price.minor > budget.minor
      ? { minor: o.price.minor - budget.minor, currency: budget.currency } : undefined;

  // Amounts a model sentence may state: offer prices, the budget, and differences the code can compute.
  const allowed = new Set<number>();
  const prices = registry.list().filter(isConfirmed).map((o) => o.price.minor);
  for (const a of prices) allowed.add(a);
  if (budget) {
    allowed.add(budget.minor);
    for (const a of prices) allowed.add(Math.abs(a - budget.minor));
  }
  const picked = picks.map((p) => p.offer.price.minor);
  for (const a of picked) for (const b of picked) if (a !== b) allowed.add(Math.abs(a - b));
  const drop = () => { stats.droppedSentences++; };
  const line = (t: string | null | undefined, max: number = SHOPPING_LIMITS.line): string | undefined => {
    if (typeof t !== "string" || !t.trim()) return undefined;
    const kept = keepBackedSentences(t, allowed, drop);
    return kept ? shorten(kept, max) : undefined;
  };
  const lines = (list: string[], n: number) => list.flatMap((t) => line(t) ?? []).slice(0, n);

  // Offers in the result: the picked ones, then the ones the model annotated, at most 12.
  const notes = new Map<string, string>();
  for (const n of card.offerNotes) {
    const id = n.offerId.trim();
    const t = line(n.notes, SHOPPING_LIMITS.notes);
    const noted = registry.get(id);
    if (noted && isConfirmed(noted) && t && !notes.has(id)) notes.set(id, t);
  }
  const ids: string[] = [];
  for (const p of picks) ids.push(p.offer.id);
  for (const id of notes.keys()) if (!ids.includes(id)) ids.push(id);
  const offers = ids.slice(0, SHOPPING_LIMITS.offers).flatMap((id) => {
    const o = registry.get(id);
    if (!o) return [];
    return [{
      id: o.id, title: o.title, shop: o.shop, price: o.price, delivery: o.delivery, url: o.url, site: o.site,
      // Written last, from the finished picks: a tracked link never reaches the model or the ordering (ADR-612).
      buyUrl: affiliate?.link(o.url),
      evidence: o.evidence, seenAt: o.seenAt, gtin: o.gtin, notes: notes.get(o.id),
    }];
  });

  type OutPick = ShoppingResult["picks"][number];
  const shoppingPicks = picks.flatMap((p): OutPick[] => {
    // A pick whose reason was all dropped keeps its offer, with the role's label as the reason.
    const why = line(p.why) ?? pick(ROLE_LABEL[p.role], lang);
    return [{ role: p.role, offerId: p.offer.id, why, tradeoff: line(p.tradeoff), overBudget: over(p.offer) }];
  });

  const notConfirmed = unconfirmedLine(registry.list().filter((o) => !isConfirmed(o)), lang);
  const shopping: ShoppingResult = {
    priorities: content.priorities,
    budget,
    offers,
    picks: shoppingPicks,
    howChosen: lines(card.howChosen, SHOPPING_LIMITS.howChosen),
    watchOuts: lines(card.watchOuts, SHOPPING_LIMITS.watchOuts),
    // The code's own line about unconfirmed offers comes first, so the cap never cuts it.
    unknowns: [...(notConfirmed ? [notConfirmed] : []), ...lines(card.unknowns, SHOPPING_LIMITS.unknowns)].slice(0, SHOPPING_LIMITS.unknowns),
    rejected: lines(card.rejected, SHOPPING_LIMITS.rejected),
    stats: { offersSeen: Math.max(registry.seen, registry.size), shops: registry.shopCount },
  };

  // The research card's fields, written by the code from the picks.
  const fmt = (m: Money) => formatMoney(m, lang);
  const bestPick = shoppingPicks[0];
  const answer = shorten(
    (lang === "pl"
      ? `Mój wybór: ${best.offer.title}, ${fmt(best.offer.price)} w ${best.offer.shop}.`
      : `My pick: ${best.offer.title}, ${fmt(best.offer.price)} at ${best.offer.shop}.`)
      + (bestPick && bestPick.why !== pick(ROLE_LABEL.best, lang) ? ` ${bestPick.why}` : ""),
    LIMITS.answer);
  const items = shoppingPicks.flatMap((p) => {
    const o = registry.get(p.offerId);
    if (!o) return [];
    const parts = [pick(ROLE_LABEL[p.role], lang), p.why !== pick(ROLE_LABEL[p.role], lang) ? p.why : undefined,
      p.overBudget ? (lang === "pl" ? `${fmt(p.overBudget)} ponad budżet` : `${fmt(p.overBudget)} over budget`) : undefined,
      pick(EVIDENCE_LABEL[o.evidence], lang)].filter((x): x is string => !!x);
    return [{ title: shorten(o.title, LIMITS.itemTitle), detail: shorten(parts.join(" · "), LIMITS.detail), price: shorten(fmt(o.price), LIMITS.price), url: o.url, site: o.site }];
  });
  const sources: ErrandResult["sources"] = [];
  for (const o of offers) {
    if (sources.length >= LIMITS.sources || sources.some((s) => s.url === o.url)) continue;
    sources.push({ title: shorten(o.title, LIMITS.sourceTitle), url: o.url, site: o.site });
  }
  const draft = {
    answer,
    sections: [{ heading: lang === "pl" ? "Propozycje" : "Picks", kind: "options" as const, items }],
    recommendation: line(card.recommendation, LIMITS.recommendation),
    budget: budget
      ? { asked: lang === "pl" ? `do ${fmt(budget)}` : `up to ${fmt(budget)}`, within: (over(best.offer) ? "no" : "yes") as "yes" | "no" }
      : undefined,
    next: card.next.flatMap((n) => line(n, LIMITS.nextLine) ?? []).slice(0, LIMITS.next),
    sources,
    checkedAt: now.toISOString(),
    shopping,
  };
  const parsed = ErrandResultSchema.safeParse(JSON.parse(JSON.stringify(draft)));
  return parsed.success ? { result: parsed.data, stats } : undefined;
}
