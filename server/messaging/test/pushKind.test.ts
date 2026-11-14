import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { pushData } from "../src/outbox.js";
import { alertPayload } from "../src/providers/apns.js";

describe("what a tap on a push opens", () => {
  it("a finished call's push says only its kind", () => {
    assert.deepEqual(pushData("call-result:6f1c2a9e-0000-4000-8000-000000000000"), { kind: "call-result" });
    // Never the attempt, the case or any words: the payload is readable on the Lock Screen.
    assert.deepEqual(Object.keys(pushData("call-result:abc")!), ["kind"]);
  });

  it("a finished task or file opens Messages, by kind only", () => {
    assert.deepEqual(pushData("errand-result:6f1c2a9e-0000-4000-8000-000000000000"), { kind: "errand-result" });
    assert.deepEqual(pushData("file-watch:abc"), { kind: "file-ready" });
    assert.deepEqual(Object.keys(pushData("errand-result:abc")!), ["kind"]);
  });

  it("a radar story's push opens On my radar, by kind only (decision 2026-11-13-radar-fixes)", () => {
    const key = "radar:6f1c2a9e-0000-4000-8000-000000000000:7a2d3b0f-0000-4000-8000-000000000000";
    assert.deepEqual(pushData(key), { kind: "radar" });
    // Never the alert, the follow, the story or the words.
    assert.deepEqual(Object.keys(pushData(key)!), ["kind"]);
    // A radar push doesn't wake the app: the list is read when On my radar opens.
    assert.deepEqual(alertPayload({ title: "Doddy", body: "x" }, { kind: "radar" }), {
      aps: { alert: { title: "Doddy", body: "x" }, sound: "default" }, doddy: { kind: "radar" },
    });
  });

  it("a deal watch's push opens Shopping, by kind only (decision 2026-11-13-leaflet-results-and-deal-watches)", () => {
    const key = "deal-watch:6f1c2a9e-0000-4000-8000-000000000000:0123456789abcdef0123456789abcdef";
    assert.deepEqual(pushData(key), { kind: "deal-watch" });
    // Never the watch, the item, the shop or the price; it doesn't wake the app (the matches are read when it opens).
    assert.deepEqual(Object.keys(pushData(key)!), ["kind"]);
    assert.deepEqual(alertPayload({ title: "Doddy", body: "x" }, { kind: "deal-watch" }), {
      aps: { alert: { title: "Doddy", body: "x" }, sound: "default" }, doddy: { kind: "deal-watch" },
    });
  });

  it("every other push carries nothing extra", () => {
    for (const key of [undefined, "", "news:2026-11-05", "call-results", "xcall-result:1", "xerrand-result:1", "file-watches",
      "radars:1", "xradar:1", "deal-watches:1", "xdeal-watch:1", "watch-triggered:1"]) {
      assert.equal(pushData(key), undefined, String(key));
    }
  });
});

describe("a finished task's or file's push wakes the app to save the result (12 Nov 2026)", () => {
  const alert = { title: "Doddy", body: "Gotowe." };
  it("adds content-available to the alert for a task or a file, and only for them", () => {
    assert.deepEqual(alertPayload(alert, { kind: "errand-result" }), {
      aps: { alert, sound: "default", "content-available": 1 }, doddy: { kind: "errand-result" },
    });
    assert.deepEqual(alertPayload(alert, { kind: "file-ready" }), {
      aps: { alert, sound: "default", "content-available": 1 }, doddy: { kind: "file-ready" },
    });
    assert.deepEqual(alertPayload(alert, { kind: "call-result" }), { aps: { alert, sound: "default" }, doddy: { kind: "call-result" } });
    assert.deepEqual(alertPayload(alert), { aps: { alert, sound: "default" } });
  });
});
