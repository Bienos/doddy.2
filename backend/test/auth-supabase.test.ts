import assert from "node:assert/strict";
import { generateKeyPairSync, type KeyObject, sign } from "node:crypto";
import { afterEach, test } from "node:test";
import { AnyOfSessionVerifier, type FetchJson, SignedSessionVerifier, SupabaseSessionVerifier } from "../src/auth.js";
import { sessionVerifier } from "../src/app.js";
import { ConfigError, loadConfig } from "../src/config.js";
import { AppError } from "../src/errors.js";
import { CAL, type Harness, harness } from "./helpers.js";

// ADR-526: the backend accepts Supabase Auth sessions (Apple or Google sign-in).

const PROJECT = "https://abcdefghijklmnopqrst.supabase.co";
const ISSUER = `${PROJECT}/auth/v1`;
const USER = "5b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
const NOW = new Date("2026-10-19T10:00:00Z");
const NOW_S = Math.floor(NOW.getTime() / 1000);

const ec = generateKeyPairSync("ec", { namedCurve: "P-256" });
const other = generateKeyPairSync("ec", { namedCurve: "P-256" });
const rsa = generateKeyPairSync("rsa", { modulusLength: 2048 });
const weakRsa = generateKeyPairSync("rsa", { modulusLength: 1024 });

const jwk = (key: KeyObject, kid: string, alg: string) => ({ ...key.export({ format: "jwk" }), kid, alg, use: "sig" });
const b64 = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");

function token(
  claims: Record<string, unknown> = {},
  opts: { kid?: string; alg?: string; key?: KeyObject; rsa?: boolean } = {},
): string {
  const header = b64({ alg: opts.alg ?? (opts.rsa ? "RS256" : "ES256"), kid: opts.kid ?? "k1", typ: "JWT" });
  const body = b64({
    iss: ISSUER,
    aud: "authenticated",
    role: "authenticated",
    sub: USER,
    iat: NOW_S - 10,
    exp: NOW_S + 3600,
    is_anonymous: false,
    ...claims,
  });
  const data = Buffer.from(`${header}.${body}`);
  const signature = opts.rsa
    ? sign("RSA-SHA256", data, opts.key ?? rsa.privateKey)
    : sign("sha256", data, { key: opts.key ?? ec.privateKey, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${signature.toString("base64url")}`;
}

/** A fake JWKS endpoint that counts fetches and can fail. */
function jwks(keys: unknown[]) {
  const state = { keys, fetches: 0, fail: false, urls: [] as string[] };
  const fetchJson: FetchJson = async (url) => {
    state.fetches += 1;
    state.urls.push(url);
    if (state.fail) throw new Error("unreachable");
    return { keys: state.keys };
  };
  return { state, fetchJson };
}

const bearer = (t: string) => `Bearer ${t}`;

test("a valid Supabase session is accepted and names the Supabase user", async () => {
  const { state, fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256")]);
  const v = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson });
  assert.deepEqual(await v.verify(bearer(token()), NOW), { userId: USER });
  assert.deepEqual(state.urls, [`${ISSUER}/.well-known/jwks.json`]);
  assert.deepEqual(await v.verify(bearer(token()), NOW), { userId: USER });
  assert.equal(state.fetches, 1, "keys are cached");
});

test("expired, wrong project, wrong audience or role, anonymous and non-UUID users are refused", async () => {
  const { fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256")]);
  const v = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson });
  const refused: Record<string, Record<string, unknown>> = {
    expired: { exp: NOW_S },
    "other project": { iss: "https://zzzzzzzzzzzzzzzzzzzz.supabase.co/auth/v1" },
    "wrong audience": { aud: "anon" },
    "anon role": { role: "anon" },
    "service role": { role: "service_role" },
    anonymous: { is_anonymous: true },
    "email as user": { sub: "alice@example.com" },
    "issued in the future": { iat: NOW_S + 3600 },
    "no expiry": { exp: undefined },
  };
  for (const [name, claims] of Object.entries(refused)) {
    assert.equal(await v.verify(bearer(token(claims)), NOW), null, name);
  }
  assert.deepEqual(await v.verify(bearer(token({ aud: ["authenticated", "other"] })), NOW), { userId: USER }, "audience list");
});

test("forged, re-signed, algorithm-swapped and malformed tokens are refused", async () => {
  const { fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256"), jwk(rsa.publicKey, "r1", "RS256")]);
  const v = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson });
  const good = token();
  const [h, , s] = good.split(".") as [string, string, string];
  const forgedBody = b64({ iss: ISSUER, aud: "authenticated", role: "authenticated", sub: "00000000-0000-4000-8000-00000000000b", exp: NOW_S + 3600 });
  assert.equal(await v.verify(bearer(`${h}.${forgedBody}.${s}`), NOW), null, "claims changed");
  assert.equal(await v.verify(bearer(token({}, { key: other.privateKey })), NOW), null, "signed by another key");
  assert.equal(await v.verify(bearer(token({}, { alg: "HS256" })), NOW), null, "shared-secret algorithm");
  assert.equal(await v.verify(bearer(token({}, { alg: "none" })), NOW), null, "no algorithm");
  assert.equal(await v.verify(bearer(token({}, { kid: "r1" })), NOW), null, "ES256 token naming the RSA key");
  assert.deepEqual(await v.verify(bearer(token({}, { kid: "r1", rsa: true })), NOW), { userId: USER }, "RS256 works");
  for (const bad of [undefined, "", "Basic abc", "Bearer a.b", `Bearer ${good}.x`, `Bearer ${good} extra`]) {
    assert.equal(await v.verify(bad, NOW), null, String(bad));
  }
});

test("an owner token is not mistaken for a Supabase one, and fetches nothing", async () => {
  const { state, fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256")]);
  const v = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson });
  const owner = new SignedSessionVerifier(Buffer.alloc(32, 1)).mint(USER, NOW, 3600);
  assert.equal(await v.verify(bearer(owner), NOW), null);
  assert.equal(state.fetches, 0);
});

test("weak RSA keys and keys for other uses are never trusted", async () => {
  const { fetchJson } = jwks([jwk(weakRsa.publicKey, "w1", "RS256"), { ...jwk(ec.publicKey, "k1", "ES256"), use: "enc" }]);
  const v = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson });
  await assert.rejects(() => v.verify(bearer(token({}, { kid: "w1", rsa: true, key: weakRsa.privateKey })), NOW), AppError);
});

test("a rotated key is picked up; unknown key IDs refetch at most every 30 seconds", async () => {
  const { state, fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256")]);
  const v = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson });
  assert.ok(await v.verify(bearer(token()), NOW));
  state.keys = [jwk(ec.publicKey, "k1", "ES256"), jwk(other.publicKey, "k2", "ES256")];
  const later = new Date(NOW.getTime() + 31_000);
  assert.ok(await v.verify(bearer(token({}, { kid: "k2", key: other.privateKey })), later), "new key after rotation");
  assert.equal(state.fetches, 2);
  for (let i = 0; i < 5; i++) assert.equal(await v.verify(bearer(token({}, { kid: `junk${i}` })), later), null);
  assert.equal(state.fetches, 2, "junk key IDs don't hammer Supabase");
});

test("Supabase unreachable: a 'try again' error before any keys, the cached keys after", async () => {
  const { state, fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256")]);
  state.fail = true;
  const v = new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson });
  await assert.rejects(
    () => v.verify(bearer(token()), NOW),
    (e: unknown) => e instanceof AppError && e.code === "provider_unavailable" && /sign-in/.test(e.message),
  );
  state.fail = false;
  const later = new Date(NOW.getTime() + 31_000);
  assert.ok(await v.verify(bearer(token()), later));
  state.fail = true;
  const muchLater = new Date(NOW.getTime() + 60 * 60_000);
  assert.ok(await v.verify(bearer(token({ exp: NOW_S + 7200 })), muchLater), "stale keys still work while Supabase is down");
});

test("development accepts the owner's token next to Supabase sign-ins", async () => {
  const { fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256")]);
  const signed = new SignedSessionVerifier(Buffer.alloc(32, 1));
  const v = new AnyOfSessionVerifier([signed, new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson })]);
  const owner = "3f1c2a8e-1b2c-4d3e-8f90-123456789abc";
  assert.deepEqual(await v.verify(bearer(signed.mint(owner, NOW, 3600)), NOW), { userId: owner });
  assert.deepEqual(await v.verify(bearer(token()), NOW), { userId: USER });
  assert.equal(await v.verify("Bearer nope.nope.nope", NOW), null);
});

// ------------------------------------------------------------------ config

const KEY = Buffer.alloc(32, 7).toString("base64");
const live = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "supabase",
  SUPABASE_URL: PROJECT,
  DODDY_PUBLIC_BASE_URL: "https://doddy-dev.example.com",
  COMPOSIO_API_KEY: "ak_secret_value_123",
  COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID: "ac_123",
  COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: "20250909_00",
};
const problems = (env: Record<string, string>) => {
  try {
    loadConfig(env);
    return [];
  } catch (e) {
    assert.ok(e instanceof ConfigError);
    return e.problems;
  }
};

test("config: supabase mode needs the project's https origin", () => {
  assert.equal(loadConfig(live).supabaseUrl, PROJECT);
  assert.equal(loadConfig({ ...live, SUPABASE_URL: `${PROJECT}/` }).supabaseUrl, PROJECT);
  for (const bad of ["", "http://abcdefghijklmnopqrst.supabase.co", `${PROJECT}/auth/v1`, `${PROJECT}?x=1`, "https://user:pw@x.supabase.co", "not a url"]) {
    assert.ok(problems({ ...live, SUPABASE_URL: bad }).some((p) => p.includes("SUPABASE_URL")), bad);
  }
});

test("config: production live mode needs Supabase sign-in, and never takes owner tokens", () => {
  assert.ok(problems({ ...live, DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: KEY, DODDY_ENV: "production" }).some((p) => p.includes("production")));
  const prod = loadConfig({ ...live, DODDY_ENV: "production", DATABASE_URL: "postgres://u:p@db.example.com:5432/postgres", DODDY_SESSION_SIGNING_KEY: KEY });
  assert.equal(prod.authMode, "supabase");
  assert.equal(prod.sessionSigningKey, null, "owner tokens are off in production");
  assert.ok(!(sessionVerifier(prod) instanceof AnyOfSessionVerifier));
  const dev = loadConfig({ ...live, DODDY_SESSION_SIGNING_KEY: KEY });
  assert.ok(dev.sessionSigningKey);
  assert.ok(sessionVerifier(dev) instanceof AnyOfSessionVerifier);
  assert.ok(problems({ ...live, DODDY_SESSION_SIGNING_KEY: "short" }).some((p) => p.includes("DODDY_SESSION_SIGNING_KEY")));
});

// ------------------------------------------------------------------ over HTTP

let h: Harness | undefined;
afterEach(async () => h?.close());

test("over HTTP: a Supabase session reaches the API; none is 401; Supabase down is 502 'try again'", async () => {
  const { state, fetchJson } = jwks([jwk(ec.publicKey, "k1", "ES256")]);
  h = await harness({ verifier: new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson }), nowIso: "2026-10-19T10:00:00Z" });
  const ok = await h.call("GET", CAL, { token: token() });
  assert.equal(ok.status, 200);
  assert.equal((await h.call("GET", CAL, { token: null })).status, 401);
  assert.equal((await h.call("GET", CAL, { token: token({ exp: NOW_S - 1 }) })).status, 401);
  await h.close();

  state.fail = true;
  h = await harness({ verifier: new SupabaseSessionVerifier({ projectUrl: PROJECT, fetchJson }), nowIso: "2026-10-19T10:00:00Z" });
  const down = await h.call("GET", CAL, { token: token() });
  assert.equal(down.status, 502);
  assert.match(down.body.error.message, /couldn't check your sign-in/);
});
