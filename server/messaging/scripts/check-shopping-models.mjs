#!/usr/bin/env node
// Asks Anthropic what a model can do, and says what that means for the shopping runner (ADR-611).
// Nobody has run Claude Haiku 5.5 with the dynamic-filtering web tools, so this reads the model's own
// capability listing (GET /v1/models/{id}) instead of guessing.
//
//   export ANTHROPIC_API_KEY=...                                    # the key is read from here and nowhere else
//   node scripts/check-shopping-models.mjs                          # claude-haiku-5-5 and claude-sonnet-5-5
//   node scripts/check-shopping-models.mjs claude-haiku-5-5         # one or more model ids
//   npm run build                                                   # first, if you want the runner's own choice shown
//
// Cost: nothing. The models endpoint is a read; no tokens are used.
// Never: prints or accepts the key as an argument, sends anything but the model id, calls a model, writes a file.
// Exit codes: 0 every model answered; 1 a model could not be read (HTTP error or no answer); 2 not started
// (no key, bad arguments).
//
// What it can't tell you: the listing says what Anthropic documents for a model. It is not a test that the
// tools work with the runner's prompts. One real research errand on the model is still the proof.

import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const DEFAULT_MODELS = ["claude-haiku-5-5", "claude-sonnet-5-5"];
const MODELS_URL = "https://api.anthropic.com/v1/models/";
const NOT_REPORTED = "not reported";
const TIMEOUT_MS = 15_000;

const isObject = (v) => typeof v === "object" && v !== null && !Array.isArray(v);
/** true, false, or undefined when the field is missing or not shaped like { supported: boolean }. */
const supportedOf = (v) => (isObject(v) && typeof v.supported === "boolean" ? v.supported : undefined);
const yesNo = (b) => (b === true ? "yes" : b === false ? "no" : NOT_REPORTED);
const count = (n) => (typeof n === "number" && Number.isFinite(n) ? n.toLocaleString("en-US") : NOT_REPORTED);

/** The names under `obj` (other than `supported`) whose own `supported` is `wanted`. */
const namesWhere = (obj, wanted) =>
  isObject(obj) ? Object.entries(obj).filter(([k, v]) => k !== "supported" && supportedOf(v) === wanted).map(([k]) => k) : [];

/** A group of options ("effort" with its levels, "thinking" with its types) in one phrase. */
function describeGroup(group, options) {
  if (!isObject(group)) return NOT_REPORTED;
  if (group.supported === false) return "not supported";
  const on = namesWhere(options, true);
  const off = namesWhere(options, false);
  if (on.length === 0) return group.supported === true ? "supported (which ones: not reported)" : NOT_REPORTED;
  return on.join(", ") + (off.length ? ` (not available: ${off.join(", ")})` : "");
}

/** What the response's capabilities object says, with undefined wherever it says nothing. */
export function readCapabilities(model) {
  const caps = isObject(model) && isObject(model.capabilities) ? model.capabilities : {};
  const tools = isObject(caps.server_tools) ? caps.server_tools : {};
  return {
    effort: describeGroup(caps.effort, caps.effort),
    structuredOutputs: supportedOf(caps.structured_outputs),
    thinking: describeGroup(caps.thinking, isObject(caps.thinking) ? caps.thinking.types : undefined),
    webSearch: supportedOf(tools.web_search),
    webFetch: supportedOf(tools.web_fetch),
    serverCodeExecution: supportedOf(tools.code_execution),
    programmaticToolCalling: supportedOf(caps.code_execution),
  };
}

/** The dynamic-filtering tools run code on Anthropic's side, so web search and code execution must both be
 * reported as supported. A "no" on any of them (web fetch included, when reported) is a no. */
export function dynamicFilteringVerdict(c) {
  const needed = [["web search", c.webSearch], ["server-side code execution", c.serverCodeExecution], ["web fetch", c.webFetch]];
  const no = needed.filter(([, v]) => v === false).map(([name]) => name);
  if (no.length) return { answer: "LIKELY NOT USABLE", why: `the listing says ${no.join(" and ")} ${no.length > 1 ? "are" : "is"} not supported` };
  if (c.webSearch === true && c.serverCodeExecution === true) {
    return { answer: "LIKELY USABLE", why: c.webFetch === true ? "web search, web fetch and code execution are all reported as supported" : "web search and code execution are reported as supported, web fetch is not reported" };
  }
  const missing = needed.filter(([name, v]) => v === undefined && name !== "web fetch").map(([name]) => name);
  return { answer: "CANNOT TELL", why: `the listing does not report ${missing.join(" and ")}` };
}

/** What the runner sends for this model: { webTools: [{ type, name }], serverFallback: boolean }, or undefined
 * when it could not be read (the project is not built). */
const isDynamic = (runner) => runner.webTools.some((t) => /_20260209$/.test(t.type));

function runnerLines(verdict, runner) {
  if (!runner) {
    return [
      "  The runner currently uses: could not read (run `npm run build` in server/messaging, then run this again).",
    ];
  }
  const tools = runner.webTools.map((t) => t.type).join(" + ");
  const kind = isDynamic(runner) ? "the dynamic-filtering tools" : "the basic tools";
  const lines = [
    `  The runner currently uses: ${tools} (${kind}).`,
    `  Server-side fallbacks: the runner ${runner.serverFallback ? "sends" : "does not send"} the fallbacks parameter for this model.`,
  ];
  if (isDynamic(runner) && verdict.answer === "LIKELY NOT USABLE") {
    lines.push("  Mismatch: the runner sends the _20260209 tools to a model whose listing says it can't take them. Expect a 400; fix webToolsFor in runner.ts.");
  } else if (isDynamic(runner) && verdict.answer === "CANNOT TELL") {
    lines.push("  The runner sends the _20260209 tools and the listing does not confirm them. One real research errand on this model will show.");
  } else if (isDynamic(runner)) {
    lines.push("  Consistent: the runner's choice matches what the listing reports.");
  } else if (verdict.answer === "LIKELY USABLE") {
    lines.push("  The listing allows more than the runner uses. Moving this model to the _20260209 tools is a change to webToolsFor in runner.ts and an ADR; try it on one real research errand first. This script changes nothing.");
  } else {
    lines.push("  Consistent: the basic tools don't depend on code execution, so they are the safe choice here.");
  }
  return lines;
}

/** The plain report for one model. Pure: the response JSON in, text out. */
export function formatModelReport(requestedId, model, runner) {
  const m = isObject(model) ? model : {};
  const c = readCapabilities(m);
  const verdict = dynamicFilteringVerdict(c);
  const lines = [`Model: ${requestedId}`];
  if (typeof m.id === "string" && m.id !== requestedId) lines.push(`  (the API calls it ${m.id})`);
  lines.push(
    `  max_input_tokens: ${count(m.max_input_tokens)}`,
    `  max_tokens: ${count(m.max_tokens)}`,
    `  effort levels: ${c.effort}`,
    `  structured outputs: ${yesNo(c.structuredOutputs)}`,
    `  thinking types: ${c.thinking}`,
    `  server tool web_search: ${yesNo(c.webSearch)}`,
    `  server tool web_fetch: ${yesNo(c.webFetch)}`,
    `  server tool code_execution: ${yesNo(c.serverCodeExecution)}`,
    `  code_execution (programmatic tool calling): ${yesNo(c.programmaticToolCalling)}`,
    "",
    "Verdict for the shopping runner",
    `  Dynamic-filtering web tools (web_search_20260209 / web_fetch_20260209): ${verdict.answer} (${verdict.why}).`,
    ...runnerLines(verdict, runner),
    "  This comes from the capability listing only; no call with these tools was made.",
  );
  return lines.join("\n");
}

/** The runner's choices for one model, read from the built code; undefined when it isn't built. */
export async function loadRunnerChoice(modelId) {
  try {
    const runner = await import("../dist/src/shopping/runner.js");
    return { webTools: [...runner.webToolsFor(modelId)], serverFallback: runner.supportsServerFallback(modelId) };
  } catch {
    return undefined;
  }
}

const USAGE = `Usage: node scripts/check-shopping-models.mjs [model-id ...]
  Default models: ${DEFAULT_MODELS.join(" ")}
  The key is read from ANTHROPIC_API_KEY (never an argument). Costs nothing.`;

/** Returns the exit code. Everything it needs comes in through `io`, so a test can run it with no network. */
export async function run(argv, io = {}) {
  const env = io.env ?? process.env;
  const out = io.stdout ?? ((s) => process.stdout.write(s));
  const err = io.stderr ?? ((s) => process.stderr.write(s));
  const fetchFn = io.fetch ?? fetch;
  const choice = io.loadRunnerChoice ?? loadRunnerChoice;

  const ids = [];
  for (const a of argv) {
    if (a === "-h" || a === "--help") { out(USAGE + "\n"); return 0; }
    // Never echo what was typed: it may be a key.
    if (a.startsWith("-")) { err("Unknown option. " + USAGE + "\n"); return 2; }
    if (a.startsWith("sk-")) { err("That looks like an API key. The key is read only from ANTHROPIC_API_KEY; arguments are model ids.\n"); return 2; }
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/.test(a)) { err("A model id is letters, digits, dots, dashes and underscores.\n"); return 2; }
    ids.push(a);
  }
  const key = (env.ANTHROPIC_API_KEY ?? "").trim();
  if (!key) {
    err("ANTHROPIC_API_KEY is not set. Export it in this shell (for example: export ANTHROPIC_API_KEY=...) and run again. Nothing was sent.\n");
    return 2;
  }

  let failed = 0;
  for (const id of ids.length ? [...new Set(ids)] : DEFAULT_MODELS) {
    let res;
    try {
      res = await fetchFn(MODELS_URL + encodeURIComponent(id), {
        headers: { "x-api-key": key, "anthropic-version": "2023-06-01" },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch {
      err(`${id}: the API could not be reached (network error or timeout).\n`);
      failed++;
      continue;
    }
    if (!res.ok) {
      // The status and the API's error type only: nothing else from the body is printed.
      let type = "unknown error type";
      try {
        const t = (await res.json())?.error?.type;
        if (typeof t === "string" && /^[a-z_]{1,60}$/.test(t)) type = t;
      } catch { /* no usable body */ }
      err(`${id}: HTTP ${res.status} ${type}\n`);
      failed++;
      continue;
    }
    let body;
    try { body = await res.json(); } catch {
      err(`${id}: the API answered, but not with JSON.\n`);
      failed++;
      continue;
    }
    out(formatModelReport(id, body, await choice(id)) + "\n\n");
  }
  return failed ? 1 : 0;
}

/** True when this file was started from the command line, not imported (by a test). */
function startedFromCommandLine() {
  try { return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; }
}
if (startedFromCommandLine()) process.exitCode = await run(process.argv.slice(2));
