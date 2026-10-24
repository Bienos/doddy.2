#!/usr/bin/env node
// Judge Polish leaflet reading on about 50 real pages (SHOPPING.md section 2, ADR-609, ADR-611).
// It finds this week's leaflet of one chain, sends up to N of its pages through the service's own page reader
// (the polite fetcher, prepareImage, readPage, Claude Haiku 5.5) and writes ONE Markdown review sheet and ONE
// JSON file, so the owner can open a page and tick what the reader got right. It uses the BUILT code in dist/.
//
//   cd server/messaging && npm ci && npm run build                  # first, once
//   export ANTHROPIC_API_KEY=...                                    # read from here and nowhere else
//   node scripts/leaflet-eval.mjs --dry-run                         # no key needed: the pages it would read, worst-case cost
//   node scripts/leaflet-eval.mjs                                   # Biedronka, 50 pages, masło / mleko / kawa
//   node scripts/leaflet-eval.mjs --chain lidl --max-pages 30 --items "masło,mleko,kawa" --out ~/leaflet-review
//   (options: --chain biedronka|lidl|dino|rossmann, --max-pages 1..60, --items "a,b,c", --out DIR, --dry-run)
//
// Cost: Claude Haiku 5.5 at $0.10 per million input and $0.50 per million output tokens (up to 100K-token
// prompts). A page is about 4,800 image tokens plus the instructions, and the reply is usually a few hundred
// tokens, so 50 pages should be around five cents: an estimate, not a measurement (nobody had run this with a
// key when it was written). --dry-run prints the worst case, about 23 cents for 50 pages. The report shows what
// the reader really used.
//
// Never: saves a page image (only page addresses), writes inside the repository, takes the key as an argument
// or prints it, reads more than --max-pages (hard cap 60), goes around a block (a chain that blocks is reported
// as blocked; robots.txt and the chain's own signals are obeyed by the same fetcher the service uses), or keeps
// anything but the two files. The files hold facts read from a leaflet for the owner's review: delete them
// afterwards (the product keeps no leaflet data).
//
// How it differs from the service: the service reads only the pages that could hold the person's items (Lidl:
// pages whose text names them; Dino: pages with a matching product). This reads the first N pages in leaflet
// order, because it is meant to judge the reader, not the choice of pages. Rossmann publishes product data and
// no page images, so there is nothing for the reader to judge there. The items are sent to the model (and, for
// Rossmann only, to rossmann.pl as a search term), exactly as in the service.
//
// Exit codes: 0 done; 1 no page could be read (blocked, no leaflet, ...); 2 not started (bad options, no key,
// not built, --out inside the repository).

import { mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** server/messaging/scripts is three levels below the repository root. */
export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");

export const CHAINS = ["biedronka", "lidl", "dino", "rossmann"];
export const DEFAULT_CHAIN = "biedronka";
export const DEFAULT_MAX_PAGES = 50;
export const HARD_MAX_PAGES = 60;
export const DEFAULT_ITEMS = ["masło", "mleko", "kawa"];
/** The service's own limits on a request's items. */
export const MAX_ITEMS = 12;
export const MAX_ITEM_LENGTH = 60;
export const DEFAULT_MODEL = "claude-haiku-5-5";
/** Same pattern as DEALS_VISION_MODEL in config.ts. */
const MODEL_PATTERN = /^[a-z0-9][a-z0-9.-]{1,63}$/;

/** Claude Haiku 5.5's published price, per million tokens, for prompts up to 100K tokens. */
export const PRICE = { model: "claude-haiku-5-5", inputPerMillionUsd: 0.1, outputPerMillionUsd: 0.5, promptTokensUpTo: 100_000 };
/** What a page can cost at most: the API's image budget (the real constant is read from vision.js when the
 * code is loaded), an allowance for the instructions, the output schema and the item list, and the reader's
 * own max_tokens (8,000, set in vision.ts). */
export const WORST_CASE = { imageTokens: 4784, overheadTokens: 2000, maxOutputTokens: 8000 };

/** Pages read at once. The service reads 10 at once per chain; a review run is gentler. */
const READ_CONCURRENCY = 4;
/** The same Accept the service sends for page images (service.ts). */
const IMAGE_ACCEPT = "image/avif;q=0,image/webp,image/png,image/jpeg,image/*;q=0.8";

export const NOTICE = "This file holds facts read from a chain's leaflet (product names, prices, conditions, dates) for the owner's quality review only. "
  + "It contains no page images. Delete it afterwards: the product keeps no leaflet data (ADR-609).";

const USAGE = `Usage: node scripts/leaflet-eval.mjs [options]
  --chain biedronka|lidl|dino|rossmann   the chain whose leaflet to read (default ${DEFAULT_CHAIN})
  --max-pages N                          pages to read, 1 to ${HARD_MAX_PAGES} (default ${DEFAULT_MAX_PAGES}; ${HARD_MAX_PAGES} is the hard cap)
  --items "masło,mleko,kawa"             the items to look for, 1 to ${MAX_ITEMS} (default: ${DEFAULT_ITEMS.join(",")})
  --out DIR                              where the two files go (default: a new folder under the system temp directory;
                                         never inside the repository)
  --dry-run                              find the leaflet and list the pages; no model call, no key needed, nothing written
  -h, --help
Needs ANTHROPIC_API_KEY in the environment (not for --dry-run). The model is DEALS_VISION_MODEL (default ${DEFAULT_MODEL}).
Run \`npm run build\` in server/messaging first: this uses the built code in dist/.`;

// ---------- options ----------

const VALUE_OPTIONS = ["--chain", "--max-pages", "--items", "--out"];

/** "masło, mleko ,kawa" → ["masło", "mleko", "kawa"], or why not. Same limits as a request to the service. */
function parseItems(text) {
  const items = [];
  const seen = new Set();
  for (const raw of text.split(",")) {
    const item = raw.replace(/\s+/g, " ").trim();
    if (!item) continue;
    if (item.length > MAX_ITEM_LENGTH) return { error: `Each item is at most ${MAX_ITEM_LENGTH} characters.` };
    if (/[\u0000-\u001f\u007f]/.test(item)) return { error: "Items are plain words, without control characters." };
    const key = item.toLocaleLowerCase("pl");
    if (seen.has(key)) continue;
    seen.add(key);
    items.push(item);
  }
  if (items.length === 0 || items.length > MAX_ITEMS) return { error: `--items takes 1 to ${MAX_ITEMS} items, separated by commas.` };
  return { items };
}

/** The command line as options, or the reason it is refused. Nothing from an unknown argument is echoed (it
 * could be a key). Pure. */
export function parseArgs(argv) {
  const options = { chain: DEFAULT_CHAIN, maxPages: DEFAULT_MAX_PAGES, items: [...DEFAULT_ITEMS], out: undefined, dryRun: false, help: false };
  const fail = (error) => ({ ok: false, error });
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("-")) return fail("Unexpected argument: options start with --.");
    const eq = arg.indexOf("=");
    const name = eq > 0 ? arg.slice(0, eq) : arg;
    const inline = eq > 0 ? arg.slice(eq + 1) : undefined;
    if (name === "-h" || name === "--help") { options.help = true; continue; }
    if (name === "--dry-run") {
      if (inline !== undefined) return fail("--dry-run takes no value.");
      options.dryRun = true;
      continue;
    }
    if (!VALUE_OPTIONS.includes(name)) return fail(/^--[a-z-]{1,24}$/.test(name) ? `Unknown option ${name}.` : "Unknown option.");
    const value = inline ?? argv[++i];
    if (value === undefined || (inline === undefined && value.startsWith("--"))) return fail(`${name} needs a value.`);
    if (name === "--chain") {
      if (!CHAINS.includes(value)) return fail(`--chain is one of: ${CHAINS.join(", ")}.`);
      options.chain = value;
    } else if (name === "--max-pages") {
      const n = /^\d{1,4}$/.test(value) ? Number(value) : NaN;
      if (!(n >= 1 && n <= HARD_MAX_PAGES)) return fail(`--max-pages is a whole number from 1 to ${HARD_MAX_PAGES} (the hard cap; the default is ${DEFAULT_MAX_PAGES}).`);
      options.maxPages = n;
    } else if (name === "--items") {
      const parsed = parseItems(value);
      if (parsed.error) return fail(parsed.error);
      options.items = parsed.items;
    } else {
      if (!value.trim()) return fail("--out needs a folder.");
      options.out = value;
    }
  }
  return { ok: true, options };
}

/** ANTHROPIC_API_KEY from the environment. Not needed (and not looked at) for a dry run. */
export function checkKey(env, dryRun) {
  if (dryRun) return { ok: true };
  const key = (env.ANTHROPIC_API_KEY ?? "").trim();
  if (key) return { ok: true, key };
  return {
    ok: false,
    error: "ANTHROPIC_API_KEY is not set. Export it in this shell (for example: export ANTHROPIC_API_KEY=...) and run again, "
      + "or add --dry-run to rehearse without it. Nothing was fetched or sent.",
  };
}

const stampOf = (date) => date.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");

function isInside(child, parent) {
  const rel = path.relative(parent, child);
  return rel === "" || (rel !== ".." && !rel.startsWith(".." + path.sep) && !path.isAbsolute(rel));
}

/** The real path of `p`, or of its nearest existing parent with the rest added (so a symlink can't hide a place). */
function realPathWithMissingTail(p) {
  const tail = [];
  let current = path.resolve(p);
  for (;;) {
    try { return path.join(realpathSync(current), ...tail.reverse()); } catch {
      const parent = path.dirname(current);
      if (parent === current) return path.resolve(p);
      tail.push(path.basename(current));
      current = parent;
    }
  }
}

/** Where the two files go: `out`, or a new folder under the temp directory. Never inside the repository. */
export function resolveOutDir(out, { tmp = tmpdir(), repoRoot = REPO_ROOT, now = new Date() } = {}) {
  const dir = path.resolve(out ?? path.join(tmp, `doddy-leaflet-eval-${stampOf(now)}`));
  if (isInside(realPathWithMissingTail(dir), realPathWithMissingTail(repoRoot))) {
    return {
      ok: false,
      error: "The folder for the review files is inside the repository. The files hold facts read from a leaflet and must not be committed. "
        + "Use --out with a folder outside it (for example under /tmp or your home folder).",
    };
  }
  return { ok: true, dir };
}

// ---------- cost ----------

/** What the tokens cost at Haiku 5.5's published prices, in US dollars. */
export function estimateCost({ inputTokens, outputTokens }) {
  return (inputTokens * PRICE.inputPerMillionUsd + outputTokens * PRICE.outputPerMillionUsd) / 1_000_000;
}

/** The most `pages` pages can cost: every page at the full image budget and the full reply limit. */
export function worstCaseCost(pages, limits = WORST_CASE) {
  return estimateCost({
    inputTokens: pages * (limits.imageTokens + limits.overheadTokens),
    outputTokens: pages * limits.maxOutputTokens,
  });
}

export const formatUsd = (n) => `$${n.toFixed(n < 0.1 ? 4 : 2)}`;

function formatDuration(ms) {
  const s = Math.round(ms / 1000);
  return s < 60 ? `${(ms / 1000).toFixed(1)} s` : `${Math.floor(s / 60)} min ${s % 60} s`;
}

// ---------- the sheet ----------
//
// A result (what evaluate() returns and the writers take):
//   { notice, startedAt, chain, items, model, maxPages, status, reason?, incomplete?,
//     leaflets: [{ title?, url, validFrom?, validTo?, strategy, pagesAvailable }],
//     pages: [{ leaflet, number, url, imageUrl, status, reason?, products: [product] }],
//     totals: { pagesPlanned, pagesSent, pagesRead, pagesNotRead, byStatus, products, flagged, inputTokens,
//               outputTokens, estimatedCostUsd, worstCaseCostUsd?, elapsedMs },
//     pricing: { model, inputPerMillionUsd, outputPerMillionUsd, promptTokensUpTo, appliesToRunModel } }
// A product: { name, size, price, regularPrice, lowest30d, printedUnitPrice, conditions, validFrom, validTo,
//              unitPrice, check, doubts, matchedItems }. Money is { minor, currency }; unitPrice is the code's.

const money = (m) => (m ? `${(m.minor / 100).toFixed(2).replace(".", ",")} zł` : "-");
const unit = (u) => (u ? `${(u.minor / 100).toFixed(2).replace(".", ",")} zł/${u.per}` : "-");
/** Text from a page or the model, made safe for one table cell. */
const cell = (v) => {
  const t = String(v ?? "").replace(/\s+/g, " ").trim();
  return t ? t.replace(/\\/g, "\\\\").replace(/\|/g, "\\|").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/`/g, "'") : "-";
};
const mono = (v) => `\`${String(v ?? "").replace(/`/g, "'")}\``;
const countsText = (byStatus) => Object.entries(byStatus ?? {}).map(([k, n]) => `${n} ${k}`).join(", ");

/** The review sheet. It starts with the notice. Pure. */
export function renderMarkdown(result) {
  const t = result.totals;
  const lines = [
    `> **Notice:** ${result.notice ?? NOTICE}`,
    "",
    `# Leaflet reading review: ${result.chain}`,
    "",
    `- Run: ${result.startedAt}, took ${formatDuration(t.elapsedMs)}.`,
    `- Result: **${result.status}**${result.reason ? ` (${cell(result.reason)})` : ""}${result.incomplete ? `; the chain's own listing was incomplete (${cell(result.incomplete)})` : ""}.`,
    `- Items looked for: ${result.items.map(cell).join(", ")}.`,
    `- Reader model: ${result.model}.`,
  ];
  for (const [i, l] of result.leaflets.entries()) {
    lines.push(`- Leaflet ${result.leaflets.length > 1 ? `${i + 1}: ` : ""}${cell(l.title ?? "(no title)")}, ${l.validFrom ?? "?"} to ${l.validTo ?? "?"}, ${l.pagesAvailable} pages, ${mono(l.url)}.`);
  }
  lines.push(
    `- Pages: ${t.pagesPlanned} planned (at most ${result.maxPages}), ${t.pagesRead} read${t.pagesNotRead ? `, ${t.pagesNotRead} not read (${countsText(t.byStatus)})` : ""}.`,
    `- Products returned: ${t.products}, ${t.flagged} of them with the \`check\` flag.`,
    `- Tokens used: ${t.inputTokens.toLocaleString("en-US")} in, ${t.outputTokens.toLocaleString("en-US")} out. Estimated cost: ${formatUsd(t.estimatedCostUsd)}`
      + ` at ${PRICE.model}'s published prices ($${PRICE.inputPerMillionUsd.toFixed(2)} / $${PRICE.outputPerMillionUsd.toFixed(2)} per million tokens, prompts up to ${PRICE.promptTokensUpTo.toLocaleString("en-US")} tokens)`
      + `${result.pricing?.appliesToRunModel === false ? `; the run used ${result.model}, so treat this as a rough figure` : ""}.`,
    "",
    "## How to judge",
    "",
    "Open each page address, find the products that fit the items, and compare with the table. Put an x in `Right?` when every field of a row matches the page;",
    "write what is wrong or missing under the table. `Computed unit` is the code's own price per kg, l or piece (from price and size); `Check` is the flag the app would show.",
    "`Matches` is the items the service's matcher would pair the product with (none means the service would drop it).",
    "",
  );
  for (const p of result.pages) {
    lines.push(`## Page ${p.number}${result.leaflets.length > 1 ? ` (leaflet ${p.leaflet + 1})` : ""}`, "", `Address: ${mono(p.url)}; page image address: ${mono(p.imageUrl)}`, "");
    if (p.status !== "read") {
      lines.push(`Not read: ${p.status}${p.reason ? ` (${cell(p.reason)})` : ""}.`, "");
      continue;
    }
    if (p.products.length === 0) {
      lines.push("The reader returned no products for this page.", "", "Missed on this page: ________", "");
      continue;
    }
    lines.push(
      "| # | Product | Size | Price | Regular | 30-day low | Printed unit | Computed unit | Conditions | Dates | Check | Matches | Right? |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    );
    for (const [i, x] of p.products.entries()) {
      const dates = x.validFrom || x.validTo ? `${x.validFrom ?? "?"}-${x.validTo ?? "?"}` : "-";
      const check = x.check ? `CHECK${x.doubts?.length ? ` (${x.doubts.join(", ")})` : ""}` : "-";
      lines.push(`| ${i + 1} | ${cell(x.name)} | ${cell(x.size)} | ${money(x.price)} | ${money(x.regularPrice)} | ${money(x.lowest30d)} | ${cell(x.printedUnitPrice)} | ${unit(x.unitPrice)} | ${cell(x.conditions?.join("; "))} | ${dates} | ${cell(check)} | ${cell(x.matchedItems?.join(", ") || "none")} | [ ] |`);
    }
    lines.push("", "Missed on this page: ________", "");
  }
  return lines.join("\n");
}

/** The same facts as JSON. The notice is the first key. Pure. */
export const renderJson = (result) => JSON.stringify({ notice: NOTICE, ...result }, null, 2) + "\n";

/** Writes the two files (never over an existing one), and refuses a folder inside the repository. */
export function writeReport(dir, result, { repoRoot = REPO_ROOT } = {}) {
  if (isInside(realPathWithMissingTail(dir), realPathWithMissingTail(repoRoot))) {
    throw new Error("refusing to write the review files inside the repository");
  }
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const base = path.join(dir, `leaflet-eval-${result.chain}-${stampOf(new Date(result.startedAt))}`);
  const files = { json: `${base}.json`, markdown: `${base}.md` };
  writeFileSync(files.json, renderJson(result), { flag: "wx", mode: 0o600 });
  writeFileSync(files.markdown, renderMarkdown(result), { flag: "wx", mode: 0o600 });
  return files;
}

// ---------- the run ----------

/** The built service code (dist/), loaded when needed so that the pure parts above work without a build. */
export async function loadDealsModules() {
  const [service, vision, fetcher, match, common] = await Promise.all([
    import("../dist/src/deals/service.js"),
    import("../dist/src/deals/vision.js"),
    import("../dist/src/deals/fetcher.js"),
    import("../dist/src/deals/match.js"),
    import("../dist/src/deals/chains/common.js"),
  ]);
  return {
    ADAPTERS: service.ADAPTERS, buildOffer: service.buildOffer,
    readPage: vision.readPage, prepareImage: vision.prepareImage, AnthropicDealsModel: vision.AnthropicDealsModel,
    IMAGE_MAX_VISUAL_TOKENS: vision.IMAGE_MAX_VISUAL_TOKENS,
    PoliteFetcher: fetcher.PoliteFetcher,
    terms: match.terms, matchScore: match.matchScore, MATCH_THRESHOLD: match.MATCH_THRESHOLD,
    mapLimit: common.mapLimit, warsawDay: common.warsawDay,
  };
}

const dateText = (d) => (d ? `${String(d.day).padStart(2, "0")}.${String(d.month).padStart(2, "0")}${d.year ? `.${d.year}` : ""}` : null);
/** An error as a short code. The message is never kept: it could hold anything the API echoed. */
const errorCode = (e) => (typeof e?.status === "number" ? `api_${e.status}` : String(e?.name ?? "error").slice(0, 40));

/** Finds the leaflet, reads up to `maxPages` pages and returns a result (see above). With no `model` it is a
 * dry run: the pages are listed and nothing is downloaded or sent.
 * deps: { modules, fetcher, model?, now?, signal? } */
export async function evaluate(options, deps) {
  const { modules: m, fetcher, model } = deps;
  const now = deps.now ?? (() => new Date());
  const startedAt = now();
  const dryRun = !model;
  const maxPages = Math.min(options.maxPages, HARD_MAX_PAGES);
  // Stopped by the caller's signal, or here when the key is refused (no point asking 50 times).
  const stop = new AbortController();
  deps.signal?.addEventListener("abort", () => stop.abort());
  if (deps.signal?.aborted) stop.abort();
  const signal = stop.signal;

  const result = {
    notice: NOTICE, startedAt: startedAt.toISOString(), chain: options.chain, items: options.items,
    model: options.model ?? DEFAULT_MODEL, maxPages, status: "failed", leaflets: [], pages: [],
    totals: {
      pagesPlanned: 0, pagesSent: 0, pagesRead: 0, pagesNotRead: 0, byStatus: {}, products: 0, flagged: 0,
      inputTokens: 0, outputTokens: 0, estimatedCostUsd: 0, elapsedMs: 0,
    },
    pricing: { ...PRICE, appliesToRunModel: (options.model ?? DEFAULT_MODEL) === PRICE.model },
  };
  const t = result.totals;
  const finish = (status, reason) => {
    result.status = status;
    if (reason) result.reason = reason;
    t.estimatedCostUsd = estimateCost(t);
    t.elapsedMs = now().getTime() - startedAt.getTime();
    return result;
  };

  // This week's leaflet, from the chain's official site, through the same adapter and fetcher as the service.
  let read;
  try {
    read = await m.ADAPTERS[options.chain].read({ fetcher, queries: options.items, today: m.warsawDay(startedAt), signal });
  } catch {
    return finish("failed", "adapter_error");
  }
  if (read.kind === "no_leaflet" || (read.kind === "ok" && read.leaflets.length === 0)) return finish("no_leaflet");
  if (read.kind !== "ok") return finish(read.kind, read.reason); // "blocked" or "failed": reported, never worked around
  if (read.incomplete) result.incomplete = read.incomplete;

  const planned = [];
  const seen = new Set();
  for (const [li, l] of read.leaflets.entries()) {
    result.leaflets.push({
      ...(l.leaflet.title ? { title: l.leaflet.title } : {}), url: l.leaflet.url,
      ...(l.leaflet.validFrom ? { validFrom: l.leaflet.validFrom } : {}), ...(l.leaflet.validTo ? { validTo: l.leaflet.validTo } : {}),
      strategy: l.strategy, pagesAvailable: l.pages.length,
    });
    for (const page of [...l.pages].sort((a, b) => a.number - b.number)) {
      if (seen.has(page.imageUrl)) continue;
      seen.add(page.imageUrl);
      planned.push({ li, page });
    }
  }
  const chosen = planned.slice(0, maxPages);
  t.pagesPlanned = chosen.length;
  result.pages = chosen.map(({ li, page }) => ({
    leaflet: li, number: page.number, url: page.url, imageUrl: page.imageUrl, status: dryRun ? "planned" : "not_run", products: [],
  }));
  if (chosen.length === 0) return finish("no_pages", "the chain publishes no page images");
  if (dryRun) {
    t.worstCaseCostUsd = worstCaseCost(chosen.length, { ...WORST_CASE, imageTokens: m.IMAGE_MAX_VISUAL_TOKENS ?? WORST_CASE.imageTokens });
    return finish("dry_run");
  }

  const describe = ({ page }, p) => {
    const { offer, doubts } = m.buildOffer({
      chain: options.chain, name: p.name, price: p.price, sizeText: p.sizeText, regularPrice: p.regularPrice, lowest30d: p.lowest30d,
      printedUnitPrice: p.printedUnitPrice, conditions: p.conditions, source: { url: page.url, page: page.number },
      readBy: "page_image", doubts: p.lowConfidence ? ["low_confidence_read"] : [],
    }, "pl");
    return {
      name: p.name, size: p.sizeText ?? null, price: p.price, regularPrice: p.regularPrice ?? null, lowest30d: p.lowest30d ?? null,
      printedUnitPrice: p.printedUnitPrice ?? null, conditions: offer.conditions, validFrom: dateText(p.validFrom), validTo: dateText(p.validTo),
      unitPrice: offer.unitPrice ?? null, check: offer.check, doubts,
      matchedItems: options.items.filter((item) => m.matchScore(m.terms(item), m.terms(p.name)) >= m.MATCH_THRESHOLD),
    };
  };

  // The page image is fetched, handed to the reader and dropped: nothing here writes it anywhere.
  await m.mapLimit(chosen, READ_CONCURRENCY, async (job, index) => {
    const entry = result.pages[index];
    if (signal.aborted) return;
    const f = await fetcher.fetchPage(job.page.imageUrl, { accept: IMAGE_ACCEPT, aiInput: true, signal });
    if (f.kind !== "ok") { entry.status = f.kind; entry.reason = f.reason; return; }
    const image = m.prepareImage(f.body);
    if ("error" in image) { entry.status = image.error; return; }
    t.pagesSent++;
    try {
      const r = await m.readPage(model, image, { chain: options.chain, queries: options.items, signal });
      if (r.usage) { t.inputTokens += r.usage.inputTokens; t.outputTokens += r.usage.outputTokens; }
      entry.status = r.kind === "ok" ? "read" : r.kind;
      if (r.kind === "ok") entry.products = r.products.map((p) => describe(job, p));
    } catch (e) {
      entry.status = signal.aborted ? "not_run" : "error";
      if (!signal.aborted) entry.reason = errorCode(e);
      if (e?.status === 401 || e?.status === 403) { result.reason = "the API refused the key; stopped"; stop.abort(); }
    }
  });

  for (const p of result.pages) {
    if (p.status === "read") t.pagesRead++;
    else t.byStatus[p.status] = (t.byStatus[p.status] ?? 0) + 1;
    t.products += p.products.length;
    t.flagged += p.products.filter((x) => x.check).length;
  }
  t.pagesNotRead = t.pagesPlanned - t.pagesRead;
  if (t.pagesRead > 0) return finish("read", result.reason);
  const blocked = result.pages.some((p) => p.status === "blocked" || p.status === "disallowed");
  return finish(blocked ? "blocked" : "failed", result.reason ?? (blocked ? "the chain blocks or disallows its page images" : "no page could be read"));
}

const listPages = (result) => result.pages.map((p) => `  page ${String(p.number).padStart(3)}  ${p.imageUrl}`);

/** Everything from the command line to the exit code. `io` replaces the environment, the output, the web and the
 * model in tests: { env, stdout, stderr, tmp, repoRoot, modules, fetcher, model, now, signal }. */
export async function main(argv, io = {}) {
  const env = io.env ?? process.env;
  const out = io.stdout ?? ((s) => process.stdout.write(s));
  const err = io.stderr ?? ((s) => process.stderr.write(s));
  const now = io.now ?? (() => new Date());

  const parsed = parseArgs(argv);
  if (!parsed.ok) { err(`${parsed.error}\n\n${USAGE}\n`); return 2; }
  const options = parsed.options;
  if (options.help) { out(USAGE + "\n"); return 0; }

  const key = checkKey(env, options.dryRun);
  if (!key.ok) { err(key.error + "\n"); return 2; }
  const model = (env.DEALS_VISION_MODEL ?? "").trim() || DEFAULT_MODEL;
  if (!MODEL_PATTERN.test(model)) { err("DEALS_VISION_MODEL is not a model id (lowercase letters, digits, dots and dashes).\n"); return 2; }
  const folder = resolveOutDir(options.out, { tmp: io.tmp, repoRoot: io.repoRoot, now: now() });
  if (!folder.ok) { err(folder.error + "\n"); return 2; }

  let modules;
  try { modules = io.modules ?? await loadDealsModules(); } catch (e) {
    err(`The built code could not be loaded (${String(e?.code ?? e?.name ?? "error").slice(0, 40)}). Run \`npm ci\` and \`npm run build\` in server/messaging first.\n`);
    return 2;
  }
  const fetcher = io.fetcher ?? new modules.PoliteFetcher();
  const reader = options.dryRun ? undefined : (io.model ?? new modules.AnthropicDealsModel(key.key, { model }));

  // Ctrl-C stops starting new pages; what was read so far is still written.
  const interrupt = new AbortController();
  const onSigint = () => interrupt.abort();
  if (!io.signal) process.once("SIGINT", onSigint);
  const signal = io.signal ?? interrupt.signal;
  let result;
  try {
    result = await evaluate({ ...options, model }, { modules, fetcher, model: reader, now, signal });
  } finally {
    process.removeListener("SIGINT", onSigint);
  }

  if (options.chain === "rossmann") out("Note: for Rossmann the item words are sent to rossmann.pl as a search term, as the service does.\n");
  if (options.dryRun) {
    out(`Dry run: the chain's own site was asked for this week's leaflet (robots.txt obeyed); nothing was sent to a model, no page image was downloaded, nothing was written.\n`);
    out(`Chain: ${result.chain}. Result: ${result.status}${result.reason ? ` (${result.reason})` : ""}.\n`);
    for (const [i, l] of result.leaflets.entries()) out(`Leaflet ${i + 1}: ${l.title ?? "(no title)"}, ${l.validFrom ?? "?"} to ${l.validTo ?? "?"}, ${l.pagesAvailable} pages (page choice in the service: ${l.strategy}).\n`);
    if (result.status === "dry_run") {
      out(`Items: ${result.items.join(", ")}\n`);
      out(`Would read ${result.totals.pagesPlanned} pages (at most ${result.maxPages}), in leaflet order:\n${listPages(result).join("\n")}\n`);
      out(`Worst case: ${formatUsd(result.totals.worstCaseCostUsd)} for these pages, every page at the full image budget and the full reply limit, at ${PRICE.model}'s prices ($${PRICE.inputPerMillionUsd.toFixed(2)} / $${PRICE.outputPerMillionUsd.toFixed(2)} per million tokens). A real run costs far less.\n`);
      if (!result.pricing.appliesToRunModel) out(`Note: DEALS_VISION_MODEL is ${model}; those prices are ${PRICE.model}'s.\n`);
    }
    return result.status === "dry_run" ? 0 : 1;
  }

  const files = writeReport(folder.dir, result, { repoRoot: io.repoRoot });
  const t = result.totals;
  out(`${result.chain}: ${result.status}${result.reason ? ` (${result.reason})` : ""}. Pages read ${t.pagesRead} of ${t.pagesPlanned}${t.pagesNotRead ? ` (not read: ${countsText(t.byStatus)})` : ""}; ${t.products} products, ${t.flagged} flagged.\n`);
  out(`Tokens: ${t.inputTokens} in, ${t.outputTokens} out. Estimated cost ${formatUsd(t.estimatedCostUsd)}. Took ${formatDuration(t.elapsedMs)}.\n`);
  out(`Review sheet: ${files.markdown}\nJSON:         ${files.json}\nThey hold facts read from a leaflet for your review only: delete them afterwards.\n`);
  return result.status === "read" ? 0 : 1;
}

/** True when this file was started from the command line, not imported (by a test). */
function startedFromCommandLine() {
  try { return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; }
}
if (startedFromCommandLine()) process.exitCode = await main(process.argv.slice(2));
