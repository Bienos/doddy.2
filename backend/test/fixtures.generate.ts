import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { CAL, connectMock, harness, tomorrow } from "./helpers.js";

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
process.stdout.write(`fixtures written to ${out}\n`);
