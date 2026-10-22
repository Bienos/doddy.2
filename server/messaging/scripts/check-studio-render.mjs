// Cross-check (ADR-584): the server's own Studio checks, run on files the real renderers made.
// Keeps studio-skills/ (Python) and src/studio/checks.ts (TypeScript) from drifting apart.
//   node scripts/check-studio-render.mjs <content.json> <dir with the four files>
// Needs the compiled server (npm run build or npm test first). Prints each check; exit 1 on a failure.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { checkFiles } from "../dist/src/studio/checks.js";
import { contentProblems, FILE_NAMES } from "../dist/src/studio/schema.js";

const [contentPath, dir] = process.argv.slice(2);
if (!contentPath || !dir) {
  console.error("usage: node scripts/check-studio-render.mjs <content.json> <dir>");
  process.exit(64);
}
const content = JSON.parse(readFileSync(contentPath, "utf8"));
const problems = contentProblems(content, { claims: content.claims, sources: content.sources });
for (const p of problems) console.log(`FAIL content: ${p}`);
const files = FILE_NAMES.map((name) => {
  try { return { name, bytes: readFileSync(join(dir, name)) }; } catch { return undefined; }
}).filter(Boolean);
const checks = checkFiles(files, content);
for (const c of checks) console.log(`${c.passed ? "PASS" : "FAIL"} ${c.name}${c.detail ? `: ${c.detail}` : ""}`);
process.exit(problems.length || checks.some((c) => !c.passed) ? 1 : 0);
