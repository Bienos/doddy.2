import assert from "node:assert/strict";
import { test } from "node:test";
import type { Receipt } from "../src/contracts.js";
import { Store } from "../src/store.js";

const DAY = 86_400_000;
const NOW = Date.parse("2026-10-11T10:00:00Z");
const USER = "00000000-0000-4000-8000-00000000000a";

const receipt = (n: number) => ({ operationId: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, summary: `r${n}` }) as unknown as Receipt;

test("prune keeps live rows and drops expired attempts and approvals, old usage and old or excess receipts", async () => {
  const store = await Store.memory();
  try {
    (await store.composioUserId(USER, NOW)); // creates the user row
    (await store.createAttempt({ userId: USER, provider: "gmail", authConfigId: "ac", now: NOW - 3 * DAY, ttlSeconds: 600 }));
    const live = (await store.createAttempt({ userId: USER, provider: "gmail", authConfigId: "ac", now: NOW, ttlSeconds: 600 }));
    (await store.createApproval({ userId: USER, capability: "draft_email", accountId: "ca", argsDigest: "d", now: NOW - 3 * DAY, ttlSeconds: 120 }));
    const approval = (await store.createApproval({ userId: USER, capability: "draft_email", accountId: "ca", argsDigest: "d", now: NOW, ttlSeconds: 120 }));
    (await store.reserveUsage([{ counter: "service:calls", period: "day:2026-01-01", limit: 10 }], 1));
    (await store.reserveUsage([{ counter: "service:calls", period: "day:2026-10-11", limit: 10 }], 1));
    (await store.reserveUsage([{ counter: "service:calls", period: "month:2025-01", limit: 10 }], 1));
    (await store.reserveUsage([{ counter: "service:calls", period: "month:2026-10", limit: 10 }], 1));
    (await store.saveReceipt(USER, receipt(0), NOW - 100 * DAY));
    for (let i = 1; i <= 205; i++) (await store.saveReceipt(USER, receipt(i), NOW - (205 - i) * 1000));

    const gone = (await store.prune(NOW));
    assert.deepEqual(gone, { attempts: 1, approvals: 1, usage: 2, receipts: 6, toolReceipts: 0 });

    assert.ok((await store.consumeAttempt({ attemptId: live.attemptId, userId: USER, provider: "gmail", nonce: live.nonce, now: NOW })), "a live attempt still works");
    assert.ok((await store.consumeApproval({ approvalId: approval.approvalId, userId: USER, capability: "draft_email", accountId: "ca", argsDigest: "d", now: NOW })));
    assert.equal((await store.usage("service:calls", "day:2026-10-11")), 1);
    assert.equal((await store.usage("service:calls", "month:2026-10")), 1);
    assert.equal((await store.usage("service:calls", "day:2026-01-01")), 0);
    const kept = (await store.receipts(USER, 500));
    assert.equal(kept.length, 200);
    assert.equal((kept[0] as unknown as { summary: string }).summary, "r205", "newest kept");
  } finally {
    (await store.close());
  }
});
