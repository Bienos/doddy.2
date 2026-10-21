import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { SignedSessionVerifier } from "../src/auth.js";
import { ConfigError, loadConfig } from "../src/config.js";
import { DeviceSessionIssuer, deviceUserId } from "../src/deviceSession.js";
import { DocumentLinks } from "../src/documents.js";
import { AppError, ProviderError } from "../src/errors.js";
import { AnthropicClaudeProvider, fileIdsOf, fileName, MockClaudeProvider } from "../src/tools/claude.js";
import { Store } from "../src/store.js";
import { USER_A } from "./helpers.js";
import { connect, on, type Rig, run, runRaw, start, TEST_LINK_KEY } from "./toolsRig.js";

/**
 * ADR-563 and ADR-564 (21 Oct 2026): the phone can sign itself in, web lookups start on,
 * connecting an account turns its tools on, and Claude writes, sums up and makes documents.
 */

let rig: Rig | undefined;
afterEach(async () => {
  await rig?.tools.settle();
  await rig?.close();
  rig = undefined;
});

const KEY = Buffer.alloc(32, 3);
const DEVICE_A = "1b4e28ba-2fa1-41d2-883f-0016d3cca427";
const DEVICE_B = "6f9619ff-8b86-4011-b42d-00c04fc964ff";

// ------------------------------------------------------------------ device sign-in (ADR-563)

test("first device: the first iPhone gets a token the server accepts, and keeps getting one", async () => {
  const store = await Store.memory();
  try {
    const issuer = new DeviceSessionIssuer(KEY, { signup: "first-device", inviteCodes: [], store });
    const now = new Date("2026-10-21T00:00:00Z");
    const first = await issuer.issue({ deviceId: DEVICE_A }, now);
    const user = new SignedSessionVerifier(KEY).verify(`Bearer ${first.token}`, now);
    assert.deepEqual(user, { userId: deviceUserId(KEY, DEVICE_A) });
    assert.equal(first.expiresAt, "2026-11-20T00:00:00.000Z");
    // Same phone again (a new token after 30 days, or after a reinstall): same user.
    const again = await issuer.issue({ deviceId: DEVICE_A.toUpperCase() }, now);
    assert.deepEqual(new SignedSessionVerifier(KEY).verify(`Bearer ${again.token}`, now), user);
  } finally {
    await store.close();
  }
});

test("first device: any other device is refused, unless it brings a valid invite code", async () => {
  const store = await Store.memory();
  try {
    const now = new Date("2026-10-21T00:00:00Z");
    const issuer = new DeviceSessionIssuer(KEY, { signup: "first-device", inviteCodes: ["second-phone-code"], store });
    await issuer.issue({ deviceId: DEVICE_A }, now);
    await assert.rejects(issuer.issue({ deviceId: DEVICE_B }, now), (e: AppError) => e.code === "unauthenticated" && /another iPhone/.test(e.message));
    await assert.rejects(issuer.issue({ deviceId: DEVICE_B, inviteCode: "wrong-code-123" }, now), (e: AppError) => e.code === "unauthenticated");
    const second = await issuer.issue({ deviceId: DEVICE_B, inviteCode: "second-phone-code" }, now);
    assert.deepEqual(new SignedSessionVerifier(KEY).verify(`Bearer ${second.token}`, now), { userId: deviceUserId(KEY, DEVICE_B) });
    // The owner stays the first phone.
    assert.equal(await store.claimDeviceOwner(deviceUserId(KEY, DEVICE_B), now.getTime()), deviceUserId(KEY, DEVICE_A));
  } finally {
    await store.close();
  }
});

test("device sign-in rejects anything but a UUID and an optional code, and two devices never share a user", async () => {
  const store = await Store.memory();
  try {
    const issuer = new DeviceSessionIssuer(KEY, { signup: "off", inviteCodes: ["only-with-code"], store });
    const now = new Date();
    for (const body of [{}, { deviceId: "not-a-uuid" }, { deviceId: DEVICE_A, userId: USER_A }, null, "x"]) {
      await assert.rejects(issuer.issue(body, now), (e: AppError) => e.code === "invalid_request");
    }
    await assert.rejects(issuer.issue({ deviceId: DEVICE_A }, now), (e: AppError) => e.code === "unauthenticated" && /invite code is needed/.test(e.message));
    assert.notEqual(deviceUserId(KEY, DEVICE_A), deviceUserId(KEY, DEVICE_B));
    // Another server key, another user: a user ID can't be linked to a device without the key.
    assert.notEqual(deviceUserId(KEY, DEVICE_A), deviceUserId(Buffer.alloc(32, 9), DEVICE_A));
    assert.match(deviceUserId(KEY, DEVICE_A), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  } finally {
    await store.close();
  }
});

test("config: device sign-in needs the signing key and is refused in production", () => {
  const key = Buffer.alloc(32, 1).toString("base64");
  const base = { DODDY_MODE: "mock", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: key };
  assert.equal(loadConfig({ ...base, DODDY_DEVICE_SIGNUP: "first-device" }).deviceSignup, "first-device");
  assert.deepEqual(loadConfig({ ...base, DODDY_DEVICE_INVITE_CODES: "abcdefgh, ijklmnop " }).deviceInviteCodes, ["abcdefgh", "ijklmnop"]);
  assert.equal(loadConfig(base).deviceSignup, "off");
  assert.throws(() => loadConfig({ ...base, DODDY_DEVICE_INVITE_CODES: "short" }), (e: ConfigError) => e.problems.some((p) => /8 to 64/.test(p)));
  assert.throws(
    () => loadConfig({ DODDY_MODE: "mock", DODDY_AUTH_MODE: "dev", DODDY_DEVICE_SIGNUP: "first-device" }),
    (e: ConfigError) => e.problems.some((p) => /needs DODDY_SESSION_SIGNING_KEY/.test(p)),
  );
  assert.throws(
    () => loadConfig({ ...base, DODDY_ENV: "production", DODDY_DEVICE_SIGNUP: "first-device" }),
    (e: ConfigError) => e.problems.some((p) => /development only/.test(p)),
  );
});

test("POST /v1/session/device is the one route without a session, and its token opens the tools", async () => {
  const { createHandler } = await import("../src/http.js");
  const { ConnectedAppsService } = await import("../src/service.js");
  const { defaultRegistry } = await import("../src/capabilities.js");
  const { MockCalendarProvider } = await import("../src/providers/mock.js");
  const { MockToolsProvider } = await import("../src/tools/mock.js");
  const { CloudToolsService } = await import("../src/tools/service.js");
  const { testLimits } = await import("../src/config.js");
  const store = await Store.memory();
  const common = { store, limits: testLimits(), publicBaseUrl: "https://api.doddy.test", appReturnUrl: "doddy-dev://connected-apps/return" };
  const handler = createHandler({
    service: new ConnectedAppsService({ ...common, provider: new MockCalendarProvider(), registry: defaultRegistry(), completionMode: "mock" }),
    tools: new CloudToolsService({ ...common, provider: new MockToolsProvider(), completionMode: "mock" }),
    verifier: new SignedSessionVerifier(KEY),
    deviceSessions: new DeviceSessionIssuer(KEY, { signup: "first-device", inviteCodes: [], store }),
    appReturnUrl: common.appReturnUrl,
    maxBodyBytes: 8 * 1024,
    log: () => {},
  });
  const server = createServer((req, res) => void handler(req, res));
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  try {
    const post = (body: unknown) => fetch(`${base}/v1/session/device`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    const signedIn = await post({ deviceId: DEVICE_A });
    assert.equal(signedIn.status, 200);
    const { token } = (await signedIn.json()) as { token: string };
    assert.equal((await fetch(`${base}/v1/tools`, { headers: { authorization: `Bearer ${token}` } })).status, 200);
    assert.equal((await fetch(`${base}/v1/tools`)).status, 401);
    assert.equal((await post({ deviceId: DEVICE_B })).status, 401);
  } finally {
    server.close();
    await store.close();
  }
});

// ------------------------------------------------------------------ web search on by default (ADR-563)

test("web lookups start on; the user's own off still wins; every search still asks first", async () => {
  rig = await start();
  const web = (await rig.call("GET", "/v1/tools")).body.toolkits.find((t: any) => t.id === "websearch");
  assert.deepEqual(web.tools.map((t: any) => t.enabled), [true, true, true]);

  // ASK-01 unchanged: without the user's yes nothing is searched.
  const unasked = await runRaw(rig, "web_search", { query: "Warsaw weather" });
  assert.equal(unasked.status, 403);
  assert.equal(unasked.body.error.receipt.errorCode, "ask_first_required");
  assert.deepEqual(rig.webSearch!.queries, []);

  const asked = await run(rig, "web_search", { query: "Warsaw weather" });
  assert.equal(asked.status, 200, asked.text);
  assert.deepEqual(rig.webSearch!.queries, ["Warsaw weather"]);

  const off = await rig.call("PUT", "/v1/tools/switch", { body: { tool: "web_search", enabled: false } });
  assert.equal(off.status, 200);
  assert.equal((await run(rig, "web_search", { query: "again" })).body.error.code, "capability_disabled");
});

// ------------------------------------------------------------------ connect turns tools on (ADR-563)

test("an account that isn't connected answers not_connected (so the app can offer Connect), even with its switch off", async () => {
  rig = await start();
  const res = await run(rig, "check_email", { query: "from:ania" });
  assert.equal(res.status, 409, res.text);
  assert.equal(res.body.error.code, "not_connected");
  assert.match(res.body.error.message, /Gmail isn't connected/);
});

test("connecting Gmail turns its tools on; reads still ask, sends still need the tap on their card", async () => {
  rig = await start();
  const done = await connect(rig, "gmail");
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.receipt.summary, /Gmail connected\. Doddy can use it now/);
  const gmail = (await rig.call("GET", "/v1/tools")).body.toolkits.find((t: any) => t.id === "gmail");
  assert.ok(gmail.tools.length > 0);
  for (const tool of gmail.tools) assert.equal(tool.enabled, true, tool.name);

  assert.equal((await runRaw(rig, "check_email", { query: "from:ania" })).body.error.receipt.errorCode, "ask_first_required");
  assert.equal((await run(rig, "check_email", { query: "from:ania" })).status, 200);
  const send = await runRaw(rig, "send_email", { to: "ania@example.com", subject: "Hi", body: "Hello" });
  assert.notEqual(send.status, 200);
  assert.match(send.body.error.receipt.errorCode, /confirmation_required|ask_first_required/);

  // The user can still switch one off, and that sticks.
  await rig.call("PUT", "/v1/tools/switch", { body: { tool: "send_email", enabled: false } });
  const after = (await rig.call("GET", "/v1/tools")).body.toolkits.find((t: any) => t.id === "gmail");
  assert.equal(after.tools.find((t: any) => t.name === "send_email").enabled, false);
});

// ------------------------------------------------------------------ Claude (ADR-564)

test("ask_claude: card first, nothing sent before the yes, then the answer", async () => {
  rig = await start();
  const args = { task: "summarize", request: "Sum up this email", material: "Dear Pat, the meeting moved to Friday." };
  const prepared = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "ask_claude", arguments: args } });
  assert.equal(prepared.status, 200, prepared.text);
  assert.equal(prepared.body.preview.title, "Ask Claude?");
  assert.ok(prepared.body.preview.lines.some((l: string) => /Anthropic/.test(l)));
  assert.equal((await runRaw(rig, "ask_claude", args)).body.error.receipt.errorCode, "ask_first_required");
  const res = await runRaw(rig, "ask_claude", args, { approvalId: prepared.body.approvalId });
  assert.equal(res.status, 200, res.text);
  assert.match(res.body.text, /^Claude's answer/);
  assert.equal(res.body.receipt.toolkit, "claude");
  // One yes, one run.
  assert.equal((await runRaw(rig, "ask_claude", args, { approvalId: prepared.body.approvalId })).body.error.receipt.errorCode, "ask_first_required");
});

test("make_document: answers at once with a link; the link says 'still making', then serves the file", async () => {
  let release!: () => void;
  const gate = new Promise<void>((r) => (release = r));
  const slow = new MockClaudeProvider();
  const original = slow.makeDocument.bind(slow);
  slow.makeDocument = async (args) => {
    await gate;
    return original(args);
  };
  rig = await start({}, { claude: slow });
  const res = await run(rig, "make_document", { kind: "deck", title: "Q4 plan: Doddy/beta", request: "Ten slides on the beta plan" });
  assert.equal(res.status, 200, res.text);
  assert.match(res.body.text, /^started: Claude is making the deck "Q4 plan: Doddy\/beta"/);
  assert.doesNotMatch(res.body.text, /https?:\/\//, "the voice agent never gets the link");
  assert.equal(res.body.document.status, "working");
  assert.equal(res.body.document.name, "Q4 plan Doddybeta.pptx");
  const link = new URL(res.body.document.url);
  assert.equal(link.origin, "https://api.doddy.test");

  const local = (u: URL) => rig!.call("GET", `${u.pathname}${u.search}`, { token: null });
  const working = await local(link);
  assert.equal(working.status, 200);
  assert.match(working.text, /still making this/);
  assert.match(working.text, /http-equiv="refresh"/);

  release();
  await rig.tools.settle();
  const ready = await local(link);
  assert.equal(ready.status, 200);
  assert.equal(ready.text, "DEMO deck: Q4 plan: Doddy/beta");

  // A changed signature, a changed ID or an expired link opens nothing.
  const forged = new URL(link);
  forged.searchParams.set("sig", "x".repeat(43));
  assert.equal((await local(forged)).status, 404);
  const expired = new URL(link);
  expired.searchParams.set("exp", "1");
  assert.equal((await local(expired)).status, 404);
});

test("make_document: a failure says so on the page and in the log, without content", async () => {
  const failing = new MockClaudeProvider();
  failing.makeDocument = async () => {
    throw new ProviderError("provider_unavailable");
  };
  rig = await start({}, { claude: failing });
  const res = await run(rig, "make_document", { kind: "text", title: "Blog: private stuff", request: "Write a blog post" });
  assert.equal(res.status, 200, res.text);
  await rig.tools.settle();
  const link = new URL(res.body.document.url);
  const page = await rig.call("GET", `${link.pathname}${link.search}`, { token: null });
  assert.match(page.text, /didn't work/);
  assert.ok(rig.logs.some((l) => /document_failed/.test(l)));
  assert.doesNotMatch(rig.logs.join("\n"), /private stuff/);
});

test("Claude not set up, or no document links: the card is refused honestly and nothing runs", async () => {
  rig = await start({}, { claude: null });
  const res = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "ask_claude", arguments: { task: "answer", request: "hi" } } });
  assert.equal(res.status, 503);
  assert.equal(res.body.error.message, "Claude isn't set up on this server.");
  await rig.close();
  rig = await start({}, { documentLinks: false });
  const doc = await rig.call("POST", "/v1/tools/prepare", { body: { tool: "make_document", arguments: { kind: "pdf", title: "x", request: "y" } } });
  assert.equal(doc.status, 503);
});

test("Claude daily cap, counted after the yes and before the call", async () => {
  let calls = 0;
  const counting = new MockClaudeProvider();
  counting.ask = async () => {
    calls++;
    return { text: "ok" };
  };
  rig = await start({ userDailyClaude: 1 }, { claude: counting });
  assert.equal((await run(rig, "ask_claude", { task: "answer", request: "one" })).status, 200);
  const second = await run(rig, "ask_claude", { task: "answer", request: "two" });
  assert.equal(second.status, 429);
  assert.equal(second.body.error.message, "Today's Claude limit was reached.");
  assert.equal(calls, 1);
});

test("Claude arguments are strict", async () => {
  rig = await start();
  for (const args of [{ task: "hack", request: "x" }, { task: "answer" }, { task: "answer", request: "x", model: "claude-fable-5-1" }, { kind: "deck", title: "", request: "x" }]) {
    const tool = "kind" in args ? "make_document" : "ask_claude";
    assert.equal((await rig.call("POST", "/v1/tools/prepare", { body: { tool, arguments: args } })).status, 400, JSON.stringify(args));
  }
});

// ------------------------------------------------------------------ the live Anthropic adapter, offline

type Call = { url: string; method: string; body: any; headers: Record<string, string> };
function fakeAnthropic(responses: ((call: Call) => Response)[]) {
  const calls: Call[] = [];
  const impl = (async (input: any, init: any) => {
    const call: Call = { url: String(input), method: init?.method ?? "GET", body: init?.body ? JSON.parse(init.body) : null, headers: init?.headers ?? {} };
    calls.push(call);
    const next = responses.shift();
    if (!next) return new Response("{}", { status: 200 });
    return next(call);
  }) as typeof fetch;
  return { impl, calls };
}
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

test("live adapter: a deck uses the pptx skill and code execution, follows pause_turn, downloads the file", async () => {
  const fake = fakeAnthropic([
    () => json({ content: [{ type: "text", text: "Working" }], stop_reason: "pause_turn", container: { id: "cntr_1" } }),
    () =>
      json({
        content: [
          { type: "bash_code_execution_tool_result", content: { type: "bash_code_execution_result", content: [{ type: "bash_code_execution_output", file_id: "file_1" }] } },
          { type: "text", text: "A 9-slide deck." },
        ],
        stop_reason: "end_turn",
        container: { id: "cntr_1" },
      }),
    () => json({ filename: "plan.pptx", mime_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation" }),
    () => new Response(Buffer.from("PPTXBYTES")),
  ]);
  const claude = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model: "claude-sonnet-5-5" }, fake.impl, "https://anthropic.test");
  const file = await claude.makeDocument({ kind: "deck", title: "Plan", request: "A plan" }, AbortSignal.timeout(5_000));
  assert.equal(file.bytes.toString(), "PPTXBYTES");
  assert.equal(file.name, "Plan.pptx");
  assert.equal(file.summary, "A 9-slide deck.");

  const [first, second, meta, content] = fake.calls;
  assert.equal(first!.url, "https://anthropic.test/v1/messages");
  assert.equal(first!.headers["x-api-key"], "sk-ant-test-key-1234");
  assert.equal(first!.headers["anthropic-version"], "2023-06-01");
  assert.deepEqual(first!.body.container, { skills: [{ type: "anthropic", skill_id: "pptx", version: "latest" }] });
  assert.deepEqual(first!.body.tools, [{ type: "code_execution_20250825", name: "code_execution" }]);
  assert.equal(first!.body.model, "claude-sonnet-5-5");
  assert.equal(second!.body.container.id, "cntr_1");
  assert.equal(second!.body.messages.at(-1).role, "assistant");
  assert.equal(meta!.url, "https://anthropic.test/v1/files/file_1");
  assert.equal(content!.url, "https://anthropic.test/v1/files/file_1/content");
});

test("live adapter: text needs no skill; errors map to safe codes", async () => {
  const fake = fakeAnthropic([() => json({ content: [{ type: "text", text: "# Title\n\nBody" }], stop_reason: "end_turn" })]);
  const claude = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model: "claude-sonnet-5-5" }, fake.impl, "https://anthropic.test");
  const post = await claude.makeDocument({ kind: "text", title: "My post", request: "Write it" }, AbortSignal.timeout(5_000));
  assert.equal(post.bytes.toString(), "# Title\n\nBody");
  assert.equal(post.name, "My post.md");
  assert.equal(fake.calls[0]!.body.container, undefined);
  assert.equal(fake.calls[0]!.body.tools, undefined);

  const limited = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model: "m" }, fakeAnthropic([() => json({}, 429)]).impl, "https://anthropic.test");
  await assert.rejects(limited.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000)), (e: ProviderError) => e.code === "rate_limited");
  const down = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model: "m" }, fakeAnthropic([() => json({}, 500)]).impl, "https://anthropic.test");
  await assert.rejects(down.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000)), (e: ProviderError) => e.code === "provider_unavailable");
  const empty = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model: "m" }, fakeAnthropic([() => json({ content: [], stop_reason: "end_turn" })]).impl, "https://anthropic.test");
  await assert.rejects(empty.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000)), (e: ProviderError) => e.code === "malformed_provider_result");
});

test("helpers: file IDs only from code-execution results; file names never carry a path", () => {
  assert.deepEqual(
    fileIdsOf([
      { type: "text", text: "file_id: file_fake" },
      { type: "bash_code_execution_tool_result", content: { type: "bash_code_execution_result", content: [{ file_id: "file_a" }, { file_id: 5 }] } },
      { type: "bash_code_execution_tool_result", content: { type: "bash_code_execution_tool_result_error" } },
    ]),
    ["file_a"],
  );
  assert.equal(fileName("../../etc/passwd", "pdf"), "etcpasswd.pdf");
  assert.equal(fileName("Plan na Q4 — Doddy", "pptx"), "Plan na Q4 Doddy.pptx");
  assert.equal(fileName("///", "md"), "Doddy.md");
});

test("config: Claude is live-only, checked, and has its own caps", () => {
  const key = Buffer.alloc(32, 1).toString("base64");
  const live = { DODDY_MODE: "live", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: key, MONID_API_KEY: "monid_live_abcdefghij", DODDY_PUBLIC_BASE_URL: "https://doddy.test" };
  assert.deepEqual(loadConfig({ ...live, ANTHROPIC_API_KEY: "sk-ant-api03-abcdefghij" }).claude, { apiKey: "sk-ant-api03-abcdefghij", model: "claude-sonnet-5-5" });
  assert.equal(loadConfig(live).claude, null);
  assert.equal(loadConfig({ DODDY_MODE: "mock", ANTHROPIC_API_KEY: "sk-ant-api03-abcdefghij" }).claude, null);
  assert.throws(() => loadConfig({ ...live, ANTHROPIC_API_KEY: "nope" }), (e: ConfigError) => e.problems.some((p) => /ANTHROPIC_API_KEY/.test(p) && !/nope/.test(p)));
  const limits = loadConfig({ DODDY_LIMIT_USER_DAILY_CLAUDE: "5", DODDY_LIMIT_SERVICE_DAILY_CLAUDE: "50" }).limits;
  assert.equal(limits.userDailyClaude, 5);
  assert.equal(limits.serviceDailyClaude, 50);
});

test("document links: signed, expiring, and bound to one ID", () => {
  const links = new DocumentLinks(TEST_LINK_KEY, "https://api.doddy.test");
  const now = new Date("2026-10-21T00:00:00Z");
  const url = new URL(links.link("abcdefghijklmnopqrstuvwx", now));
  assert.equal(links.verify(url, now), "abcdefghijklmnopqrstuvwx");
  assert.equal(links.verify(url, new Date("2026-10-29T00:00:00Z")), null);
  const other = new URL(url);
  other.pathname = "/v1/documents/abcdefghijklmnopqrstuvwy";
  assert.equal(links.verify(other, now), null);
  assert.equal(new DocumentLinks(Buffer.alloc(32, 8), "https://api.doddy.test").verify(url, now), null);
});

void on;
