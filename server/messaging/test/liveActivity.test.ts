import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { liveActivityRequest } from "../src/providers/apns.js";
import { finishedContent, MAX_TIMER_ATTEMPTS, nextState, toActivityDate } from "../src/liveActivity.js";

const TOKEN = "cd".repeat(32);

describe("Live Activity pushes (ADR-483)", () => {
  test("the request targets the activity token on the liveactivity topic", () => {
    const r = liveActivityRequest("com.example.doddy", { activityToken: TOKEN, environment: "sandbox" },
      { event: "update", contentState: { isPaused: false }, alert: { title: "Time's up", body: "Done." } }, 1000);
    assert.equal(r.path, `/3/activity/${TOKEN}`);
    assert.equal(r.headers["apns-topic"], "com.example.doddy.push-type.liveactivity");
    assert.equal(r.headers["apns-push-type"], "liveactivity");
    assert.equal(r.headers["apns-priority"], "10");
    const aps = JSON.parse(r.body).aps;
    assert.equal(aps.timestamp, 1000);
    assert.equal(aps.event, "update");
    assert.deepEqual(aps["content-state"], { isPaused: false });
    assert.deepEqual(aps.alert, { title: "Time's up", body: "Done.", sound: "default" });
  });

  test("a silent update has no alert and a lower priority", () => {
    const r = liveActivityRequest("com.example.doddy", { activityToken: TOKEN, environment: "production" },
      { event: "end", contentState: {} }, 5);
    assert.equal(r.headers["apns-priority"], "5");
    assert.equal(JSON.parse(r.body).aps.alert, undefined);
    assert.equal(JSON.parse(r.body).aps.event, "end");
  });

  test("dates are seconds since 2001-01-01, as ActivityKit reads them", () => {
    assert.equal(toActivityDate(new Date("2001-01-01T00:00:00Z")), 0);
    assert.equal(toActivityDate(new Date("2001-01-01T00:00:10.500Z")), 10.5);
  });

  test("the finished timer's content keys match the app's ContentState", () => {
    const c = finishedContent({ endsAt: new Date("2001-01-01T00:01:00Z"), label: "Pasta" });
    assert.deepEqual(c, { isPaused: false, endsAt: 60, remaining: 0, label: "Pasta", isFinished: true });
    assert.equal(finishedContent({ endsAt: new Date("2001-01-01T00:01:00Z") }).label, null);
  });

  test("a result decides whether the timer is sent, retried or failed", () => {
    assert.deepEqual(nextState({ kind: "accepted", providerId: "x" }, 1), { state: "sent" });
    assert.deepEqual(nextState({ kind: "transient", code: "apns_503" }, 1), { state: "queued", error: "apns_503" });
    assert.deepEqual(nextState({ kind: "transient", code: "apns_503" }, MAX_TIMER_ATTEMPTS),
      { state: "failed", error: "apns_503" });
    assert.deepEqual(nextState({ kind: "rejected", code: "apns_BadDeviceToken" }, 1), { state: "failed", error: "apns_BadDeviceToken" });
    // Unknown outcomes are never retried: the alert may already have been shown.
    assert.deepEqual(nextState({ kind: "unknown", code: "apns_timeout" }, 1), { state: "failed", error: "apns_timeout" });
  });
});
