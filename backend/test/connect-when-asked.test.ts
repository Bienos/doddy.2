import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { ConfigError, loadConfig, testLimits } from "../src/config.js";
import { DEV_IDENTITIES } from "../src/auth.js";
import { AppError } from "../src/errors.js";
import { UnconfiguredToolsProvider } from "../src/providers/unconfigured.js";
import { Store } from "../src/store.js";
import { CLOUD_TOOLS, TOOLKITS, type ToolkitId } from "../src/tools/catalog.js";
import { MockToolsProvider, type ToolsMockScenario } from "../src/tools/mock.js";
import { CloudToolsService } from "../src/tools/service.js";
import { Clock, USER_A } from "./helpers.js";
import { TOOL_ARGS } from "./toolArgs.js";
import { connect, on, type Rig, runRaw, start } from "./toolsRig.js";

/**
 * ADR-511, "connect when asked" (owner, 2026-10-19): every account stays set up on the server, but
 * for each user nothing is connected and every tool is off until they ask for something that needs
 * it. Then Doddy offers to connect right there, and a verified sign-in switches on only the tool
 * they asked for. The action itself still waits for its own card and tap (ASK-01).
 * Mock provider only: nothing here has run against a real Google account.
 */

let rig: Rig;
afterEach(async () => rig?.close());

const prepare = (r: Rig, tool: string, args: Record<string, unknown>) =>
  r.call("POST", "/v1/tools/prepare", { body: { tool, arguments: args, timeZone: "Europe/Warsaw" } });

/** The stored user id behind the test token (the store is keyed by user id, not token). */
const A = DEV_IDENTITIES[USER_A]!;

const SEND = { to: "anna@example.com", subject: "Running late", body: "I'll be ten minutes late." };

/** A sign-in started from a conversation for one tool; `outcome` is what the user did on the provider's screen. */
async function connectFor(r: Rig, toolkit: string, forTool: string, o: { outcome?: "approve" | "deny" | "cancel"; scenario?: ToolsMockScenario } = {}) {
  const begin = await r.call("POST", `/v1/tools/${toolkit}/connect`, { body: { forTool }, ...(o.scenario ? { scenario: o.scenario } : {}) });
  assert.equal(begin.status, 200, begin.text);
  const result = o.outcome === "cancel" ? { kind: "canceled" } : { kind: "mock", outcome: o.outcome ?? "approve" };
  return r.call("POST", `/v1/tools/${toolkit}/complete`, { body: { attemptId: begin.body.attemptId, nonce: begin.body.nonce, result } });
}

const gmailView = async (r: Rig) => ((await r.call("GET", "/v1/tools")).body.toolkits as any[]).find((t) => t.id === "gmail");
const enabled = (view: any) => (view.tools as any[]).filter((t) => t.enabled).map((t) => t.name);

test("nothing is on until the user asks: a new user has no account connected and every tool off", async () => {
  rig = await start();
  const catalog = await rig.call("GET", "/v1/tools");
  assert.equal(catalog.status, 200);
  for (const section of catalog.body.toolkits) {
    if (section.needsAccount) assert.equal(section.status, "disconnected", section.id);
    assert.deepEqual(enabled(section), [], `${section.id}: every tool starts off`);
  }
});

test("a new user's first ask gets a connect offer, the same error code as before, no approval and no provider call", async () => {
  rig = await start();
  for (const tool of CLOUD_TOOLS) {
    const asked = await prepare(rig, tool.name, TOOL_ARGS[tool.name]!);
    assert.equal(asked.status, 403, `${tool.name}: ${asked.text}`);
    // Older app builds read only the code, which is what they always got (the switch is checked first).
    assert.equal(asked.body.error.code, "capability_disabled", tool.name);
    assert.equal(asked.body.error.approvalId, undefined);
    const offer = asked.body.error.connect;
    assert.ok(offer, `${tool.name} has a connect offer`);
    assert.equal(offer.need, "connect", tool.name);
    assert.equal(offer.toolkit, tool.toolkit, tool.name);
    assert.equal(offer.tool, tool.name);
    assert.equal(offer.accountTitle, TOOLKITS[tool.toolkit].title);
    assert.ok(offer.permissions.length > 0, `${tool.name}: the card can say what will be asked`);
  }
  assert.equal(rig.provider.executed.length, 0, "asking reads and sends nothing");
  assert.ok(!rig.provider.calls.some((c) => c.startsWith("createConnectionLink")), "an offer starts no sign-in");
});

test("Gmail: a first send asks Google only for sending; any other first Gmail ask asks for the full set", async () => {
  rig = await start();
  const send = await prepare(rig, "send_email", SEND);
  assert.deepEqual(send.body.error.connect.permissions, ["Send email on your behalf"]);
  const check = await prepare(rig, "check_email", {});
  assert.deepEqual(check.body.error.connect.permissions, [...TOOLKITS.gmail.permissions]);
  assert.equal(TOOLKITS.gmail.permissions.length, TOOLKITS.gmail.requestedScopes.length, "one plain line per scope asked for");
});

test("the first experience: connecting for a send switches on Send an email alone, sends nothing, and the send still needs its card and tap", async () => {
  rig = await start();
  const done = await connectFor(rig, "gmail", "send_email");
  assert.equal(done.status, 200, done.text);
  assert.ok(rig.provider.calls.includes("createConnectionLink:gmail:narrow"), "the send-only sign-in");
  assert.equal(done.body.receipt.status, "succeeded");
  assert.match(done.body.receipt.summary, /Switched on: Send an email\. Its other tools stay off/);
  assert.equal(done.body.toolkit.status, "connected");
  assert.deepEqual(enabled(done.body.toolkit), ["send_email"], "only the tool the user asked for");
  assert.match(done.body.toolkit.access, /sending only/);
  assert.equal(rig.provider.executed.length, 0, "connecting sends nothing");

  // ASK-01 still holds: no tap, no send.
  assert.equal((await runRaw(rig, "send_email", SEND)).status, 403);
  const card = await prepare(rig, "send_email", SEND);
  assert.equal(card.status, 200, card.text);
  assert.equal(card.body.preview.confirmLabel, "Send");
  const sent = await runRaw(rig, "send_email", SEND, { approvalId: card.body.approvalId });
  assert.equal(sent.status, 200, sent.text);
  assert.match(sent.body.text, /^sent:/);
  assert.deepEqual(rig.provider.executed.map((e) => e.slug), ["GMAIL_SEND_EMAIL"]);
});

test("a send-only connection can't read mail; asking to read offers more permission and keeps sending working until the new sign-in is verified", async () => {
  rig = await start();
  await connectFor(rig, "gmail", "send_email");
  const before = rig.store.getConnection(A, "gmail")!;

  const asked = await prepare(rig, "check_email", {});
  assert.equal(asked.status, 403);
  assert.equal(asked.body.error.connect.need, "more_permission");
  assert.deepEqual(asked.body.error.connect.permissions, [...TOOLKITS.gmail.permissions]);
  // Settings can't switch it on either: the grant doesn't cover it.
  assert.equal((await on(rig, "check_email")).status, 403);

  // The user starts the bigger sign-in, then cancels it: nothing is lost.
  const canceled = await connectFor(rig, "gmail", "check_email", { outcome: "cancel" });
  assert.equal(canceled.status, 200);
  assert.equal(canceled.body.receipt.status, "canceled");
  assert.equal(rig.store.getConnection(A, "gmail")!.connection_id, before.connection_id, "the send-only connection stays");
  assert.deepEqual(enabled(await gmailView(rig)), ["send_email"]);

  // Then does it: the full connection replaces the send-only one, which is removed at the provider.
  const removalsBefore = rig.provider.calls.filter((c) => c === "removeConnection").length;
  assert.equal(removalsBefore, 1, "the canceled attempt's pending connection was removed when it was canceled");
  const done = await connectFor(rig, "gmail", "check_email");
  assert.equal(done.status, 200, done.text);
  assert.ok(rig.provider.calls.includes("createConnectionLink:gmail"), "the full sign-in");
  assert.notEqual(rig.store.getConnection(A, "gmail")!.connection_id, before.connection_id);
  assert.equal(rig.provider.calls.filter((c) => c === "removeConnection").length, removalsBefore + 1, "the old send-only connection is removed");
  // A fresh connection never inherits switches (it could be another Google account): only the new ask is on.
  assert.deepEqual(enabled(done.body.toolkit), ["check_email"]);
  assert.doesNotMatch(done.body.toolkit.access, /sending only/);
});

test("a user who unticks the permission on Google's screen ends with nothing connected (D4)", async () => {
  rig = await start();
  const done = await connectFor(rig, "gmail", "send_email", { scenario: "missing_scope" });
  assert.equal(done.status, 200, done.text);
  assert.equal(done.body.receipt.status, "failed");
  assert.equal(done.body.receipt.errorCode, "permission_not_granted");
  assert.match(done.body.receipt.summary, /wasn't connected/);
  assert.equal(rig.store.getConnection(A, "gmail"), null, "no grant without a purpose");
  assert.ok(rig.provider.calls.includes("removeConnection"), "removed at the provider too");
  assert.deepEqual(enabled(await gmailView(rig)), []);
});

test("a more-permission sign-in without that permission leaves the working connection as it was", async () => {
  rig = await start();
  await connectFor(rig, "gmail", "send_email");
  const before = rig.store.getConnection(A, "gmail")!;
  const done = await connectFor(rig, "gmail", "check_email", { scenario: "missing_scope" });
  assert.equal(done.body.receipt.errorCode, "permission_not_granted");
  assert.equal(rig.store.getConnection(A, "gmail")!.connection_id, before.connection_id);
  assert.deepEqual(enabled(await gmailView(rig)), ["send_email"]);
});

test("a declined sign-in connects nothing and switches nothing on", async () => {
  rig = await start();
  const done = await connectFor(rig, "gmail", "send_email", { outcome: "deny" });
  assert.equal(done.status, 200);
  assert.equal(done.body.receipt.status, "failed");
  assert.equal(rig.store.getConnection(A, "gmail"), null);
  assert.deepEqual(enabled(await gmailView(rig)), []);
});

test("forTool must be a tool of that account that needs a sign-in; anything else is refused before any sign-in", async () => {
  rig = await start();
  const tryConnect = (toolkit: string, body: unknown) => rig.call("POST", `/v1/tools/${toolkit}/connect`, { body });
  assert.equal((await tryConnect("gmail", { forTool: "check_outlook_email" })).status, 400, "another account's tool");
  assert.equal((await tryConnect("gmail", { forTool: "send_everything" })).status, 400, "a made-up tool");
  assert.equal((await tryConnect("gmail", { forTool: "send_email", enable: ["trash_email"] })).status, 400, "no extra fields");
  assert.equal((await tryConnect("gmail", { forTool: "" })).status, 400);
  assert.ok(!rig.provider.calls.some((c) => c.startsWith("createConnectionLink")));
  // Connected through Settings: the tool needs a switch, not a sign-in.
  assert.equal((await connect(rig, "gmail")).status, 200);
  assert.equal((await tryConnect("gmail", { forTool: "send_email" })).status, 400);
});

test("Settings' Connect still switches nothing on", async () => {
  rig = await start();
  const done = await connect(rig, "gmail");
  assert.equal(done.status, 200);
  assert.match(done.body.receipt.summary, /Its tools are off until you switch them on/);
  assert.deepEqual(enabled(done.body.toolkit), []);
  assert.ok(rig.provider.calls.includes("createConnectionLink:gmail"), "Settings uses the full sign-in");
});

test("connected but switched off: the offer is a switch, with nothing to sign in to", async () => {
  rig = await start();
  await connect(rig, "gmail");
  const asked = await prepare(rig, "send_email", SEND);
  assert.equal(asked.body.error.code, "capability_disabled");
  assert.equal(asked.body.error.connect.need, "switch_on");
  assert.deepEqual(asked.body.error.connect.permissions, []);
  assert.equal((await on(rig, "send_email")).status, 200);
  assert.equal((await prepare(rig, "send_email", SEND)).status, 200, "then the card");
});

test("an expired connection offers a reconnect; a reconnect of a full grant doesn't shrink it to send-only", async () => {
  rig = await start();
  await connect(rig, "gmail");
  rig.store.db.prepare("UPDATE connections SET status = 'expired' WHERE user_id = ? AND provider = 'gmail'").run(A);
  const asked = await prepare(rig, "send_email", SEND);
  assert.equal(asked.body.error.code, "capability_disabled");
  assert.equal(asked.body.error.connect.need, "reconnect");
  assert.deepEqual(asked.body.error.connect.permissions, [...TOOLKITS.gmail.permissions], "the user had the full grant");
  const done = await connectFor(rig, "gmail", "send_email");
  assert.equal(done.status, 200, done.text);
  assert.ok(rig.provider.calls.filter((c) => c.startsWith("createConnectionLink")).every((c) => c === "createConnectionLink:gmail"));
  assert.deepEqual(enabled(done.body.toolkit), ["send_email"]);
});

test("web search has no account: its offer is a switch", async () => {
  rig = await start();
  const asked = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "web_search", arguments: { query: "cafe hours" } } });
  assert.equal(asked.status, 403);
  assert.equal(asked.body.error.code, "capability_disabled");
  assert.deepEqual(asked.body.error.connect, { toolkit: "websearch", tool: "web_search", need: "switch_on", accountTitle: "Web search", toolTitle: "Search the web", permissions: [] });
});

/** A service on its own (no HTTP) with a chosen provider. */
function service(provider: MockToolsProvider | UnconfiguredToolsProvider) {
  const clock = new Clock(Date.parse("2026-10-10T10:00:00Z"));
  return new CloudToolsService({
    store: new Store(":memory:"),
    provider,
    webSearch: null,
    limits: testLimits({}),
    publicBaseUrl: "https://api.doddy.test",
    appReturnUrl: "doddy-dev://connected-apps/return",
    completionMode: provider.mode === "mock" ? "mock" : "verifier",
    now: clock.now,
    sleep: async () => {},
  });
}

async function refusal(promise: Promise<unknown>): Promise<AppError> {
  try {
    await promise;
  } catch (error) {
    if (error instanceof AppError) return error;
    throw error;
  }
  assert.fail("expected a refusal");
}

test("an account the server hasn't set up offers no sign-in: no sign-in could fix it", async () => {
  const tools = service(new UnconfiguredToolsProvider());
  const error = await refusal(tools.prepare(USER_A, { tool: "send_email", arguments: SEND }));
  assert.equal(error.code, "live_not_configured");
  assert.equal(error.options.connect, undefined);
});

test("without a send-only auth config on the server, the first send uses the full sign-in and says so", async () => {
  class FullOnly extends MockToolsProvider {
    override narrowAuthConfigId(_toolkit: ToolkitId): string | null {
      return null;
    }
  }
  const provider = new FullOnly();
  const tools = service(provider);
  const error = await refusal(tools.prepare(USER_A, { tool: "send_email", arguments: SEND }));
  assert.deepEqual(error.options.connect?.permissions, [...TOOLKITS.gmail.permissions]);
  await tools.connect(USER_A, "gmail", { forTool: "send_email" });
  assert.deepEqual(provider.calls.filter((c) => c.startsWith("createConnectionLink")), ["createConnectionLink:gmail"]);
});

test("a completion is checked against the attempt's own auth config, not just any of the account's", async () => {
  rig = await start();
  const begin = await rig.call("POST", "/v1/tools/gmail/connect", { body: { forTool: "send_email" } });
  // Someone swaps the attempt's auth config for the full one after the narrow sign-in started.
  rig.store.db.prepare("UPDATE attempts SET auth_config_id = ? WHERE attempt_id = ?").run("mock_auth_gmail", begin.body.attemptId);
  const done = await rig.call("POST", "/v1/tools/gmail/complete", {
    body: { attemptId: begin.body.attemptId, nonce: begin.body.nonce, result: { kind: "mock", outcome: "approve" } },
  });
  assert.equal(done.status, 400);
  assert.equal(rig.store.getConnection(A, "gmail"), null);
});

test("the send-only auth config is optional, must differ from the full one, and needs the account's main settings", () => {
  // The same minimal live setup as tools.test.ts's config test.
  const live = {
    DODDY_MODE: "live",
    DODDY_ENV: "development",
    DODDY_AUTH_MODE: "signed",
    DODDY_SESSION_SIGNING_KEY: Buffer.alloc(32, 7).toString("base64"),
    COMPOSIO_API_KEY: "k",
    COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID: "ac_cal",
    COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: "20250909_00",
  };
  const gmail = { COMPOSIO_GMAIL_AUTH_CONFIG_ID: "ac_full", COMPOSIO_GMAIL_TOOLKIT_VERSION: "20260101_00" };
  assert.equal(loadConfig({ ...live, ...gmail }).toolkits.gmail?.narrowAuthConfigId, undefined, "optional");
  assert.equal(loadConfig({ ...live, ...gmail, COMPOSIO_GMAIL_ONLY_SEND_AUTH_CONFIG_ID: "ac_send" }).toolkits.gmail?.narrowAuthConfigId, "ac_send");
  assert.throws(() => loadConfig({ ...live, ...gmail, COMPOSIO_GMAIL_ONLY_SEND_AUTH_CONFIG_ID: "ac_full" }), (e: unknown) => e instanceof ConfigError && /must be a different auth config/.test(e.message));
  assert.throws(() => loadConfig({ ...live, COMPOSIO_GMAIL_ONLY_SEND_AUTH_CONFIG_ID: "ac_send" }), (e: unknown) => e instanceof ConfigError && /needs COMPOSIO_GMAIL_AUTH_CONFIG_ID/.test(e.message));
});
