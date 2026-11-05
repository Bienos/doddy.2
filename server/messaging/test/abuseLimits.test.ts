// What anonymous accounts can spend, against real Postgres (security review 4 Nov 2026): accounts made per address and
// per day (ADR-702), the small pools of new accounts inside each paid feature's server-wide cap (ADR-702), the countries
// whose numbers may be verified, texted and called, and the daily caps on texts and calls (ADR-704), the verification
// caps per address and per account (ADR-705), and queued text that is never stored unencrypted in production (ADR-706).
// Nothing here calls a provider; the fakes record what would have been sent.
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { reserve as reserveAssistant } from "../src/assistant/usage.js";
import { DEFAULT_ERRAND_SETTINGS, type AbuseLimits } from "../src/config.js";
import { counterKey } from "../src/dailyCounters.js";
import { sha256 } from "../src/crypto.js";
import type { Db } from "../src/db.js";
import { reserve as reserveDeals } from "../src/deals/usage.js";
import type { ErrandResearcher } from "../src/errands/researcher.js";
import { buildDigest, type NewsDeps } from "../src/news/digest.js";
import type { NewsItem } from "../src/news/feeds.js";
import type { FeedSource } from "../src/news/sources.js";
import { dispatchDue, enqueue, EncryptionNotConfigured } from "../src/outbox.js";
import type { PhoneVerifier, SendOutcome, VerifyCheck } from "../src/providers/types.js";
import { dbSkip, FakeOutbound, FakePush, FakeSms, FakeVerifier, freshDb, testApp, testCipher, TOOL_SECRET } from "./helpers.js";

/** Provider message ids are unique in the table, so each text this fake sends gets its own. */
class UniqueSms extends FakeSms {
  override async send(to: string, body: string): Promise<SendOutcome> {
    this.sent.push({ to, body });
    return { kind: "accepted", providerId: `SM${randomUUID()}` };
  }
}

class CountingVerifier extends FakeVerifier implements PhoneVerifier {
  checked: string[] = [];
  override async check(to: string, code: string): Promise<VerifyCheck> {
    this.checked.push(to);
    return super.check(to, code);
  }
}

describe("abuse limits against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => {
    // The dispatcher takes the oldest due messages first, whoever queued them: each test starts with none.
    await db.query("DELETE FROM outbound_messages; DELETE FROM daily_counters; DELETE FROM server_daily_usage; DELETE FROM phone_verification_starts; DELETE FROM assistant_usage; DELETE FROM deals_usage; DELETE FROM errand_usage");
  });

  // Every account, address and number below is new, so no test depends on what an earlier one left in the database.
  let seq = 0;
  const nextIp = () => `10.${200 + Math.floor(++seq / 60000)}.${Math.floor(seq / 250) % 250}.${(seq % 250) + 1}`;
  const nextPhone = () => `+48500${String(200000 + ++seq).slice(-6)}`;
  const nextForeignPhone = () => `+1212555${String(1000 + ++seq).slice(-4)}`;
  const usage = async () => Object.fromEntries((await db.query<{ feature: string; requests: number }>(
    "SELECT feature, requests FROM server_daily_usage ORDER BY feature")).rows.map((r) => [r.feature, r.requests]));
  /** Runs `fn` as the production server would: NODE_ENV=production for the time of the call. */
  async function inProduction<T>(fn: () => Promise<T>): Promise<T> {
    const was = process.env.NODE_ENV;
    process.env.NODE_ENV = "production";
    try { return await fn(); } finally { if (was === undefined) delete process.env.NODE_ENV; else process.env.NODE_ENV = was; }
  }
  /** The server's day for some features only (accounts made through the API are counted too). */
  const usageOf = async (...features: string[]) => Object.fromEntries(Object.entries(await usage()).filter(([f]) => features.includes(f)));
  const counter = async (scope: string, key: string) =>
    (await db.query<{ n: number }>("SELECT n FROM daily_counters WHERE scope = $1 AND key = $2", [scope, key])).rows[0]?.n ?? 0;
  const count = async (table: string) => (await db.query<{ n: number }>(`SELECT count(*)::int AS n FROM ${table}`)).rows[0]!.n;

  async function signedIn(app: FastifyInstance, opts: { phone?: string; ip?: string } = {}) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: opts.ip ?? nextIp() });
    assert.equal(r.statusCode, 201, r.body);
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const api = (method: "GET" | "POST" | "PUT" | "DELETE", url: string, payload?: unknown, extra: { headers?: Record<string, string>; ip?: string } = {}) =>
      app.inject({ method, url, headers: { ...h, ...extra.headers }, payload: payload as never, ...(extra.ip ? { remoteAddress: extra.ip } : {}) });
    const phone = opts.phone;
    if (phone) assert.equal((await api("POST", "/v1/phone/verification/check", { phone, code: "123456" })).statusCode, 200);
    return { accountId, h, api, phone };
  }

  // ---------------------------------------------------------------------------------------------------------------
  describe("accounts made per day (ADR-702)", () => {
    test("per client address: the next account from that address is refused, and nothing is made or left counted", async () => {
      const { app } = await testApp(db, { limits: { accountsPerIpDay: 3 } });
      try {
        const make = (ip: string) => app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: ip });
        const before = await count("accounts");
        for (let i = 0; i < 3; i++) assert.equal((await make("198.51.100.20")).statusCode, 201);
        const refused = await make("198.51.100.20");
        assert.equal(refused.statusCode, 429);
        assert.deepEqual(refused.json(), { error: "rate_limited" });
        assert.equal((await make("198.51.100.21")).statusCode, 201, "another address is not affected");
        assert.equal(await count("accounts"), before + 4);
        // The key is the keyed hash of the address, never the address.
        const key = counterKey(testCipher.derivedKey("client-address"), "198.51.100.20");
        assert.equal(await counter("signup_ip", key), 3);
        const { rows } = await db.query<{ key: string }>("SELECT key FROM daily_counters WHERE scope = 'signup_ip'");
        assert.ok(rows.every((r) => /^[0-9a-f]{64}$/.test(r.key) && !r.key.includes("198.51")));
      } finally {
        await app.close();
      }
    });

    test("for the whole server: the next account is refused from any address, and the refused one doesn't use its address's count", async () => {
      const { app } = await testApp(db, { limits: { accountsPerIpDay: 100, accountsPerServerDay: 4 } });
      try {
        const make = (ip: string) => app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: ip });
        for (let i = 1; i <= 4; i++) assert.equal((await make(`198.51.100.${30 + i}`)).statusCode, 201);
        assert.equal((await make("198.51.100.99")).statusCode, 429);
        assert.deepEqual(await usage(), { accounts: 4 });
        assert.equal(await counter("signup_ip", counterKey(testCipher.derivedKey("client-address"), "198.51.100.99")), 0);
      } finally {
        await app.close();
      }
    });

    test("parallel requests can't pass the caps together", async () => {
      const server = await testApp(db, { limits: { accountsPerIpDay: 100, accountsPerServerDay: 5 } });
      try {
        const r = await Promise.all(Array.from({ length: 20 }, () => server.app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: nextIp() })));
        assert.equal(r.filter((x) => x.statusCode === 201).length, 5);
        assert.equal(r.filter((x) => x.statusCode === 429).length, 15);
        assert.deepEqual(await usage(), { accounts: 5 });
      } finally {
        await server.app.close();
      }
      await db.query("DELETE FROM daily_counters; DELETE FROM server_daily_usage");
      const address = await testApp(db, { limits: { accountsPerIpDay: 4 } });
      try {
        const same = "198.51.100.77";
        const r = await Promise.all(Array.from({ length: 8 }, () => address.app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: same })));
        assert.equal(r.filter((x) => x.statusCode === 201).length, 4);
        assert.equal(await counter("signup_ip", counterKey(testCipher.derivedKey("client-address"), same)), 4);
      } finally {
        await address.app.close();
      }
    });

    test("a made-up Authorization or X-Forwarded-For header doesn't buy another address's count", async () => {
      const { app } = await testApp(db, { trustProxyHops: 1, limits: { accountsPerIpDay: 3 } });
      try {
        const statuses: number[] = [];
        for (let i = 0; i < 5; i++) {
          const r = await app.inject({
            method: "POST", url: "/v1/accounts", remoteAddress: "198.51.100.88",
            headers: { authorization: `Bearer made-up-${i}`, "x-forwarded-for": `203.0.113.${i}, 198.51.100.89` },
          });
          statuses.push(r.statusCode);
        }
        // Behind one proxy hop the client is the right-most entry, 198.51.100.89 here, whatever the others say.
        assert.deepEqual(statuses, [201, 201, 201, 429, 429]);
      } finally {
        await app.close();
      }
    });

    test("IPv6 addresses of one /64 share a count; another prefix has its own", async () => {
      const { app } = await testApp(db, { limits: { accountsPerIpDay: 1 } });
      try {
        const make = (ip: string) => app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: ip }).then((r) => r.statusCode);
        assert.equal(await make("2001:db8:aaaa:1::1"), 201);
        assert.equal(await make("2001:db8:aaaa:1:ffff::2"), 429);
        assert.equal(await make("2001:0db8:aaaa:0001:0:0:0:3"), 429);
        assert.equal(await make("2001:db8:aaaa:2::1"), 201);
        assert.equal(await make("::ffff:198.51.100.55"), 201);
        assert.equal(await make("198.51.100.55"), 429, "IPv4 written the IPv6 way is the same client");
      } finally {
        await app.close();
      }
    });

    test("without the encryption key the address is kept as a plain hash; old counts are dropped when accounts are made", async () => {
      const { app } = await testApp(db, { cipher: undefined, limits: { accountsPerIpDay: 5 } });
      try {
        await db.query("INSERT INTO daily_counters (scope, key, day, n) VALUES ('signup_ip', 'old', (now() AT TIME ZONE 'utc')::date - 5, 3), ('sms_account', 'older', (now() AT TIME ZONE 'utc')::date - 3, 1)");
        assert.equal((await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: "198.51.100.66" })).statusCode, 201);
        assert.equal(await counter("signup_ip", counterKey(undefined, "198.51.100.66")), 1);
        assert.equal(await counter("signup_ip", "old"), 0, "three days old: gone");
        assert.equal(await counter("sms_account", "older"), 0);
      } finally {
        await app.close();
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  describe("new accounts share small pools inside the server-wide caps (ADR-702)", () => {
    async function account(opts: { ageHours?: number; phone?: string } = {}) {
      const id = randomUUID();
      await db.query("INSERT INTO accounts (id, created_at) VALUES ($1, now() - make_interval(hours => $2::int))", [id, opts.ageHours ?? 0]);
      if (opts.phone) await db.query("INSERT INTO phone_numbers (account_id, e164, verified_at) VALUES ($1, $2, now())", [id, opts.phone]);
      return id;
    }
    const caps = { perAccount: 100, perServer: 10, newAccountPool: 3 };

    for (const [name, reserve, feature] of [
      ["Messages", reserveAssistant, "assistant"], ["leaflets", reserveDeals, "deals"],
    ] as const) {
      test(`${name}: many new accounts use only the pool; a verified account and an older one are still served`, async () => {
        const fresh = await Promise.all(Array.from({ length: 6 }, () => account()));
        const results: string[] = [];
        for (const id of fresh) results.push(await reserve(db, id, caps));
        assert.deepEqual(results, ["ok", "ok", "ok", "new_account_cap", "new_account_cap", "new_account_cap"]);
        assert.deepEqual(await usageOf(feature, `${feature}_new`), { [feature]: 3, [`${feature}_new`]: 3 }, "the refused ones used nothing of the server's day");

        const verified = await account({ phone: nextPhone() });
        const older = await account({ ageHours: 48 });
        assert.equal(await reserve(db, verified, caps), "ok");
        assert.equal(await reserve(db, older, caps), "ok");
        assert.deepEqual(await usageOf(feature, `${feature}_new`), { [feature]: 5, [`${feature}_new`]: 3 }, "established accounts don't count in the pool");

        // Established accounts may use everything the new ones did not, up to the server's cap.
        const results2: string[] = [];
        for (let i = 0; i < 6; i++) results2.push(await reserve(db, i % 2 ? verified : older, caps));
        assert.deepEqual(results2, ["ok", "ok", "ok", "ok", "ok", "server_cap"]);
        assert.equal((await usage())[feature], 10);
        assert.equal(await reserve(db, fresh[0]!, caps), "new_account_cap", "a new account is refused by its pool first");
      });
    }

    test("an account is new until it has a verified phone number or is a day old", async () => {
      const c = { ...caps, newAccountPool: 0 };
      const young = await account({ ageHours: 23 });
      const oneDay = await account({ ageHours: 25 });
      const phoned = await account({ phone: nextPhone() });
      assert.equal(await reserveAssistant(db, young, c), "new_account_cap");
      assert.equal(await reserveAssistant(db, oneDay, c), "ok");
      assert.equal(await reserveAssistant(db, phoned, c), "ok");
      assert.equal(await reserveAssistant(db, await account({ ageHours: 23 }), { ...c, newAccountHours: 22 }), "ok", "the age is a setting");
      assert.equal(await reserveAssistant(db, await account(), { ...c, newAccountHours: 0 }), "ok", "0: every account counts as established");
      assert.equal(await reserveAssistant(db, randomUUID(), c), "new_account_cap", "an account that isn't there counts as new");
      assert.deepEqual(await usageOf("assistant_new"), {}, "a pool of 0 is closed from the first request on");
    });

    test("a new account refused because established accounts used the whole day takes nothing from its pool", async () => {
      const older = await account({ ageHours: 48 });
      const small = { perAccount: 100, perServer: 4, newAccountPool: 3 };
      for (let i = 0; i < 4; i++) assert.equal(await reserveAssistant(db, older, small), "ok");
      assert.equal(await reserveAssistant(db, await account(), small), "server_cap");
      assert.deepEqual(await usageOf("assistant", "assistant_new"), { assistant: 4, assistant_new: 0 }, "the pool slot it had taken went back");
    });

    test("a refusal by the account's own cap gives back both slots it took", async () => {
      const id = await account();
      const c = { perAccount: 1, perServer: 10, newAccountPool: 5 };
      assert.equal(await reserveAssistant(db, id, c), "ok");
      assert.equal(await reserveAssistant(db, id, c), "account_cap");
      assert.deepEqual(await usage(), { assistant: 1, assistant_new: 1 });
    });

    test("parallel requests from new accounts can't pass the pool", async () => {
      const ids = await Promise.all(Array.from({ length: 20 }, () => account()));
      const r = await Promise.all(ids.map((id) => reserveAssistant(db, id, { perAccount: 100, perServer: 15, newAccountPool: 5 })));
      assert.equal(r.filter((x) => x === "ok").length, 5);
      assert.equal(r.filter((x) => x === "new_account_cap").length, 15);
      assert.deepEqual(await usage(), { assistant: 5, assistant_new: 5 });
    });

    test("errands: the same through the API, answered like the server's own cap; a verified phone number lifts it", async () => {
      const researcher: ErrandResearcher = { provider: "anthropic", model: "claude-opus-5-5", research: async () => { throw new Error("not run here"); } };
      const { app, verifier } = await testApp(db, {
        errands: { settings: { ...DEFAULT_ERRAND_SETTINGS, dailyPerServer: 10, dailyForNewAccounts: 2 }, researcher },
      });
      void verifier;
      try {
        const approve = async (a: Awaited<ReturnType<typeof signedIn>>) => {
          const draft = await a.api("POST", "/v1/errands", { words: "sprawdź loty do Rzymu", brief: "Loty do Rzymu.", title: "Rzym", language: "pl" });
          assert.equal(draft.statusCode, 201, draft.body);
          const { id, digest } = draft.json() as { id: string; digest: string };
          return a.api("POST", `/v1/errands/${id}/approve`, { digest });
        };
        const users = await Promise.all([signedIn(app), signedIn(app), signedIn(app)]);
        assert.deepEqual((await Promise.all(users.slice(0, 2).map(approve))).map((r) => r.statusCode), [202, 202]);
        const refused = await approve(users[2]!);
        assert.equal(refused.statusCode, 429);
        assert.deepEqual(refused.json(), { error: "errand_daily_limit", scope: "server" });
        assert.deepEqual(await usageOf("errands", "errands_new"), { errands: 2, errands_new: 2 });
        assert.equal((await users[2]!.api("POST", "/v1/phone/verification/check", { phone: nextPhone(), code: "123456" })).statusCode, 200);
        assert.equal((await approve(users[2]!)).statusCode, 202);
        assert.deepEqual(await usageOf("errands", "errands_new"), { errands: 3, errands_new: 2 });
      } finally {
        await app.close();
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  describe("countries whose numbers may be verified, texted and called (ADR-704)", () => {
    const allowed = ["+4930123456", "+441234567890", "+41791234567", "+3598123456", "+420123456789", "+421912345678", "+4236601234", "+35312345678"];
    const refused = ["+12125551234", "+919876543210", "+79161234567", "+380501234567", "+3551234567", "+4251234567", "+2348012345678"];

    test("a code is sent only to allowed countries, and a refusal happens before anything is counted or sent", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier, limits: { verifyPerIpDay: 1000, verifyPerAccountDay: 1000 } });
      try {
        // The route lets one token start five codes an hour, refused ones included: a few numbers per account.
        const one = async () => signedIn(app);
        let a = await one();
        for (const [i, phone] of refused.entries()) {
          if (i % 4 === 3) a = await one();
          const r = await a.api("POST", "/v1/phone/verification", { phone });
          assert.equal(r.statusCode, 400, phone);
          assert.deepEqual(r.json(), { error: "phone_rejected" });
        }
        assert.deepEqual(verifier.started, [], "no code was asked for");
        assert.equal(await count("phone_verification_starts"), 0, "and nothing was counted");
        for (const [i, phone] of allowed.entries()) {
          if (i % 4 === 0) a = await one();
          assert.equal((await a.api("POST", "/v1/phone/verification", { phone })).statusCode, 202, phone);
        }
        assert.deepEqual(verifier.started, allowed);
      } finally {
        await app.close();
      }
    });

    test("a code is never checked for a number outside the list", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier });
      try {
        const a = await signedIn(app);
        for (const phone of refused) {
          const r = await a.api("POST", "/v1/phone/verification/check", { phone, code: "123456" });
          assert.equal(r.statusCode, 400, phone);
          assert.deepEqual(r.json(), { error: "phone_rejected" });
        }
        assert.deepEqual(verifier.checked, []);
        assert.equal(await count("phone_numbers WHERE account_id = '" + a.accountId + "'"), 0);
        assert.equal((await a.api("POST", "/v1/phone/verification/check", { phone: allowed[0], code: "123456" })).statusCode, 200);
        assert.deepEqual(verifier.checked, [allowed[0]]);
      } finally {
        await app.close();
      }
    });

    test("the list is a setting", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier, limits: { allowedCountryCodes: ["1"], verifyPerIpDay: 1000, verifyPerAccountDay: 1000 } });
      try {
        const a = await signedIn(app);
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: "+12125551234" })).statusCode, 202);
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: "+48500100200" })).statusCode, 400);
      } finally {
        await app.close();
      }
    });

    /** A number stored before the list existed: put in the table directly, as an earlier release would have. */
    async function storedAccount(app: FastifyInstance, phone: string) {
      const a = await signedIn(app);
      await db.query("INSERT INTO phone_numbers (account_id, e164, verified_at, sms_consent_at, sms_consent_text_version) VALUES ($1, $2, now(), now(), 'sms-v1')", [a.accountId, phone]);
      return a;
    }

    test("a text queued for a number outside the list is cancelled at send time and never sent", async () => {
      const sms = new UniqueSms();
      const { app } = await testApp(db, { sms });
      try {
        const old = await storedAccount(app, nextForeignPhone());
        const ok = await storedAccount(app, nextPhone());
        for (const [name, a] of [["old", old], ["ok", ok]] as const) {
          const q = await a.api("POST", "/v1/updates", { text: `for ${name}`, channels: ["sms"], idempotencyKey: `k-${name}` });
          assert.equal(q.statusCode, 202, q.body);
        }
        await dispatchDue(db, { sms, cipher: testCipher });
        assert.deepEqual(sms.sent.map((s) => s.body), ["for ok"]);
        const { rows } = await db.query("SELECT state, error_code FROM outbound_messages WHERE account_id = $1", [old.accountId]);
        assert.deepEqual(rows, [{ state: "cancelled", error_code: "sms_country_not_allowed" }]);
        // The worker is given the list; with another list the same two messages go the other way.
        sms.sent = [];
        for (const [name, a] of [["old", old], ["ok", ok]] as const) {
          await a.api("POST", "/v1/updates", { text: `again ${name}`, channels: ["sms"], idempotencyKey: `k2-${name}` });
        }
        await dispatchDue(db, { sms, cipher: testCipher, allowedCountryCodes: ["1"] });
        assert.deepEqual(sms.sent.map((s) => s.body), ["again old"]);
      } finally {
        await app.close();
      }
    });

    test("a call me is not placed to a number outside the list", async () => {
      const outbound = new FakeOutbound();
      const { app } = await testApp(db, { outbound });
      try {
        const old = await storedAccount(app, nextForeignPhone());
        assert.equal((await old.api("PUT", "/v1/calls/settings", { outboundConsent: true, outboundConsentTextVersion: "calls-v1" })).statusCode, 204);
        const r = await old.api("POST", "/v1/calls/outbound");
        assert.equal(r.statusCode, 409);
        assert.deepEqual(r.json(), { error: "phone_not_allowed" });
        assert.deepEqual(outbound.calls, [], "the provider was not asked");
        assert.equal((await db.query("SELECT 1 FROM calls WHERE account_id = $1", [old.accountId])).rowCount, 0);
      } finally {
        await app.close();
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  describe("texts and calls per day (ADR-704)", () => {
    async function textable(app: FastifyInstance) {
      const a = await signedIn(app, { phone: nextPhone() });
      assert.equal((await a.api("PUT", "/v1/phone/sms-consent", { consent: true, textVersion: "sms-v1" })).statusCode, 204);
      return a;
    }
    const sms = (a: Awaited<ReturnType<typeof textable>>, key: string, text = "hej") =>
      a.api("POST", "/v1/updates", { text, channels: ["sms"], idempotencyKey: key });
    const smsServer = async () => (await usage()).sms ?? 0;
    const acctKey = (id: string) => sha256(id).toString("hex");

    test("per account: the next text is refused with a daily limit, and a retry of one already queued still gets its answer", async () => {
      const { app } = await testApp(db, { limits: { smsPerAccountDay: 2, smsPerServerDay: 100 } });
      try {
        const a = await textable(app);
        const first = await sms(a, "k1");
        assert.equal(first.statusCode, 202);
        assert.equal((await sms(a, "k2")).statusCode, 202);
        const over = await sms(a, "k3");
        assert.equal(over.statusCode, 429);
        assert.deepEqual(over.json(), { error: "daily_limit" });
        assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [a.accountId])).rowCount, 2, "the refused text was not queued");
        const again = await sms(a, "k1");
        assert.equal(again.statusCode, 202, "a replay queues nothing, so the cap doesn't stop it");
        assert.deepEqual(again.json(), first.json());
        assert.equal(await counter("sms_account", acctKey(a.accountId)), 2);
        assert.equal(await smsServer(), 2);
        // Push is not texts.
        await a.api("PUT", "/v1/device/push-token", { token: "ab".repeat(32), environment: "sandbox" });
        assert.equal((await a.api("POST", "/v1/updates", { text: "x", channels: ["push"], idempotencyKey: "p1" })).statusCode, 202);
        assert.equal(await smsServer(), 2);
        // Only a hash of the account is counted.
        const { rows } = await db.query<{ key: string }>("SELECT key FROM daily_counters WHERE scope = 'sms_account'");
        assert.ok(rows.every((r) => !r.key.includes(a.accountId) && /^[0-9a-f]{64}$/.test(r.key)));
      } finally {
        await app.close();
      }
    });

    test("for the whole server: another account's text is refused once the day's texts are used up", async () => {
      const { app } = await testApp(db, { limits: { smsPerAccountDay: 10, smsPerServerDay: 3 } });
      try {
        const a = await textable(app);
        const b = await textable(app);
        assert.equal((await sms(a, "a1")).statusCode, 202);
        assert.equal((await sms(a, "a2")).statusCode, 202);
        assert.equal((await sms(b, "b1")).statusCode, 202);
        const over = await sms(b, "b2");
        assert.equal(over.statusCode, 429);
        assert.deepEqual(over.json(), { error: "daily_limit" });
        assert.equal(await smsServer(), 3);
        assert.equal(await counter("sms_account", acctKey(b.accountId)), 1, "the account's slot was given back when the server's refused");
      } finally {
        await app.close();
      }
    });

    test("parallel texts can't pass the caps together", async () => {
      const { app } = await testApp(db, { limits: { smsPerAccountDay: 4, smsPerServerDay: 100 } });
      try {
        const a = await textable(app);
        const r = await Promise.all(Array.from({ length: 12 }, (_, i) => sms(a, `par-${i}`)));
        assert.equal(r.filter((x) => x.statusCode === 202).length, 4);
        assert.equal(r.filter((x) => x.statusCode === 429).length, 8);
        assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [a.accountId])).rowCount, 4);
      } finally {
        await app.close();
      }
      await db.query("DELETE FROM daily_counters; DELETE FROM server_daily_usage");
      const server = await testApp(db, { limits: { smsPerAccountDay: 50, smsPerServerDay: 5 } });
      try {
        const users = await Promise.all(Array.from({ length: 4 }, () => textable(server.app)));
        const r = await Promise.all(users.flatMap((u, i) => [0, 1, 2].map((j) => sms(u, `s-${i}-${j}`))));
        assert.equal(r.filter((x) => x.statusCode === 202).length, 5);
        assert.equal(await smsServer(), 5);
      } finally {
        await server.app.close();
      }
    });

    test("the same request sent at once many times uses one text, not many", async () => {
      const { app } = await testApp(db, { limits: { smsPerAccountDay: 3, smsPerServerDay: 3 } });
      try {
        const a = await textable(app);
        const r = await Promise.all(Array.from({ length: 6 }, () => sms(a, "same-key", "one text")));
        assert.deepEqual(r.map((x) => x.statusCode), Array(6).fill(202));
        assert.equal(new Set(r.map((x) => (x.json() as { messages: { id: string }[] }).messages[0]!.id)).size, 1, "one message");
        assert.equal(await counter("sms_account", acctKey(a.accountId)), 1, "and one text counted");
        assert.equal(await smsServer(), 1);
      } finally {
        await app.close();
      }
    });

    test("a request that fails after taking its slot gives the slot back", async () => {
      const { app } = await testApp(db, { limits: { smsPerAccountDay: 5, smsPerServerDay: 5 } });
      try {
        const a = await textable(app);
        await a.api("PUT", "/v1/device/push-token", { token: "cd".repeat(32), environment: "sandbox" });
        assert.equal((await a.api("POST", "/v1/updates", { text: "first", channels: ["push"], idempotencyKey: "same" })).statusCode, 202);
        // The text goes first, takes its slot, and then the push finds its key used with another text: nothing is queued.
        const clash = await a.api("POST", "/v1/updates", { text: "second", channels: ["sms", "push"], idempotencyKey: "same" });
        assert.equal(clash.statusCode, 409);
        assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1 AND channel = 'sms'", [a.accountId])).rowCount, 0);
        assert.equal(await counter("sms_account", acctKey(a.accountId)), 0);
        assert.equal(await smsServer(), 0);
      } finally {
        await app.close();
      }
    });

    test("a text queued without a transaction gives its slot back when the insert fails", async () => {
      const accountId = randomUUID(); // not in accounts: the insert fails on its foreign key
      await assert.rejects(enqueue(db, accountId, ["sms"], "x", new Date(), "k", { cipher: testCipher, smsCaps: { perAccount: 5, perServer: 5 } }));
      assert.equal(await counter("sms_account", acctKey(accountId)), 0);
      assert.equal(await smsServer(), 0);
    });

    test("the day is the UTC day: yesterday's count doesn't stop today's texts", async () => {
      const { app } = await testApp(db, { limits: { smsPerAccountDay: 1, smsPerServerDay: 1 } });
      try {
        const a = await textable(app);
        assert.equal((await sms(a, "d1")).statusCode, 202);
        assert.equal((await sms(a, "d2")).statusCode, 429);
        await db.query("UPDATE daily_counters SET day = day - 1; UPDATE server_daily_usage SET day = day - 1");
        assert.equal((await sms(a, "d3")).statusCode, 202);
      } finally {
        await app.close();
      }
    });

    test("a call me is refused once the server's calls for the day are used, and a call the provider refused is not counted", async () => {
      const outbound = new FakeOutbound();
      const { app } = await testApp(db, { outbound, limits: { outboundCallsPerServerDay: 2 } });
      try {
        const callable = async () => {
          const a = await signedIn(app, { phone: nextPhone() });
          assert.equal((await a.api("PUT", "/v1/calls/settings", { outboundConsent: true, outboundConsentTextVersion: "calls-v1" })).statusCode, 204);
          return a;
        };
        const [a, b, c] = [await callable(), await callable(), await callable()] as const;
        outbound.next = [{ kind: "rejected", code: "elevenlabs_422" }];
        const refusedByProvider = await a.api("POST", "/v1/calls/outbound");
        assert.equal(refusedByProvider.statusCode, 502);
        assert.equal((await usage()).outbound_calls, 0, "no call was placed, so the server's day is not used");
        assert.equal((await a.api("POST", "/v1/calls/outbound")).statusCode, 202);
        assert.equal((await b.api("POST", "/v1/calls/outbound")).statusCode, 202);
        const over = await c.api("POST", "/v1/calls/outbound");
        assert.equal(over.statusCode, 429);
        assert.deepEqual(over.json(), { error: "daily_limit" });
        assert.equal(outbound.calls.length, 3, "the third was never handed to the provider");
        assert.equal((await db.query("SELECT 1 FROM calls WHERE account_id = $1", [c.accountId])).rowCount, 0);
        assert.equal((await usage()).outbound_calls, 2);
      } finally {
        await app.close();
      }
    });

    test("parallel calls can't pass the server's cap", async () => {
      const outbound = new FakeOutbound();
      const { app } = await testApp(db, { outbound, limits: { outboundCallsPerServerDay: 3 } });
      try {
        const users = [];
        for (let i = 0; i < 8; i++) {
          const a = await signedIn(app, { phone: nextPhone() });
          await a.api("PUT", "/v1/calls/settings", { outboundConsent: true, outboundConsentTextVersion: "calls-v1" });
          users.push(a);
        }
        const r = await Promise.all(users.map((u) => u.api("POST", "/v1/calls/outbound")));
        assert.equal(r.filter((x) => x.statusCode === 202).length, 3);
        assert.equal(r.filter((x) => x.statusCode === 429).length, 5);
        assert.equal(outbound.calls.length, 3);
      } finally {
        await app.close();
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  describe("verification codes per address and per account (ADR-705)", () => {
    test("two accounts from one address share the address's count, whatever tokens and headers they send", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier, trustProxyHops: 1, limits: { verifyPerIpDay: 3, verifyPerAccountDay: 100 } });
      try {
        const ip = nextIp();
        const a = await signedIn(app);
        const b = await signedIn(app);
        const start = (u: typeof a, phone: string, xff: string) =>
          u.api("POST", "/v1/phone/verification", { phone }, { ip, headers: { "x-forwarded-for": `${xff}, ${ip}` } });
        assert.equal((await start(a, nextPhone(), "203.0.113.1")).statusCode, 202);
        assert.equal((await start(b, nextPhone(), "203.0.113.2")).statusCode, 202);
        assert.equal((await start(a, nextPhone(), "203.0.113.3")).statusCode, 202);
        const over = await start(b, nextPhone(), "203.0.113.4");
        assert.equal(over.statusCode, 429);
        assert.deepEqual(over.json(), { error: "too_many_attempts" });
        assert.equal(verifier.started.length, 3, "the fourth code was not requested");
        // Another address is not affected.
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: nextIp() })).statusCode, 202);
      } finally {
        await app.close();
      }
    });

    test("addresses of one IPv6 /64 share the count too", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier, limits: { verifyPerIpDay: 2, verifyPerAccountDay: 100 } });
      try {
        const [a, b] = [await signedIn(app), await signedIn(app)];
        const prefix = `2001:db8:${(++seq).toString(16)}:7`;
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: `${prefix}::1` })).statusCode, 202);
        assert.equal((await b.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: `${prefix}:abcd::2` })).statusCode, 202);
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: `${prefix}:ffff:ffff:ffff:ffff` })).statusCode, 429);
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: `2001:db8:${(++seq).toString(16)}:8::1` })).statusCode, 202, "another prefix");
      } finally {
        await app.close();
      }
    });

    test("one account's count follows it across addresses", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier, limits: { verifyPerIpDay: 100, verifyPerAccountDay: 2 } });
      try {
        const a = await signedIn(app);
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: nextIp() })).statusCode, 202);
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: nextIp() })).statusCode, 202);
        const over = await a.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: nextIp(), headers: { "x-forwarded-for": "198.51.100.200" } });
        assert.equal(over.statusCode, 429);
        assert.equal(verifier.started.length, 2);
        // A different account is not stopped by it.
        const b = await signedIn(app);
        assert.equal((await b.api("POST", "/v1/phone/verification", { phone: nextPhone() }, { ip: nextIp() })).statusCode, 202);
      } finally {
        await app.close();
      }
    });

    test("the number is counted under a keyed hash, and counts made under the old plain hash still count", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier, limits: { verifyPerIpDay: 100, verifyPerAccountDay: 100 } });
      try {
        const a = await signedIn(app);
        const phone = nextPhone();
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone })).statusCode, 202);
        const { rows } = await db.query<{ phone_hash: Buffer; ip_hash: Buffer; account_hash: Buffer }>(
          "SELECT phone_hash, ip_hash, account_hash FROM phone_verification_starts");
        assert.equal(rows.length, 1);
        assert.ok(!rows[0]!.phone_hash.equals(sha256(phone)), "not the bare SHA-256 of the number any more");
        assert.ok(rows[0]!.ip_hash.length === 32 && rows[0]!.account_hash.length === 32);
        // Rows written before the number was keyed: three in the last hour block the number all the same.
        const old = nextPhone();
        for (let i = 0; i < 3; i++) await db.query("INSERT INTO phone_verification_starts (phone_hash) VALUES ($1)", [sha256(old)]);
        const refused = await a.api("POST", "/v1/phone/verification", { phone: old });
        assert.equal(refused.statusCode, 429);
        assert.equal(verifier.started.filter((p) => p === old).length, 0);
      } finally {
        await app.close();
      }
    });

    test("without the encryption key the number is counted under its plain hash, as before", async () => {
      const verifier = new CountingVerifier();
      const { app } = await testApp(db, { verifier, cipher: undefined, limits: { verifyPerIpDay: 100, verifyPerAccountDay: 100 } });
      try {
        const a = await signedIn(app);
        const phone = nextPhone();
        assert.equal((await a.api("POST", "/v1/phone/verification", { phone })).statusCode, 202);
        const { rows } = await db.query<{ phone_hash: Buffer }>("SELECT phone_hash FROM phone_verification_starts");
        assert.ok(rows[0]!.phone_hash.equals(sha256(phone)));
      } finally {
        await app.close();
      }
    });
  });


  // ---------------------------------------------------------------------------------------------------------------
  describe("a news digest keeps going when one channel can't take it (ADR-704, ADR-706)", () => {
    const NOW = new Date("2026-10-10T06:00:00Z");
    const stories: NewsItem[] = [1, 2, 3].map((n) => ({
      title: `Chip story ${n}`, url: `https://news.example/chips-${n}`, source: "BBC", summary: "", publishedAt: new Date(NOW.getTime() - n * 3_600_000).toISOString(),
    }));
    const feeds: FeedSource = { fetchFeed: async () => ({ title: "Feed", items: stories }) };

    /** An account with push and texts on that asked for a digest on both channels. */
    async function subscriber(app: FastifyInstance) {
      const a = await signedIn(app, { phone: nextPhone() });
      await a.api("PUT", "/v1/phone/sms-consent", { consent: true, textVersion: "sms-v1" });
      await a.api("PUT", "/v1/device/push-token", { token: Math.random().toString(16).slice(2).padEnd(64, "b").slice(0, 64), environment: "sandbox" });
      const put = await a.api("PUT", "/v1/news/settings", {
        enabled: true, sendTime: "08:00", timezone: "Europe/Warsaw", channels: ["push", "sms"], language: "en", topics: [{ catalogId: "technology" }], feeds: [],
      });
      assert.equal(put.statusCode, 200, put.body);
      return a;
    }
    const channelsOf = async (accountId: string) =>
      (await db.query<{ channel: string }>("SELECT channel FROM outbound_messages WHERE account_id = $1 ORDER BY channel", [accountId])).rows.map((r) => r.channel);

    test("when the day's texts are used up, the push still goes and the digest is kept; the text is skipped", async () => {
      const { app } = await testApp(db, { limits: { smsPerAccountDay: 1 } });
      try {
        const a = await subscriber(app);
        // The account's one text of the day goes to something else.
        assert.equal((await a.api("POST", "/v1/updates", { text: "hej", channels: ["sms"], idempotencyKey: "uses-the-text" })).statusCode, 202);
        const news: NewsDeps = { feeds, cipher: testCipher, smsCaps: { perAccount: 1, perServer: 100 } };
        const r = await buildDigest(db, news, a.accountId, "manual", NOW);
        assert.equal(r.status, "queued", "queued through the push");
        assert.deepEqual(await channelsOf(a.accountId), ["push", "sms"], "the digest's push and the update's text");
        const { rows } = await db.query<{ channel: string; idempotency_key: string }>("SELECT channel, idempotency_key FROM outbound_messages WHERE account_id = $1", [a.accountId]);
        assert.deepEqual(rows.filter((x) => x.idempotency_key.startsWith("news:")).map((x) => x.channel), ["push"], "no news text");
        assert.equal((await db.query("SELECT 1 FROM news_digest_items WHERE digest_id = $1", [r.digestId])).rowCount, 3, "the digest is kept for the app");
      } finally {
        await app.close();
      }
    });

    test("when no channel can take it the digest is ready in the app and nothing is lost", async () => {
      const { app } = await testApp(db);
      try {
        const a = await subscriber(app);
        await db.query("DELETE FROM outbound_messages WHERE account_id = $1", [a.accountId]);
        const news: NewsDeps = { feeds, smsCaps: { perAccount: 1, perServer: 1 } }; // no cipher: production refuses both channels
        const r = await inProduction(() => buildDigest(db, news, a.accountId, "manual", NOW));
        assert.equal(r.status, "ready");
        assert.equal(r.errorCode, "no_channel");
        assert.deepEqual(await channelsOf(a.accountId), []);
        assert.equal((await db.query("SELECT 1 FROM news_digest_items WHERE digest_id = $1", [r.digestId])).rowCount, 3);
      } finally {
        await app.close();
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  describe("queued text is never stored unencrypted in production (ADR-706)", () => {
    const pushUpdate = (a: Awaited<ReturnType<typeof signedIn>>, key: string) =>
      a.api("POST", "/v1/updates", { text: "Your dentist is at 15:00", channels: ["push"], idempotencyKey: key });

    test("without MEMORY_ENCRYPTION_KEY, production queues nothing and answers 503 not_configured", async () => {
      const { app } = await testApp(db, { cipher: undefined });
      try {
        const a = await signedIn(app);
        await a.api("PUT", "/v1/device/push-token", { token: "ef".repeat(32), environment: "sandbox" });
        const r = await inProduction(() => pushUpdate(a, "prod-1"));
        assert.equal(r.statusCode, 503);
        assert.deepEqual(r.json(), { error: "not_configured" });
        assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [a.accountId])).rowCount, 0);
        await assert.rejects(inProduction(() => enqueue(db, a.accountId, ["push"], "x", new Date(), "prod-2")), EncryptionNotConfigured);
      } finally {
        await app.close();
      }
    });

    test("outside production it still works without the key, as it did, and with the key production works", async () => {
      const plain = await testApp(db, { cipher: undefined });
      const keyed = await testApp(db);
      try {
        const a = await signedIn(plain.app);
        await a.api("PUT", "/v1/device/push-token", { token: "01".repeat(32), environment: "sandbox" });
        assert.equal((await pushUpdate(a, "dev-1")).statusCode, 202);
        const { rows } = await db.query<{ body: string | null; body_ciphertext: Buffer | null }>("SELECT body, body_ciphertext FROM outbound_messages WHERE account_id = $1", [a.accountId]);
        assert.deepEqual([rows[0]!.body, rows[0]!.body_ciphertext], ["Your dentist is at 15:00", null], "unchanged outside production");

        const b = await signedIn(keyed.app);
        await b.api("PUT", "/v1/device/push-token", { token: "02".repeat(32), environment: "sandbox" });
        const r = await inProduction(() => pushUpdate(b, "prod-3"));
        assert.equal(r.statusCode, 202);
        const { rows: sealed } = await db.query<{ body: string | null; body_ciphertext: Buffer | null }>("SELECT body, body_ciphertext FROM outbound_messages WHERE account_id = $1", [b.accountId]);
        assert.equal(sealed[0]!.body, null);
        assert.ok(sealed[0]!.body_ciphertext);
      } finally {
        await plain.app.close();
        await keyed.app.close();
      }
    });

    test("a queued text is still sent in production: the worker reads rows written before", async () => {
      const push = new FakePush();
      const { app } = await testApp(db, { cipher: undefined, push });
      try {
        const a = await signedIn(app);
        await a.api("PUT", "/v1/device/push-token", { token: "03".repeat(32), environment: "sandbox" });
        assert.equal((await pushUpdate(a, "old-row")).statusCode, 202); // plain row, as an earlier release would have queued it
        await inProduction(() => dispatchDue(db, { push }));
        assert.deepEqual(push.sent.map((p) => p.body), ["Your dentist is at 15:00"]);
      } finally {
        await app.close();
      }
    });

    test("a PIN lock is still recorded when its alert can't be queued", async () => {
      const { app } = await testApp(db, { cipher: undefined });
      try {
        const phone = nextPhone();
        const a = await signedIn(app, { phone });
        const inj = (url: string, payload: object, headers: Record<string, string>, method: "POST" | "PUT" = "POST") => app.inject({ method, url, headers, payload });
        assert.equal((await inj("/v1/calls/pin", { pin: "258025" }, a.h, "PUT")).statusCode, 204);
        assert.equal((await inj("/v1/calls/settings", { inboundEnabled: true }, a.h, "PUT")).statusCode, 204);
        assert.equal((await inj("/v1/device/push-token", { token: "04".repeat(32), environment: "sandbox" }, a.h, "PUT")).statusCode, 204);
        const start = await inj("/webhooks/elevenlabs/call-start", { caller_id: phone }, { "x-doddy-tool-secret": TOOL_SECRET });
        const session = start.json().dynamic_variables.secret__doddy_session as string;
        let last;
        await inProduction(async () => {
          for (let i = 0; i < 5; i++) {
            last = await inj("/webhooks/elevenlabs/tools/verify-pin", { pin: "000000" }, { "x-doddy-tool-secret": TOOL_SECRET, "x-doddy-session": session });
          }
        });
        assert.equal(last!.statusCode, 200);
        assert.deepEqual(last!.json(), { status: "locked", minutes: 15 });
        const { rows } = await db.query<{ locked: boolean }>("SELECT pin_locked_until > now() AS locked FROM call_settings WHERE account_id = $1", [a.accountId]);
        assert.equal(rows[0]!.locked, true, "the lock stands");
        assert.equal((await db.query("SELECT 1 FROM outbound_messages WHERE account_id = $1", [a.accountId])).rowCount, 0, "and no text was stored in the clear");
      } finally {
        await app.close();
      }
    });
  });
});
