import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { opReader } from "../lib/op.mjs";
import { renderClient, vercelClient, HostError } from "../lib/hosts.mjs";
import { redactor, fingerprint } from "../lib/redact.mjs";
import { fileState } from "../lib/state.mjs";
import { CANARY } from "./helpers.mjs";

// A stand-in for the 1Password CLI: answers `op read --no-newline <ref>` from a JSON file.
function fakeOp() {
  const dir = mkdtempSync(join(tmpdir(), "fake-op-"));
  const store = join(dir, "store.json");
  writeFileSync(store, JSON.stringify({ "op://doddy-prod/api-key/credential": CANARY, "op://doddy-prod/multi/notesPlain": "line one\nline two" }));
  const bin = join(dir, "op");
  writeFileSync(bin, `#!/usr/bin/env node
const [cmd, flag, ref] = process.argv.slice(2);
if (cmd !== "read" || flag !== "--no-newline") { process.stderr.write("unexpected arguments"); process.exit(2); }
if (ref === "op://doddy-prod/broken/credential") { process.stderr.write("[ERROR] network trouble"); process.exit(1); }
const store = JSON.parse(require("node:fs").readFileSync(${JSON.stringify(store)}, "utf8"));
if (!(ref in store)) { process.stderr.write('[ERROR] "' + ref + '" isn\\'t an item in the vault'); process.exit(1); }
process.stdout.write(store[ref]);
`);
  chmodSync(bin, 0o755);
  // The fake is CommonJS (require) so it runs without a package.json beside it.
  return bin;
}

test("opReader reads a value through the CLI, including multi-line notes", async () => {
  const read = opReader({ opPath: fakeOp() });
  assert.deepEqual(await read("op://doddy-prod/api-key/credential"), { status: "ok", value: CANARY });
  assert.deepEqual(await read("op://doddy-prod/multi/notesPlain"), { status: "ok", value: "line one\nline two" });
});

test("opReader reports missing items and other failures without echoing anything", async () => {
  const read = opReader({ opPath: fakeOp() });
  assert.deepEqual(await read("op://doddy-prod/nope/credential"), { status: "missing" });
  assert.deepEqual(await read("op://doddy-prod/broken/credential"), { status: "error", reason: "op read failed (exit 1)" });
  assert.deepEqual(await opReader({ opPath: join(tmpdir(), "definitely-not-op") })("op://x/y/z"), { status: "error", reason: "1Password CLI (op) not found on PATH" });
});

test("a real timeout on a write is unknown", async () => {
  // AbortSignal.timeout doesn't keep Node running by itself (a real socket would), so hold it open.
  const keepAlive = setInterval(() => {}, 1000);
  const never = (_url, init) => new Promise((_resolve, reject) => init.signal.addEventListener("abort", () => reject(init.signal.reason)));
  const render = renderClient({ apiKey: "k", fetch: never, timeoutMs: 20 });
  try {
    await assert.rejects(render.put("render", "srv-a", "KEY", CANARY), (error) => error instanceof HostError && error.outcome === "unknown" && error.message === "timed out");
  } finally {
    clearInterval(keepAlive);
  }
});

test("reads that fail are 'failed', and error messages never carry the request or the body", async () => {
  const leaky = async () => new Response(JSON.stringify({ message: `bad ${CANARY}` }), { status: 400 });
  const vercel = vercelClient({ token: "t", teamId: "team", fetch: leaky });
  await assert.rejects(vercel.create("web", "KEY", CANARY, "production"), (error) => error.outcome === "failed" && error.message === "HTTP 400");
  const throwsWithUrl = async (url) => { throw new TypeError(`fetch failed for ${url} with ${CANARY}`); };
  await assert.rejects(vercelClient({ token: "t", teamId: "team", fetch: throwsWithUrl }).list("web"), (error) => error.message === "connection failed");
});

test("the Render client keeps only fingerprints of what it reads", async () => {
  const fetchImpl = async () => new Response(JSON.stringify([{ envVar: { key: "KEY", value: CANARY }, cursor: "c" }]), { status: 200 });
  const listing = await renderClient({ apiKey: "k", fetch: fetchImpl }).list("render", "srv-a");
  assert.deepEqual([...listing], [["KEY", fingerprint(CANARY)]]);
});

test("the Vercel client never asks to decrypt and sends the team id", async () => {
  const seen = [];
  const fetchImpl = async (url) => { seen.push(url); return new Response(JSON.stringify({ envs: [] }), { status: 200 }); };
  await vercelClient({ token: "t", teamId: "team_x", fetch: fetchImpl }).list("doddy-voice-token");
  assert.equal(seen.length, 1);
  assert.match(seen[0], /^https:\/\/api\.vercel\.com\/v10\/projects\/doddy-voice-token\/env\?teamId=team_x$/);
});

test("redactor removes raw, JSON-escaped and URL-encoded forms", () => {
  const value = 'a"b/c d+e\nf-0123456789';
  const redact = redactor([value]);
  for (const form of [value, JSON.stringify(value).slice(1, -1), encodeURIComponent(value)]) {
    assert.equal(redact(`x ${form} y`), "x [redacted] y");
  }
});

test("the state file keeps fingerprints and survives a reload", () => {
  const path = join(mkdtempSync(join(tmpdir(), "state-")), "state.json");
  const a = fileState(path);
  a.set("vercel:web|production|KEY", { fingerprint: "abcd1234", updatedAt: 5, id: "env_1" });
  a.save();
  assert.deepEqual(fileState(path).get("vercel:web|production|KEY"), { fingerprint: "abcd1234", updatedAt: 5, id: "env_1" });
  writeFileSync(path, "{ not json");
  assert.equal(fileState(path).get("vercel:web|production|KEY"), undefined);
});
