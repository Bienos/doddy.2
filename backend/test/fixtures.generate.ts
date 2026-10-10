import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { mkdirSync } from "node:fs";
import { CAL, connectMock, harness, tomorrow } from "./helpers.js";
import { connect, on, ready, run as runTool, start as startRig } from "./toolsRig.js";

/**
 * Regenerates contracts/connected-apps/*.json from the mock server (fixed clock), so the Swift
 * decoder tests and the TypeScript schema tests share real server output. Run: npm run fixtures
 */
const out = join(process.cwd(), "..", "contracts", "connected-apps");
const write = (name: string, body: unknown) => writeFileSync(join(out, `${name}.json`), `${JSON.stringify(body, null, 2)}\n`);

const h = await harness();
const status0 = await h.call("GET", CAL);
write("connection-view-disconnected", status0.body);
const start = await h.call("POST", `${CAL}/connect`, { body: {} });
write("connect-response-mock", start.body);
const done = await h.call("POST", `${CAL}/complete`, {
  body: { attemptId: start.body.attemptId, nonce: start.body.nonce, result: { kind: "mock", outcome: "approve" } },
});
write("connection-result-connected", done.body);
const events = await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
write("events-result-mock", events.body);
const empty = await h.call("POST", `${CAL}/events`, {
  body: { date: tomorrow(h), timeZone: "Europe/Warsaw" },
  headers: { "x-doddy-demo-scenario": "empty" },
});
write("events-result-empty", empty.body);
const malformed = await h.call("POST", `${CAL}/events`, {
  body: { date: tomorrow(h), timeZone: "Europe/Warsaw" },
  headers: { "x-doddy-demo-scenario": "rate_limited" },
});
write("error-rate-limited", malformed.body);
const off = await h.call("POST", `${CAL}/disconnect`, { body: {} });
write("connection-result-disconnected", off.body);
const blocked = await h.call("POST", `${CAL}/events`, { body: { date: tomorrow(h), timeZone: "Europe/Warsaw" } });
write("error-not-connected", blocked.body);
const h2 = await harness();
const broad = await connectMock(h2, "dev-user-a", "broad_scope");
write("connection-result-not-read-only", broad.done.body);
await h.close();
await h2.close();

// ---- online accounts (Gmail, Drive, Notion, Todoist): contracts/online-accounts/
const outTools = join(process.cwd(), "..", "contracts", "online-accounts");
mkdirSync(outTools, { recursive: true });
const writeTool = (name: string, body: unknown) => writeFileSync(join(outTools, `${name}.json`), `${JSON.stringify(body, null, 2)}\n`);
const t = await startRig();
writeTool("catalog-disconnected", (await t.call("GET", "/v1/tools")).body);
writeTool("error-tool-disabled", (await runTool(t, "check_email", {})).body);
const begin = await t.call("POST", "/v1/tools/gmail/connect", { body: {} });
writeTool("connect-response-mock", begin.body);
const connected = await t.call("POST", "/v1/tools/gmail/complete", {
  body: { attemptId: begin.body.attemptId, nonce: begin.body.nonce, result: { kind: "mock", outcome: "approve" } },
});
writeTool("toolkit-result-connected", connected.body);
writeTool("switch-result-on", (await on(t, "check_email")).body);
writeTool("run-result-email", (await runTool(t, "check_email", { max: 5 })).body);
await on(t, "draft_email");
const draftArgs = { to: "anna@example.com", subject: "Lunch Friday", body: "Yes, 1pm works." };
const prepared = await t.call("POST", "/v1/tools/prepare", { body: { tool: "draft_email", arguments: draftArgs } });
writeTool("prepare-result-draft", prepared.body);
writeTool("run-result-draft", (await runTool(t, "draft_email", draftArgs, { approvalId: prepared.body.approvalId })).body);
writeTool("error-confirmation-expired", (await runTool(t, "draft_email", draftArgs, { approvalId: prepared.body.approvalId })).body);
writeTool("catalog-gmail-on", (await t.call("GET", "/v1/tools")).body);
writeTool("receipts", (await t.call("GET", "/v1/tools/receipts")).body);
const t2 = await startRig();
writeTool("toolkit-result-too-broad", (await connect(t2, "gmail", "dev-user-a", "broad_scope")).body);
writeTool("error-permission-insufficient", (await on(t2, "check_email")).body);
await ready(t2, "todoist", "list_todoist_tasks");
t2.provider.setScenario(t2.store.composioUserId("00000000-0000-4000-8000-00000000000a", t2.clock.now()), "rate_limited");
writeTool("error-rate-limited", (await runTool(t2, "list_todoist_tasks", {})).body);
await t.close();
await t2.close();
process.stdout.write(`fixtures written to ${out} and ${outTools}\n`);
