import assert from "node:assert/strict";
import { test } from "node:test";
import { mapProviderError, removeComposioConnection } from "../src/providers/composioShared.js";

const httpError = (status: number) => Object.assign(new Error("x"), { status });
const named = (name: string) => Object.assign(new Error("x"), { name });

test("a 404 means an expired account only for account lookups, not when running a tool", () => {
  assert.equal(mapProviderError(httpError(404)).code, "connection_expired");
  assert.equal(mapProviderError(httpError(410)).code, "connection_expired");
  assert.equal(mapProviderError(httpError(404), { execute: true }).code, "provider_unavailable");
  // A missing account is still recognised by its own error name, whatever the call.
  assert.equal(mapProviderError(named("ComposioConnectedAccountNotFoundError"), { execute: true }).code, "connection_expired");
  assert.equal(mapProviderError(httpError(429), { execute: true }).code, "rate_limited");
});

test("removing a connection: a revoke that times out stops before the delete", async () => {
  const calls: string[] = [];
  const client = (revoke: () => Promise<unknown>, del: () => Promise<unknown>) => ({
    connectedAccounts: {
      revoke: async () => { calls.push("revoke"); return revoke(); },
      delete: async () => { calls.push("delete"); return del(); },
    },
  }) as never;
  const signal = new AbortController().signal;

  assert.equal(await removeComposioConnection(client(async () => { throw named("TimeoutError"); }, async () => ({})), "ca_1", signal), "failed");
  assert.deepEqual(calls, ["revoke"]);

  calls.length = 0;
  assert.equal(await removeComposioConnection(client(async () => { throw httpError(400); }, async () => ({})), "ca_1", signal), "removed");
  assert.deepEqual(calls, ["revoke", "delete"], "a toolkit that can't revoke is still deleted");

  calls.length = 0;
  assert.equal(await removeComposioConnection(client(async () => ({}), async () => { throw named("ComposioConnectedAccountNotFoundError"); }), "ca_1", signal), "removed");
  assert.equal(await removeComposioConnection(client(async () => ({}), async () => { throw httpError(500); }), "ca_1", signal), "failed");
});
