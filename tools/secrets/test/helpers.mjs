// Test helpers: a throwaway repo root with a small manifest, in-memory stand-ins for the Vercel
// and Render APIs (no network), and a fake 1Password reader. The fakes echo values back the way
// Render's real API does, so tests can prove no value ever reaches the output.
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { templateFor, loadManifest } from "../lib/manifest.mjs";
import { memoryState } from "../lib/state.mjs";
import { main } from "../sync.mjs";

export const CANARY = "CANARY-Zq7f3a9c1e5b2d4086Xy-SECRET";

export function baseManifest() {
  return {
    version: 1,
    vaults: { production: "doddy-prod", development: "doddy-dev" },
    templates: { api: "api/.env.op", worker: "worker/.env.op" },
    hosts: {
      vercel: { teamId: "team_test", projects: ["web"] },
      render: { services: { worker: "srv-worker1" }, envGroups: { shared: "evg-shared1" } },
    },
    secrets: [
      { name: "API_KEY", item: "api-key", services: ["api", "worker"], targets: ["vercel:web", "render:worker"], push: true, dev: true, rotate: "new key, sync, revoke old" },
      { name: "TOKEN", item: "token", services: ["api"], targets: ["vercel:web"], push: true, dev: false, rotate: "new token, sync" },
      { name: "GROUP_KEY", item: "group-key", services: ["worker"], targets: ["render-group:shared"], push: true, dev: false, rotate: "new key, sync" },
      { name: "ENC_KEY", item: "enc-key", services: ["worker"], targets: ["render:worker"], push: false, dev: true, whyNotPushed: "data becomes unreadable", rotate: "never casually" },
    ],
    managed: [{ name: "DATABASE_URL", by: "render" }],
    retired: [{ name: "OLD_CODES", targets: ["vercel:web", "render:worker"], why: "replaced by sign-in" }],
    notSecrets: ["PORT"],
  };
}

/** Writes a temporary repo root with manifest, render.yaml, templates and .env.example files. */
export function makeRoot(manifest = baseManifest(), { examples = {} } = {}) {
  const root = mkdtempSync(join(tmpdir(), "doddy-secrets-"));
  mkdirSync(join(root, "secrets"));
  writeFileSync(join(root, "secrets", "manifest.json"), JSON.stringify(manifest, null, 2));
  writeFileSync(join(root, "render.yaml"), "services:\n  - type: worker\n    name: worker\nenvVarGroups:\n  - name: shared\n");
  for (const service of Object.keys(manifest.templates ?? {})) mkdirSync(join(root, service), { recursive: true });
  for (const [service, text] of Object.entries(examples)) writeFileSync(join(root, service, ".env.example"), text);
  try {
    const loaded = loadManifest(join(root, "secrets", "manifest.json"), { root });
    for (const [service, path] of Object.entries(loaded.templates)) if (path !== null) writeFileSync(join(root, path), templateFor(loaded, service));
  } catch {
    // Invalid manifests are written as-is for validation tests.
  }
  return root;
}

export function fakeSecrets(values) {
  const reads = [];
  return {
    reads,
    readSecret: async (reference) => {
      reads.push(reference);
      return Object.hasOwn(values, reference) ? { status: "ok", value: values[reference] } : { status: "missing" };
    },
  };
}

/**
 * In-memory Vercel + Render. `faults` entries: {host, method, key?, status?, timeout?, wrongEcho?, body?}.
 */
export function fakeHosts({ vercel = {}, render = {}, groups = {}, faults = [] } = {}) {
  const calls = [];
  let clock = 1_000;
  let nextId = 1;
  const vercelEnvs = Object.fromEntries(Object.entries(vercel).map(([project, list]) => [project, list.map((e) => ({ id: `env_${nextId++}`, updatedAt: ++clock, type: "sensitive", ...e }))]));
  const renderVars = structuredClone(render);
  const groupVars = structuredClone(groups);
  const json = (status, body) => new Response(body === undefined ? null : JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  const fault = (host, method, key) => faults.find((f) => f.host === host && f.method === method && (!f.key || f.key === key));

  async function fetchImpl(url, init = {}) {
    const u = new URL(url);
    const method = init.method ?? "GET";
    const host = u.hostname === "api.vercel.com" ? "vercel" : u.hostname === "api.render.com" ? "render" : "other";
    const body = init.body ? JSON.parse(init.body) : undefined;
    let key;
    let match;
    if (host === "vercel") {
      if ((match = u.pathname.match(/^\/v10\/projects\/([^/]+)\/env$/))) key = body?.key;
      else if ((match = u.pathname.match(/^\/v9\/projects\/([^/]+)\/env\/([^/]+)$/))) key = (vercelEnvs[decodeURIComponent(match[1])] ?? []).find((e) => e.id === decodeURIComponent(match[2]))?.key;
    } else if (host === "render") {
      match = u.pathname.match(/env-vars\/([^/]+)$/);
      key = match ? decodeURIComponent(match[1]) : undefined;
    }
    calls.push({ host, method, path: u.pathname, key });
    const f = fault(host, method, key);
    if (f?.timeout) {
      const error = new Error("The operation was aborted due to timeout");
      error.name = "TimeoutError";
      throw error;
    }
    if (f?.status) return json(f.status, f.body ?? { error: { message: `rejected ${body?.value ?? ""}` } });

    if (host === "vercel") {
      let m;
      if ((m = u.pathname.match(/^\/v10\/projects\/([^/]+)\/env$/))) {
        const project = decodeURIComponent(m[1]);
        const list = (vercelEnvs[project] ??= []);
        if (method === "GET") {
          if (u.searchParams.has("decrypt")) throw new Error("test: the tool must never ask Vercel to decrypt");
          // Config-type values come back readable, the way the real API returns them.
          return json(200, { envs: list.map((e) => ({ id: e.id, key: e.key, type: e.type, target: e.target, updatedAt: e.updatedAt, ...(e.type === "sensitive" ? {} : { value: e.value }) })) });
        }
        if (method === "POST") {
          const created = { id: `env_${nextId++}`, key: body.key, value: body.value, type: body.type, target: body.target, updatedAt: ++clock };
          list.push(created);
          return json(201, { created: { ...created, value: undefined } });
        }
      }
      if ((m = u.pathname.match(/^\/v9\/projects\/([^/]+)\/env\/([^/]+)$/))) {
        const list = vercelEnvs[decodeURIComponent(m[1])] ?? [];
        const entry = list.find((e) => e.id === decodeURIComponent(m[2]));
        if (!entry) return json(404, { error: { message: "not found" } });
        if (method === "PATCH") { entry.value = body.value; entry.updatedAt = ++clock; return json(200, { ...entry, value: undefined }); }
        if (method === "DELETE") { list.splice(list.indexOf(entry), 1); return json(200, {}); }
      }
    }
    if (host === "render") {
      let m;
      if ((m = u.pathname.match(/^\/v1\/services\/([^/]+)\/env-vars$/)) && method === "GET") {
        const vars = renderVars[decodeURIComponent(m[1])] ?? {};
        return json(200, Object.entries(vars).map(([k, v], i) => ({ envVar: { key: k, value: v }, cursor: `c${i}` })));
      }
      if ((m = u.pathname.match(/^\/v1\/services\/([^/]+)\/env-vars\/([^/]+)$/))) {
        const vars = (renderVars[decodeURIComponent(m[1])] ??= {});
        const k = decodeURIComponent(m[2]);
        if (method === "PUT") { vars[k] = body.value; return json(200, { key: k, value: f?.wrongEcho ? "something-else" : body.value }); }
        if (method === "DELETE") { delete vars[k]; return json(204); }
      }
      if ((m = u.pathname.match(/^\/v1\/env-groups\/([^/]+)$/)) && method === "GET") {
        const vars = groupVars[decodeURIComponent(m[1])] ?? {};
        return json(200, { id: m[1], envVars: Object.entries(vars).map(([k, v]) => ({ key: k, value: v })) });
      }
      if ((m = u.pathname.match(/^\/v1\/env-groups\/([^/]+)\/env-vars\/([^/]+)$/)) && method === "PUT") {
        const vars = (groupVars[decodeURIComponent(m[1])] ??= {});
        vars[decodeURIComponent(m[2])] = body.value;
        return json(200, { id: m[1], envVars: Object.entries(vars).map(([k, v]) => ({ key: k, value: v })) });
      }
    }
    return json(404, { error: { message: "no such route in the fake" } });
  }
  return {
    fetch: fetchImpl,
    calls,
    writes: () => calls.filter((c) => c.method !== "GET"),
    vercelEnvs,
    renderVars,
    groupVars,
  };
}

/** Runs the CLI in-process and captures everything it prints. */
export async function run(argv, { root, hosts, secrets, state = memoryState(), env = { VERCEL_TOKEN: "vt", RENDER_API_KEY: "rk" }, ask } = {}) {
  const lines = { out: [], err: [] };
  const code = await main(argv, {
    root,
    env,
    fetch: hosts?.fetch,
    readSecret: secrets?.readSecret,
    state,
    ask,
    isTTY: false,
    out: (line) => lines.out.push(line),
    err: (line) => lines.err.push(line),
  });
  return { code, out: lines.out.join("\n"), err: lines.err.join("\n"), state };
}

export function planCode(output) {
  return output.match(/Plan code: ([0-9a-f]{8})/)?.[1];
}
