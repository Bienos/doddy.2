import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { CAL, FakeComposio, type Harness, harness, liveProvider, PLANTED_TOKEN, USER_B } from "./helpers.js";

let h: Harness;
afterEach(async () => h?.close());

async function start(h: Harness, fake: FakeComposio, token?: string) {
  const res = await h.call("POST", `${CAL}/connect`, { body: {}, ...(token ? { token } : {}) });
  assert.equal(res.status, 200, res.text);
  const pending = [...fake.accounts.keys()].at(-1)!;
  return { ...res.body, pending } as { attemptId: string; nonce: string; authorizationUrl: string; pending: string };
}

const complete = (h: Harness, s: { attemptId: string; nonce: string }, result: unknown, token?: string) =>
  h.call("POST", `${CAL}/complete`, { body: { attemptId: s.attemptId, nonce: s.nonce, result }, ...(token ? { token } : {}) });

test("callback flow: link is created server-side for the authenticated user; success is verified, not trusted", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  assert.match(s.authorizationUrl, /^https:\/\/connect\.composio\.dev\//);
  // The Composio user is Doddy's random per-user ID, never an email or the internal ID.
  const owner = fake.accounts.get(s.pending)!.userId;
  assert.match(owner, /^doddy_[0-9a-f]{32}$/);

  fake.activate(s.pending);
  const done = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.equal(done.status, 200, done.text);
  assert.equal(done.body.connection.status, "connected");
  assert.equal(done.body.receipt.status, "succeeded");
  assert.ok(fake.calls.includes("get") && fake.calls.includes("list"), "status and ownership were re-read");
  assert.ok(!done.text.includes(PLANTED_TOKEN));
});

test("forged success: a 'success' redirect for a connection that never activated connects nothing", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  const done = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.equal(done.body.error.code, "attempt_invalid");
  assert.equal(done.body.error.receipt.status, "failed");
  assert.equal((await h.call("GET", CAL)).body.status, "disconnected");
});

test("tampered completion: another connection ID, or success without an ID, is rejected", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.addAccount({ id: "ca_someone_else", userId: "doddy_other" });
  fake.activate(s.pending);
  const swapped = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: "ca_someone_else" });
  assert.equal(swapped.body.error.code, "attempt_invalid");
  assert.equal(swapped.body.error.receipt.errorCode, "attempt_mismatch");

  const s2 = await start(h, fake);
  fake.activate(s2.pending);
  const missing = await complete(h, s2, { kind: "callback", status: "success" });
  assert.equal(missing.body.error.code, "attempt_invalid");
  assert.equal((await h.call("GET", CAL)).body.status, "disconnected");
});

test("ownership is checked with the provider: a connection owned by another Composio user is refused", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.activate(s.pending);
  fake.accounts.get(s.pending)!.userId = "doddy_attacker";
  const done = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.equal(done.body.error.receipt.errorCode, "verification_failed");
});

test("wrong provider/auth config on the returned connection is refused", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.activate(s.pending);
  fake.accounts.get(s.pending)!.toolkit = "gmail";
  const done = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.equal(done.body.error.receipt.errorCode, "verification_failed");
});

test("a completion that fails after the grant became active removes it at the provider", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.activate(s.pending);
  fake.accounts.get(s.pending)!.toolkit = "gmail"; // verification will fail
  const done = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.equal(done.body.error.receipt.errorCode, "verification_failed");
  assert.ok(!fake.accounts.has(s.pending), "the active grant Doddy didn't keep is gone at the provider");
  assert.equal((await h.call("GET", CAL)).body.remoteCleanup, "none");
});

test("if that removal fails it stays queued, is shown, and is retried before the next connect", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.activate(s.pending);
  fake.accounts.get(s.pending)!.toolkit = "gmail";
  fake.deleteFails = true;
  await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.ok(fake.accounts.has(s.pending));
  assert.equal((await h.call("GET", CAL)).body.remoteCleanup, "failed");
  fake.deleteFails = false;
  assert.equal((await h.call("POST", `${CAL}/connect`, { body: {} })).status, 200);
  assert.ok(!fake.accounts.has(s.pending), "retried before a new link was made");
});

test("a successful completion is kept, not removed", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.activate(s.pending);
  const done = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.equal(done.status, 200);
  assert.ok(fake.accounts.has(s.pending));
  assert.ok(!fake.calls.includes("delete"));
});

test("nonce: missing, tampered, expired and replayed completions are rejected", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.activate(s.pending);
  const result = { kind: "callback", status: "success", connectedAccountId: s.pending };

  const missing = await h.call("POST", `${CAL}/complete`, { body: { attemptId: s.attemptId, result } });
  assert.equal(missing.status, 400);
  const tampered = await complete(h, { ...s, nonce: `${s.nonce.slice(0, -1)}${s.nonce.endsWith("A") ? "B" : "A"}` }, result);
  assert.equal(tampered.body.error.code, "attempt_invalid");

  const ok = await complete(h, s, result);
  assert.equal(ok.status, 200);
  const replay = await complete(h, s, result);
  assert.equal(replay.body.error.code, "attempt_invalid");

  await h.call("POST", `${CAL}/disconnect`, { body: {} });
  const s2 = await start(h, fake);
  fake.activate(s2.pending);
  h.clock.advance(601_000);
  const expired = await complete(h, s2, { kind: "callback", status: "success", connectedAccountId: s2.pending });
  assert.equal(expired.body.error.code, "attempt_invalid");
});

test("mismatched owner: user B cannot complete user A's attempt", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const s = await start(h, fake);
  fake.activate(s.pending);
  const res = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending }, USER_B);
  assert.equal(res.body.error.code, "attempt_invalid");
});

test("a new attempt supersedes the previous unfinished one", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake) });
  const first = await start(h, fake);
  await start(h, fake);
  fake.activate(first.pending);
  const res = await complete(h, first, { kind: "callback", status: "success", connectedAccountId: first.pending });
  assert.equal(res.body.error.code, "attempt_invalid");
});

test("completion kind must match the server's configured flow", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake), completionMode: "verifier" });
  const s = await start(h, fake);
  fake.activate(s.pending);
  const viaCallback = await complete(h, s, { kind: "callback", status: "success", connectedAccountId: s.pending });
  assert.equal(viaCallback.body.error.receipt.errorCode, "completion_mode_mismatch");
  const mock = await complete(h, await start(h, fake), { kind: "mock", outcome: "approve" });
  assert.equal(mock.body.error.code, "attempt_invalid");
});

test("verifier flow: the session URI is redeemed for the authenticated user only and must match the attempt", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake), completionMode: "verifier" });
  const s = await start(h, fake);
  fake.sessions.set("composio://session/abc123", s.pending);
  fake.accounts.get(s.pending)!.scope = "https://www.googleapis.com/auth/calendar.events.readonly";
  const done = await complete(h, s, { kind: "verifier", sessionUri: "composio://session/abc123" });
  assert.equal(done.status, 200, done.text);
  assert.equal(done.body.connection.status, "connected");
  // Single use at the provider too.
  await h.call("POST", `${CAL}/disconnect`, { body: {} });
  const s2 = await start(h, fake);
  assert.notEqual((await complete(h, s2, { kind: "verifier", sessionUri: "composio://session/abc123" })).status, 200);
});

test("verifier flow: a session belonging to another user's pending connection is refused", async () => {
  const fake = new FakeComposio();
  h = await harness({ provider: liveProvider(fake), completionMode: "verifier" });
  const a = await start(h, fake);
  const b = await start(h, fake, USER_B);
  fake.sessions.set("composio://session/victim", a.pending);
  // B holds a valid attempt of their own but presents A's session URI.
  const res = await complete(h, b, { kind: "verifier", sessionUri: "composio://session/victim" }, USER_B);
  assert.notEqual(res.status, 200);
  assert.equal((await h.call("GET", CAL, { token: USER_B })).body.status, "disconnected");
});

test("browser return routes only forward allowlisted parameters to the configured app URL", async () => {
  h = await harness();
  const res = await h.call(
    "GET",
    "/v1/oauth/return?attempt=8b0c7f1e-2d3a-4b5c-9d8e-0f1a2b3c4d5e&status=success&connected_account_id=ca_1&redirect=https://evil.example&user_id=victim",
    { token: null },
  );
  assert.equal(res.status, 302);
  const location = new URL(res.headers.get("location")!);
  assert.equal(`${location.protocol}//${location.host}${location.pathname}`, "doddy-dev://connected-apps/return");
  assert.deepEqual([...location.searchParams.keys()].sort(), ["attempt", "connected_account_id", "status"]);

  const bad = await h.call("GET", "/v1/oauth/return?attempt=not-a-uuid&status=pwned&connected_account_id=<script>", { token: null });
  assert.equal(new URL(bad.headers.get("location")!).search, "");

  const verify = await h.call("GET", "/v1/oauth/verify?session_uri=composio://session/xyz&user_id=1", { token: null });
  assert.deepEqual([...new URL(verify.headers.get("location")!).searchParams.keys()], ["session_uri"]);
});

test("cancel and denial are recorded as such, not as failures of Doddy or as success", async () => {
  h = await harness();
  const s1 = await h.call("POST", `${CAL}/connect`, { body: {} });
  const cancel = await complete(h, s1.body, { kind: "canceled" });
  assert.equal(cancel.body.receipt.status, "canceled");
  const s2 = await h.call("POST", `${CAL}/connect`, { body: {} });
  const deny = await complete(h, s2.body, { kind: "mock", outcome: "deny" });
  assert.equal(deny.body.receipt.status, "failed");
  assert.equal(deny.body.receipt.errorCode, "access_denied");
  assert.equal(deny.body.connection.status, "disconnected");
});
