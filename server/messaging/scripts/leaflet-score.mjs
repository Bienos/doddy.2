#!/usr/bin/env node
// Score a leaflet-reading run against pages labelled by hand (ADR-661; research:
// docs/research/2026-10-28/research_deals_better.md, section 4 #1). Pure: two JSON files in, numbers out; nothing
// is fetched or sent anywhere.
//
//   node scripts/leaflet-eval.mjs --chain biedronka --max-pages 30 --out ~/leaflet-review   # the run (needs a key)
//   node scripts/leaflet-score.mjs ~/leaflet-review/<run>.json ~/labels/biedronka-2026-10-29.json
//
// Labels (kept outside the repository, like the run: they hold facts from a leaflet for the owner's review only):
//   { "chain": "biedronka", "pages": [ { "number": 4, "offers": [ { "name": "Masło Extra 82%", "price": "4,99",
//       "regularPrice": "6,49", "lowest30d": null, "conditions": ["app", "limit"] } ], "prices": ["4,99", "6,49"] } ] }
// `prices` is every price printed on the page (optional): a read price that isn't among them is a hallucination.
// Only pages the run read and the labels cover are scored. A labelled offer counts as found when a read product on
// the same page matches its name (the service's own matcher, either way round).
//
// Measures: offers found; price exact (grosze); regular and 30-day price exact where labelled; condition kinds
// recall and precision; products with no labelled match; prices not printed on the page; and how often `check`
// was set on a found offer whose price was wrong.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** "4,99", "4.99", "4,99 zł", 499 (grosze as a number is not accepted: labels are written as printed). */
export function grosze(v) {
  if (v === null || v === undefined || v === "") return undefined;
  if (typeof v === "object" && Number.isInteger(v.minor)) return v.minor;
  const m = /^\s*(\d{1,4})(?:[.,](\d{2}))?\s*(?:zł|zl|pln)?\s*$/i.exec(String(v));
  return m ? Number(m[1]) * 100 + Number(m[2] ?? "0") : undefined;
}

const ratio = (n, d) => (d === 0 ? null : Math.round((n / d) * 1000) / 1000);

/** The scores for one run against its labels. `match(a, b)` says whether two product names are the same offer. */
export function score(run, labels, match) {
  const read = new Map((run.pages ?? []).filter((p) => p.status === "read").map((p) => [p.number, p]));
  const c = {
    pagesScored: 0, labelledOffers: 0, found: 0, priceExact: 0,
    regularLabelled: 0, regularExact: 0, lowestLabelled: 0, lowestExact: 0,
    conditionsLabelled: 0, conditionsRead: 0, conditionsRight: 0,
    readProducts: 0, unmatchedProducts: 0, pricesChecked: 0, pricesNotPrinted: 0, wrongPrices: 0, wrongPricesChecked: 0,
  };
  for (const lp of labels.pages ?? []) {
    const rp = read.get(lp.number);
    if (!rp) continue;
    c.pagesScored++;
    const products = rp.products ?? [];
    c.readProducts += products.length;
    const used = new Set();
    for (const lo of lp.offers ?? []) {
      c.labelledOffers++;
      const i = products.findIndex((p, j) => !used.has(j) && (match(lo.name, p.name) || match(p.name, lo.name)));
      if (i < 0) continue;
      used.add(i);
      const p = products[i];
      c.found++;
      const priceRight = grosze(p.price) === grosze(lo.price);
      if (priceRight) c.priceExact++;
      else { c.wrongPrices++; if (p.check) c.wrongPricesChecked++; }
      if (grosze(lo.regularPrice) !== undefined) { c.regularLabelled++; if (grosze(p.regularPrice) === grosze(lo.regularPrice)) c.regularExact++; }
      if (grosze(lo.lowest30d) !== undefined) { c.lowestLabelled++; if (grosze(p.lowest30d) === grosze(lo.lowest30d)) c.lowestExact++; }
      const want = new Set(lo.conditions ?? []);
      const got = new Set(p.conditionKinds ?? []);
      c.conditionsLabelled += want.size;
      c.conditionsRead += got.size;
      for (const k of got) if (want.has(k)) c.conditionsRight++;
    }
    c.unmatchedProducts += products.length - used.size;
    if (Array.isArray(lp.prices)) {
      const printed = new Set(lp.prices.map(grosze).filter((g) => g !== undefined));
      for (const p of products) {
        c.pricesChecked++;
        if (!printed.has(grosze(p.price))) c.pricesNotPrinted++;
      }
    }
  }
  return {
    counts: c,
    rates: {
      offersFound: ratio(c.found, c.labelledOffers),
      priceExact: ratio(c.priceExact, c.found),
      regularExact: ratio(c.regularExact, c.regularLabelled),
      lowest30dExact: ratio(c.lowestExact, c.lowestLabelled),
      conditionRecall: ratio(c.conditionsRight, c.conditionsLabelled),
      conditionPrecision: ratio(c.conditionsRight, c.conditionsRead),
      unmatchedProducts: ratio(c.unmatchedProducts, c.readProducts),
      pricesNotPrinted: ratio(c.pricesNotPrinted, c.pricesChecked),
      wrongPricesFlagged: ratio(c.wrongPricesChecked, c.wrongPrices),
    },
  };
}

const pct = (r) => (r === null ? "-" : `${Math.round(r * 1000) / 10}%`);

/** The scores as a short Markdown table. */
export function renderScore(result, run) {
  const { counts: c, rates: r } = result;
  return [
    `# Leaflet reading score: ${run.chain ?? "?"} (${run.startedAt ?? "?"})`,
    "",
    `${c.pagesScored} pages scored, ${c.labelledOffers} labelled offers, ${c.readProducts} products read.`,
    "",
    "| Measure | Value | Of |",
    "|---|---|---|",
    `| Offers found | ${pct(r.offersFound)} | ${c.labelledOffers} labelled |`,
    `| Price exact | ${pct(r.priceExact)} | ${c.found} found |`,
    `| Regular price exact | ${pct(r.regularExact)} | ${c.regularLabelled} labelled |`,
    `| 30-day price exact | ${pct(r.lowest30dExact)} | ${c.lowestLabelled} labelled |`,
    `| Condition recall | ${pct(r.conditionRecall)} | ${c.conditionsLabelled} labelled |`,
    `| Condition precision | ${pct(r.conditionPrecision)} | ${c.conditionsRead} read |`,
    `| Products with no labelled match | ${pct(r.unmatchedProducts)} | ${c.readProducts} read |`,
    `| Prices not printed on the page | ${pct(r.pricesNotPrinted)} | ${c.pricesChecked} checked |`,
    `| Wrong prices flagged \`check\` | ${pct(r.wrongPricesFlagged)} | ${c.wrongPrices} wrong |`,
    "",
  ].join("\n");
}

export async function main(argv, io = {}) {
  const out = io.stdout ?? ((t) => process.stdout.write(t));
  const err = io.stderr ?? ((t) => process.stderr.write(t));
  if (argv.length !== 2) { err("Usage: node scripts/leaflet-score.mjs RUN.json LABELS.json\n"); return 2; }
  let run, labels;
  try {
    run = JSON.parse(readFileSync(argv[0], "utf8"));
    labels = JSON.parse(readFileSync(argv[1], "utf8"));
  } catch (e) {
    err(`Couldn't read the files: ${String(e?.code ?? e?.name ?? "error")}\n`);
    return 2;
  }
  const match = io.match ?? (await loadMatcher());
  const result = score(run, labels, match);
  out(renderScore(result, run));
  out("\n" + JSON.stringify(result, null, 2) + "\n");
  return 0;
}

/** The service's own name matcher, from the built code. */
async function loadMatcher() {
  const m = await import("../dist/src/deals/match.js");
  return (a, b) => m.matchScore(m.terms(a), m.terms(b)) >= m.MATCH_THRESHOLD;
}

const self = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === self) {
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; });
}
