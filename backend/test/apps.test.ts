import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { AppError } from "../src/errors.js";
import {
  accessOf,
  APP_IDS,
  APP_REGISTRY,
  type AppEntry,
  appTools,
  FIND_IN_APP,
  READ_FROM_APP,
  registryProblems,
  toolsForAccess,
  translateAppsCall,
} from "../src/tools/apps.js";
import { CLOUD_TOOLS } from "../src/tools/catalog.js";
import { USER_B } from "./helpers.js";
import { connect, type Rig, runRaw, start } from "./toolsRig.js";

/**
 * A1 (ADR-699): find_in_app / read_from_app and one access choice per app. Mock provider only: none
 * of this ran against a real account or the live voice agent.
 */
let rig: Rig;
afterEach(async () => rig?.close());

const prepare = (r: Rig, tool: string, args: Record<string, unknown>, token?: string) =>
  r.call("POST", "/v1/tools/prepare", { ...(token ? { token } : {}), body: { tool, arguments: args } });
const access = (r: Rig, app: string, mode: string, token?: string) =>
  r.call("PUT", "/v1/tools/access", { ...(token ? { token } : {}), body: { app, mode } });
/** The app's flow for a generic read: ask, then run with the approval. */
async function ask(r: Rig, tool: string, args: Record<string, unknown>) {
  const asked = await prepare(r, tool, args);
  if (asked.status !== 200) return asked;
  return runRaw(r, tool, args, { approvalId: asked.body.approvalId });
}
const slugs = (r: Rig) => r.provider.executed.map((e) => e.slug);
const enabledNames = async (r: Rig) =>
  new Set<string>(((await r.call("GET", "/v1/tools")).body.toolkits as any[]).flatMap((t) => t.tools).filter((t: any) => t.enabled).map((t: any) => t.name));

// ------------------------------------------------------------------ the registry

test("the registry maps only existing reads of the same app (and says so when it doesn't)", () => {
  assert.deepEqual(registryProblems(APP_REGISTRY), []);
  assert.deepEqual([...APP_IDS], ["gmail", "gcalendar"]);

  const same = (tool: string) => ({ tool, translate: () => ({}), usage: "" });
  const problem = (entry: AppEntry) => registryProblems([entry]).map((p) => p.problem);
  // A write can never be registered as a generic read.
  assert.deepEqual(problem({ app: "gmail", find: same("send_email") }), ["tool send_email is not a read"]);
  assert.deepEqual(problem({ app: "gmail", read: same("trash_email") }), ["tool trash_email is not a read"]);
  // The wrong app's tool, and a tool that doesn't exist.
  assert.deepEqual(problem({ app: "gcalendar", find: same("read_email") }), ["tool read_email belongs to gmail"]);
  assert.deepEqual(problem({ app: "gmail", find: same("run_anything") }), ["tool run_anything does not exist"]);
  // The same app twice.
  assert.ok(registryProblems([APP_REGISTRY[0]!, APP_REGISTRY[0]!]).some((p) => p.problem === "the app is listed twice"));
  // Every registered tool in the real registry is a read.
  for (const entry of APP_REGISTRY) {
    for (const role of ["find", "read"] as const) {
      const mapped = entry[role];
      if (mapped) assert.equal(CLOUD_TOOLS.find((t) => t.name === mapped.tool)?.risk, "read", `${entry.app}/${role}`);
    }
  }
});

// ------------------------------------------------------------------ translation

test("generic words become the mapped tool's arguments, and nothing else is accepted", () => {
  assert.deepEqual(translateAppsCall(FIND_IN_APP, { app: "gmail", query: "is:unread" }), { tool: "check_email", arguments: { query: "is:unread" } });
  assert.deepEqual(translateAppsCall(READ_FROM_APP, { app: "gmail", query: "from:marta" }), { tool: "read_email", arguments: { query: "from:marta" } });
  assert.deepEqual(translateAppsCall(FIND_IN_APP, { app: "gcalendar", query: "2026-11-04" }), { tool: "read_google_calendar", arguments: { from: "2026-11-04", to: "2026-11-04" } });
  assert.deepEqual(translateAppsCall(FIND_IN_APP, { app: "gcalendar", query: "2026-11-04..2026-11-06" }), { tool: "read_google_calendar", arguments: { from: "2026-11-04", to: "2026-11-06" } });

  const refused = (name: typeof FIND_IN_APP | typeof READ_FROM_APP, args: Record<string, unknown>) => {
    assert.throws(() => translateAppsCall(name, args), (e: unknown) => e instanceof AppError && e.code === "invalid_request", JSON.stringify(args));
  };
  refused(FIND_IN_APP, { app: "notion", query: "x" }); // not in the registry
  refused(FIND_IN_APP, { app: "gmail" }); // no words
  refused(FIND_IN_APP, { app: "gmail", query: "x", slug: "GMAIL_SEND_EMAIL" }); // extra field
  refused(FIND_IN_APP, { app: "gmail", query: "x", userId: "dev-user-b" });
  refused(READ_FROM_APP, { app: "gcalendar", query: "2026-11-04" }); // that app has no read role
  refused(FIND_IN_APP, { app: "gcalendar", query: "tomorrow" }); // not a date
  refused(FIND_IN_APP, { app: "gcalendar", query: "2026-02-31" }); // not a real day
  refused(FIND_IN_APP, { app: "gcalendar", query: "2026-11-04..2026-11-05..2026-11-06" });
  refused(FIND_IN_APP, { app: "gmail", query: "x".repeat(201) });
});

// ------------------------------------------------------------------ access modes (pure)

test("Off, Read only and Read and act pick exactly the right switches", () => {
  for (const app of APP_IDS) {
    const all = appTools(app);
    assert.ok(all.some((t) => t.risk === "read") && all.length > 0);
    const off = toolsForAccess(app, "off");
    assert.deepEqual(off.on, []);
    assert.equal(off.off.length, all.length);

    const read = toolsForAccess(app, "read");
    assert.deepEqual(read.on.sort(), all.filter((t) => t.risk === "read").map((t) => t.name).sort());
    assert.deepEqual(read.off.sort(), all.filter((t) => t.risk === "write").map((t) => t.name).sort());

    const act = toolsForAccess(app, "act");
    assert.equal(act.on.length, all.length);
    assert.deepEqual(act.off, []);

    assert.equal(accessOf(app, new Set()), "off");
    assert.equal(accessOf(app, new Set(read.on)), "read");
    assert.equal(accessOf(app, new Set(act.on)), "act");
  }
  assert.ok(toolsForAccess("gmail", "read").off.includes("send_email"));
  assert.ok(!toolsForAccess("gmail", "read").on.includes("send_email"));
});

// ------------------------------------------------------------------ through the server

test("find_in_app asks first, then runs the one mapped read; a repeat or changed words can't reuse the yes", async () => {
  rig = await start();
  assert.equal((await connect(rig, "gmail")).status, 200);

  // ASK-01: no approval, no provider call.
  const unasked = await runRaw(rig, FIND_IN_APP, { app: "gmail", query: "in:inbox" });
  assert.equal(unasked.status, 403, unasked.text);
  assert.equal(unasked.body.error.receipt.errorCode, "ask_first_required");
  assert.equal(rig.provider.executed.length, 0);

  const asked = await prepare(rig, FIND_IN_APP, { app: "gmail", query: "in:inbox" });
  assert.equal(asked.status, 200, asked.text);
  assert.equal(asked.body.tool, FIND_IN_APP);
  assert.equal(asked.body.preview.title, "Check your Gmail?");
  assert.equal(rig.provider.executed.length, 0, "the card is made before anything is read");

  // The yes belongs to exactly these words.
  const other = await runRaw(rig, FIND_IN_APP, { app: "gmail", query: "from:boss" }, { approvalId: asked.body.approvalId });
  assert.equal(other.status, 403);
  assert.equal(rig.provider.executed.length, 0);

  const ran = await runRaw(rig, FIND_IN_APP, { app: "gmail", query: "in:inbox" }, { approvalId: asked.body.approvalId });
  assert.equal(ran.status, 200, ran.text);
  assert.equal(ran.body.tool, FIND_IN_APP);
  assert.equal(ran.body.receipt.operation, "read");
  assert.deepEqual(slugs(rig), ["GMAIL_FETCH_EMAILS"]);
  assert.equal(rig.provider.executed[0]!.arguments.query, "in:inbox");
  assert.ok(ran.body.count > 0);

  // One yes, one read.
  const again = await runRaw(rig, FIND_IN_APP, { app: "gmail", query: "in:inbox" }, { approvalId: asked.body.approvalId });
  assert.equal(again.status, 403);
  assert.deepEqual(slugs(rig), ["GMAIL_FETCH_EMAILS"]);
});

test("a yes for the named tool and the generic tool are the same yes for the same words, and nothing more", async () => {
  rig = await start();
  await connect(rig, "gmail");
  const named = await prepare(rig, "check_email", { query: "is:unread" });
  assert.equal(named.status, 200);
  const viaGeneric = await runRaw(rig, FIND_IN_APP, { app: "gmail", query: "is:unread" }, { approvalId: named.body.approvalId });
  assert.equal(viaGeneric.status, 200, viaGeneric.text);
  // But it never opens a different tool: read_from_app needs its own yes.
  const read = await runRaw(rig, READ_FROM_APP, { app: "gmail", query: "is:unread" }, { approvalId: named.body.approvalId });
  assert.equal(read.status, 403);
});

test("read_from_app opens one email; Calendar takes dates through find_in_app", async () => {
  rig = await start();
  await connect(rig, "gmail");
  await connect(rig, "gcalendar");
  const email = await ask(rig, READ_FROM_APP, { app: "gmail", query: "from:anna" });
  assert.equal(email.status, 200, email.text);
  assert.equal(email.body.tool, READ_FROM_APP);

  const cal = await ask(rig, FIND_IN_APP, { app: "gcalendar", query: "2026-10-12" });
  assert.equal(cal.status, 200, cal.text);
  assert.ok(slugs(rig).includes("GOOGLECALENDAR_EVENTS_LIST"));

  // Unusable words never reach the provider.
  const before = rig.provider.executed.length;
  assert.equal((await prepare(rig, FIND_IN_APP, { app: "gcalendar", query: "next week" })).status, 400);
  assert.equal((await prepare(rig, FIND_IN_APP, { app: "gcalendar", query: "2026-10-12..2026-12-31" })).status, 400);
  assert.equal((await prepare(rig, FIND_IN_APP, { app: "notion", query: "trip" })).status, 400);
  assert.equal((await prepare(rig, READ_FROM_APP, { app: "gcalendar", query: "2026-10-12" })).status, 400);
  assert.equal(rig.provider.executed.length, before);
});

test("the generic tools never run a write, whatever words they get", async () => {
  rig = await start();
  await connect(rig, "gmail");
  for (const tool of [FIND_IN_APP, READ_FROM_APP]) {
    for (const query of ["send_email", "GMAIL_SEND_EMAIL", "delete everything", "to:me body:hello"]) {
      const res = await ask(rig, tool, { app: "gmail", query });
      assert.ok(res.status < 500, `${tool} ${query}: ${res.status}`);
    }
  }
  assert.ok(slugs(rig).every((s) => s === "GMAIL_FETCH_EMAILS"), slugs(rig).join(","));
});

test("find_in_app needs the app connected, and the user's off still wins", async () => {
  rig = await start();
  const none = await prepare(rig, FIND_IN_APP, { app: "gmail", query: "in:inbox" });
  assert.equal(none.status, 409);
  assert.equal(none.body.error.code, "not_connected");

  await connect(rig, "gmail");
  assert.equal((await access(rig, "gmail", "off")).status, 200);
  const blocked = await prepare(rig, FIND_IN_APP, { app: "gmail", query: "in:inbox" });
  assert.equal(blocked.status, 403);
  assert.equal(blocked.body.error.code, "capability_disabled");
  assert.equal(rig.provider.executed.length, 0);
});

// ------------------------------------------------------------------ one access choice per app

test("PUT /v1/tools/access sets an app's switches in bulk: off, read only, read and act", async () => {
  rig = await start();
  assert.equal((await connect(rig, "gmail")).status, 200);
  const gmailReads = appTools("gmail").filter((t) => t.risk === "read").map((t) => t.name);
  const gmailAll = appTools("gmail").map((t) => t.name);

  const read = await access(rig, "gmail", "read");
  assert.equal(read.status, 200, read.text);
  assert.equal(read.body.toolkit.id, "gmail");
  assert.equal(read.body.receipt.operation, "switch");
  assert.equal(read.body.receipt.summary, "Gmail access set to read only.");
  assert.deepEqual([...(await enabledNames(rig))].filter((n) => gmailAll.includes(n)).sort(), [...gmailReads].sort());
  // A write is refused at once, before any approval is looked at.
  assert.equal((await prepare(rig, "send_email", { to: "a@b.example", subject: "s", body: "b" })).status, 403);

  assert.equal((await access(rig, "gmail", "act")).status, 200);
  assert.deepEqual([...(await enabledNames(rig))].filter((n) => gmailAll.includes(n)).sort(), [...gmailAll].sort());

  const off = await access(rig, "gmail", "off");
  assert.equal(off.status, 200);
  assert.equal(off.body.receipt.summary, "Gmail access set to off.");
  assert.deepEqual([...(await enabledNames(rig))].filter((n) => gmailAll.includes(n)), []);
});

test("an access choice that can't be honoured changes nothing", async () => {
  rig = await start();
  // Not connected: read or act is refused, and off is fine.
  const refused = await access(rig, "gmail", "read");
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error.code, "not_connected");
  assert.equal((await access(rig, "gmail", "off")).status, 200);

  // Connected with only compose-level reads: "act" needs every tool's grant, so it is refused whole.
  await connect(rig, "gmail", undefined, "read_compose_only");
  const before = await enabledNames(rig);
  const act = await access(rig, "gmail", "act");
  assert.equal(act.status, 403, act.text);
  assert.equal(act.body.error.code, "permission_insufficient");
  assert.deepEqual([...(await enabledNames(rig))].sort(), [...before].sort());
});

test("access strict bodies, unknown apps, and one user can't change another's", async () => {
  rig = await start();
  assert.equal((await rig.call("PUT", "/v1/tools/access", { body: { app: "gmail", mode: "all" } })).status, 400);
  assert.equal((await rig.call("PUT", "/v1/tools/access", { body: { app: "facebook", mode: "read" } })).status, 400);
  assert.equal((await rig.call("PUT", "/v1/tools/access", { body: { app: "gmail", mode: "read", userId: "dev-user-b" } })).status, 400);
  assert.equal((await rig.call("PUT", "/v1/tools/access", { token: null, body: { app: "gmail", mode: "off" } })).status, 401);

  await connect(rig, "gmail");
  await connect(rig, "gmail", USER_B);
  assert.equal((await access(rig, "gmail", "off")).status, 200);
  // User B's switches are untouched by A's change.
  const b = (await rig.call("GET", "/v1/tools", { token: USER_B })).body.toolkits.find((t: any) => t.id === "gmail");
  assert.ok(b.tools.every((t: any) => t.enabled));
});
