import { test } from "node:test";
import assert from "node:assert/strict";
import { CANARY, makeRoot, fakeHosts, fakeSecrets, run, planCode } from "./helpers.mjs";
import { memoryState } from "../lib/state.mjs";
import { fingerprint } from "../lib/redact.mjs";

const PROD = {
  "op://doddy-prod/api-key/credential": CANARY,
  "op://doddy-prod/token/credential": "token-value-0123456789",
  "op://doddy-prod/group-key/credential": "group-value-0123456789",
  "op://doddy-prod/enc-key/credential": "enc-value-0123456789",
};

function noCanary(result, extra = "") {
  for (const text of [result.out, result.err, extra]) {
    assert.ok(!text.includes(CANARY), `a secret value leaked into output:\n${text}`);
  }
}

test("a dry run reads 1Password and the hosts, writes nothing, and never prints a value", async () => {
  const root = makeRoot();
  const hosts = fakeHosts({ render: { "srv-worker1": { API_KEY: "old-value-0123456789" } } });
  const secrets = fakeSecrets(PROD);
  const result = await run([], { root, hosts, secrets });
  assert.equal(result.code, 0, result.err);
  assert.equal(hosts.writes().length, 0);
  assert.ok(hosts.calls.every((c) => c.method === "GET"));
  assert.match(result.out, /render:worker\n\s+change\s+API_KEY/);
  assert.match(result.out, /vercel:web\n\s+add\s+API_KEY/);
  assert.match(result.out, /Kept in 1Password only[\s\S]*ENC_KEY\s+data becomes unreadable/);
  assert.match(result.out, /--apply --confirm [0-9a-f]{8}/);
  assert.ok(result.out.includes(`fp ${fingerprint(CANARY)}`));
  noCanary(result);
});

test("--apply without a matching code writes nothing", async () => {
  const root = makeRoot();
  for (const confirm of [null, "deadbeef"]) {
    const hosts = fakeHosts();
    const argv = confirm ? ["--apply", "--confirm", confirm] : ["--apply"];
    const result = await run(argv, { root, hosts, secrets: fakeSecrets(PROD) });
    assert.equal(result.code, 1);
    assert.equal(hosts.writes().length, 0, `writes with confirm=${confirm}`);
    assert.match(result.err, confirm ? /doesn't match this plan, so nothing was written/ : /no --confirm given, so nothing was written/);
    noCanary(result);
  }
});

test("a typed code that doesn't match cancels", async () => {
  const root = makeRoot();
  const hosts = fakeHosts();
  const result = await run(["--apply"], { root, hosts, secrets: fakeSecrets(PROD), ask: async () => "nope" });
  assert.equal(result.code, 1);
  assert.equal(hosts.writes().length, 0);
});

test("applying the confirmed plan writes it, confirms each write, and a second run is all same", async () => {
  const root = makeRoot();
  const hosts = fakeHosts({ render: { "srv-worker1": { API_KEY: "old-value-0123456789" } } });
  const secrets = fakeSecrets(PROD);
  const state = memoryState();
  const dry = await run([], { root, hosts, secrets, state });
  const applied = await run(["--apply", "--confirm", planCode(dry.out)], { root, hosts, secrets, state });
  assert.equal(applied.code, 0, applied.out + applied.err);
  assert.match(applied.out, /set\s+render:worker\s+API_KEY/);
  assert.match(applied.out, /set\s+vercel:web\s+API_KEY/);
  assert.match(applied.out, /set\s+vercel:web\s+TOKEN/);
  assert.match(applied.out, /set\s+render-group:shared\s+GROUP_KEY/);
  assert.match(applied.out, /Redeploy for the change to take effect/);
  assert.equal(hosts.renderVars["srv-worker1"].API_KEY, CANARY);
  assert.equal(hosts.vercelEnvs.web.find((e) => e.key === "TOKEN").type, "sensitive");
  assert.deepEqual(hosts.vercelEnvs.web.find((e) => e.key === "TOKEN").target, ["production"]);
  noCanary(applied);

  const again = await run([], { root, hosts, secrets, state });
  assert.equal(again.code, 0);
  assert.match(again.out, /0 write\(s\)/);
  assert.doesNotMatch(again.out, /\b(add|change)\b\s+[A-Z]/);
  noCanary(again);
});

test("record-only secrets are never written, even when applying", async () => {
  const root = makeRoot();
  const hosts = fakeHosts();
  const secrets = fakeSecrets(PROD);
  const dry = await run([], { root, hosts, secrets });
  await run(["--apply", "--confirm", planCode(dry.out)], { root, hosts, secrets });
  assert.ok(!hosts.writes().some((c) => c.key === "ENC_KEY"));
  assert.ok(!secrets.reads.includes("op://doddy-prod/enc-key/credential"), "not even read from 1Password");
});

test("a failure on one target is reported on its own and the rest still go through", async () => {
  const root = makeRoot();
  const hosts = fakeHosts({ faults: [{ host: "render", method: "PUT", key: "API_KEY", status: 400 }] });
  const secrets = fakeSecrets(PROD);
  const dry = await run([], { root, hosts, secrets });
  const applied = await run(["--apply", "--confirm", planCode(dry.out)], { root, hosts, secrets });
  assert.equal(applied.code, 1);
  assert.match(applied.out, /failed\s+render:worker\s+API_KEY\s+HTTP 400/);
  assert.match(applied.out, /set\s+vercel:web\s+API_KEY/);
  assert.match(applied.out, /set\s+render-group:shared\s+GROUP_KEY/);
  noCanary(applied); // the fake's error body echoes the value; it must not surface
});

test("a timeout, a 5xx or an answer that doesn't match is unknown, never success", async () => {
  const root = makeRoot();
  const hosts = fakeHosts({
    faults: [
      { host: "vercel", method: "POST", key: "API_KEY", timeout: true },
      { host: "vercel", method: "POST", key: "TOKEN", status: 503 },
      { host: "render", method: "PUT", key: "API_KEY", wrongEcho: true },
    ],
  });
  const secrets = fakeSecrets(PROD);
  const dry = await run([], { root, hosts, secrets });
  const applied = await run(["--apply", "--confirm", planCode(dry.out)], { root, hosts, secrets });
  assert.equal(applied.code, 1);
  assert.match(applied.out, /unknown\s+vercel:web\s+API_KEY\s+timed out; check the dashboard/);
  assert.match(applied.out, /unknown\s+vercel:web\s+TOKEN\s+HTTP 503/);
  assert.match(applied.out, /unknown\s+render:worker\s+API_KEY\s+Render answered, but not with the value sent/);
  assert.match(applied.out, /Unknown is not success/);
  assert.equal(hosts.writes().filter((c) => c.key === "API_KEY" && c.host === "vercel").length, 1, "no retry");
  noCanary(applied);
});

test("a secret missing from 1Password is reported and skipped", async () => {
  const root = makeRoot();
  const hosts = fakeHosts();
  const values = { ...PROD };
  delete values["op://doddy-prod/token/credential"];
  const result = await run([], { root, hosts, secrets: fakeSecrets(values) });
  assert.match(result.out, /missing\s+TOKEN\s+not in 1Password \(op:\/\/doddy-prod\/token\/credential\)/);
});

test("a Vercel variable shared with preview is a conflict, and a Config-type one is flagged", async () => {
  const root = makeRoot();
  const hosts = fakeHosts({
    vercel: {
      web: [
        { key: "API_KEY", value: "x", target: ["production", "preview"] },
        { key: "TOKEN", value: "readable-config-value", type: "encrypted", target: ["production"] },
      ],
    },
  });
  const secrets = fakeSecrets(PROD);
  const dry = await run([], { root, hosts, secrets });
  assert.equal(dry.code, 1, "a conflict needs a person");
  assert.match(dry.out, /CONFLICT\s+API_KEY.*shared with production, preview/);
  assert.match(dry.out, /change\s+TOKEN.*stored as encrypted type, readable in the dashboard/);
  assert.ok(!dry.out.includes("readable-config-value"), "Config values from Vercel's list are dropped");
  const applied = await run(["--apply", "--confirm", planCode(dry.out)], { root, hosts, secrets });
  assert.ok(!hosts.writes().some((c) => c.host === "vercel" && c.key === "API_KEY"));
  assert.match(applied.out, /set\s+vercel:web\s+TOKEN/);
});

test("retired names are removed only with --prune", async () => {
  const root = makeRoot();
  const secrets = fakeSecrets(PROD);
  const hosts = fakeHosts({ vercel: { web: [{ key: "OLD_CODES", value: "codes", target: ["production"] }] }, render: { "srv-worker1": { OLD_CODES: "codes" } } });
  const plain = await run([], { root, hosts, secrets });
  assert.doesNotMatch(plain.out, /remove/);
  const dry = await run(["--prune"], { root, hosts, secrets });
  assert.match(dry.out, /remove\s+OLD_CODES/);
  assert.match(dry.out, /--apply --confirm [0-9a-f]{8} --prune/);
  const applied = await run(["--apply", "--prune", "--confirm", planCode(dry.out)], { root, hosts, secrets });
  assert.match(applied.out, /removed\s+render:worker\s+OLD_CODES/);
  assert.match(applied.out, /removed\s+vercel:web\s+OLD_CODES/);
  assert.equal(hosts.renderVars["srv-worker1"].OLD_CODES, undefined);
});

test("a plan code made without --prune doesn't authorise removals", async () => {
  const root = makeRoot();
  const secrets = fakeSecrets(PROD);
  const hosts = fakeHosts({ render: { "srv-worker1": { OLD_CODES: "codes" } } });
  const dry = await run([], { root, hosts, secrets });
  const applied = await run(["--apply", "--prune", "--confirm", planCode(dry.out)], { root, hosts, secrets });
  assert.equal(applied.code, 1);
  assert.equal(hosts.writes().length, 0);
});

test("development uses the dev vault and only Vercel; Render has no development environment", async () => {
  const root = makeRoot();
  const hosts = fakeHosts();
  const secrets = fakeSecrets({ "op://doddy-dev/api-key/credential": "dev-value-0123456789" });
  const result = await run(["--env", "development"], { root, hosts, secrets });
  assert.deepEqual(secrets.reads, ["op://doddy-dev/api-key/credential"]);
  assert.match(result.out, /vercel:web\n\s+add\s+API_KEY/);
  assert.doesNotMatch(result.out, /render/);
  const applied = await run(["--env", "development", "--apply", "--confirm", planCode(result.out)], { root, hosts, secrets });
  assert.equal(applied.code, 0, applied.out);
  assert.deepEqual(hosts.vercelEnvs.web[0].target, ["development"]);
});

test("filters narrow the plan to one target or one service", async () => {
  const root = makeRoot();
  const hosts = fakeHosts();
  const byTarget = await run(["--target", "render:worker"], { root, hosts, secrets: fakeSecrets(PROD) });
  assert.match(byTarget.out, /render:worker/);
  assert.doesNotMatch(byTarget.out, /vercel:web|render-group/);
  const byService = await run(["--service", "api"], { root, hosts, secrets: fakeSecrets(PROD) });
  assert.doesNotMatch(byService.out, /GROUP_KEY|ENC_KEY/);
});

test("without host credentials the targets are skipped, not guessed", async () => {
  const root = makeRoot();
  const hosts = fakeHosts();
  const result = await run([], { root, hosts, secrets: fakeSecrets(PROD), env: {} });
  assert.match(result.out, /skipped\s+API_KEY\s+no VERCEL_TOKEN in the environment/);
  assert.match(result.out, /skipped\s+API_KEY\s+no RENDER_API_KEY in the environment/);
  assert.equal(hosts.calls.length, 0);
});

test("a host that can't be listed turns its items into errors and nothing is written there", async () => {
  const root = makeRoot();
  const hosts = fakeHosts({ faults: [{ host: "render", method: "GET", status: 401 }] });
  const result = await run([], { root, hosts, secrets: fakeSecrets(PROD) });
  assert.equal(result.code, 1);
  assert.match(result.out, /ERROR\s+API_KEY\s+couldn't list \(HTTP 401\)/);
});

test("usage errors exit 2", async () => {
  const root = makeRoot();
  assert.equal((await run(["--env", "staging"], { root })).code, 2);
  assert.equal((await run(["--bogus"], { root })).code, 2);
  assert.equal((await run(["deploy"], { root })).code, 2);
  assert.equal((await run(["--target", "vercel:nope"], { root })).code, 2);
  assert.equal((await run(["--service", "nope"], { root })).code, 2);
  assert.equal((await run(["--help"], { root })).code, 0);
});

test("a manifest change after the dry run changes the code, so the old code is refused", async () => {
  const root = makeRoot();
  const hosts = fakeHosts();
  const dry = await run([], { root, hosts, secrets: fakeSecrets(PROD) });
  const changed = { ...PROD, "op://doddy-prod/token/credential": "a-new-token-0123456789" };
  const applied = await run(["--apply", "--confirm", planCode(dry.out)], { root, hosts, secrets: fakeSecrets(changed) });
  assert.equal(applied.code, 1);
  assert.equal(hosts.writes().length, 0);
});


test("the plan and the results themselves hold no values (not just the redacted output)", async () => {
  const { loadManifest } = await import("../lib/manifest.mjs");
  const { buildPlan, applyPlan } = await import("../lib/plan.mjs");
  const { vercelClient, renderClient } = await import("../lib/hosts.mjs");
  const { join } = await import("node:path");
  const root = makeRoot();
  const manifest = loadManifest(join(root, "secrets/manifest.json"), { root });
  const hosts = fakeHosts({ render: { "srv-worker1": { API_KEY: "old-value-0123456789" } }, faults: [{ host: "render", method: "PUT", key: "API_KEY", status: 400 }] });
  const clients = { vercel: vercelClient({ token: "t", teamId: "team_test", fetch: hosts.fetch }), render: renderClient({ apiKey: "k", fetch: hosts.fetch }) };
  const state = memoryState();
  const { plan, context } = await buildPlan({ manifest, env: "production", readSecret: fakeSecrets(PROD).readSecret, clients, state });
  assert.ok(!JSON.stringify(plan).includes(CANARY), "plan holds a value");
  const results = await applyPlan({ manifest, plan, context, confirm: plan.code, clients, state });
  assert.ok(!JSON.stringify(results).includes(CANARY), "results hold a value");
  assert.ok(!JSON.stringify(state.data).includes(CANARY), "state holds a value");
});
