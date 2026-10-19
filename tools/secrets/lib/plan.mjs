// Works out what a sync would change (the plan), and applies exactly that plan once the person
// running it types the plan's code (ADR-493). The plan holds names, actions and fingerprints only;
// values stay in `context`, which is never printed.
import { createHash } from "node:crypto";
import { parseTarget, referenceFor } from "./manifest.mjs";
import { HostError } from "./hosts.mjs";
import { fingerprint } from "./redact.mjs";

export const WRITE_ACTIONS = new Set(["add", "change", "remove"]);

export class PlanError extends Error {}

/**
 * @param {object} options
 * @param {object} options.manifest  from loadManifest
 * @param {"production"|"development"} options.env
 * @param {{service?: string, target?: string}} [options.filter]
 * @param {boolean} [options.prune]  include removals of retired names
 * @param {(ref: string) => Promise<object>} options.readSecret
 * @param {{vercel?: object|null, render?: object|null, why?: Record<string,string>}} options.clients
 * @param {{get: (key: string) => any}} options.state
 */
export async function buildPlan({ manifest, env, filter = {}, prune = false, readSecret, clients, state }) {
  if (env !== "production" && env !== "development") throw new PlanError(`unknown environment "${env}"`);
  const vercelEnv = env;
  const matches = (secret, target) =>
    (!filter.service || secret.services.includes(filter.service)) && (!filter.target || target === filter.target);

  const pairs = [];
  const recordOnly = [];
  for (const secret of manifest.secrets) {
    if (!secret.push) {
      const shown = filter.target
        ? secret.targets.includes(filter.target)
        : !filter.service || secret.services.includes(filter.service);
      if (shown) recordOnly.push({ name: secret.name, item: secret.item, why: secret.whyNotPushed });
      continue;
    }
    for (const target of secret.targets) {
      if (!matches(secret, target)) continue;
      const { host } = parseTarget(target);
      if (env === "development" && (host !== "vercel" || !secret.dev)) continue;
      pairs.push({ secret, target, reference: referenceFor(manifest, secret, env) });
    }
  }
  const removals = [];
  if (prune) {
    for (const retired of manifest.retired) {
      for (const target of retired.targets ?? []) {
        if (filter.target && target !== filter.target) continue;
        if (env === "development" && parseTarget(target).host !== "vercel") continue;
        removals.push({ name: retired.name, target });
      }
    }
  }

  // 1Password: each reference read once.
  const reads = new Map();
  for (const { reference } of pairs) {
    if (!reads.has(reference)) reads.set(reference, await readSecret(reference));
    const result = reads.get(reference);
    if (result.status === "error" && /not found on PATH/.test(result.reason)) throw new PlanError(result.reason);
  }

  // Hosts: each target listed once.
  const listings = new Map();
  for (const target of new Set([...pairs.map((p) => p.target), ...removals.map((r) => r.target)])) {
    listings.set(target, await listTarget(manifest, target, clients));
  }

  const items = [];
  const values = new Map();
  const meta = new Map();
  for (const { secret, target, reference } of pairs) {
    const key = `${target}|${secret.name}`;
    const base = { target, host: parseTarget(target).host, name: secret.name, reference };
    const read = reads.get(reference);
    const listing = listings.get(target);
    if (read.status === "missing") { items.push({ ...base, action: "missing", note: `not in 1Password (${reference})` }); continue; }
    if (read.status !== "ok") { items.push({ ...base, action: "error", note: read.reason }); continue; }
    if (listing.status !== "ok") { items.push({ ...base, action: listing.status, note: listing.reason }); continue; }
    const fp = fingerprint(read.value);
    values.set(key, read.value);
    if (base.host === "vercel") {
      const decided = decideVercel(listing.entries.get(secret.name) ?? [], vercelEnv, fp, state.get(`${target}|${vercelEnv}|${secret.name}`));
      if (decided.entry) meta.set(key, decided.entry);
      items.push({ ...base, action: decided.action, fingerprint: fp, note: decided.note });
    } else {
      const current = listing.entries.get(secret.name);
      const action = current === undefined ? "add" : current === fp ? "same" : "change";
      items.push({ ...base, action, fingerprint: fp, note: action === "change" ? `host has ${current}` : undefined });
    }
  }
  for (const { name, target } of removals) {
    const key = `${target}|${name}`;
    const base = { target, host: parseTarget(target).host, name };
    const listing = listings.get(target);
    if (listing.status !== "ok") { items.push({ ...base, action: listing.status, note: listing.reason }); continue; }
    if (base.host === "vercel") {
      const entries = (listing.entries.get(name) ?? []).filter((e) => e.targets.includes(vercelEnv));
      if (entries.length === 0) continue;
      if (entries.length > 1 || entries[0].targets.length > 1) {
        items.push({ ...base, action: "conflict", note: `shared with ${entries.flatMap((e) => e.targets).join(", ")}; remove it in the dashboard` });
        continue;
      }
      meta.set(key, entries[0]);
      items.push({ ...base, action: "remove", note: "retired" });
    } else if (listing.entries.has(name)) {
      items.push({ ...base, action: "remove", note: "retired" });
    }
  }

  items.sort((a, b) => a.target.localeCompare(b.target) || a.name.localeCompare(b.name));
  const writes = items.filter((item) => WRITE_ACTIONS.has(item.action));
  const code = createHash("sha256")
    .update(JSON.stringify({ env, writes: writes.map((i) => [i.target, i.name, i.action, i.fingerprint ?? null]) }))
    .digest("hex")
    .slice(0, 8);
  const plan = {
    env,
    items,
    recordOnly: recordOnly.sort((a, b) => a.name.localeCompare(b.name)),
    writes: writes.length,
    code,
    redeploy: [...new Set(writes.map((i) => i.target))],
  };
  return { plan, context: { values, meta, vercelEnv } };
}

function decideVercel(entries, vercelEnv, fp, saved) {
  const here = entries.filter((e) => e.targets.includes(vercelEnv));
  if (here.length === 0) return { action: "add" };
  if (here.length > 1 || here[0].targets.length > 1) {
    return { action: "conflict", note: `shared with ${here.flatMap((e) => e.targets).join(", ")}; give ${vercelEnv} its own variable in the dashboard first` };
  }
  const entry = here[0];
  const configType = entry.type !== "sensitive" && entry.type !== "secret";
  const typeNote = configType ? `stored as ${entry.type || "unknown"} type, readable in the dashboard; re-create it as Secret` : undefined;
  if (saved && entry.updatedAt !== null && saved.fingerprint === fp && saved.updatedAt === entry.updatedAt && saved.id === entry.id) {
    return { action: "same", entry, note: typeNote };
  }
  const why = saved ? "changed since the last sync" : "Vercel can't show the stored value, so it is overwritten";
  return { action: "change", entry, note: typeNote ? `${why}; ${typeNote}` : why };
}

async function listTarget(manifest, target, clients) {
  const { host, name } = parseTarget(target);
  const client = host === "vercel" ? clients.vercel : clients.render;
  if (!client) return { status: "skipped", reason: clients.why?.[host === "vercel" ? "vercel" : "render"] ?? "no credentials" };
  try {
    if (host === "vercel") return { status: "ok", entries: await client.list(name) };
    const id = host === "render" ? manifest.hosts.render.services[name] : manifest.hosts.render.envGroups[name];
    return { status: "ok", entries: await client.list(host, id) };
  } catch (error) {
    if (error instanceof HostError) return { status: "error", reason: `couldn't list (${error.message})` };
    throw error;
  }
}

/**
 * Applies the writes in `plan`, only if `confirm` equals the plan's code. Returns one result per
 * write: set, removed, failed or unknown. Vercel writes are confirmed by listing the project again.
 */
export async function applyPlan({ manifest, plan, context, confirm, clients, state }) {
  if (confirm !== plan.code) throw new PlanError("the code doesn't match this plan, so nothing was written");
  const results = [];
  const vercelToCheck = new Map();
  for (const item of plan.items.filter((i) => WRITE_ACTIONS.has(i.action))) {
    const key = `${item.target}|${item.name}`;
    const { host, name } = parseTarget(item.target);
    try {
      if (host === "vercel") {
        if (item.action === "add") await clients.vercel.create(name, item.name, context.values.get(key), context.vercelEnv);
        if (item.action === "change") await clients.vercel.update(name, context.meta.get(key).id, context.values.get(key));
        if (item.action === "remove") await clients.vercel.remove(name, context.meta.get(key).id);
        vercelToCheck.set(name, [...(vercelToCheck.get(name) ?? []), item]);
        continue;
      }
      const id = host === "render" ? manifest.hosts.render.services[name] : manifest.hosts.render.envGroups[name];
      if (item.action === "remove") {
        await clients.render.remove(host, id, item.name);
        results.push({ ...item, outcome: "removed" });
      } else {
        const stored = await clients.render.put(host, id, item.name, context.values.get(key));
        results.push(stored === item.fingerprint
          ? { ...item, outcome: "set" }
          : { ...item, outcome: "unknown", reason: "Render answered, but not with the value sent; check the dashboard" });
      }
    } catch (error) {
      if (!(error instanceof HostError)) throw error;
      results.push({ ...item, outcome: error.outcome, reason: error.outcome === "unknown" ? `${error.message}; check the dashboard before running again` : error.message });
    }
  }

  for (const [project, written] of vercelToCheck) {
    let listing;
    try {
      listing = await clients.vercel.list(project);
    } catch {
      for (const item of written) results.push({ ...item, outcome: "unknown", reason: "written, but the project couldn't be listed to confirm it" });
      continue;
    }
    for (const item of written) {
      const key = `${item.target}|${item.name}`;
      const here = (listing.get(item.name) ?? []).filter((e) => e.targets.includes(context.vercelEnv));
      const before = context.meta.get(key);
      if (item.action === "remove") {
        results.push(here.some((e) => e.id === before?.id) ? { ...item, outcome: "unknown", reason: "still listed after removal" } : { ...item, outcome: "removed" });
        continue;
      }
      const entry = here.length === 1 ? here[0] : null;
      const confirmed = entry && entry.updatedAt !== null && (item.action === "add" || entry.updatedAt !== before?.updatedAt);
      if (confirmed) {
        state.set(`${item.target}|${context.vercelEnv}|${item.name}`, { fingerprint: item.fingerprint, updatedAt: entry.updatedAt, id: entry.id });
        results.push({ ...item, outcome: "set" });
      } else {
        results.push({ ...item, outcome: "unknown", reason: "written, but Vercel's list doesn't show the update yet" });
      }
    }
  }
  results.sort((a, b) => a.target.localeCompare(b.target) || a.name.localeCompare(b.name));
  return results;
}
