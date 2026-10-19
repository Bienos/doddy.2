import { test } from "node:test";
import assert from "node:assert/strict";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFileSync } from "node:fs";
import {
  loadManifest, validate, templateFor, opFileProblems, keyShapedProblems, uncoveredExampleNames, ManifestError, renderYamlNames,
} from "../lib/manifest.mjs";
import { baseManifest, makeRoot, run } from "./helpers.mjs";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");

test("the repository's own manifest, templates and .env.example files pass check", async () => {
  const result = await run(["check"], { root: REPO });
  assert.equal(result.code, 0, result.err);
  assert.match(result.out, /^OK: \d+ secrets/);
});

test("every Render service in the real manifest is named in render.yaml", () => {
  const manifest = loadManifest(join(REPO, "secrets/manifest.json"), { root: REPO });
  const names = renderYamlNames(join(REPO, "render.yaml"));
  for (const name of Object.keys(manifest.hosts.render.services)) assert.ok(names.has(name), name);
});

test("the state-bound keys are never pushed by the tool", () => {
  const manifest = loadManifest(join(REPO, "secrets/manifest.json"), { root: REPO });
  const pushed = (name) => manifest.secrets.filter((s) => s.name === name).map((s) => s.push);
  assert.deepEqual(pushed("MEMORY_ENCRYPTION_KEY"), [false]);
  assert.deepEqual(pushed("DODDY_SESSION_SIGNING_KEY"), [false, false]);
  assert.deepEqual(pushed("GATEWAY_TOKEN_SECRET"), [false]);
  assert.deepEqual(pushed("ELEVENLABS_TOOL_SECRET"), [false]);
});

test("a valid manifest has no problems", () => {
  assert.deepEqual(validate(baseManifest()), []);
});

test("duplicates are refused: same name twice for one service, or twice to one target", () => {
  const m = baseManifest();
  m.secrets.push({ ...m.secrets[0], item: "api-key-2" });
  const problems = validate(m);
  assert.ok(problems.some((p) => /API_KEY is listed twice for api/.test(p)), problems.join("\n"));
  assert.ok(problems.some((p) => /API_KEY goes to vercel:web twice/.test(p)), problems.join("\n"));
});

test("one 1Password item can't hold two different variables", () => {
  const m = baseManifest();
  m.secrets[1].item = "api-key";
  assert.ok(validate(m).some((p) => /item "api-key" is already used by API_KEY/.test(p)));
});

test("malformed names, items and fields are refused", () => {
  const m = baseManifest();
  m.secrets[0].item = "Api Key";
  m.secrets[1].name = "lowercase";
  m.secrets[2].field = "bad field";
  const problems = validate(m).join("\n");
  assert.match(problems, /item must be a lowercase 1Password item name without spaces/);
  assert.match(problems, /name must be an UPPER_SNAKE/);
  assert.match(problems, /field must be letters/);
});

test("unknown targets, and Render services missing from render.yaml, are refused", () => {
  const m = baseManifest();
  m.secrets[0].targets.push("vercel:nope", "supabase:fn");
  m.hosts.render.services.ghost = "srv-ghost1";
  const problems = validate(m, { renderNames: new Set(["worker", "shared"]) }).join("\n");
  assert.match(problems, /unknown target "vercel:nope"/);
  assert.match(problems, /unknown target "supabase:fn"/);
  assert.match(problems, /Render service "ghost" is not named in render.yaml/);
});

test("a record-only secret must say why", () => {
  const m = baseManifest();
  delete m.secrets[3].whyNotPushed;
  assert.ok(validate(m).some((p) => /whyNotPushed/.test(p)));
});

test("a value pasted into the manifest fails loading", () => {
  const m = baseManifest();
  m.secrets[0].rotate = "old key was sk-proj-AbCdEfGh1234567890XyZ";
  const root = makeRoot(m);
  assert.throws(() => loadManifest(join(root, "secrets/manifest.json"), { root }), (error) => error instanceof ManifestError && /looks like a real credential/.test(error.message));
});

test("the detector flags random-looking strings but not folder paths or op:// references", () => {
  assert.equal(keyShapedProblems("see docs/archive/supabase-functions-2026-10-18 for the code", "x").length, 0);
  assert.equal(keyShapedProblems(`API_${"KEY"}=op://doddy-prod/some-very-long-item-name-for-testing/credential`, "x").length, 0);
  assert.equal(keyShapedProblems("token: Qm9vb3RzdHJhcFRva2VuMTIzNDU2Nzg5MEFCQ0RFRg", "x").length, 1);
  assert.equal(keyShapedProblems("sha 4c8bb51e2a90f3b1c7d6e5f4a3b2c1d0e9f8a7b6", "x").length, 1);
  assert.equal(keyShapedProblems("-----BEGIN " + "PRIVATE KEY-----", "x").length, 1);
});

test(".env.op files may hold only NAME=op://vault/item/field lines", () => {
  // Built from pieces so the repository's own secret scanner doesn't read these fixtures as keys.
  const line = (value) => `API_${"KEY"}=${value}\n`;
  assert.deepEqual(opFileProblems(`# comment\n\n${line("op://doddy-dev/api-key/credential")}`, "f"), []);
  assert.match(opFileProblems(line("plain-value"), "f").join(), /only NAME=op:\/\/vault\/item\/field/);
  assert.match(opFileProblems(line("op://doddy dev/api key/credential"), "f").join(), /only NAME=op:/);
});

test("templates hold development references only, sorted, for dev secrets of that service", () => {
  const root = makeRoot();
  const manifest = loadManifest(join(root, "secrets/manifest.json"), { root });
  const api = templateFor(manifest, "api");
  assert.ok(api.split("\n").includes("API_KEY=" + "op://doddy-dev/api-key/credential"), api);
  assert.doesNotMatch(api, /TOKEN=/, "dev: false stays out");
  assert.doesNotMatch(api, /doddy-prod/);
  const worker = templateFor(manifest, "worker");
  assert.ok(worker.indexOf("API_KEY=") < worker.indexOf("ENC_KEY="));
  assert.equal(templateFor(manifest, "api"), api, "deterministic");
});

test("check fails on a stale template and on an .env.example name nobody listed", async () => {
  const root = makeRoot(baseManifest(), { examples: { api: ["API_KEY=", "PORT=3000", "# NEW_THING=", ""].join("\n") } });
  let result = await run(["check"], { root });
  assert.equal(result.code, 1);
  assert.match(result.err, /api\/.env.example names NEW_THING/);
  const { writeFileSync } = await import("node:fs");
  writeFileSync(join(root, "worker/.env.op"), "# edited by hand\n");
  result = await run(["check"], { root });
  assert.match(result.err, /worker\/.env.op is out of date/);
});

test("uncoveredExampleNames accepts secrets of that service, managed values and not-secrets", () => {
  const root = makeRoot();
  const manifest = loadManifest(join(root, "secrets/manifest.json"), { root });
  assert.deepEqual(uncoveredExampleNames(manifest, "worker", ["API_KEY=", "ENC_KEY=", "DATABASE_URL=", "PORT=", "TOKEN=", ""].join("\n")), ["TOKEN"]);
});

test("the real deploy.env.op holds references only", () => {
  assert.deepEqual(opFileProblems(readFileSync(join(REPO, "secrets/deploy.env.op"), "utf8"), "deploy"), []);
});

test("a service can have no local template; its .env.example is still checked", async () => {
  const m = baseManifest();
  m.templates.worker = null;
  const root = makeRoot(m, { examples: { worker: ["API_KEY=", "SURPRISE=", ""].join("\n") } });
  const result = await run(["check"], { root });
  assert.equal(result.code, 1);
  assert.match(result.err, /worker\/.env.example names SURPRISE/);
  assert.doesNotMatch(result.err, /worker\/.env.op/);
  m.templates.worker = "elsewhere/.env.op";
  assert.ok(validate(m).some((p) => /templates.worker must be a path inside worker\//.test(p)));
});
