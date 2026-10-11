import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES } from "../src/auth.js";
import { ConfigError, loadConfig, testLimits } from "../src/config.js";
import { Store } from "../src/store.js";
import { ADD_TODOIST_TASK, CHECK_EMAIL, DRAFT_EMAIL, driveQuoted, FIND_DRIVE_FILE, LIST_TODOIST_TASKS, SEARCH_NOTION, todoistSearchWord } from "../src/tools/catalog.js";
import { ComposioToolsProvider, type ComposioToolsLike } from "../src/tools/composio.js";
import { CloudToolsService } from "../src/tools/service.js";
import { USER_A, USER_B } from "./helpers.js";
import { connect, on, type Rig, ready, run, start } from "./toolsRig.js";

let rig: Rig;
afterEach(async () => rig?.close());

// ------------------------------------------------------------------ access control

test("every tools route needs a valid session and calls no provider without one", async () => {
  rig = await start();
  const routes: [string, string][] = [
    ["GET", "/v1/tools"],
    ["GET", "/v1/tools/receipts"],
    ["PUT", "/v1/tools/switch"],
    ["POST", "/v1/tools/prepare"],
    ["POST", "/v1/tools/run"],
    ["POST", "/v1/tools/gmail/connect"],
    ["POST", "/v1/tools/gmail/complete"],
    ["POST", "/v1/tools/gmail/disconnect"],
  ];
  for (const [method, path] of routes) {
    for (const token of [null, "dev-user-z", "eyJhbGciOiJub25lIn0.e30."]) {
      const res = await rig.call(method, path, { token, ...(method === "GET" ? {} : { body: {} }) });
      assert.equal(res.status, 401, `${method} ${path}`);
    }
  }
  assert.equal(rig.provider.calls.length, 0);
});

test("unknown toolkits, tools and methods are refused", async () => {
  rig = await start();
  assert.equal((await rig.call("POST", "/v1/tools/facebook/connect", { body: {} })).status, 404);
  assert.equal((await rig.call("GET", "/v1/tools/gmail/connect")).status, 404);
  assert.equal((await rig.call("PUT", "/v1/tools/switch", { body: { tool: "delete_everything", enabled: true } })).status, 404);
  assert.equal((await run(rig, "GMAIL_SEND_EMAIL", {})).status, 404);
  assert.equal(rig.provider.executed.length, 0);
});

test("strict bodies: user, connection and slug fields are rejected, not ignored", async () => {
  rig = await start();
  await ready(rig, "gmail", "check_email");
  for (const extra of [{ userId: "dev-user-b" }, { connectedAccountId: "x" }, { slug: "GMAIL_SEND_EMAIL" }]) {
    const res = await rig.call("POST", "/v1/tools/run", { body: { tool: "check_email", arguments: {}, timeZone: "UTC", ...extra } });
    assert.equal(res.status, 400);
  }
  const res = await run(rig, "check_email", { query: "in:inbox", user_id: "someone@else.example" });
  assert.equal(res.status, 400);
  assert.equal(rig.provider.executed.length, 0);
});

// ------------------------------------------------------------------ switches

test("everything starts off and nothing runs until the user switches it on", async () => {
  rig = await start();
  const catalog = await rig.call("GET", "/v1/tools");
  assert.equal(catalog.status, 200);
  assert.deepEqual(catalog.body.toolkits.map((t: any) => t.id), ["gmail", "googledrive", "notion", "todoist", "websearch"]);
  for (const toolkit of catalog.body.toolkits) {
    // Web search has no account (test/websearch.test.ts); every account starts disconnected.
    assert.equal(toolkit.status, toolkit.id === "websearch" ? "connected" : "disconnected");
    for (const tool of toolkit.tools) assert.equal(tool.enabled, false);
  }
  // Not connected: a switch cannot be turned on, and running is refused.
  assert.equal((await on(rig, "check_email")).status, 409);
  assert.equal((await run(rig, "check_email", {})).status, 403);

  // Connected but switch still off: connecting does not switch tools on.
  assert.equal((await connect(rig, "gmail")).status, 200);
  const blocked = await run(rig, "check_email", {});
  assert.equal(blocked.status, 403);
  assert.equal(blocked.body.error.code, "capability_disabled");
  assert.equal(blocked.body.error.receipt.status, "blocked");
  assert.equal(rig.provider.executed.length, 0);

  assert.equal((await on(rig, "check_email")).status, 200);
  const ok = await run(rig, "check_email", {});
  assert.equal(ok.status, 200, ok.text);
  assert.equal(rig.provider.executed.length, 1);
});

test("switching one tool does not switch its neighbours, and off is immediate", async () => {
  rig = await start();
  await ready(rig, "todoist", "list_todoist_tasks");
  const catalog = await rig.call("GET", "/v1/tools");
  const todoist = catalog.body.toolkits.find((t: any) => t.id === "todoist");
  assert.equal(todoist.tools.find((t: any) => t.name === "list_todoist_tasks").enabled, true);
  assert.equal(todoist.tools.find((t: any) => t.name === "add_todoist_task").enabled, false);
  assert.equal((await run(rig, "add_todoist_task", { content: "x" })).status, 403);

  const off = await rig.call("PUT", "/v1/tools/switch", { body: { tool: "list_todoist_tasks", enabled: false } });
  assert.equal(off.status, 200);
  const after = await run(rig, "list_todoist_tasks", {});
  assert.equal(after.status, 403);
  assert.equal(after.body.error.code, "capability_disabled");
});

test("switches and connections are per user", async () => {
  rig = await start();
  await ready(rig, "gmail", "check_email", USER_A);
  const b = await run(rig, "check_email", {}, {}, USER_B);
  assert.equal(b.status, 403);
  assert.equal((await rig.call("GET", "/v1/tools", { token: USER_B })).body.toolkits[0].status, "disconnected");
  assert.equal((await on(rig, "check_email", USER_B)).status, 409);
  // B's receipts never show A's operations.
  assert.deepEqual((await rig.call("GET", "/v1/tools/receipts", { token: USER_B })).body.receipts.filter((r: any) => r.status === "succeeded"), []);
});

test("disconnect switches the account's tools off and blocks them at once", async () => {
  rig = await start();
  await ready(rig, "todoist", "list_todoist_tasks");
  const gone = await rig.call("POST", "/v1/tools/todoist/disconnect", { body: {} });
  assert.equal(gone.status, 200);
  assert.equal(gone.body.toolkit.status, "disconnected");
  assert.equal(gone.body.receipt.status, "succeeded");
  const res = await run(rig, "list_todoist_tasks", {});
  assert.equal(res.status, 403);
  // Reconnecting does not bring the old switch back.
  await connect(rig, "todoist");
  assert.equal((await run(rig, "list_todoist_tasks", {})).status, 403);
});

// ------------------------------------------------------------------ grants

test("a Google grant broader than Doddy needs blocks the tools and cannot be switched on", async () => {
  rig = await start();
  const done = await connect(rig, "gmail", USER_A, "broad_scope");
  assert.equal(done.status, 200);
  assert.equal(done.body.toolkit.status, "permission_insufficient");
  assert.equal(done.body.toolkit.reason, "grant_too_broad");
  assert.equal(done.body.receipt.status, "blocked");
  const sw = await on(rig, "check_email");
  assert.equal(sw.status, 403);
  assert.equal(sw.body.error.code, "permission_insufficient");
  assert.equal((await run(rig, "check_email", {})).status, 403);
  assert.equal(rig.provider.executed.length, 0);
});

test("a Google grant that doesn't include the needed scope blocks that tool", async () => {
  rig = await start();
  const done = await connect(rig, "googledrive", USER_A, "missing_scope");
  assert.equal(done.body.toolkit.status, "connected");
  const sw = await on(rig, "find_drive_file");
  assert.equal(sw.status, 403);
});

// ------------------------------------------------------------------ reads

test("check_email returns newest first and only sender, subject, time and a short preview", async () => {
  rig = await start();
  await ready(rig, "gmail", "check_email");
  const res = await run(rig, "check_email", { max: 5 });
  assert.equal(res.status, 200);
  assert.equal(res.body.mode, "mock");
  assert.equal(res.body.count, 2);
  const lines: string[] = res.body.text.split("\n");
  assert.ok(lines[1]!.includes("Lunch on Friday?"), "newest first");
  assert.ok(lines[2]!.includes("Your statement is ready"));
  assert.ok(lines[1]!.includes("2026-10-09 11:30"), "shown in the user's time zone (Europe/Warsaw)");
  assert.equal(res.body.receipt.operation, "read");
  assert.equal(res.body.receipt.status, "succeeded");
  // The receipt keeps no message content.
  assert.ok(!JSON.stringify(res.body.receipt).includes("Lunch"));
  assert.ok(!rig.logs.join("\n").includes("Lunch"));
});

test("empty and malformed provider answers become honest text or an error, never invented data", async () => {
  rig = await start();
  await ready(rig, "gmail", "check_email");
  rig.provider.setScenario(rigComposioUser(rig, USER_A), "empty");
  const empty = await run(rig, "check_email", {});
  assert.equal(empty.status, 200);
  assert.equal(empty.body.count, 0);
  assert.match(empty.body.text, /No emails matched/);

  rig.provider.setScenario(rigComposioUser(rig, USER_A), "malformed");
  const bad = await run(rig, "check_email", {});
  assert.equal(bad.status, 502);
  assert.equal(bad.body.error.code, "malformed_provider_result");
  assert.equal(bad.body.error.receipt.status, "failed");
});

test("search_notion hides archived pages and reads titles only", async () => {
  rig = await start();
  await ready(rig, "notion", "search_notion");
  const res = await run(rig, "search_notion", { query: "trip" });
  assert.equal(res.status, 200);
  assert.ok(res.body.text.includes("Demo trip plan"));
  assert.ok(!res.body.text.includes("archived"));
  assert.equal(res.body.count, 1);
});

test("a rate-limited read retries once; a second failure is reported", async () => {
  rig = await start();
  await ready(rig, "todoist", "list_todoist_tasks");
  rig.provider.setScenario(rigComposioUser(rig, USER_A), "rate_limited");
  const res = await run(rig, "list_todoist_tasks", { when: "today" });
  assert.equal(res.status, 429);
  assert.equal(res.body.error.code, "rate_limited");
  assert.equal(rig.provider.executed.length, 2, "one try plus one retry");
});

test("an expired account switches its tools off and asks to reconnect", async () => {
  rig = await start();
  await ready(rig, "todoist", "list_todoist_tasks");
  rig.provider.setScenario(rigComposioUser(rig, USER_A), "expired");
  const res = await run(rig, "list_todoist_tasks", {});
  assert.equal(res.status, 409);
  assert.equal(res.body.error.code, "connection_expired");
  const status = (await rig.call("GET", "/v1/tools")).body.toolkits.find((t: any) => t.id === "todoist");
  assert.equal(status.status, "expired");
  assert.ok(status.tools.every((t: any) => t.enabled === false));
});

// ------------------------------------------------------------------ writes need a fresh approval

test("a write without a confirmation does nothing", async () => {
  rig = await start();
  await ready(rig, "todoist", "add_todoist_task");
  const res = await run(rig, "add_todoist_task", { content: "Renew passport" });
  assert.equal(res.status, 403);
  assert.equal(res.body.error.receipt.errorCode, "confirmation_required");
  assert.equal(rig.provider.executed.length, 0);
  const fake = await run(rig, "add_todoist_task", { content: "Renew passport" }, { approvalId: "11111111-1111-4111-8111-111111111111" });
  assert.equal(fake.status, 403);
  assert.equal(rig.provider.executed.length, 0);
});

test("an approval is bound to the exact arguments, the user, and works once", async () => {
  rig = await start();
  await ready(rig, "todoist", "add_todoist_task");
  const prepared = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "add_todoist_task", arguments: { content: "Renew passport", due: "tomorrow 9am" } } });
  assert.equal(prepared.status, 200, prepared.text);
  assert.equal(prepared.body.preview.confirmLabel, "Add task");
  assert.deepEqual(prepared.body.preview.lines, ["Renew passport", "Due: tomorrow 9am"]);
  const approvalId = prepared.body.approvalId;

  // Changed arguments: refused, and the approval is NOT consumed by the failed attempt of another shape.
  const changed = await run(rig, "add_todoist_task", { content: "Buy a boat", due: "tomorrow 9am" }, { approvalId });
  assert.equal(changed.status, 403);
  // Another user cannot use it.
  await ready(rig, "todoist", "add_todoist_task", USER_B);
  const other = await run(rig, "add_todoist_task", { content: "Renew passport", due: "tomorrow 9am" }, { approvalId }, USER_B);
  assert.equal(other.status, 403);
  assert.equal(rig.provider.executed.length, 0);

  const done = await run(rig, "add_todoist_task", { content: "Renew passport", due: "tomorrow 9am" }, { approvalId });
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.text, /^added: Todoist task "Renew passport"/);
  assert.equal(done.body.receipt.operation, "write");
  assert.equal(rig.provider.executed.length, 1);
  assert.deepEqual(rig.provider.executed[0]!.arguments, { content: "Renew passport", due_string: "tomorrow 9am" });

  const again = await run(rig, "add_todoist_task", { content: "Renew passport", due: "tomorrow 9am" }, { approvalId });
  assert.equal(again.status, 403, "single use");
  assert.equal(rig.provider.executed.length, 1);
});

test("an approval expires", async () => {
  rig = await start();
  await ready(rig, "todoist", "add_todoist_task");
  const prepared = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "add_todoist_task", arguments: { content: "Call mum" } } });
  rig.clock.advance(3 * 60_000);
  const res = await run(rig, "add_todoist_task", { content: "Call mum" }, { approvalId: prepared.body.approvalId });
  assert.equal(res.status, 403);
  assert.equal(rig.provider.executed.length, 0);
});

test("prepare refuses reads and tools that are switched off", async () => {
  rig = await start();
  await connect(rig, "gmail");
  const off = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "draft_email", arguments: { to: "anna@example.com", subject: "Hi", body: "Hello" } } });
  assert.equal(off.status, 403);
  await on(rig, "check_email");
  const read = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "check_email", arguments: {} } });
  assert.equal(read.status, 400);
});

test("a draft is created with the exact text the user saw, and is never sent", async () => {
  rig = await start();
  await ready(rig, "gmail", "draft_email");
  const args = { to: "anna@example.com", subject: "Lunch Friday", body: "Yes, 1pm works." };
  const prepared = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "draft_email", arguments: args } });
  assert.deepEqual(prepared.body.preview.lines, ["To: anna@example.com", "Subject: Lunch Friday", "Yes, 1pm works."]);
  const done = await run(rig, "draft_email", args, { approvalId: prepared.body.approvalId });
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.text, /NOT sent/);
  assert.deepEqual(rig.provider.executed.map((e) => e.slug), ["GMAIL_CREATE_EMAIL_DRAFT"]);
  assert.deepEqual(rig.provider.executed[0]!.arguments, { user_id: "me", recipient_email: "anna@example.com", subject: "Lunch Friday", body: "Yes, 1pm works.", is_html: false });
  assert.ok(!rig.provider.calls.some((c) => c.includes("SEND")));
  // A malformed address is refused before anything is prepared.
  const bad = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "draft_email", arguments: { ...args, to: "not an address" } } });
  assert.equal(bad.status, 400);
});

test("a write that fails is never retried and says the outcome may be unknown", async () => {
  rig = await start();
  await ready(rig, "todoist", "add_todoist_task");
  const args = { content: "Pay rent" };
  const prepared = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "add_todoist_task", arguments: args } });
  rig.provider.setScenario(rigComposioUser(rig, USER_A), "provider_error");
  const res = await run(rig, "add_todoist_task", args, { approvalId: prepared.body.approvalId });
  assert.equal(res.status, 502);
  assert.equal(res.body.error.receipt.status, "outcome_unknown");
  assert.equal(rig.provider.executed.length, 1, "no automatic retry for a write");
});

test("a write whose answer can't be read is reported as maybe done, not as failed", async () => {
  rig = await start();
  await ready(rig, "todoist", "add_todoist_task");
  const args = { content: "Call the plumber" };
  const prepared = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "add_todoist_task", arguments: args } });
  rig.provider.setScenario(rigComposioUser(rig, USER_A), "malformed");
  const res = await run(rig, "add_todoist_task", args, { approvalId: prepared.body.approvalId });
  assert.notEqual(res.status, 200);
  assert.equal(rig.provider.executed.length, 1, "the provider ran it");
  assert.equal(res.body.error.receipt.status, "outcome_unknown");
  assert.match(res.body.error.receipt.summary, /may or may not have gone through/);
});

test("a write refused by the provider's rate limit is reported as not done", async () => {
  rig = await start();
  await ready(rig, "todoist", "add_todoist_task");
  const args = { content: "Water plants" };
  const prepared = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "add_todoist_task", arguments: args } });
  rig.provider.setScenario(rigComposioUser(rig, USER_A), "rate_limited");
  const res = await run(rig, "add_todoist_task", args, { approvalId: prepared.body.approvalId });
  assert.equal(res.body.error.receipt.status, "failed");
});

// ------------------------------------------------------------------ limits and privacy

test("the daily tool-run limit stops further runs before any provider call", async () => {
  rig = await start({ userDailyToolRuns: 2, serviceDailyCalls: 300 });
  await ready(rig, "todoist", "list_todoist_tasks");
  assert.equal((await run(rig, "list_todoist_tasks", {})).status, 200);
  assert.equal((await run(rig, "list_todoist_tasks", {})).status, 200);
  const third = await run(rig, "list_todoist_tasks", {});
  assert.equal(third.status, 429);
  assert.equal(third.body.error.code, "quota_exceeded");
  assert.equal(rig.provider.executed.length, 2);
});

test("receipts and logs keep no email, task or file content", async () => {
  rig = await start();
  await ready(rig, "gmail", "check_email");
  await run(rig, "check_email", {});
  await ready(rig, "googledrive", "find_drive_file");
  await run(rig, "find_drive_file", { name: "budget" });
  const receipts = (await rig.call("GET", "/v1/tools/receipts")).text;
  const everything = receipts + rig.logs.join("\n");
  for (const secret of ["Lunch on Friday", "Anna Demo", "Demo budget 2026", "anna@demo.example"]) assert.ok(!everything.includes(secret), secret);
});

test("mock demo scenarios cannot be used against a live provider", async () => {
  const store = new Store(":memory:");
  const fake = {} as ComposioToolsLike;
  const provider = new ComposioToolsProvider("key", { todoist: { authConfigId: "ac_1", toolkitVersion: "20260101_00" } }, fake);
  const tools = new CloudToolsService({
    store,
    provider,
    limits: testLimits(),
    publicBaseUrl: "https://api.doddy.test",
    appReturnUrl: "doddy-dev://connected-apps/return",
    completionMode: "verifier",
  });
  assert.throws(() => tools.applyMockScenario("u", "empty"), /only in mock mode/);
  // Only toolkits with their own settings are connectable.
  assert.equal(tools.catalog("u").toolkits.find((t) => t.id === "gmail")!.status, "unavailable");
  assert.equal(tools.catalog("u").toolkits.find((t) => t.id === "todoist")!.status, "disconnected");
  await assert.rejects(() => tools.connect("u", "gmail", {}), /isn't set up/);
  store.close();
});

// ------------------------------------------------------------------ tool arguments (what Composio would receive)

test("tool arguments are built only from validated input", () => {
  assert.deepEqual(CHECK_EMAIL.toArguments({}), { user_id: "me", query: "in:inbox", max_results: 5, verbose: false, include_payload: false, include_spam_trash: false });
  assert.equal(CHECK_EMAIL.input.safeParse({ max: 50 }).success, false);
  assert.equal(CHECK_EMAIL.input.safeParse({ query: "x", extra: 1 }).success, false);

  assert.equal(driveQuoted("Anna's \\ budget"), "Anna\\'s \\\\ budget");
  assert.equal((FIND_DRIVE_FILE.toArguments({ name: "O'Brien" }) as { q: string }).q, "name contains 'O\\'Brien' and trashed = false");
  assert.equal(FIND_DRIVE_FILE.input.safeParse({ name: "" }).success, false);

  assert.equal(todoistSearchWord("a & b | !c (d) #p @l"), "a b c d p l");
  assert.deepEqual(LIST_TODOIST_TASKS.toArguments({}), { limit: 20, filter: "(today | overdue)" });
  assert.deepEqual(LIST_TODOIST_TASKS.toArguments({ when: "all", search: "milk & eggs" }), { limit: 20, filter: "search: milk eggs" });

  assert.deepEqual(ADD_TODOIST_TASK.toArguments({ content: "x", due: "demain", due_lang: "fr" }), { content: "x", due_string: "demain", due_lang: "fr" });
  assert.equal(ADD_TODOIST_TASK.input.safeParse({ content: "x", project_id: "123" }).success, false);
  assert.equal(DRAFT_EMAIL.input.safeParse({ to: "a@b.co", subject: "s", body: "b", cc: ["x@y.z"] }).success, false);
  assert.equal(SEARCH_NOTION.toArguments({ query: "trip" }).filter_value, "page");
});

test("the live adapter sends the pinned version, the user's own connection, and nothing else", async () => {
  const sent: unknown[] = [];
  const fake = {
    tools: {
      execute: async (slug: string, body: unknown) => {
        sent.push({ slug, body });
        return { successful: true, data: { tasks: [] }, error: null, logId: "log_1" };
      },
    },
  } as unknown as ComposioToolsLike;
  const provider = new ComposioToolsProvider("key", { todoist: { authConfigId: "ac_1", toolkitVersion: "20260101_00" } }, fake);
  const result = await provider.execute({
    toolkit: "todoist",
    slug: "TODOIST_GET_ALL_TASKS",
    composioUserId: "doddy_abc",
    connectionId: "ca_1",
    arguments: { limit: 20 },
    signal: AbortSignal.timeout(1000),
  });
  assert.deepEqual(sent, [{ slug: "TODOIST_GET_ALL_TASKS", body: { userId: "doddy_abc", connectedAccountId: "ca_1", version: "20260101_00", arguments: { limit: 20 } } }]);
  assert.equal(result.providerReference, "log_1");
});

test("config: a toolkit needs both values, a pinned version, and a live key", () => {
  const live = {
    DODDY_MODE: "live",
    DODDY_ENV: "development",
    DODDY_AUTH_MODE: "signed",
    DODDY_SESSION_SIGNING_KEY: Buffer.alloc(32, 7).toString("base64"),
    COMPOSIO_API_KEY: "k",
    COMPOSIO_GOOGLECALENDAR_AUTH_CONFIG_ID: "ac_cal",
    COMPOSIO_GOOGLECALENDAR_TOOLKIT_VERSION: "20250909_00",
  };
  const config = loadConfig({ ...live, COMPOSIO_TODOIST_AUTH_CONFIG_ID: "ac_t", COMPOSIO_TODOIST_TOOLKIT_VERSION: "20260101_00" });
  assert.deepEqual(Object.keys(config.toolkits), ["todoist"]);
  assert.throws(() => loadConfig({ ...live, COMPOSIO_GMAIL_AUTH_CONFIG_ID: "ac_g" }), (e: unknown) => e instanceof ConfigError && /GMAIL_TOOLKIT_VERSION is required/.test(e.message));
  assert.throws(() => loadConfig({ ...live, COMPOSIO_GMAIL_AUTH_CONFIG_ID: "ac_g", COMPOSIO_GMAIL_TOOLKIT_VERSION: "latest" }), /pinned version/);
  assert.deepEqual(loadConfig({ ...live }).toolkits, {});
});

/** The Composio user ID the store assigned to a dev identity (the mock keys scenarios by it). */
function rigComposioUser(r: Rig, token: string): string {
  return r.store.composioUserId(DEV_IDENTITIES[token]!, r.clock.now());
}

// ------------------------------------------------------------------ shared fixtures (Swift decodes the same files)

test("contracts/online-accounts fixtures match the server's schemas", async () => {
  const { readFileSync } = await import("node:fs");
  const { join } = await import("node:path");
  const c = await import("../src/tools/contracts.js");
  const { ErrorResponseSchema, ConnectResponseSchema } = await import("../src/contracts.js");
  const load = (name: string) => JSON.parse(readFileSync(join(process.cwd(), "..", "contracts", "online-accounts", `${name}.json`), "utf8")) as unknown;
  c.ToolsCatalogSchema.parse(load("catalog-disconnected"));
  c.ToolsCatalogSchema.parse(load("catalog-gmail-on"));
  ConnectResponseSchema.parse(load("connect-response-mock"));
  c.ToolkitResultSchema.parse(load("toolkit-result-connected"));
  c.ToolkitResultSchema.parse(load("toolkit-result-too-broad"));
  c.ToolkitResultSchema.parse(load("switch-result-on"));
  c.PrepareResultSchema.parse(load("prepare-result-draft"));
  c.RunResultSchema.parse(load("run-result-email"));
  c.RunResultSchema.parse(load("run-result-draft"));
  c.RunResultSchema.parse(load("run-result-web-search"));
  c.ToolReceiptsSchema.parse(load("receipts"));
  // Error bodies carry a tool receipt, not a calendar receipt, so check the shape directly.
  for (const name of ["error-tool-disabled", "error-confirmation-expired", "error-permission-insufficient", "error-rate-limited"]) {
    const body = load(name) as { error: { code: string; message: string; receipt?: unknown } };
    assert.ok(body.error.code && body.error.message, name);
    if (body.error.receipt) c.ToolReceiptSchema.parse(body.error.receipt);
  }
  void ErrorResponseSchema;
});
