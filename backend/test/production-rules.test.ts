import assert from "node:assert/strict";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { generateKeyPairSync, type KeyObject, sign } from "node:crypto";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { buildApp, sessionVerifier } from "../src/app.js";
import { AccountSessionOrSupabaseVerifier, AnyOfSessionVerifier, type FetchJson, SignedSessionVerifier, SupabaseSessionVerifier } from "../src/auth.js";
import { appliesProductionRules, ConfigError, loadConfig, type ProductionRuleFacts, productionRuleProblems } from "../src/config.js";
import { deviceUserId } from "../src/deviceSession.js";
import { DocumentLinks } from "../src/documents.js";
import { SigningKeys } from "../src/signingKeys.js";
import { listeningLine, notStartingLines } from "../src/startLine.js";
import { Store } from "../src/store.js";

/**
 * The start-up check "live on a public host means production rules" (decision
 * 2026-11-12-account-and-device-tokens, part a), and what a production server still serves:
 * account sessions, file links and the proof of an iPhone's earlier data, with the keys derived from
 * DODDY_SESSION_SIGNING_KEY, and nothing else that key used to allow in development.
 *
 * Every key, token, password and code here is an obviously fake test value.
 */

const KEY = Buffer.alloc(32, 7);
const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const FAKE_DB_PASSWORD = "fake-db-password-not-real";
const FAKE_INVITE_CODE = "fake-invite-code-not-real";
const FAKE_MONID_KEY = "monid_live_notreal1234";
const ACCOUNT = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const ACCOUNT_2 = "6c1d9a8f-3b52-4d4e-8f70-123456789abc";
const OWNER = "3f1c2a8e-1b2c-4d3e-8f90-123456789abc";
const PHONE = (n: number) => `1b4e28ba-2fa1-41d2-883f-${String(n).padStart(12, "0")}`;
const WHERE = "DODDY_MODE=live and DODDY_HOST is not loopback";

// ------------------------------------------------------------------ the rules, on the resolved settings

const CLEAN_FACTS: ProductionRuleFacts = {
  mode: "live",
  host: "0.0.0.0",
  env: "production",
  authMode: "supabase",
  ownerTokensBesideSupabase: false,
  deviceSignup: "off",
  deviceInviteCodes: 0,
  ownerClaim: "closed",
  completionMode: "verifier",
};

/** One deviation from a clean server per rule, and the setting its line has to name. */
const RULES: readonly { name: string; deviation: Partial<ProductionRuleFacts>; setting: string }[] = [
  { name: "an environment other than production (development)", deviation: { env: "development" }, setting: "DODDY_ENV" },
  { name: "an environment other than production (test)", deviation: { env: "test" }, setting: "DODDY_ENV" },
  { name: "owner-minted tokens as the only sign-in", deviation: { authMode: "signed" }, setting: "DODDY_AUTH_MODE" },
  { name: "owner-minted tokens beside Supabase", deviation: { ownerTokensBesideSupabase: true }, setting: "DODDY_SESSION_SIGNING_KEY" },
  { name: "device sign-in for the first iPhone", deviation: { deviceSignup: "first-device" }, setting: "DODDY_DEVICE_SIGNUP" },
  { name: "device sign-in open to everyone, guests included", deviation: { deviceSignup: "open" }, setting: "DODDY_DEVICE_SIGNUP" },
  { name: "device sign-in by invite codes", deviation: { deviceInviteCodes: 2 }, setting: "DODDY_DEVICE_INVITE_CODES" },
  { name: "an open owner claim", deviation: { ownerClaim: "open" }, setting: "DODDY_OWNER_CLAIM" },
  { name: "completion by callback", deviation: { completionMode: "callback" }, setting: "COMPOSIO_COMPLETION_MODE" },
];

test("rules: a clean live server on a public host has nothing to fix", () => {
  assert.deepEqual(productionRuleProblems(CLEAN_FACTS), []);
});

test("rules: each of the six settings alone refuses, naming the setting and not its value", () => {
  for (const rule of RULES) {
    const found = productionRuleProblems({ ...CLEAN_FACTS, ...rule.deviation });
    assert.equal(found.length, 1, `${rule.name}: ${found.join(" | ")}`);
    assert.ok(found[0]!.startsWith(rule.setting) || found[0]!.includes(rule.setting), `${rule.name} names ${rule.setting}: ${found[0]}`);
    assert.ok(found[0]!.includes(WHERE), `${rule.name} says where it applies: ${found[0]}`);
  }
});

test("rules: whatever DODDY_ENV says, the settings are refused on a live public host", () => {
  for (const env of ["development", "test", "production"] as const) {
    for (const rule of RULES.filter((r) => r.deviation.env === undefined)) {
      const found = productionRuleProblems({ ...CLEAN_FACTS, env, ...rule.deviation });
      assert.ok(found.some((p) => p.includes(rule.setting)), `${rule.name} under ${env}`);
    }
  }
});

test("rules: every problem on its own, one line each, and no value in any of them", () => {
  const everything = productionRuleProblems({
    ...CLEAN_FACTS,
    env: "development",
    authMode: "signed",
    ownerTokensBesideSupabase: true,
    deviceSignup: "open",
    deviceInviteCodes: 3,
    ownerClaim: "open",
    completionMode: "callback",
  });
  assert.equal(everything.length, 7, everything.join("\n"));
  for (const line of everything) {
    assert.ok(!line.includes("\n"), "one line per problem");
    assert.ok(!/=(signed|development|first-device|open|callback)\b/.test(line), `no offending value in: ${line}`);
  }
  for (const setting of ["DODDY_ENV", "DODDY_AUTH_MODE", "DODDY_SESSION_SIGNING_KEY", "DODDY_DEVICE_SIGNUP", "DODDY_DEVICE_INVITE_CODES", "DODDY_OWNER_CLAIM", "COMPOSIO_COMPLETION_MODE"]) {
    assert.equal(everything.filter((p) => p.includes(setting)).length >= 1, true, setting);
  }
});

test("rules: they apply only to a live server on a host that is not loopback", () => {
  const worst: Partial<ProductionRuleFacts> = {
    env: "development",
    authMode: "signed",
    ownerTokensBesideSupabase: true,
    deviceSignup: "open",
    deviceInviteCodes: 3,
    ownerClaim: "open",
    completionMode: "callback",
  };
  for (const host of ["127.0.0.1", "::1", "localhost"]) {
    assert.deepEqual(productionRuleProblems({ ...CLEAN_FACTS, ...worst, host }), [], `loopback ${host}`);
    assert.equal(appliesProductionRules("live", host), false, host);
  }
  assert.deepEqual(productionRuleProblems({ ...CLEAN_FACTS, ...worst, mode: "mock" }), [], "mock mode");
  assert.equal(appliesProductionRules("mock", "0.0.0.0"), false);
  for (const host of ["0.0.0.0", "::", "10.0.0.5", "doddy.example.test"]) {
    assert.equal(appliesProductionRules("live", host), true, host);
    assert.ok(productionRuleProblems({ ...CLEAN_FACTS, ...worst, host }).length > 0, host);
  }
});

// ------------------------------------------------------------------ the rules, through loadConfig

const CLEAN_ENV = {
  DODDY_MODE: "live",
  DODDY_ENV: "production",
  DODDY_HOST: "0.0.0.0",
  DODDY_AUTH_MODE: "supabase",
  SUPABASE_URL: PROJECT,
  DODDY_SESSION_SIGNING_KEY: KEY.toString("base64"),
  DODDY_PUBLIC_BASE_URL: "https://doddy.example.test",
  DATABASE_URL: `postgres://doddy:${FAKE_DB_PASSWORD}@db.example.test/doddy`,
  MONID_API_KEY: FAKE_MONID_KEY,
};

const problems = (env: Record<string, string>): string[] => {
  try {
    loadConfig(env);
    return [];
  } catch (e) {
    assert.ok(e instanceof ConfigError, "a config problem is always a ConfigError");
    return e.problems;
  }
};
const ofRules = (list: string[]) => list.filter((p) => p.includes("is not loopback"));

test("config: a clean production config loads on a public host", () => {
  const c = loadConfig(CLEAN_ENV);
  assert.equal(c.env, "production");
  assert.equal(c.ownerClaim, "closed");
  assert.equal(c.deviceSignup, "off");
  assert.deepEqual(c.deviceInviteCodes, []);
});

test("config: DODDY_ENV other than production is refused on its own", () => {
  // Without the signing key nothing else is wrong, so this is the one line.
  for (const env of ["development", "test"]) {
    const found = problems({ ...CLEAN_ENV, DODDY_ENV: env, DODDY_SESSION_SIGNING_KEY: "" });
    assert.equal(found.length, 1, found.join(" | "));
    assert.ok(found[0]!.includes("DODDY_ENV") && found[0]!.includes(WHERE));
  }
});

test("config: owner-minted tokens as the only sign-in are refused", () => {
  const found = problems({ ...CLEAN_ENV, DODDY_AUTH_MODE: "signed" });
  assert.ok(found.some((p) => p.includes("DODDY_AUTH_MODE") && p.includes(WHERE)), found.join(" | "));
  const inDevelopment = problems({ ...CLEAN_ENV, DODDY_ENV: "development", DODDY_AUTH_MODE: "signed" });
  assert.ok(inDevelopment.some((p) => p.includes("DODDY_AUTH_MODE") && p.includes(WHERE)), inDevelopment.join(" | "));
});

test("config: owner-minted tokens beside Supabase are refused (with the key set, development is where they would be accepted)", () => {
  const found = problems({ ...CLEAN_ENV, DODDY_ENV: "development" });
  assert.ok(found.some((p) => p.includes("beside Supabase") && p.includes(WHERE)), found.join(" | "));
  assert.ok(found.some((p) => p.includes("DODDY_ENV")), "and the environment is named too");
  // Production with the same key is the supported shape, and takes no owner tokens (below).
  assert.deepEqual(ofRules(problems(CLEAN_ENV)), []);
});

test("config: device sign-in is refused, by DODDY_DEVICE_SIGNUP and by invite codes, each by its own line", () => {
  for (const signup of ["first-device", "open"]) {
    const found = problems({ ...CLEAN_ENV, DODDY_DEVICE_SIGNUP: signup });
    assert.ok(found.some((p) => p.includes("DODDY_DEVICE_SIGNUP") && p.includes(WHERE)), found.join(" | "));
  }
  const codes = problems({ ...CLEAN_ENV, DODDY_DEVICE_INVITE_CODES: FAKE_INVITE_CODE });
  assert.ok(codes.some((p) => p.includes("DODDY_DEVICE_INVITE_CODES") && p.includes(WHERE)), codes.join(" | "));
  assert.ok(!codes.join(" ").includes(FAKE_INVITE_CODE), "the code is never printed");
  // An empty value is not a code.
  assert.deepEqual(ofRules(problems({ ...CLEAN_ENV, DODDY_DEVICE_INVITE_CODES: " , " })), []);
});

test("config: an open owner claim is refused on its own", () => {
  const found = problems({ ...CLEAN_ENV, DODDY_OWNER_CLAIM: "open" });
  assert.equal(found.length, 1, found.join(" | "));
  assert.ok(found[0]!.includes("DODDY_OWNER_CLAIM") && found[0]!.includes(WHERE));
  assert.deepEqual(problems({ ...CLEAN_ENV, DODDY_OWNER_CLAIM: "closed" }), []);
});

test("config: completion by callback is refused on its own, by one line", () => {
  const found = problems({ ...CLEAN_ENV, COMPOSIO_COMPLETION_MODE: "callback" });
  assert.equal(found.length, 1, found.join(" | "));
  assert.ok(found[0]!.includes("COMPOSIO_COMPLETION_MODE") && found[0]!.includes(WHERE));
  assert.ok(!found[0]!.includes("callback"), "the value is not printed");
  assert.deepEqual(problems({ ...CLEAN_ENV, COMPOSIO_COMPLETION_MODE: "verifier" }), []);
});

test("config: the same settings do not refuse when the server is not live, or the host is loopback", () => {
  const bad = { DODDY_ENV: "development", DODDY_DEVICE_SIGNUP: "open", DODDY_DEVICE_INVITE_CODES: FAKE_INVITE_CODE, DODDY_OWNER_CLAIM: "open", COMPOSIO_COMPLETION_MODE: "callback" };
  for (const host of ["127.0.0.1", "::1", "localhost"]) {
    assert.deepEqual(ofRules(problems({ ...CLEAN_ENV, ...bad, DODDY_HOST: host })), [], host);
    // Development on a loopback host with the owner's tokens still loads, as before.
    assert.equal(
      problems({ ...CLEAN_ENV, DODDY_ENV: "development", DODDY_AUTH_MODE: "signed", DODDY_HOST: host, DODDY_DEVICE_SIGNUP: "open", DODDY_OWNER_CLAIM: "open", COMPOSIO_COMPLETION_MODE: "callback" }).length,
      0,
      host,
    );
  }
  // Mock mode on a public host: the demo server is not the live service.
  assert.deepEqual(ofRules(problems({ DODDY_MODE: "mock", DODDY_HOST: "0.0.0.0", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: CLEAN_ENV.DODDY_SESSION_SIGNING_KEY, DODDY_DEVICE_SIGNUP: "open" })), []);
});

test("config: no key, password or code is in any problem, and the settings of a refused config are named once", () => {
  const found = problems({
    ...CLEAN_ENV,
    DODDY_ENV: "development",
    DODDY_AUTH_MODE: "signed",
    DODDY_DEVICE_SIGNUP: "open",
    DODDY_DEVICE_INVITE_CODES: FAKE_INVITE_CODE,
    DODDY_OWNER_CLAIM: "open",
    COMPOSIO_COMPLETION_MODE: "callback",
  });
  const all = found.join("\n");
  for (const secret of [CLEAN_ENV.DODDY_SESSION_SIGNING_KEY, FAKE_DB_PASSWORD, FAKE_INVITE_CODE, FAKE_MONID_KEY]) assert.ok(!all.includes(secret), "no secret in a problem");
  for (const setting of ["DODDY_ENV", "DODDY_AUTH_MODE", "DODDY_DEVICE_SIGNUP", "DODDY_DEVICE_INVITE_CODES", "DODDY_OWNER_CLAIM", "COMPOSIO_COMPLETION_MODE"]) {
    assert.equal(found.filter((p) => p.includes(setting) && p.includes("is not loopback")).length, 1, `${setting} once`);
  }
  // The callback setting has no second line from the older check.
  assert.equal(found.filter((p) => p.includes("COMPOSIO_COMPLETION_MODE")).length, 1, found.join(" | "));
});

// ------------------------------------------------------------------ the start-up output

test("start-up output: one line per problem, each saying it is not starting", () => {
  const text = notStartingLines(["first problem", "second problem"]);
  assert.deepEqual(text.split("\n"), ["Not starting. first problem", "Not starting. second problem"]);
  assert.equal(notStartingLines([]), "");
});

test("start-up line: says whether production rules apply (a flag, never a value)", () => {
  const live = { host: "0.0.0.0", port: 10000, mode: "live", authMode: "supabase", env: "production", web: null, ownerClaim: "closed" } as const;
  assert.equal(JSON.parse(listeningLine(live, "postgres", {})).productionRules, true);
  assert.equal(JSON.parse(listeningLine({ ...live, host: "127.0.0.1" }, "postgres", {})).productionRules, false);
  assert.equal(JSON.parse(listeningLine({ ...live, mode: "mock" }, "memory", {})).productionRules, false);
});

/** Runs the real `server.js` and returns how it ended. Only for configs that are refused before anything is opened. */
async function refused(settings: Record<string, string>): Promise<{ code: number | null; stdout: string; stderr: string }> {
  const child = spawn(process.execPath, [new URL("../src/server.js", import.meta.url).pathname], {
    env: { PATH: process.env.PATH ?? "", DODDY_DB_PATH: ":memory:", ...settings },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (c: Buffer) => (stdout += c.toString("utf8")));
  child.stderr.on("data", (c: Buffer) => (stderr += c.toString("utf8")));
  const timer = setTimeout(() => child.kill("SIGKILL"), 30_000);
  const [code] = (await once(child, "exit")) as [number | null];
  clearTimeout(timer);
  return { code, stdout, stderr };
}

test("the real server refuses to start with every rule broken: one line per setting, exit code not zero, no value", async () => {
  const ended = await refused({
    ...CLEAN_ENV,
    DODDY_ENV: "development",
    DODDY_AUTH_MODE: "signed",
    DODDY_DEVICE_SIGNUP: "open",
    DODDY_DEVICE_INVITE_CODES: FAKE_INVITE_CODE,
    DODDY_OWNER_CLAIM: "open",
    COMPOSIO_COMPLETION_MODE: "callback",
    DODDY_PORT: "1",
  });
  assert.notEqual(ended.code, 0);
  assert.notEqual(ended.code, null);
  assert.ok(!ended.stdout.includes("listening"), "it never listened");
  const lines = ended.stderr.split("\n").filter((l) => l !== "");
  assert.ok(lines.length >= 6, ended.stderr);
  for (const line of lines) assert.ok(line.startsWith("Not starting. "), line);
  for (const setting of ["DODDY_ENV", "DODDY_AUTH_MODE", "DODDY_DEVICE_SIGNUP", "DODDY_DEVICE_INVITE_CODES", "DODDY_OWNER_CLAIM", "COMPOSIO_COMPLETION_MODE"]) {
    assert.equal(lines.filter((l) => l.includes(setting) && l.includes("is not loopback")).length, 1, `${setting}: ${ended.stderr}`);
  }
  for (const secret of [CLEAN_ENV.DODDY_SESSION_SIGNING_KEY, FAKE_DB_PASSWORD, FAKE_INVITE_CODE, FAKE_MONID_KEY]) {
    assert.ok(!ended.stderr.includes(secret) && !ended.stdout.includes(secret), "no secret in the output");
  }
  assert.ok(!/=(signed|development|open|callback)\b/.test(ended.stderr), "no setting is printed with its value");
});

// ------------------------------------------------------------------ what a production server serves

const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const jwks: FetchJson = async () => ({ keys: [{ ...ec.publicKey.export({ format: "jwk" }), kid: "k1", alg: "ES256", use: "sig" }] });
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");

/** A Supabase access token signed with the test project's key. */
function account(sub: string, key: KeyObject = ec.privateKey): string {
  const nowS = Math.floor(Date.now() / 1000);
  const header = b64({ alg: "ES256", kid: "k1", typ: "JWT" });
  const body = b64({
    iss: ISSUER,
    aud: "authenticated",
    role: "authenticated",
    sub,
    iat: nowS - 10,
    exp: nowS + 3600,
    is_anonymous: false,
    app_metadata: { provider: "google", providers: ["google"] },
    amr: [{ method: "oauth", timestamp: nowS - 10 }],
  });
  const signature = sign("sha256", Buffer.from(`${header}.${body}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${signature.toString("base64url")}`;
}

/** The settings a production server runs with, on the loopback host a test can listen on. */
const PRODUCTION_ENV = {
  DODDY_MODE: "live",
  DODDY_ENV: "production",
  DODDY_AUTH_MODE: "supabase",
  SUPABASE_URL: PROJECT,
  DODDY_SESSION_SIGNING_KEY: KEY.toString("base64"),
  DODDY_PUBLIC_BASE_URL: "https://doddy.example.test",
  DATABASE_URL: `postgres://doddy:${FAKE_DB_PASSWORD}@db.example.test/doddy`,
  DODDY_WEB_ORIGIN: "http://127.0.0.1:8787",
  DODDY_MEMORY_KEY: Buffer.alloc(32, 9).toString("base64"),
  MONID_API_KEY: FAKE_MONID_KEY,
};

const servers: Server[] = [];
const closers: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const s of servers.splice(0)) s.close();
  for (const c of closers.splice(0)) await c();
});

async function production(env: Record<string, string> = {}) {
  const config = loadConfig({ ...PRODUCTION_ENV, ...env });
  const store = await Store.open({ dataDir: ":memory:" });
  const built = await buildApp(config, { store, webSearch: null, supabaseFetchJson: jwks });
  built.server.listen(0, "127.0.0.1");
  await once(built.server, "listening");
  servers.push(built.server);
  closers.push(() => store.close());
  const base = `http://127.0.0.1:${(built.server.address() as AddressInfo).port}`;
  const call = async (method: string, path: string, authorization?: string, body?: unknown) => {
    const headers: Record<string, string> = {};
    if (authorization) headers.authorization = `Bearer ${authorization}`;
    if (body !== undefined) headers["content-type"] = "application/json";
    const res = await fetch(`${base}${path}`, { method, headers, ...(body !== undefined ? { body: JSON.stringify(body) } : {}) });
    const text = await res.text();
    return { status: res.status, body: text ? (JSON.parse(text) as any) : null, text };
  };
  const exchange = (supabaseToken: string | undefined, deviceId: unknown = PHONE(1)) => call("POST", "/v1/session/account", supabaseToken, { deviceId });
  const signedIn = async (sub: string, deviceId = PHONE(1)) => {
    const res = await exchange(account(sub), deviceId);
    assert.equal(res.status, 200, res.text);
    return res.body as { token: string; expiresAt: string; access: "full"; deviceListId: string };
  };
  /** An everyday route that needs a signed-in person. */
  const everyday = (token: string | undefined) => call("GET", "/v1/tools/receipts", token);
  return { config, store, call, exchange, signedIn, everyday, base };
}

const signer = new SignedSessionVerifier(KEY);
const NOW = () => new Date();

test("production: loads the signing key for account sessions, file links and the link proof only", () => {
  const prod = loadConfig(PRODUCTION_ENV);
  assert.equal(prod.signingKeys, null, "the keys of owner-minted and device tokens are not loaded");
  assert.ok(prod.accountKeys, "the keys of account sessions, file links and the link proof are");
  assert.ok(prod.identifierKey, "an account session's iPhone row is derived with the identifier key");
  assert.equal(prod.deviceSignup, "off");
  // Development keeps one keyring for everything, as before.
  const dev = loadConfig({ ...PRODUCTION_ENV, DODDY_ENV: "development", DODDY_HOST: "127.0.0.1" });
  assert.ok(dev.signingKeys);
  assert.equal(dev.accountKeys, dev.signingKeys);
  // The mock demo has neither.
  assert.equal(loadConfig({}).accountKeys, null);
  // Without the key, production is what it was: nothing to sign with.
  const none = loadConfig({ ...PRODUCTION_ENV, DODDY_SESSION_SIGNING_KEY: "" });
  assert.equal(none.accountKeys, null);
  assert.equal(none.signingKeys, null);
  assert.equal(none.identifierKey, null);
});

test("production: the key is checked as it is in development, and a rotation works the same way", () => {
  const short = problems({ ...PRODUCTION_ENV, DODDY_SESSION_SIGNING_KEY: Buffer.alloc(8).toString("base64") });
  assert.ok(short.some((p) => p.includes("DODDY_SESSION_SIGNING_KEY")), short.join(" | "));
  const previous = Buffer.alloc(32, 5).toString("base64");
  const needsIdentifier = problems({ ...PRODUCTION_ENV, DODDY_SESSION_SIGNING_KEY_PREVIOUS: previous });
  assert.ok(needsIdentifier.some((p) => p.includes("DODDY_IDENTIFIER_KEY")), needsIdentifier.join(" | "));
  const rotating = loadConfig({ ...PRODUCTION_ENV, DODDY_SESSION_SIGNING_KEY_PREVIOUS: previous, DODDY_IDENTIFIER_KEY: previous });
  assert.equal(rotating.accountKeys?.hasPrevious, true);
  assert.equal(rotating.signingKeys, null);
  assert.equal(JSON.parse(listeningLine(rotating, "postgres", {})).signingKeyPrevious, true, "the log says a previous key is held");
  assert.ok(![needsIdentifier, short].flat().join(" ").includes(previous), "no key in a problem");
});

test("production: the verifier takes a Doddy account's own sign-in and its session, and nothing an owner or a device could hold", async () => {
  const config = loadConfig(PRODUCTION_ENV);
  const verifier = sessionVerifier(config, new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson: jwks }));
  assert.ok(verifier instanceof AccountSessionOrSupabaseVerifier);
  assert.ok(!(verifier instanceof AnyOfSessionVerifier), "never the owner-token verifier");
  const now = NOW();
  const row = "00000000-0000-4000-8000-000000000042";
  const asAccount = signer.mintAccount(ACCOUNT, row, now, 3600);
  assert.deepEqual(await verifier.verify(`Bearer ${asAccount}`, now), { userId: ACCOUNT, deviceId: row, account: ACCOUNT });
  assert.deepEqual(await verifier.verify(`Bearer ${account(ACCOUNT)}`, now), { userId: ACCOUNT });
  const phoneUser = deviceUserId(KEY, PHONE(1));
  for (const [name, token] of [
    ["an owner-minted token", signer.mint(OWNER, now, 3600)],
    ["an earlier device session", signer.mint(phoneUser, now, 3600)],
    ["a device session of a stored iPhone", signer.mint(phoneUser, now, 3600, undefined, row)],
    ["a guest's session", signer.mint(phoneUser, now, 3600, "ask")],
    ["a session signed with another key", new SignedSessionVerifier(Buffer.alloc(32, 8)).mintAccount(ACCOUNT, row, now, 3600)],
  ] as const) {
    assert.equal(await verifier.verify(`Bearer ${token}`, now), null, name);
  }
  assert.equal(await verifier.verify(undefined, now), null);
  assert.equal(await verifier.verify("Bearer ds1.not.real", now), null);
});

test("production: the account-session route is served, and its session works on everyday routes", async () => {
  const d = await production();
  const first = await d.signedIn(ACCOUNT);
  assert.match(first.token, /^ds1\./);
  assert.equal((await d.everyday(first.token)).status, 200, "the session is the account's on the routes the app uses");
  assert.equal((await d.everyday(account(ACCOUNT))).status, 200, "the Supabase token still is too");
  // Another account's session reaches nothing of this one's: its rows are its own.
  const second = await d.signedIn(ACCOUNT_2, PHONE(2));
  assert.equal((await d.everyday(second.token)).status, 200);
  assert.notEqual(first.deviceListId, second.deviceListId);
  // A refused Supabase token, or none, gets nothing.
  assert.equal((await d.exchange(account(ACCOUNT, generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey))).status, 401);
  assert.equal((await d.exchange(undefined)).status, 401);
  // The sign-out of an iPhone ends its session at once, as in development.
  const gone = await d.call("DELETE", `/v1/web/devices/${first.deviceListId}`, first.token);
  assert.equal(gone.status, 200, gone.text);
  assert.equal((await d.everyday(first.token)).status, 401);
});

test("production: owner-minted tokens and device sessions are refused everywhere, and there is no device sign-in", async () => {
  const d = await production();
  const now = NOW();
  const phoneUser = deviceUserId(KEY, PHONE(1));
  const row = "00000000-0000-4000-8000-000000000042";
  for (const [name, token] of [
    ["owner-minted", signer.mint(OWNER, now, 3600)],
    ["earlier device session", signer.mint(phoneUser, now, 3600)],
    ["stored device session", signer.mint(phoneUser, now, 3600, undefined, row)],
    ["guest session", signer.mint(phoneUser, now, 3600, "ask")],
  ] as const) {
    assert.equal((await d.everyday(token)).status, 401, `${name} on a tool route`);
    assert.equal((await d.call("GET", "/v1/web/devices", token)).status, 401, `${name} on the device list`);
    assert.equal((await d.call("POST", "/v1/assist", token, { question: "hello" })).status, 401, `${name} on Ask Doddy`);
  }
  // The device sign-in route is not there, with a guest's body or an invite code in it, and it stores nothing.
  const guest = await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) });
  assert.equal(guest.status, 404, guest.text);
  const invited = await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1), inviteCode: FAKE_INVITE_CODE });
  assert.equal(invited.status, 404, invited.text);
  assert.equal((await d.store.db.query("SELECT 1 FROM devices")).rows.length, 0);
  assert.equal((await d.store.db.query("SELECT 1 FROM device_owner")).rows.length, 0, "nobody can claim an empty server");
});

test("production: file links open with the file-link key, and a link made by another key does not", async () => {
  const d = await production();
  const owner = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
  const id = await d.store.startDocument(owner, "a.pdf", "application/pdf", Date.now());
  await d.store.finishDocument(owner, id, "a.pdf", "application/pdf", Buffer.from("%PDF-fake"));
  const links = new DocumentLinks(new SigningKeys(KEY), "https://doddy.example.test");
  const opens = new URL(links.link(id, owner, NOW()));
  const served = await d.call("GET", `${opens.pathname}${opens.search}&status=1`);
  assert.equal(served.status, 200, served.text);
  assert.deepEqual(served.body, { status: "ready" });
  const file = await fetch(`${d.base}${opens.pathname}${opens.search}`);
  assert.equal(file.status, 200);
  assert.equal(await file.text(), "%PDF-fake");
  const foreign = new URL(new DocumentLinks(new SigningKeys(Buffer.alloc(32, 8)), "https://doddy.example.test").link(id, owner, NOW()));
  assert.deepEqual((await d.call("GET", `${foreign.pathname}${foreign.search}&status=1`)).body, { status: "gone" }, "another key's link opens nothing");
  assert.deepEqual((await d.call("GET", `${opens.pathname}?exp=${opens.searchParams.get("exp")}&sig=${"A".repeat(51)}&status=1`)).body, { status: "gone" });
});

test("production: an iPhone's earlier device session still proves its earlier data, and is refused everywhere else", async () => {
  const d = await production();
  const now = NOW();
  const phoneUser = deviceUserId(KEY, PHONE(1));
  const earlier = signer.mint(phoneUser, now, 3600);
  await d.store.db.query("INSERT INTO tool_switches (user_id, tool, enabled, changed_at) VALUES ($1, $2, 1, 1)", [phoneUser, "check_email"]);
  assert.equal((await d.everyday(earlier)).status, 401, "it signs in to nothing");
  const started = await d.call("POST", "/v1/account/link-device/start", earlier);
  assert.equal(started.status, 200, started.text);
  const linked = await d.call("POST", "/v1/account/link-device", account(ACCOUNT), { linkCode: started.body.linkCode });
  assert.equal(linked.status, 200, linked.text);
  const mapped = (await d.store.db.query<{ subject: string; user_id: string }>("SELECT subject, user_id FROM account_links")).rows;
  assert.deepEqual(mapped, [{ subject: ACCOUNT, user_id: phoneUser }]);
  // The account's own session now works on that data.
  const session = await d.signedIn(ACCOUNT);
  assert.equal((await d.everyday(session.token)).status, 200);
  // An account session is not an iPhone's earlier sign-in: it has nothing to hand over.
  assert.equal((await d.call("POST", "/v1/account/link-device/start", session.token)).status, 401);
  // And with no token, nothing starts.
  assert.equal((await d.call("POST", "/v1/account/link-device/start", undefined)).status, 401);
});

test("production without the signing key is what it was: no account sessions, no file links, no device sign-in", async () => {
  const d = await production({ DODDY_SESSION_SIGNING_KEY: "" });
  assert.equal(d.config.accountKeys, null);
  assert.equal((await d.exchange(account(ACCOUNT))).status, 404);
  assert.equal((await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1) })).status, 404);
  assert.equal((await d.everyday(account(ACCOUNT))).status, 200, "Supabase sign-in is all there is");
  assert.equal((await d.everyday(signer.mint(OWNER, NOW(), 3600))).status, 401);
  const link = new URL(new DocumentLinks(new SigningKeys(KEY), "https://doddy.example.test").link("abcdefghijklmnopqrstuvwx", OWNER, NOW()));
  assert.equal((await d.call("GET", `${link.pathname}${link.search}&status=1`)).body?.status, undefined, "no file route at all");
});

test("production: nothing the server writes to its log carries a key, a token or a password", async () => {
  const lines: string[] = [];
  const original = process.stdout.write.bind(process.stdout);
  process.stdout.write = ((chunk: string | Uint8Array, ...rest: unknown[]) => {
    const text = typeof chunk === "string" ? chunk : Buffer.from(chunk).toString("utf8");
    if (text.startsWith("{")) lines.push(text);
    return (original as (...args: unknown[]) => boolean)(chunk, ...rest);
  }) as typeof process.stdout.write;
  let sessionToken = "";
  const owner = signer.mint(OWNER, NOW(), 3600);
  try {
    const d = await production();
    sessionToken = (await d.signedIn(ACCOUNT)).token;
    await d.everyday(owner);
    await d.everyday(sessionToken);
    await d.call("POST", "/v1/session/device", undefined, { deviceId: PHONE(1), inviteCode: FAKE_INVITE_CODE });
    await new Promise((resolve) => setTimeout(resolve, 50));
  } finally {
    process.stdout.write = original as typeof process.stdout.write;
  }
  const logged = lines.join("");
  assert.ok(logged.length > 0, "the access lines were captured");
  for (const secret of [PRODUCTION_ENV.DODDY_SESSION_SIGNING_KEY, FAKE_DB_PASSWORD, FAKE_INVITE_CODE, FAKE_MONID_KEY, owner, sessionToken, account(ACCOUNT).split(".")[2]!, PRODUCTION_ENV.DODDY_MEMORY_KEY]) {
    assert.ok(!logged.includes(secret), "no secret in the log");
  }
});
