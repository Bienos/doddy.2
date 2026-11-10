import type { DeckImage, WikiArticle, Wikimedia } from "./research.js";
import type { DeckLanguage } from "./spec.js";

/**
 * Mock mode and tests (decision 2026-11-10-better-presentations): offline research and Claude's two
 * deck steps answered with fixed demo content, so the whole pipeline (research, checks, layout, file)
 * runs without a network or a key and makes a real .pptx. Every word says DEMO. Never used in live mode.
 */

export const DECK_PLAN_STEP = "doddy_deck_plan";
export const DECK_WRITE_STEP = "doddy_deck";

export const DEMO_ARTICLE_TEXT = [
  "DEMO. Demo Town is a town on the shore of Lake Demo, which is 27.45 km long.",
  "## History",
  "The town was founded in 1305. It received a railway station in 1872 and was rebuilt after 1945.",
  "## Population",
  "In 2002 the town had 33 245 inhabitants, in 2011 it had 32 491 and in 2021 it had 31 808.",
  "## Today",
  "Sailing on Lake Demo and the old town draw visitors every summer.",
].join("\n");

/** Offline Wikipedia: every phrase finds the same demo article; no pictures (a picture is never made up). */
export class MockWikimedia implements Wikimedia {
  readonly mode = "mock" as const;
  readonly asked: string[] = [];

  async article(language: DeckLanguage, phrase: string): Promise<WikiArticle | null> {
    this.asked.push(`${language}:${phrase}`);
    return { title: `DEMO ${phrase}`.slice(0, 120), url: `https://${language}.wikipedia.org/wiki/Demo_Town`, site: `${language}.wikipedia.org`, text: DEMO_ARTICLE_TEXT, imageFile: null };
  }

  async image(): Promise<Omit<DeckImage, "id"> | null> {
    return null;
  }
}

export function demoDeckPlan(user: string): unknown {
  const title = /^Title: (.*)$/m.exec(user)?.[1]?.trim() || "Demo";
  return { language: "en", wikipedia: [title.slice(0, 100)], web: [] };
}

/** A demo outline that cites the demo article when the request carries it, else only general slides. */
export function demoDeck(user: string): unknown {
  const sourced = user.includes('<source id="s1"');
  const cite = sourced ? ["s1"] : [];
  const notes = "DEMO speaker notes.";
  const slides: unknown[] = [
    { layout: "bullets", title: "DEMO: why it matters", points: ["A lake town", "Old streets", "Summer sailing"], sources: cite, notes },
    { layout: "two_column", title: "DEMO: then and now", left: { heading: "Then", points: ["A market town"] }, right: { heading: "Now", points: ["A holiday town"] }, sources: cite, notes },
  ];
  if (sourced) {
    slides.push(
      { layout: "stats", title: "DEMO: the lake", items: [{ value: "27.45 km", label: "Length of Lake Demo" }], context: "DEMO context.", sources: cite, notes },
      { layout: "timeline", title: "DEMO: history", events: [{ when: "1305", what: "Founded" }, { when: "1872", what: "Railway station" }, { when: "1945", what: "Rebuilt" }], sources: cite, notes },
      { layout: "chart", title: "DEMO: population", unit: "inhabitants", points: [{ label: "2002", value: 33245 }, { label: "2011", value: 32491 }, { label: "2021", value: 31808 }], note: "", sources: cite, notes },
      { layout: "comparison", title: "DEMO: compare", row_header: "", columns: ["2011", "2021"], rows: [{ label: "People", cells: ["32 491", "31 808"] }, { label: "Lake", cells: ["27.45 km", "27.45 km"] }], sources: cite, notes },
    );
  } else {
    slides.push(
      { layout: "bullets", title: "DEMO: plan", points: ["First step", "Second step"], sources: [], notes },
      { layout: "bullets", title: "DEMO: next", points: ["Ask", "Decide"], sources: [], notes },
      { layout: "bullets", title: "DEMO: end", points: ["Thanks", "Questions"], sources: [], notes },
    );
  }
  return {
    language: "en",
    title: "DEMO deck",
    subtitle: "Made offline in demo mode",
    labels: { agenda: "Agenda", summary: "Summary", sources: "Sources", source: "Source", material: "From our conversation" },
    cover_notes: notes,
    slides,
    takeaways: ["DEMO takeaway one", "DEMO takeaway two", "DEMO takeaway three"],
    summary_notes: notes,
  };
}
