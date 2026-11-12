// Accounts and quotas (decision 2026-11-08-required-account): anonymous accounts are off by default; memory on calls
// needs a signed-in Doddy account and stays within byte quotas per account and for the server; digests written by the
// AI writer count against daily caps per account, for the server and for new accounts, like Messages.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { DEFAULT_ABUSE_LIMITS, loadConfig } from "../src/config.js";
import type { Db } from "../src/db.js";
import type { AccountVerifier } from "../src/doddyAccount.js";
import { buildDigest, type NewsDeps } from "../src/news/digest.js";
import type { NewsItem } from "../src/news/feeds.js";
import type { FeedSource } from "../src/news/sources.js";
import { DEFAULT_NEWS_WRITER_CAPS, reserveWriter, type NewsWriterCaps } from "../src/news/usage.js";
import type { DigestLine, DigestWriter, WriterInput } from "../src/news/writer.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";

const ENV = { DATABASE_URL: "postgres://x/y" };
const MB = 1024 * 1024;

describe("settings", () => {
  test("anonymous accounts are off unless ANONYMOUS_ACCOUNTS is 1", () => {
    assert.equal(loadConfig(ENV).anonymousAccounts, false);
    assert.equal(loadConfig({ ...ENV, ANONYMOUS_ACCOUNTS: "" }).anonymousAccounts, false, "empty counts as unset");
    assert.equal(loadConfig({ ...ENV, ANONYMOUS_ACCOUNTS: "0" }).anonymousAccounts, false);
    assert.equal(loadConfig({ ...ENV, ANONYMOUS_ACCOUNTS: "1" }).anonymousAccounts, true);
    for (const bad of ["yes", "true", "2"]) assert.throws(() => loadConfig({ ...ENV, ANONYMOUS_ACCOUNTS: bad }), bad);
  });

  test("memory-copy quotas: 4 MB an account and 400 MB for the server by default, set in MB, within range", () => {
    const c = loadConfig(ENV);
    assert.deepEqual([c.limits.memoryCopyBytesPerAccount, c.limits.memoryCopyBytesPerServer], [4 * MB, 400 * MB]);
    assert.deepEqual([DEFAULT_ABUSE_LIMITS.memoryCopyBytesPerAccount, DEFAULT_ABUSE_LIMITS.memoryCopyBytesPerServer], [4 * MB, 400 * MB]);
    const set = loadConfig({ ...ENV, MEMORY_COPY_MB_PER_ACCOUNT: "2", MEMORY_COPY_MB_PER_SERVER: "100" });
    assert.deepEqual([set.limits.memoryCopyBytesPerAccount, set.limits.memoryCopyBytesPerServer], [2 * MB, 100 * MB]);
    // An account's copy can't be larger than one request body (8 MB).
    for (const bad of [{ MEMORY_COPY_MB_PER_ACCOUNT: "0" }, { MEMORY_COPY_MB_PER_ACCOUNT: "9" }, { MEMORY_COPY_MB_PER_SERVER: "0" },
      { MEMORY_COPY_MB_PER_ACCOUNT: "1.5" }]) {
      assert.throws(() => loadConfig({ ...ENV, ...bad }), JSON.stringify(bad));
    }
  });

  test("digest writer caps: 5 an account, 500 for the server, 50 for new accounts by default; each can be set", () => {
    assert.deepEqual(loadConfig(ENV).newsWriterCaps, { perAccount: 5, perServer: 500, newAccountPool: 50, newAccountHours: 24 });
    assert.deepEqual(DEFAULT_NEWS_WRITER_CAPS, { perAccount: 5, perServer: 500, newAccountPool: 50, newAccountHours: 24 });
    const c = loadConfig({
      ...ENV, NEWS_WRITER_DAILY_PER_ACCOUNT: "2", NEWS_WRITER_DAILY_PER_SERVER: "40", NEWS_WRITER_DAILY_NEW_ACCOUNTS: "0", NEW_ACCOUNT_HOURS: "48",
    });
    assert.deepEqual(c.newsWriterCaps, { perAccount: 2, perServer: 40, newAccountPool: 0, newAccountHours: 48 });
    for (const bad of [{ NEWS_WRITER_DAILY_PER_ACCOUNT: "0" }, { NEWS_WRITER_DAILY_PER_SERVER: "0" }, { NEWS_WRITER_DAILY_NEW_ACCOUNTS: "-1" }]) {
      assert.throws(() => loadConfig({ ...ENV, ...bad }), JSON.stringify(bad));
    }
  });
});

/** A Doddy account token is "token:<sub>"; anything else is refused (the real check is in accountSignIn.test.ts). */
const verifier: AccountVerifier = {
  async verify(token: string) { return token.startsWith("token:") ? { sub: token.slice(6) } : null; },
};

describe("anonymous accounts", { skip: dbSkip }, () => {
  let db: Db;
  let off: FastifyInstance;
  let unset: FastifyInstance;
  let on: FastifyInstance;
  let address = 0;
  const from = () => `10.31.0.${++address}`;

  before(async () => {
    db = await freshDb();
    ({ app: off } = await testApp(db, { accounts: verifier, anonymousAccounts: false }));
    ({ app: unset } = await testApp(db, { accounts: verifier, anonymousAccounts: undefined }));
    ({ app: on } = await testApp(db, { accounts: verifier, anonymousAccounts: true }));
  });
  after(async () => {
    await off?.close();
    await unset?.close();
    await on?.close();
    await db?.end();
  });

  const accounts = async () => Number((await db.query<{ n: string }>("SELECT count(*) AS n FROM accounts")).rows[0]!.n);

  test("off (and when not set): 403 sign_in_required, no account made, no daily slot taken", async () => {
    const before = await accounts();
    for (const app of [off, unset]) {
      const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: from() });
      assert.equal(r.statusCode, 403);
      assert.deepEqual(r.json(), { error: "sign_in_required" });
    }
    assert.equal(await accounts(), before);
    const slots = await db.query("SELECT 1 FROM server_daily_usage WHERE feature = 'accounts'");
    const perAddress = await db.query("SELECT 1 FROM daily_counters WHERE scope = 'signup_ip'");
    assert.equal(slots.rowCount, 0);
    assert.equal(perAddress.rowCount, 0);
  });

  test("on: an account is made as before", async () => {
    const r = await on.inject({ method: "POST", url: "/v1/accounts", remoteAddress: from() });
    assert.equal(r.statusCode, 201);
    assert.match(r.json().deviceToken, /^[A-Za-z0-9_-]{43}$/);
  });

  test("off: a device token given out earlier keeps working, and its account can still sign in and be linked", async () => {
    const earlier = (await on.inject({ method: "POST", url: "/v1/accounts", remoteAddress: from() })).json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${earlier.deviceToken}` };
    assert.equal((await off.inject({ method: "GET", url: "/v1/calls/settings", headers: h })).statusCode, 200);
    const signIn = await off.inject({
      method: "POST", url: "/v1/accounts/sign-in", remoteAddress: from(),
      headers: { authorization: "Bearer token:linked-sub" }, payload: { deviceToken: earlier.deviceToken },
    });
    assert.equal(signIn.statusCode, 200);
    assert.equal(signIn.json().accountId, earlier.accountId, "the earlier account is linked, not replaced");
  });

  test("off: signing in with a Doddy account still makes the account here, and its token works", async () => {
    const r = await off.inject({ method: "POST", url: "/v1/accounts/sign-in", remoteAddress: from(), headers: { authorization: "Bearer token:new-sub" } });
    assert.equal(r.statusCode, 200);
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const subject = await db.query<{ auth_subject: string }>("SELECT auth_subject FROM accounts WHERE id = $1", [accountId]);
    assert.equal(subject.rows[0]!.auth_subject, "new-sub");
    assert.equal((await off.inject({ method: "GET", url: "/v1/calls/settings", headers: { authorization: `Bearer ${deviceToken}` } })).statusCode, 200);
    // A bad token is still a 401, never an anonymous account.
    const bad = await off.inject({ method: "POST", url: "/v1/accounts/sign-in", remoteAddress: from(), headers: { authorization: "Bearer nope" } });
    assert.equal(bad.statusCode, 401);
  });
});

describe("memory on calls: signed-in accounts only, within byte quotas", { skip: dbSkip }, () => {
  let db: Db;
  const apps: FastifyInstance[] = [];
  let address = 0;

  before(async () => {
    db = await freshDb();
  });
  after(async () => {
    for (const app of apps) await app.close();
    await db?.end();
  });

  const appWith = async (limits: { memoryCopyBytesPerAccount?: number; memoryCopyBytesPerServer?: number } = {}) => {
    const { app } = await testApp(db, { limits: { accountsPerIpDay: 100_000, ...limits } });
    apps.push(app);
    return app;
  };
  /** An account here; `signedIn` links it to a Doddy account, as `POST /v1/accounts/sign-in` does. */
  const account = async (app: FastifyInstance, signedIn = true) => {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.32.${address >> 8}.${++address & 255}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    if (signedIn) await db.query("UPDATE accounts SET auth_subject = $2 WHERE id = $1", [accountId, randomUUID()]);
    return { accountId, h: { authorization: `Bearer ${deviceToken}` } };
  };
  const enable = (app: FastifyInstance, h: object, enabled = true) =>
    app.inject({ method: "PUT", url: "/v1/memory-copy", headers: h as Record<string, string>, payload: { enabled } });
  const snapshot = (app: FastifyInstance, h: object, texts: string[]) => app.inject({
    method: "PUT", url: "/v1/memory-copy/snapshot", headers: h as Record<string, string>,
    payload: { items: texts.map((text) => ({ id: randomUUID().toUpperCase(), text })) },
  });
  const stored = async (accountId: string) => {
    const { rows } = await db.query<{ n: number; bytes: string | null }>(
      "SELECT count(*)::int AS n, sum(octet_length(ciphertext)) AS bytes FROM memory_copies WHERE account_id = $1", [accountId]);
    const { rows: s } = await db.query<{ bytes: string }>("SELECT memory_copy_bytes AS bytes FROM call_settings WHERE account_id = $1", [accountId]);
    return { items: rows[0]!.n, bytes: Number(rows[0]!.bytes ?? 0), recorded: Number(s[0]?.bytes ?? 0) };
  };
  const serverTotal = async () =>
    Number((await db.query<{ n: string }>("SELECT coalesce(sum(octet_length(ciphertext)), 0) AS n FROM memory_copies")).rows[0]!.n);
  /** The ciphertext of a text of `n` ASCII characters: 12-byte IV, 16-byte tag, then the text's bytes. */
  const sealed = (n: number) => n + 28;

  test("an anonymous account can't turn it on or send a copy, but can always turn it off, which deletes what it kept", async () => {
    const app = await appWith();
    const { accountId, h } = await account(app, false);
    const on = await enable(app, h);
    assert.equal(on.statusCode, 403);
    assert.deepEqual(on.json(), { error: "sign_in_required" });
    const send = await snapshot(app, h, ["a memory"]);
    assert.equal(send.statusCode, 403);
    assert.deepEqual(send.json(), { error: "sign_in_required" });

    // A copy it made before this rule (anonymous accounts could then): turning it off deletes it all.
    await db.query("INSERT INTO call_settings (account_id, memory_copy_enabled_at, memory_copy_bytes) VALUES ($1, now(), $2)", [accountId, sealed(5)]);
    await db.query("INSERT INTO memory_copies (account_id, memory_id, key_version, ciphertext) VALUES ($1, $2, 1, $3)",
      [accountId, randomUUID(), testCipher.encrypt("hello", "x")]);
    assert.equal((await snapshot(app, h, ["new"])).statusCode, 403, "and can't replace it");
    assert.equal((await enable(app, h, false)).statusCode, 204);
    assert.deepEqual(await stored(accountId), { items: 0, bytes: 0, recorded: 0 });
    const s = await db.query("SELECT memory_copy_enabled_at FROM call_settings WHERE account_id = $1", [accountId]);
    assert.equal(s.rows[0].memory_copy_enabled_at, null);
  });

  test("a signed-in account: the bytes stored are counted by the database and kept beside the settings; off sets them to 0", async () => {
    const app = await appWith();
    const { accountId, h } = await account(app);
    assert.equal((await enable(app, h)).statusCode, 204);
    const r = await snapshot(app, h, ["one", "twenty", "Zażółć gęślą jaźń"]);
    assert.equal(r.statusCode, 200);
    assert.deepEqual(r.json(), { count: 3 });
    const after = await stored(accountId);
    assert.equal(after.items, 3);
    assert.equal(after.bytes, sealed(3) + sealed(6) + sealed(Buffer.byteLength("Zażółć gęślą jaźń")));
    assert.equal(after.recorded, after.bytes);
    assert.equal((await snapshot(app, h, ["only"])).statusCode, 200);
    assert.deepEqual(await stored(accountId), { items: 1, bytes: sealed(4), recorded: sealed(4) });
    assert.equal((await enable(app, h, false)).statusCode, 204);
    assert.deepEqual(await stored(accountId), { items: 0, bytes: 0, recorded: 0 });
  });

  test("over the account's quota: 413 memory_copy_too_large, and the copy it had is kept as it was", async () => {
    const app = await appWith({ memoryCopyBytesPerAccount: 200 });
    const { accountId, h } = await account(app);
    await enable(app, h);
    assert.equal((await snapshot(app, h, ["kept"])).statusCode, 200);
    const kept = await stored(accountId);

    // The text alone is over: refused before anything is encrypted.
    const plain = await snapshot(app, h, ["x".repeat(201)]);
    assert.equal(plain.statusCode, 413);
    assert.deepEqual(plain.json(), { error: "memory_copy_too_large", limitBytes: 200 });
    // The text fits, the encrypted copy doesn't (28 bytes more per memory): counted in the database, then rolled back.
    const sealedOver = await snapshot(app, h, ["a".repeat(80), "b".repeat(80)]);
    assert.equal(sealedOver.statusCode, 413);
    assert.deepEqual(sealedOver.json(), { error: "memory_copy_too_large", limitBytes: 200 });
    assert.deepEqual(await stored(accountId), kept);
    const rows = await db.query<{ ciphertext: Buffer; memory_id: string }>("SELECT memory_id, ciphertext FROM memory_copies WHERE account_id = $1", [accountId]);
    assert.equal(testCipher.decrypt(rows.rows[0]!.ciphertext, `${accountId}:memory:${rows.rows[0]!.memory_id}`), "kept");

    // Exactly at the quota is allowed.
    assert.equal((await snapshot(app, h, ["c".repeat(200 - 28)])).statusCode, 200);
    assert.equal((await stored(accountId)).bytes, 200);
  });

  test("over the server's quota: 507 memory_copy_server_full; a copy that doesn't grow still goes through", async () => {
    const base = await serverTotal();
    const app = await appWith({ memoryCopyBytesPerAccount: 1000, memoryCopyBytesPerServer: base + 1000 });
    const a = await account(app);
    const b = await account(app);
    await enable(app, a.h);
    await enable(app, b.h);
    assert.equal((await snapshot(app, a.h, ["a".repeat(600 - 28)])).statusCode, 200);
    const full = await snapshot(app, b.h, ["b".repeat(500 - 28)]);
    assert.equal(full.statusCode, 507);
    assert.deepEqual(full.json(), { error: "memory_copy_server_full" });
    assert.deepEqual(await stored(b.accountId), { items: 0, bytes: 0, recorded: 0 });
    assert.equal((await snapshot(app, b.h, ["b".repeat(400 - 28)])).statusCode, 200, "up to the quota fits");
    assert.equal(await serverTotal(), base + 1000);

    // The owner lowers the server's quota below what is stored: nobody may grow, anyone may shrink.
    const lowered = await appWith({ memoryCopyBytesPerAccount: 1000, memoryCopyBytesPerServer: base + 500 });
    assert.equal((await snapshot(lowered, a.h, ["a".repeat(700 - 28)])).statusCode, 507);
    assert.equal((await snapshot(lowered, a.h, ["a".repeat(300 - 28)])).statusCode, 200);
    assert.equal((await snapshot(lowered, b.h, ["b".repeat(400 - 28)])).statusCode, 200, "the same size again");
    assert.equal(await serverTotal(), base + 700);

    // Turning a copy off and deleting an account give their bytes back.
    assert.equal((await enable(lowered, a.h, false)).statusCode, 204);
    assert.equal((await lowered.inject({ method: "DELETE", url: "/v1/account", headers: b.h })).statusCode, 204);
    assert.equal(await serverTotal(), base);
    const recorded = await db.query<{ n: string }>("SELECT coalesce(sum(memory_copy_bytes), 0) AS n FROM call_settings");
    assert.equal(Number(recorded.rows[0]!.n), base);
  });

  test("two copies sent at once that each fit, but not together: exactly one is kept", async () => {
    const base = await serverTotal();
    const app = await appWith({ memoryCopyBytesPerAccount: 1000, memoryCopyBytesPerServer: base + 1000 });
    const a = await account(app);
    const b = await account(app);
    await enable(app, a.h);
    await enable(app, b.h);
    const [ra, rb] = await Promise.all([snapshot(app, a.h, ["a".repeat(600 - 28)]), snapshot(app, b.h, ["b".repeat(600 - 28)])]);
    assert.deepEqual([ra.statusCode, rb.statusCode].sort(), [200, 507]);
    assert.equal(await serverTotal(), base + 600);
  });
});

class FreshFeeds implements FeedSource {
  served = 0;
  /** Each fetch carries new stories, so every digest has something not sent before. */
  async fetchFeed() {
    const n = ++this.served;
    const items: NewsItem[] = [1, 2, 3].map((i) => ({
      title: `Story ${n}.${i}`, url: `https://news.example/${n}/${i}`, source: "Example", summary: "",
      publishedAt: new Date(Date.now() - i * 3_600_000).toISOString(),
    }));
    return { title: "Example", items };
  }
}
class CountingWriter implements DigestWriter {
  readonly provider = "anthropic" as const;
  calls = 0;
  async write(input: WriterInput): Promise<DigestLine[]> {
    this.calls += 1;
    return input.candidates.slice(0, 2).map((c) => ({ id: c.id, line: `AI: ${c.title}` }));
  }
}

describe("digests written by the AI: daily caps per account, for the server and for new accounts", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  const feeds = new FreshFeeds();
  const writer = new CountingWriter();
  const caps: NewsWriterCaps = { perAccount: 2, perServer: 1000, newAccountPool: 1000 };
  const news: NewsDeps = { feeds, writer, writerCaps: caps };
  let address = 0;

  before(async () => {
    db = await freshDb();
    ({ app } = await testApp(db, { news }));
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });
  beforeEach(async () => {
    // Each test starts the day afresh, and the feed cache (30 minutes) never hands back stories already sent.
    await db.query("DELETE FROM server_daily_usage WHERE feature IN ('news', 'news_new')");
    await db.query("DELETE FROM daily_counters WHERE scope = 'news_account'");
    await db.query("DELETE FROM news_cache");
    Object.assign(caps, { perAccount: 2, perServer: 1000, newAccountPool: 1000 });
  });

  /** An account following its own feed, with notifications; `established` makes it older than NEW_ACCOUNT_HOURS. */
  async function user(established = false) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: `10.33.0.${++address}` });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    await app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h,
      payload: { token: Math.random().toString(16).slice(2).padEnd(64, "c").slice(0, 64), environment: "sandbox" } });
    const put = await app.inject({ method: "PUT", url: "/v1/news/settings", headers: h, payload: {
      enabled: true, sendTime: "08:00", timezone: "Europe/Warsaw", channels: ["push"], language: "en", topics: [], feeds: ["https://feed.example/rss"],
    } });
    assert.equal(put.statusCode, 200);
    if (established) await db.query("UPDATE accounts SET created_at = now() - interval '2 days' WHERE id = $1", [accountId]);
    return { accountId, h };
  }
  const digest = async (accountId: string, kind: "manual" | "scheduled" = "manual") => {
    await db.query("DELETE FROM news_cache");
    return buildDigest(db, news, accountId, kind, new Date());
  };
  const serverCount = async (feature: string) =>
    Number((await db.query<{ n: number }>("SELECT coalesce(sum(requests), 0)::int AS n FROM server_daily_usage WHERE feature = $1", [feature])).rows[0]!.n);

  test("per account: past the cap the digest still comes, as plain headlines, and the writer isn't asked", async () => {
    const { accountId, h } = await user(true);
    const other = await user(true);
    const before = writer.calls;
    const first = await digest(accountId, "scheduled");
    const second = await digest(accountId);
    assert.deepEqual([first.status, first.aiWritten, first.errorCode], ["queued", true, undefined]);
    assert.deepEqual([second.status, second.aiWritten], ["queued", true]);
    assert.equal(writer.calls, before + 2);

    const third = await digest(accountId);
    assert.deepEqual([third.status, third.aiWritten, third.errorCode], ["queued", false, "writer_daily_limit"]);
    assert.equal(writer.calls, before + 2, "no third request to the writer");
    const items = await db.query<{ line: string }>("SELECT line FROM news_digest_items WHERE digest_id = $1 ORDER BY position", [third.digestId]);
    assert.ok(items.rows.length > 0);
    for (const r of items.rows) assert.doesNotMatch(r.line, /^AI:/);
    const listed = (await app.inject({ method: "GET", url: "/v1/news/digests", headers: h })).json().digests[0];
    assert.deepEqual([listed.status, listed.aiWritten, listed.errorCode], ["queued", false, "writer_daily_limit"]);

    // Another account has its own count.
    const theirs = await digest(other.accountId);
    assert.equal(theirs.aiWritten, true);
    assert.equal(await serverCount("news"), 3, "only digests the writer was asked for count for the server");
  });

  test("send me one now, past the account's cap: 200, headlines only, as an app already shows it", async () => {
    caps.perAccount = 1;
    const { h } = await user(true);
    const send = async () => (await app.inject({ method: "POST", url: "/v1/news/send-now", headers: h })).json();
    await db.query("DELETE FROM news_cache");
    const first = await send();
    assert.deepEqual([first.status, first.aiWritten, first.errorCode], ["queued", true, null]);
    await db.query("DELETE FROM news_cache");
    const second = await send();
    assert.deepEqual([second.status, second.aiWritten, second.errorCode], ["queued", false, "writer_daily_limit"]);
  });

  test("for the server: the whole server's cap holds across accounts, and deleting an account gives nothing back", async () => {
    caps.perServer = 2;
    const a = await user(true);
    const b = await user(true);
    assert.equal((await digest(a.accountId)).aiWritten, true);
    assert.equal((await app.inject({ method: "DELETE", url: "/v1/account", headers: a.h })).statusCode, 204);
    assert.equal((await digest(b.accountId)).aiWritten, true);
    const over = await digest(b.accountId);
    assert.deepEqual([over.aiWritten, over.errorCode], [false, "writer_daily_limit"]);
    assert.equal(await serverCount("news"), 2);
  });

  test("new accounts share a small pool inside the server's cap; established ones don't draw from it", async () => {
    caps.newAccountPool = 1;
    const fresh = await user();
    const alsoFresh = await user();
    const old = await user(true);
    assert.equal((await digest(fresh.accountId)).aiWritten, true);
    const pooled = await digest(alsoFresh.accountId);
    assert.deepEqual([pooled.aiWritten, pooled.errorCode], [false, "writer_daily_limit"]);
    assert.equal((await digest(old.accountId)).aiWritten, true);
    assert.equal(await serverCount("news_new"), 1);
    assert.equal(await serverCount("news"), 2);
    // A verified phone number makes an account established too (as for Messages).
    await db.query("INSERT INTO phone_numbers (account_id, e164, verified_at) VALUES ($1, '+48500100200', now())", [alsoFresh.accountId]);
    assert.equal((await digest(alsoFresh.accountId)).aiWritten, true);
  });

  test("a closed pool (0) keeps new accounts on headlines; a refusal takes no slot from any cap", async () => {
    caps.newAccountPool = 0;
    const fresh = await user();
    assert.equal((await reserveWriter(db, fresh.accountId, caps, new Date())), "new_account_cap");
    assert.equal((await digest(fresh.accountId)).errorCode, "writer_daily_limit");
    assert.equal(await serverCount("news"), 0);
    assert.equal(await serverCount("news_new"), 0);
    caps.newAccountPool = 1000;
    caps.perAccount = 1;
    const old = await user(true);
    assert.equal(await reserveWriter(db, old.accountId, caps, new Date()), "ok");
    assert.equal(await reserveWriter(db, old.accountId, caps, new Date()), "account_cap");
    assert.equal(await serverCount("news"), 1, "the account's refusal gave its server slot back");
  });

  test("a digest with nothing new asks nobody, and counts nothing", async () => {
    const { accountId } = await user(true);
    const quiet: NewsDeps = { feeds: { async fetchFeed() { return { title: "Empty", items: [] }; } }, writer, writerCaps: caps };
    const before = writer.calls;
    await db.query("DELETE FROM news_cache");
    const r = await buildDigest(db, quiet, accountId, "manual", new Date());
    assert.equal(r.status, "empty");
    assert.equal(writer.calls, before);
    assert.equal(await serverCount("news"), 0);
  });
});
