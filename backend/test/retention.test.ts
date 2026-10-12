import assert from "node:assert/strict";
import { test } from "node:test";
import type { Receipt } from "../src/contracts.js";
import { Store } from "../src/store.js";

const DAY = 86_400_000;
const NOW = Date.parse("2026-10-11T10:00:00Z");
const USER = "00000000-0000-4000-8000-00000000000a";

const receipt = (n: number) => ({ operationId: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, summary: `r${n}` }) as unknown as Receipt;

test("prune keeps live rows and drops expired attempts and approvals, old usage and old or excess receipts", () => {
  const store = new Store(":memory:");
  try {
    store.composioUserId(USER, NOW); // creates the user row
    store.createAttempt({ userId: USER, provider: "gmail", authConfigId: "ac", now: NOW - 3 * DAY, ttlSeconds: 600 });
    const live = store.createAttempt({ userId: USER, provider: "gmail", authConfigId: "ac", now: NOW, ttlSeconds: 600 });
    store.createApproval({ userId: USER, capability: "draft_email", accountId: "ca", argsDigest: "d", now: NOW - 3 * DAY, ttlSeconds: 120 });
    const approval = store.createApproval({ userId: USER, capability: "draft_email", accountId: "ca", argsDigest: "d", now: NOW, ttlSeconds: 120 });
    store.reserveUsage([{ counter: "service:calls", period: "day:2026-01-01", limit: 10 }], 1);
    store.reserveUsage([{ counter: "service:calls", period: "day:2026-10-11", limit: 10 }], 1);
    store.reserveUsage([{ counter: "service:calls", period: "month:2025-01", limit: 10 }], 1);
    store.reserveUsage([{ counter: "service:calls", period: "month:2026-10", limit: 10 }], 1);
    store.saveReceipt(USER, receipt(0), NOW - 100 * DAY);
    for (let i = 1; i <= 205; i++) store.saveReceipt(USER, receipt(i), NOW - (205 - i) * 1000);

    const gone = store.prune(NOW);
    assert.deepEqual(gone, { attempts: 1, approvals: 1, usage: 2, receipts: 6, toolReceipts: 0, paymentReceipts: 0, payments: 0 });

    assert.ok(store.consumeAttempt({ attemptId: live.attemptId, userId: USER, provider: "gmail", nonce: live.nonce, now: NOW }), "a live attempt still works");
    assert.ok(store.consumeApproval({ approvalId: approval.approvalId, userId: USER, capability: "draft_email", accountId: "ca", argsDigest: "d", now: NOW }));
    assert.equal(store.usage("service:calls", "day:2026-10-11"), 1);
    assert.equal(store.usage("service:calls", "month:2026-10"), 1);
    assert.equal(store.usage("service:calls", "day:2026-01-01"), 0);
    const kept = store.receipts(USER, 500);
    assert.equal(kept.length, 200);
    assert.equal((kept[0] as unknown as { summary: string }).summary, "r205", "newest kept");
  } finally {
    store.close();
  }
});

test("prune applies the same retention to payment receipts and the payments ledger", () => {
  const store = new Store(":memory:");
  try {
    const row = (id: string, now: number) => ({ paymentId: id, userId: USER, now, host: "shop.example", amount: 50_000, network: "base-sepolia", urlHash: "h", validBefore: 1 });
    store.insertPayment(row("old", NOW - 100 * DAY));
    store.insertPayment(row("new", NOW - DAY));
    store.savePaymentReceipt(USER, receipt(0), NOW - 100 * DAY);
    for (let i = 1; i <= 205; i++) store.savePaymentReceipt(USER, receipt(i), NOW - (205 - i) * 1000);

    const gone = store.prune(NOW);
    assert.equal(gone.payments, 1);
    assert.equal(gone.paymentReceipts, 6);
    assert.equal(store.paymentReceipts(USER, 500).length, 200);
    assert.equal(store.unresolvedPayments(USER, NOW, 5 * 60_000), 1, "the recent unfinished row is still reported; the old one is gone");
  } finally {
    store.close();
  }
});
