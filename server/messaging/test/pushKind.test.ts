import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { pushData } from "../src/outbox.js";

describe("what a tap on a push opens", () => {
  it("a finished call's push says only its kind", () => {
    assert.deepEqual(pushData("call-result:6f1c2a9e-0000-4000-8000-000000000000"), { kind: "call-result" });
    // Never the attempt, the case or any words: the payload is readable on the Lock Screen.
    assert.deepEqual(Object.keys(pushData("call-result:abc")!), ["kind"]);
  });

  it("every other push carries nothing extra", () => {
    for (const key of [undefined, "", "errand-result:1", "news:2026-11-05", "call-results", "xcall-result:1"]) {
      assert.equal(pushData(key), undefined, String(key));
    }
  });
});
