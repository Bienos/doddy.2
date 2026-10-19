#!/usr/bin/env node
// Doddy's project secrets: 1Password is the record, each host keeps its own environment variables,
// and this tool copies one to the other when the owner asks (ADR-493, docs/security/SECRETS_1PASSWORD.md).
//
//   node tools/secrets/sync.mjs check                  offline checks (CI): manifest, templates, .env.example coverage
//   node tools/secrets/sync.mjs templates [--write]    show or rewrite the .env.op templates
//   node tools/secrets/sync.mjs [plan] [options]       dry run: read 1Password and the hosts, print the plan
//   node tools/secrets/sync.mjs --apply [options]      the same plan, then write it after you type its code
//
// Options: --env production|development (default production), --service <folder>, --target <host:name>,
//          --prune (also remove retired names), --confirm <code> (instead of typing it), --manifest, --state.
// Host credentials come from the environment: VERCEL_TOKEN, RENDER_API_KEY. Run it under
//   op run --env-file=secrets/deploy.env.op -- node tools/secrets/sync.mjs …
// so those come from 1Password too. Values are never printed; only names, actions and fingerprints.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline/promises";
import {
  loadManifest, templateFor, opFileProblems, uncoveredExampleNames, ManifestError,
} from "./lib/manifest.mjs";
import { buildPlan, applyPlan, PlanError } from "./lib/plan.mjs";
import { vercelClient, renderClient } from "./lib/hosts.mjs";
import { opReader } from "./lib/op.mjs";
import { redactor } from "./lib/redact.mjs";
import { fileState } from "./lib/state.mjs";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

const USAGE = `Doddy secrets: 1Password is the record, hosts keep env vars (docs/security/SECRETS_1PASSWORD.md).
  node tools/secrets/sync.mjs check                 offline checks (manifest, templates, .env.example names)
  node tools/secrets/sync.mjs templates [--write]   show or rewrite the .env.op templates
  node tools/secrets/sync.mjs [options]             dry run: print the plan, write nothing
  node tools/secrets/sync.mjs --apply [options]     write the plan after you type its code (or --confirm <code>)
Options: --env production|development, --target <vercel:project|render:service|render-group:group>,
         --service <folder>, --prune (also remove retired names)
Host tokens come from VERCEL_TOKEN and RENDER_API_KEY; run it as
  op run --env-file=secrets/deploy.env.op -- node tools/secrets/sync.mjs ...`;

export function parseArgs(argv) {
  const options = { command: "plan", env: "production", write: false, apply: false, prune: false };
  const args = [...argv];
  if (args.includes("--help") || args[0] === "help") return { ...options, command: "help" };
  if (args[0] && !args[0].startsWith("--")) options.command = args.shift();
  while (args.length > 0) {
    const arg = args.shift();
    const value = () => {
      const next = args.shift();
      if (next === undefined || next.startsWith("--")) throw new UsageError(`${arg} needs a value`);
      return next;
    };
    if (arg === "--env") options.env = value();
    else if (arg === "--service") options.service = value();
    else if (arg === "--target") options.target = value();
    else if (arg === "--confirm") options.confirm = value();
    else if (arg === "--manifest") options.manifest = value();
    else if (arg === "--state") options.state = value();
    else if (arg === "--write") options.write = true;
    else if (arg === "--apply") options.apply = true;
    else if (arg === "--prune") options.prune = true;
    else throw new UsageError(`unknown option ${arg}`);
  }
  if (!["check", "templates", "plan"].includes(options.command)) throw new UsageError(`unknown command ${options.command}`);
  if (!["production", "development"].includes(options.env)) throw new UsageError("--env must be production or development");
  return options;
}

class UsageError extends Error {}

/**
 * @param {string[]} argv
 * @param {object} [deps]  injected in tests: out, err, env, fetch, readSecret, root, ask, isTTY
 * @returns {Promise<number>} exit code
 */
export async function main(argv, deps = {}) {
  const out = deps.out ?? ((line) => process.stdout.write(`${line}\n`));
  const err = deps.err ?? ((line) => process.stderr.write(`${line}\n`));
  const env = deps.env ?? process.env;
  const root = deps.root ?? ROOT;
  let options;
  try {
    options = parseArgs(argv);
  } catch (error) {
    err(`usage: ${error.message}`);
    return 2;
  }
  if (options.command === "help") {
    out(USAGE);
    return 0;
  }
  const manifestPath = resolve(root, options.manifest ?? "secrets/manifest.json");
  let manifest;
  try {
    manifest = loadManifest(manifestPath, { root });
  } catch (error) {
    if (error instanceof ManifestError) { err(error.message); return 1; }
    throw error;
  }

  const targets = [...new Set([...manifest.secrets.flatMap((s) => s.targets), ...manifest.retired.flatMap((r) => r.targets ?? [])])].sort();
  if (options.target && !targets.includes(options.target)) { err(`usage: unknown target ${options.target} (known: ${targets.join(", ")})`); return 2; }
  if (options.service && !Object.hasOwn(manifest.templates, options.service)) { err(`usage: unknown service ${options.service} (known: ${Object.keys(manifest.templates).join(", ")})`); return 2; }

  if (options.command === "check") return check(manifest, root, out, err);
  if (options.command === "templates") return templates(manifest, root, options.write, out, err);

  // Plan (and maybe apply). Everything printed passes through the redactor once values are known.
  let say = out;
  let complain = err;
  const readSecret = deps.readSecret ?? opReader({ env });
  const clients = makeClients(manifest, env, deps.fetch);
  const state = deps.state ?? fileState(resolve(root, options.state ?? "secrets/.sync-state.json"));
  try {
    const { plan, context } = await buildPlan({
      manifest, env: options.env, filter: { service: options.service, target: options.target },
      prune: options.prune, readSecret, clients, state,
    });
    const redact = redactor([...context.values.values()]);
    say = (line) => out(redact(line));
    complain = (line) => err(redact(line));
    printPlan(plan, say);

    if (!options.apply) {
      if (plan.writes > 0) say(`To apply exactly this plan: node tools/secrets/sync.mjs --apply --confirm ${plan.code}${flagsFor(options)}`);
      return plan.items.some((i) => ["error", "conflict"].includes(i.action)) ? 1 : 0;
    }
    if (plan.writes === 0) { say("Nothing to write."); return 0; }

    const confirm = options.confirm ?? (await askForCode(deps, say));
    if (confirm === null) { complain("Not a terminal and no --confirm given, so nothing was written."); return 1; }
    const results = await applyPlan({ manifest, plan, context, confirm, clients, state });
    state.save();
    printResults(results, plan, say);
    return results.every((r) => r.outcome === "set" || r.outcome === "removed") ? 0 : 1;
  } catch (error) {
    if (error instanceof PlanError) { complain(error.message); return 1; }
    complain(`stopped: unexpected ${error?.name ?? "error"} (message withheld so no value can leak)`);
    return 1;
  }
}

function makeClients(manifest, env, fetchImpl) {
  const why = {};
  const vercel = env.VERCEL_TOKEN
    ? vercelClient({ token: env.VERCEL_TOKEN, teamId: manifest.hosts.vercel.teamId, fetch: fetchImpl ?? fetch })
    : null;
  if (!vercel) why.vercel = "no VERCEL_TOKEN in the environment";
  const render = env.RENDER_API_KEY ? renderClient({ apiKey: env.RENDER_API_KEY, fetch: fetchImpl ?? fetch }) : null;
  if (!render) why.render = "no RENDER_API_KEY in the environment";
  return { vercel, render, why };
}

async function askForCode(deps, say) {
  if (deps.ask) return deps.ask("Type the plan code to write it (anything else cancels): ");
  if (!(deps.isTTY ?? process.stdin.isTTY)) return null;
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    return (await rl.question("Type the plan code to write it (anything else cancels): ")).trim();
  } finally {
    rl.close();
    say("");
  }
}

function flagsFor(options) {
  return [
    options.env !== "production" ? ` --env ${options.env}` : "",
    options.service ? ` --service ${options.service}` : "",
    options.target ? ` --target ${options.target}` : "",
    options.prune ? " --prune" : "",
  ].join("");
}

const LABEL = { add: "add", change: "change", same: "same", remove: "remove", conflict: "CONFLICT", missing: "missing", error: "ERROR", skipped: "skipped" };

function printPlan(plan, say) {
  say(`Plan for ${plan.env}. Values are never shown; fp = first 8 hex of the value's SHA-256.`);
  let current = null;
  for (const item of plan.items) {
    if (item.target !== current) { current = item.target; say(`  ${current}`); }
    const fp = item.fingerprint ? `fp ${item.fingerprint}` : "";
    say(`    ${LABEL[item.action].padEnd(8)} ${item.name.padEnd(34)} ${fp.padEnd(11)} ${item.note ?? ""}`.trimEnd());
  }
  if (plan.items.length === 0) say("  (nothing matches)");
  if (plan.recordOnly.length > 0) {
    say("  Kept in 1Password only; this tool never writes them:");
    for (const entry of plan.recordOnly) say(`    ${entry.name.padEnd(34)} ${entry.why}`);
  }
  say(`${plan.writes} write(s). Plan code: ${plan.code}`);
}

function printResults(results, plan, say) {
  say("Results (only what the host confirmed counts as done):");
  for (const r of results) say(`  ${r.outcome.padEnd(8)} ${r.target.padEnd(26)} ${r.name.padEnd(34)} ${r.reason ?? ""}`.trimEnd());
  const touched = [...new Set(results.filter((r) => r.outcome === "set" || r.outcome === "removed").map((r) => r.target))];
  if (touched.length > 0) say(`Redeploy for the change to take effect: ${touched.join(", ")} (env changes only reach new deployments).`);
  if (results.some((r) => r.outcome === "unknown")) say("Something is unknown: look in the host's dashboard before running again. Unknown is not success.");
}

function check(manifest, root, out, err) {
  const problems = [];
  for (const [service, path] of Object.entries(manifest.templates)) {
    const example = join(root, service, ".env.example");
    if (existsSync(example)) {
      for (const name of uncoveredExampleNames(manifest, service, readFileSync(example, "utf8"))) {
        problems.push(`${service}/.env.example names ${name}, which secrets/manifest.json doesn't list as a secret, managed value or not-a-secret`);
      }
    }
    if (path === null) continue;
    const full = join(root, path);
    const expected = templateFor(manifest, service);
    if (!existsSync(full)) { problems.push(`${path} is missing (run: node tools/secrets/sync.mjs templates --write)`); continue; }
    const text = readFileSync(full, "utf8");
    if (text !== expected) problems.push(`${path} is out of date (run: node tools/secrets/sync.mjs templates --write)`);
    problems.push(...opFileProblems(text, path));
  }
  const deployFile = join(root, "secrets", "deploy.env.op");
  if (existsSync(deployFile)) problems.push(...opFileProblems(readFileSync(deployFile, "utf8"), "secrets/deploy.env.op"));
  if (problems.length > 0) {
    for (const p of problems) err(`FAIL: ${p}`);
    return 1;
  }
  const pushed = manifest.secrets.filter((s) => s.push).length;
  const templateCount = Object.values(manifest.templates).filter((path) => path !== null).length;
  out(`OK: ${manifest.secrets.length} secrets (${pushed} synced, ${manifest.secrets.length - pushed} kept in 1Password only), ${templateCount} templates up to date, .env.example names all accounted for.`);
  return 0;
}

function templates(manifest, root, write, out, err) {
  let stale = 0;
  for (const [service, path] of Object.entries(manifest.templates)) {
    if (path === null) continue;
    const full = join(root, path);
    const expected = templateFor(manifest, service);
    const current = existsSync(full) ? readFileSync(full, "utf8") : null;
    if (current === expected) { out(`same     ${path}`); continue; }
    stale++;
    if (write) { writeFileSync(full, expected); out(`written  ${path}`); } else out(`stale    ${path}`);
  }
  if (!write && stale > 0) { err("Run with --write to update them."); return 1; }
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).then((code) => { process.exitCode = code; });
}
