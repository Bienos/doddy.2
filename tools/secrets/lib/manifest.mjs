// Loads and checks secrets/manifest.json: which project secrets exist, where each lives in
// 1Password (an op:// reference, never a value) and which hosts get it (ADR-493).
// Everything here is offline and deterministic, so `check` can run in CI.
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const NAME = /^[A-Z][A-Z0-9_]*$/;
const SLUG = /^[a-z0-9][a-z0-9-]*$/;
const FIELD = /^[A-Za-z0-9_-]+$/;
const HOSTS = new Set(["vercel", "render", "render-group"]);

// Strings that look like a real credential. Anything matching is refused in the manifest and the
// templates, so a value pasted by mistake fails `check` instead of being committed.
export const KEY_SHAPED = [
  /sk-[A-Za-z0-9_-]{16,}/,
  /ops_[A-Za-z0-9_-]{16,}/,
  /eyJ[A-Za-z0-9_-]{20,}/,
  /AKIA[0-9A-Z]{16}/,
  /-----BEGIN [A-Z ]*KEY-----/,
  /\b[0-9a-f]{40,}\b/,
];

// A long run of key characters with upper case, lower case and digits mixed together reads as a
// random credential (base64 and most API keys); folder paths and prose don't.
function looksRandom(line) {
  return (line.match(/[A-Za-z0-9+/=_-]{32,}/g) ?? []).some((t) => /[A-Z]/.test(t) && /[a-z]/.test(t) && /[0-9]/.test(t));
}

export class ManifestError extends Error {
  constructor(problems) {
    super(`secrets manifest has ${problems.length} problem(s):\n- ${problems.join("\n- ")}`);
    this.problems = problems;
  }
}

/** Reads and validates the manifest; throws ManifestError listing every problem found. */
export function loadManifest(path, { root = process.cwd(), renderYaml = join(root, "render.yaml") } = {}) {
  const text = readFileSync(path, "utf8");
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (error) {
    throw new ManifestError([`not valid JSON (${error.message})`]);
  }
  const problems = [...keyShapedProblems(text, "manifest"), ...validate(raw, { renderNames: renderYamlNames(renderYaml) })];
  if (problems.length > 0) throw new ManifestError(problems);
  return normalise(raw);
}

/** The op:// reference for a secret in one environment ("production" or "development"). */
export function referenceFor(manifest, secret, env) {
  const vault = manifest.vaults[env];
  if (!vault) throw new Error(`no vault for environment ${env}`);
  return `op://${vault}/${secret.item}/${secret.field}`;
}

/** Parses "host:name" into a target the host clients understand. */
export function parseTarget(target) {
  const at = target.indexOf(":");
  return { host: target.slice(0, at), name: target.slice(at + 1), key: target };
}

export function validate(raw, { renderNames = null } = {}) {
  const problems = [];
  if (!raw || typeof raw !== "object") return ["manifest must be a JSON object"];
  if (raw.version !== 1) problems.push("version must be 1");

  const vaults = raw.vaults ?? {};
  for (const env of ["production", "development"]) {
    if (typeof vaults[env] !== "string" || !SLUG.test(vaults[env])) problems.push(`vaults.${env} must be a lowercase name without spaces`);
  }

  const templates = raw.templates ?? {};
  const services = new Set(Object.keys(templates));
  if (services.size === 0) problems.push("templates must map each service folder to its .env.op path");
  for (const [service, path] of Object.entries(templates)) {
    // null = this service has no local template (it still owns secrets for its hosts).
    if (path === null) continue;
    if (typeof path !== "string" || !path.startsWith(`${service}/`) || !path.endsWith(".env.op")) {
      problems.push(`templates.${service} must be a path inside ${service}/ ending in .env.op, or null`);
    }
  }

  const hosts = raw.hosts ?? {};
  const vercelProjects = new Set(hosts.vercel?.projects ?? []);
  const renderServices = hosts.render?.services ?? {};
  const renderGroups = hosts.render?.envGroups ?? {};
  if (vercelProjects.size > 0 && typeof hosts.vercel?.teamId !== "string") problems.push("hosts.vercel.teamId is required when there are Vercel projects");
  for (const [name, id] of Object.entries(renderServices)) {
    if (typeof id !== "string" || !/^srv-[a-z0-9]+$/.test(id)) problems.push(`hosts.render.services.${name} must be a Render service id (srv-…)`);
    if (renderNames && !renderNames.has(name)) problems.push(`Render service "${name}" is not named in render.yaml`);
  }
  for (const [name, id] of Object.entries(renderGroups)) {
    if (typeof id !== "string" || !/^evg-[a-z0-9]+$/.test(id)) problems.push(`hosts.render.envGroups.${name} must be a Render env group id (evg-…)`);
    if (renderNames && !renderNames.has(name)) problems.push(`Render env group "${name}" is not named in render.yaml`);
  }
  const knownTarget = (target) => {
    if (typeof target !== "string" || !target.includes(":")) return false;
    const { host, name } = parseTarget(target);
    if (!HOSTS.has(host)) return false;
    if (host === "vercel") return vercelProjects.has(name);
    if (host === "render") return Object.hasOwn(renderServices, name);
    return Object.hasOwn(renderGroups, name);
  };

  const secrets = Array.isArray(raw.secrets) ? raw.secrets : [];
  if (!Array.isArray(raw.secrets)) problems.push("secrets must be a list");
  const byNameService = new Map();
  const byNameTarget = new Map();
  const itemOwner = new Map();
  const secretNames = new Set();
  secrets.forEach((secret, index) => {
    const at = `secrets[${index}]${secret?.name ? ` (${secret.name})` : ""}`;
    if (!secret || typeof secret !== "object") return problems.push(`${at} must be an object`);
    if (typeof secret.name !== "string" || !NAME.test(secret.name)) problems.push(`${at}: name must be an UPPER_SNAKE environment variable name`);
    if (typeof secret.item !== "string" || !SLUG.test(secret.item)) problems.push(`${at}: item must be a lowercase 1Password item name without spaces`);
    if (secret.field !== undefined && (typeof secret.field !== "string" || !FIELD.test(secret.field))) problems.push(`${at}: field must be letters, digits, - or _`);
    if (typeof secret.push !== "boolean") problems.push(`${at}: push must be true or false`);
    if (secret.push === false && !nonEmpty(secret.whyNotPushed)) problems.push(`${at}: say in whyNotPushed why this tool never writes it`);
    if (typeof secret.dev !== "boolean") problems.push(`${at}: dev must be true or false`);
    if (!nonEmpty(secret.rotate)) problems.push(`${at}: rotate must say what breaks when the value changes`);
    if (!Array.isArray(secret.services) || secret.services.length === 0) problems.push(`${at}: services must list at least one service folder`);
    if (!Array.isArray(secret.targets)) problems.push(`${at}: targets must be a list (empty means record only)`);
    secretNames.add(secret.name);

    for (const service of secret.services ?? []) {
      if (!services.has(service)) problems.push(`${at}: unknown service "${service}" (add it to templates)`);
      const key = `${secret.name}|${service}`;
      if (byNameService.has(key)) problems.push(`${at}: ${secret.name} is listed twice for ${service}`);
      byNameService.set(key, at);
    }
    for (const target of secret.targets ?? []) {
      if (!knownTarget(target)) problems.push(`${at}: unknown target "${target}" (use vercel:<project>, render:<service> or render-group:<group> from hosts)`);
      const key = `${secret.name}|${target}`;
      if (byNameTarget.has(key)) problems.push(`${at}: ${secret.name} goes to ${target} twice`);
      byNameTarget.set(key, at);
    }
    if (typeof secret.item === "string") {
      const owner = itemOwner.get(secret.item);
      if (owner && owner !== secret.name) problems.push(`${at}: item "${secret.item}" is already used by ${owner}`);
      itemOwner.set(secret.item, secret.name);
    }
  });

  const managedNames = new Set();
  for (const [index, entry] of (raw.managed ?? []).entries()) {
    if (!entry || typeof entry.name !== "string" || !NAME.test(entry.name)) problems.push(`managed[${index}]: name must be an environment variable name`);
    if (!["render", "vercel"].includes(entry?.by)) problems.push(`managed[${index}]: by must be render or vercel`);
    if (secretNames.has(entry?.name)) problems.push(`managed[${index}]: ${entry.name} is also a secret`);
    managedNames.add(entry?.name);
  }
  for (const [index, entry] of (raw.retired ?? []).entries()) {
    if (!entry || typeof entry.name !== "string" || !NAME.test(entry.name)) problems.push(`retired[${index}]: name must be an environment variable name`);
    if (!nonEmpty(entry?.why)) problems.push(`retired[${index}]: say why it is retired`);
    for (const target of entry?.targets ?? []) if (!knownTarget(target)) problems.push(`retired[${index}]: unknown target "${target}"`);
    if (secretNames.has(entry?.name)) problems.push(`retired[${index}]: ${entry.name} is still a secret`);
  }
  for (const name of raw.notSecrets ?? []) {
    if (typeof name !== "string" || !NAME.test(name)) problems.push(`notSecrets: "${name}" is not an environment variable name`);
    else if (secretNames.has(name) || managedNames.has(name)) problems.push(`notSecrets: ${name} is also a secret or managed value`);
  }
  return problems;
}

function normalise(raw) {
  return {
    ...raw,
    secrets: raw.secrets.map((secret) => ({ ...secret, field: secret.field ?? "credential" })),
    managed: raw.managed ?? [],
    retired: raw.retired ?? [],
    notSecrets: raw.notSecrets ?? [],
    hosts: {
      vercel: { teamId: raw.hosts?.vercel?.teamId, projects: raw.hosts?.vercel?.projects ?? [] },
      render: {
        services: raw.hosts?.render?.services ?? {},
        envGroups: raw.hosts?.render?.envGroups ?? {},
        notManaged: raw.hosts?.render?.notManaged ?? [],
      },
    },
  };
}

/** Every `name:` value in render.yaml (services, env groups, databases). Null if there is no file. */
export function renderYamlNames(path) {
  if (!existsSync(path)) return null;
  const names = new Set();
  for (const match of readFileSync(path, "utf8").matchAll(/^\s*-?\s*name:\s*([A-Za-z0-9_-]+)\s*$/gm)) names.add(match[1]);
  return names;
}

/** The generated .env.op text for one service: development references only, sorted by name. */
export function templateFor(manifest, service) {
  const lines = [
    "# Generated from secrets/manifest.json by `node tools/secrets/sync.mjs templates --write`. Don't edit by hand.",
    "# 1Password references only (development vault), never values. Run a command with them:",
    "#   op run --env-file=.env.op -- <command>",
    "# Settings that aren't secret still come from your ignored .env.local (or .env).",
  ];
  const entries = manifest.secrets
    .filter((secret) => secret.dev && secret.services.includes(service))
    .sort((a, b) => a.name.localeCompare(b.name));
  if (entries.length === 0) lines.push("# (this service has no secrets for local development)");
  for (const secret of entries) lines.push(`${secret.name}=${referenceFor(manifest, secret, "development")}`);
  return `${lines.join("\n")}\n`;
}

/** Problems with one .env.op file: every non-comment line must be NAME=op://… and nothing key-shaped. */
export function opFileProblems(text, label) {
  const problems = [];
  text.split("\n").forEach((line, index) => {
    const trimmed = line.trim();
    if (trimmed === "" || trimmed.startsWith("#")) return;
    if (!/^[A-Z][A-Z0-9_]*=op:\/\/[a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]*\/[A-Za-z0-9_-]+$/.test(trimmed)) {
      problems.push(`${label} line ${index + 1}: only NAME=op://vault/item/field lines are allowed`);
    }
  });
  return [...problems, ...keyShapedProblems(text, label)];
}

export function keyShapedProblems(text, label) {
  const problems = [];
  text.split("\n").forEach((line, index) => {
    // op:// references are long but harmless; check what's left after removing them.
    const rest = line.replace(/op:\/\/[A-Za-z0-9/_-]+/g, "");
    if (KEY_SHAPED.some((pattern) => pattern.test(rest)) || looksRandom(rest)) problems.push(`${label} line ${index + 1} looks like a real credential`);
  });
  return problems;
}

/** Variable names in a .env.example, including commented-out ones like `# NAME=`. */
export function exampleNames(text) {
  const names = new Set();
  for (const match of text.matchAll(/^\s*#?\s*([A-Z][A-Z0-9_]*)=/gm)) names.add(match[1]);
  return names;
}

/** Names in a service's .env.example that the manifest doesn't account for. */
export function uncoveredExampleNames(manifest, service, text) {
  const known = new Set([
    ...manifest.secrets.filter((secret) => secret.services.includes(service)).map((secret) => secret.name),
    ...manifest.managed.map((entry) => entry.name),
    ...manifest.notSecrets,
  ]);
  return [...exampleNames(text)].filter((name) => !known.has(name)).sort();
}

function nonEmpty(value) {
  return typeof value === "string" && value.trim().length > 0;
}
