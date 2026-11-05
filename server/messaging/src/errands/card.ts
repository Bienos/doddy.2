// The rules the code enforces on the result card, not only the prompt (ERRANDS.md):
//   - every link comes from the run: a url is kept only if a search result or a fetched page in this
//     run had exactly that url (after trimming);
//   - no price without its page: an item without a kept url loses its price, and its detail says so;
//   - lengths and counts are clamped to the contract, and checkedAt is the server's clock.
import { shorten } from "../news/writer.js";
import { ErrandResultSchema, LIMITS, type CardOutput, type ErrandResult } from "./schema.js";

/** "Price not confirmed" in the errand's language (Polish for pl, English otherwise). */
export function unconfirmedPriceNote(language: string): string {
  return language === "pl" ? "Cena niepotwierdzona: brak strony źródłowej." : "Price not confirmed: no source page.";
}

function clean(value: string | null | undefined, max: number): string | undefined {
  if (typeof value !== "string") return undefined;
  const t = value.trim();
  return t ? shorten(t, max) : undefined;
}

/** The site name shown next to a link: the url's host without "www.". */
export function siteOf(url: string): string | undefined {
  try {
    const host = new URL(url).hostname.replace(/^www\./, "");
    return host ? shorten(host, LIMITS.site) : undefined;
  } catch {
    return undefined;
  }
}

export interface CardStats { droppedUrls: number; strippedPrices: number }

/**
 * Builds the stored card from what the writer returned. `seen` holds every url the run's search
 * results and fetched pages had (trimmed). Returns undefined when nothing usable is left.
 */
export function buildResult(card: CardOutput, seen: ReadonlySet<string>, language: string, now: Date):
  { result: ErrandResult; stats: CardStats } | undefined {
  const stats: CardStats = { droppedUrls: 0, strippedPrices: 0 };
  const keepUrl = (u: string | null | undefined): string | undefined => {
    if (typeof u !== "string" || !u.trim()) return undefined;
    const t = u.trim();
    if (seen.has(t) && t.length <= LIMITS.url && /^https?:\/\/\S+$/.test(t)) return t;
    stats.droppedUrls++;
    return undefined;
  };
  const note = unconfirmedPriceNote(language);

  const sections = card.sections.flatMap((s) => {
    const heading = clean(s.heading, LIMITS.heading);
    const items = s.items.flatMap((i) => {
      const title = clean(i.title, LIMITS.itemTitle);
      if (!title) return [];
      const url = keepUrl(i.url);
      let price = clean(i.price, LIMITS.price);
      let detail = clean(i.detail, LIMITS.detail);
      if (price && !url) {
        price = undefined;
        stats.strippedPrices++;
        // The note always fits: the model's detail is shortened first.
        detail = detail ? `${shorten(detail, LIMITS.detail - note.length - 3)} · ${note}` : note;
      }
      return [{
        title, detail, when: clean(i.when, LIMITS.when), price, url,
        site: url ? siteOf(url) : clean(i.site, LIMITS.site),
      }];
    }).slice(0, LIMITS.items);
    return heading && items.length ? [{ heading, kind: s.kind, items }] : [];
  }).slice(0, LIMITS.sections);

  const sources: ErrandResult["sources"] = [];
  const used = new Set<string>();
  for (const s of card.sources) {
    const url = keepUrl(s.url);
    if (!url || used.has(url)) continue;
    used.add(url);
    sources.push({ title: clean(s.title, LIMITS.sourceTitle) ?? siteOf(url) ?? url.slice(0, LIMITS.sourceTitle), url, site: siteOf(url) });
    if (sources.length === LIMITS.sources) break;
  }

  const answer = clean(card.answer, LIMITS.answer);
  if (!answer) return undefined;
  const asked = card.budget ? clean(card.budget.asked, LIMITS.budgetAsked) : undefined;
  const draft = {
    answer,
    sections,
    recommendation: clean(card.recommendation, LIMITS.recommendation),
    budget: card.budget && asked ? { asked, within: card.budget.within } : undefined,
    next: card.next.flatMap((n) => clean(n, LIMITS.nextLine) ?? []).slice(0, LIMITS.next),
    sources,
    checkedAt: now.toISOString(),
  };
  // Drop undefined keys so the stored JSON has no nulls, then check the contract once more.
  const parsed = ErrandResultSchema.safeParse(JSON.parse(JSON.stringify(draft)));
  return parsed.success ? { result: parsed.data, stats } : undefined;
}
