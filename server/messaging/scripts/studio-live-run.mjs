// First real run of Doddy Studio S0 against the live Anthropic API (STUDIO.md "First real run").
//   ANTHROPIC_API_KEY=… STUDIO_SKILLS=skill_…@skver_…,… node scripts/studio-live-run.mjs <pl|en|short> [--mix cheap|haiku|sonnet|opus] [outDir]
//   cheap (default): Haiku 5.5 plans, extracts claims and renders; Sonnet 5.5 researches and writes.
//   sonnet: Sonnet 5.5 for every step. opus: Opus 5.5 for every step (the dearest, for comparison only).
// Reads the key only from the environment and never prints or writes it. Needs the compiled server
// (npm run build). No database. The recording, cost and file writing is src/studio/liveRun.ts (tested
// against a fake Claude); this script only builds the real client and prints the summary.
import { join } from "node:path";
import { AnthropicStudioApi, parseSkills } from "../dist/src/studio/model.js";
import { MODEL_MIXES, modelLabel } from "../dist/src/studio/models.js";
import { liveRun } from "../dist/src/studio/liveRun.js";

const TOPICS = {
  pl: { kind: "brief", topic: "Pompy ciepła w Polsce: ile kosztują i czy się opłacają?", length: "short", style: "plain", language: "pl" },
  en: { kind: "brief", topic: "How do heat pumps compare with gas boilers in cold climates?", length: "standard", style: "plain", language: "en" },
  short: { kind: "brief", topic: "Is intermittent fasting better than normal dieting for weight loss?", length: "short", style: "plain", language: "en" },
};

const args = process.argv.slice(2);
const mixAt = args.indexOf("--mix");
const mix = mixAt >= 0 ? args.splice(mixAt, 2)[1] : "cheap";
const models = MODEL_MIXES[mix];
const name = args[0];
const job = TOPICS[name];
const key = process.env.ANTHROPIC_API_KEY;
if (!job || !models) { console.error("usage: studio-live-run.mjs <pl|en|short> [--mix cheap|haiku|sonnet|opus] [outDir]"); process.exit(64); }
if (!key) { console.error("ANTHROPIC_API_KEY is not set"); process.exit(2); }
const skills = parseSkills(process.env.STUDIO_SKILLS);
if (skills.length === 0) { console.error("STUDIO_SKILLS is not set"); process.exit(2); }
const outDir = args[1] ?? join(process.env.TMPDIR ?? "/tmp", `studio-live-${name}-${mix}-${Date.now()}`);

// baseURL is explicit: a sandbox may set ANTHROPIC_BASE_URL for its own inference route.
const api = new AnthropicStudioApi(key, {
  models, modelLabel: modelLabel(models), skills, maxSearches: 8, maxFetches: 8, blockedDomains: [],
  taskBudgetTokens: 150000, baseURL: "https://api.anthropic.com",
});
const { summary } = await liveRun(api, job, { name, mix, outDir, jobLimitUsd: 2, print: (l) => console.log(l) });
console.log(JSON.stringify({ ...summary, calls: undefined }, null, 2));
console.log("calls:");
for (const c of summary.calls) console.log(" ", JSON.stringify(c).slice(0, 700));
console.log("outDir:", outDir);
