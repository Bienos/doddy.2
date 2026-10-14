import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import type { Db } from "../src/db.js";
import { cancelTimer, dispatchDueTimers, scheduleTimer } from "../src/liveActivity.js";
import type { LiveActivityPush, LiveActivitySender, LiveActivityTarget, SendOutcome } from "../src/providers/types.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

class FakeLiveActivity implements LiveActivitySender {
  sent: { target: LiveActivityTarget; push: LiveActivityPush; id: string }[] = [];
  next: SendOutcome[] = [];
  async sendLiveActivity(target: LiveActivityTarget, push: LiveActivityPush, id: string): Promise<SendOutcome> {
    this.sent.push({ target, push, id });
    return this.next.shift() ?? { kind: "accepted", providerId: id };
  }
}

const TOKEN = "ef".repeat(32);
const inOneMinute = () => new Date(Date.now() + 60_000).toISOString();

describe("timers that end with a Live Activity push", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  let live: FakeLiveActivity;
  let headers: Record<string, string>;
  let accountId: string;

  before(async () => {
    db = await freshDb();
    live = new FakeLiveActivity();
    ({ app } = await testApp(db, { liveActivity: live }));
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: "10.90.0.1" });
    ({ accountId } = r.json() as { accountId: string });
    headers = { authorization: `Bearer ${(r.json() as { deviceToken: string }).deviceToken}` };
  });
  after(async () => {
    await app?.close();
    await db?.end();
  });

  const timerRow = async (id: string) =>
    (await db.query("SELECT state, activity_token, attempts, last_error, send_at FROM live_activity_timers WHERE id = $1", [id])).rows[0];
  const makeDue = (id: string) => db.query("UPDATE live_activity_timers SET send_at = now() - interval '1 second' WHERE id = $1", [id]);

  test("a timer is accepted, validated and cancellable", async () => {
    const ok = await app.inject({ method: "POST", url: "/v1/timers", headers,
      payload: { activityToken: TOKEN, environment: "sandbox", endsAt: inOneMinute(), label: "Pasta" } });
    assert.equal(ok.statusCode, 201);
    const { id } = ok.json() as { id: string };
    assert.equal((await timerRow(id)).state, "queued");

    const past = await app.inject({ method: "POST", url: "/v1/timers", headers,
      payload: { activityToken: TOKEN, environment: "sandbox", endsAt: new Date(Date.now() - 5000).toISOString() } });
    assert.equal(past.statusCode, 400);
    const far = await app.inject({ method: "POST", url: "/v1/timers", headers,
      payload: { activityToken: TOKEN, environment: "sandbox", endsAt: new Date(Date.now() + 3 * 86_400_000).toISOString() } });
    assert.equal(far.statusCode, 400);
    const badToken = await app.inject({ method: "POST", url: "/v1/timers", headers,
      payload: { activityToken: "not-hex", environment: "sandbox", endsAt: inOneMinute() } });
    assert.equal(badToken.statusCode, 400);

    const del = await app.inject({ method: "DELETE", url: `/v1/timers/${id}`, headers });
    assert.equal(del.statusCode, 204);
    const row = await timerRow(id);
    assert.equal(row.state, "cancelled");
    assert.equal(row.activity_token, null);
  });

  test("another account cannot cancel a timer, and the answer looks the same", async () => {
    const { id } = (await app.inject({ method: "POST", url: "/v1/timers", headers,
      payload: { activityToken: TOKEN, environment: "sandbox", endsAt: inOneMinute() } })).json() as { id: string };
    const other = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: "10.90.0.2" });
    const otherHeaders = { authorization: `Bearer ${(other.json() as { deviceToken: string }).deviceToken}` };
    assert.equal((await app.inject({ method: "DELETE", url: `/v1/timers/${id}`, headers: otherHeaders })).statusCode, 204);
    assert.equal((await timerRow(id)).state, "queued");
    assert.equal(await cancelTimer(db, accountId, id), true);
  });

  test("a due timer is sent once; the token is erased when it is final", async () => {
    const id = await scheduleTimer(db, accountId, { activityToken: TOKEN, environment: "sandbox", endsAt: new Date(Date.now() + 60_000), label: "Tea" });
    await makeDue(id);
    const r = await dispatchDueTimers(db, live);
    assert.equal(r.processed, 1);
    assert.equal(live.sent.length, 1);
    assert.equal(live.sent[0]!.push.event, "update");
    assert.equal(live.sent[0]!.push.alert?.title, "Tea");
    assert.equal((await timerRow(id)).state, "sent");
    assert.equal((await timerRow(id)).activity_token, null);
    // A second pass finds nothing to send.
    assert.equal((await dispatchDueTimers(db, live)).processed, 0);
  });

  test("a transient failure is retried later with the token kept; a rejection is final", async () => {
    const id = await scheduleTimer(db, accountId, { activityToken: TOKEN, environment: "sandbox", endsAt: new Date(Date.now() + 60_000) });
    await makeDue(id);
    live.next = [{ kind: "transient", code: "apns_503" }];
    await dispatchDueTimers(db, live);
    let row = await timerRow(id);
    assert.equal(row.state, "queued");
    assert.equal(row.activity_token, TOKEN);
    assert.equal(row.last_error, "apns_503");
    assert.ok(new Date(row.send_at).getTime() > Date.now());

    const id2 = await scheduleTimer(db, accountId, { activityToken: TOKEN, environment: "sandbox", endsAt: new Date(Date.now() + 60_000) });
    await makeDue(id2);
    live.next = [{ kind: "rejected", code: "apns_BadDeviceToken" }];
    await dispatchDueTimers(db, live);
    row = await timerRow(id2);
    assert.equal(row.state, "failed");
    assert.equal(row.activity_token, null);
  });

  test("with no Live Activity sender configured, due timers wait and nothing is sent", async () => {
    const id = await scheduleTimer(db, accountId, { activityToken: TOKEN, environment: "sandbox", endsAt: new Date(Date.now() + 60_000) });
    await makeDue(id);
    assert.equal((await dispatchDueTimers(db, undefined)).processed, 0);
    assert.equal((await timerRow(id)).state, "queued");
  });
});
