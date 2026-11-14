// Calls Doddy makes for a user: the per-user limits follow the account, not only the verified number, and an operator's
// stop list refuses a callee (security review 4 Nov 2026, ADR-705). Against real Postgres with fake Twilio and ElevenLabs,
// like taskCalls.test.ts; nothing here calls a provider.
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { DEFAULT_TASK_CALL_SETTINGS } from "../src/config.js";
import type { Db } from "../src/db.js";
import type { TaskCallContext } from "../src/taskCalls/context.js";
import { callerPhoneHash } from "../src/taskCalls/payload.js";
import { dbSkip, freshDb, sampleBrief, taskTestApp, type FakeTelephony, type FakeVoice, type TaskTestOptions } from "./helpers.js";

describe("call case limits against real Postgres (ADR-705)", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM call_dial_log"); });

  let seq = 0;
  const nextPhone = () => `+48501${String(100000 + ++seq).slice(-6)}`;
  const nextDestination = () => `+4822${String(3000000 + ++seq).slice(-7)}`;

  interface World {
    app: FastifyInstance; telephony: FakeTelephony; voice: FakeVoice; ctx: TaskCallContext; settings: NonNullable<TaskTestOptions["settings"]>;
    logs: { msg: string; extra?: object }[];
  }
  async function world(opts: TaskTestOptions = {}): Promise<World> {
    const w = await taskTestApp(db, opts);
    return { app: w.app, telephony: w.telephony, voice: w.voice, ctx: w.app.taskCallContext!, settings: w.settings, logs: w.logs };
  }
  async function user(w: World, phone = nextPhone()) {
    const r = await w.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const verified = (p: string) => w.app.inject({ method: "POST", url: "/v1/phone/verification/check", headers: h, payload: { phone: p, code: "123456" } });
    assert.equal((await verified(phone)).statusCode, 200);
    return { accountId, h, phone, verify: async (p: string) => assert.equal((await verified(p)).statusCode, 200) };
  }
  const api = (w: World, method: "GET" | "POST", url: string, h: object, payload?: unknown) =>
    w.app.inject({ method, url, headers: h as Record<string, string>, payload: payload as never });
  const createCase = (w: World, h: object, phone = nextDestination()) =>
    api(w, "POST", "/v1/call-cases", h, sampleBrief({ callee: { name: "Serwis Laptop", phone, source: "contacts" } }));
  const approve = (w: World, h: object, p: { caseId: string; digest: string }) =>
    api(w, "POST", `/v1/call-cases/${p.caseId}/approve`, h, { digest: p.digest });
  /** Ends the live call, so only the limits (not "one call at a time") can refuse the next one. */
  const settle = (accountId: string) => db.query(
    `UPDATE call_attempts SET state = 'ended', ended_at = now(), settled_at = now(), end_reason = 'completed' WHERE account_id = $1`, [accountId]);

  test("changing the verified number doesn't start the per-user limits again", async () => {
    const w = await world({ settings: { limits: { userPerDay: 1 } as never } });
    try {
      const u = await user(w);
      const first = (await createCase(w, u.h)).json();
      assert.equal((await approve(w, u.h, first)).statusCode, 202);
      assert.equal(w.telephony.created.length, 1);
      await settle(u.accountId);

      await u.verify(nextPhone()); // the same account, a different number: the count used to be keyed by the number alone
      const second = (await createCase(w, u.h)).json();
      const refused = await approve(w, u.h, second);
      assert.equal(refused.statusCode, 409);
      assert.deepEqual([refused.json().error, refused.json().gate], ["gate_refused", "limit_user_day"]);
      assert.equal(w.telephony.created.length, 1, "no second call was placed");
      assert.equal(w.voice.registered.length, 0);
    } finally {
      await w.app.close();
    }
  });

  test("the hourly limit and the limit per callee follow the account too", async () => {
    const w = await world({ settings: { limits: { userPerHour: 1 } as never } });
    try {
      const u = await user(w);
      const first = (await createCase(w, u.h)).json();
      assert.equal((await approve(w, u.h, first)).statusCode, 202);
      await settle(u.accountId);
      await u.verify(nextPhone());
      const second = (await createCase(w, u.h)).json();
      assert.equal((await approve(w, u.h, second)).json().gate, "limit_user_hour");

      const v = await world({ settings: { limits: { destinationPerUserDay: 1 } as never } });
      try {
        const x = await user(v);
        const d = nextDestination();
        const one = (await createCase(v, x.h, d)).json();
        assert.equal((await approve(v, x.h, one)).statusCode, 202);
        await settle(x.accountId);
        await x.verify(nextPhone());
        const two = (await createCase(v, x.h, d)).json();
        // Every per-number limit answers with one code, so a refusal never says whether others called the number.
        assert.equal((await approve(v, x.h, two)).json().gate, "limit_destination");
        assert.ok(v.logs.some((l) => l.msg === "task call limit" && (l.extra as { limit?: string }).limit === "limit_destination_user_day"));
        assert.equal(v.telephony.created.length, 1);
      } finally {
        await v.app.close();
      }
    } finally {
      await w.app.close();
    }
  });

  test("a dial is logged with a keyed hash of the account, never the account id", async () => {
    const w = await world();
    try {
      const u = await user(w);
      const p = (await createCase(w, u.h)).json();
      assert.equal((await approve(w, u.h, p)).statusCode, 202);
      const { rows } = await db.query<{ caller_account_hash: Buffer | null }>("SELECT caller_account_hash FROM call_dial_log");
      assert.equal(rows.length, 1);
      assert.equal(rows[0]!.caller_account_hash?.length, 32);
      assert.ok(!rows[0]!.caller_account_hash!.toString("hex").includes(u.accountId.replace(/-/g, "")));
    } finally {
      await w.app.close();
    }
  });

  test("rows written before the account hash existed still count by number", async () => {
    const w = await world({ settings: { limits: { userPerDay: 1 } as never } });
    try {
      const u = await user(w);
      await db.query("INSERT INTO call_dial_log (destination_hash, caller_phone_hash, dialed_at) VALUES ($1, $2, $3)",
        [Buffer.alloc(32, 1), callerPhoneHash(w.ctx.keys, u.phone), w.ctx.now()]);
      const p = (await createCase(w, u.h)).json();
      const refused = await approve(w, u.h, p);
      assert.equal(refused.json().gate, "limit_user_day");
      assert.equal(w.telephony.created.length, 0);
    } finally {
      await w.app.close();
    }
  });

  test("another account is not stopped by someone else's count", async () => {
    const w = await world({ settings: { limits: { userPerDay: 1 } as never } });
    try {
      const a = await user(w);
      const b = await user(w);
      assert.equal((await approve(w, a.h, (await createCase(w, a.h)).json())).statusCode, 202);
      assert.equal((await approve(w, b.h, (await createCase(w, b.h)).json())).statusCode, 202);
      assert.equal(w.telephony.created.length, 2);
    } finally {
      await w.app.close();
    }
  });

  // ---------------------------------------------------------------------------------------------------------------
  test("a blocked number can't be a callee: refused when the brief is made, with nothing built or sent", async () => {
    const blocked = nextDestination();
    const w = await world({ settings: { blockedNumbers: [blocked, "+48500999888"] } });
    try {
      const u = await user(w);
      for (const typed of [blocked, blocked.replace("+48", "").replace(/(\d{2})(\d{3})(\d{2})(\d{2})/, "$1 $2 $3 $4"), `0048${blocked.slice(3)}`, ` ${blocked} `]) {
        const r = await createCase(w, u.h, typed);
        assert.equal(r.statusCode, 400, typed);
        assert.deepEqual(r.json(), { error: "destination_refused", reason: "blocked" });
      }
      assert.equal((await db.query("SELECT 1 FROM call_cases WHERE account_id = $1", [u.accountId])).rowCount, 0);
      assert.equal((await createCase(w, u.h)).statusCode, 201, "other numbers are as before");
      assert.equal(w.telephony.created.length + w.voice.registered.length, 0);
    } finally {
      await w.app.close();
    }
  });

  test("a number blocked after the user approved is refused at dial time, before Twilio is asked", async () => {
    const w = await world();
    try {
      const u = await user(w);
      const dest = nextDestination();
      const preview = (await createCase(w, u.h, dest)).json();
      w.settings.blockedNumbers = [dest]; // the operator adds it between the brief and the approval
      const refused = await approve(w, u.h, preview);
      assert.equal(refused.statusCode, 409);
      assert.deepEqual([refused.json().error, refused.json().gate], ["gate_refused", "blocked_number"]);
      assert.equal(w.telephony.created.length, 0, "Twilio was not asked");
      assert.equal(w.voice.registered.length, 0);
      assert.equal((await db.query("SELECT 1 FROM call_dial_log")).rowCount, 0, "and nothing was logged as dialled");
    } finally {
      await w.app.close();
    }
  });

  test("with no stop list nothing changes", () => {
    assert.deepEqual(DEFAULT_TASK_CALL_SETTINGS.blockedNumbers, []);
  });
});
