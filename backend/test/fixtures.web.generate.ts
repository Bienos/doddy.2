import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { MockClaudeProvider } from "../src/tools/claude.js";
import { USER_A } from "./helpers.js";
import { CHROME_MAC, startWeb } from "./webRig.js";

/**
 * Writes contracts/web/*.json from the real server (mock tools, fixed clock), so the iPhone's
 * decoder tests (DoddyCore) and the web app's schema tests read actual output (ADR-585).
 * Run: npm run fixtures:web
 */
const out = join(process.cwd(), "..", "contracts", "web");
mkdirSync(out, { recursive: true });
const write = (name: string, body: unknown) => writeFileSync(join(out, `${name}.json`), `${JSON.stringify(body, null, 2)}\n`);

let release!: () => void;
const gate = new Promise<void>((r) => (release = r));
const claude = new MockClaudeProvider();
const original = claude.makeDocument.bind(claude);
let made = 0;
claude.makeDocument = async (args) => {
  // The first two wait until the fixtures have seen them working; the third never finishes, like a
  // job whose server restarted.
  if (++made === 3) return new Promise(() => {});
  await gate;
  return original(args);
};
const rig = await startWeb({ claude });

const make = async (kind: string, title: string) => {
  const args = { kind, title, request: "For the fixtures" };
  const asked = await rig.call("POST", "/v1/tools/prepare", { token: USER_A, body: { tool: "make_document", arguments: args } });
  await rig.call("POST", "/v1/tools/run", { token: USER_A, body: { tool: "make_document", arguments: args, timeZone: "Europe/Warsaw", approvalId: asked.body.approvalId } });
};

const code = await rig.call("POST", "/v1/web/link-codes", { token: USER_A, body: {} });
write("link-code", code.body);
const signedIn = await rig.call("POST", "/v1/web/session", { browser: true, body: { code: code.body.code }, headers: { "user-agent": CHROME_MAC } });
write("session-signed-in", signedIn.body);
write("error-code-invalid", (await rig.call("POST", "/v1/web/session", { browser: true, body: { code: code.body.code } })).body);
const cookie = /=([^;]*)/.exec(signedIn.headers.get("set-cookie")!)![1]!;
write("session-current", (await rig.call("GET", "/v1/web/session", { cookie })).body);
write("sessions-phone", (await rig.call("GET", "/v1/web/sessions", { token: USER_A })).body);
write("error-signed-out", (await rig.call("GET", "/v1/web/session", { cookie: "x".repeat(43) })).body);

// Logbook (ADR-593): the iPhone's calls and what the page reads. Counts only, fixed clock.
const logbookDay = (date: string, n: number) => ({
  schema: "doddy.logbook.day.v1",
  day: date,
  conversations: {
    count: n,
    seconds: n * 180,
    by_hour: Array.from({ length: 24 }, (_, h) => (h === 8 ? n - Math.floor(n / 2) : h === 19 ? Math.floor(n / 2) : 0)),
    lengths: { under_1: 0, "1_3": n, "3_5": 0, "5_10": 0 },
    ended: { you: n, doddy: 0, quiet: 0, dropped: 0 },
    languages: { en: n },
    ways_in: { app: 0, back_tap: n, action_button: 0, widget: 0, siri: 0, island: 0 },
  },
  tools: { save_memory: { done: n }, read_calendar: { done: n, failed: n > 2 ? 1 : 0 }, send_email: { done: 0, declined: 1, unsure: n > 2 ? 1 : 0 } },
  notes: { by_source: { voice: n, typed: 0, shared: 0, imported: 0 }, by_kind: { fact: n }, edited: 0 },
  lists: { added_voice: n, added_typed: 0, ticked: 1 },
  errands: { handed_over: 1, finished: 1, stopped: 0, minutes: 4, searches: 6, pages: 3 },
  translator: { sessions: 0, minutes: 0 },
});
write("logbook-off", (await rig.call("GET", "/v1/web/logbook", { cookie })).body);
write("error-logbook-off", (await rig.call("PUT", "/v1/web/logbook/days/2026-10-22", { token: USER_A, body: logbookDay("2026-10-22", 3) })).body);
write("logbook-state-on", (await rig.call("PUT", "/v1/web/logbook/state", { token: USER_A, body: { enabled: true } })).body);
write("logbook-empty", (await rig.call("GET", "/v1/web/logbook", { cookie })).body);
write("error-logbook-invalid", (await rig.call("PUT", "/v1/web/logbook/days/2026-10-22", { token: USER_A, body: { ...logbookDay("2026-10-22", 3), transcript: "x" } })).body);
write("logbook-stored", (await rig.call("PUT", "/v1/web/logbook/days/2026-10-20", { token: USER_A, body: logbookDay("2026-10-20", 4) })).body);
await rig.call("PUT", "/v1/web/logbook/days/2026-10-21", { token: USER_A, body: logbookDay("2026-10-21", 1) });
await rig.call("PUT", "/v1/web/logbook/days/2026-10-22", { token: USER_A, body: logbookDay("2026-10-22", 3) });
write("logbook-view", (await rig.call("GET", "/v1/web/logbook", { cookie })).body);
write("logbook-export", JSON.parse((await rig.call("GET", "/v1/web/logbook/export", { cookie })).text));
write("logbook-deleted", (await rig.call("DELETE", "/v1/web/logbook", { cookie, browser: true })).body);

write("documents-empty", (await rig.call("GET", "/v1/web/documents", { cookie })).body);
await make("deck", "Laptops for university");
rig.clock.advance(60_000);
await make("text", "Barcelona trip notes");
write("documents-working", (await rig.call("GET", "/v1/web/documents", { cookie })).body);
release();
await rig.tools.settle();
write("documents-ready", (await rig.call("GET", "/v1/web/documents", { cookie })).body);
await make("pdf", "Mechanics price check");
rig.clock.advance(11 * 60_000);
write("documents-interrupted", (await rig.call("GET", "/v1/web/documents", { cookie })).body);
(rig.tools as unknown as { background: Set<Promise<void>> }).background.clear();
await rig.close();
process.stdout.write(`fixtures written to ${out}\n`);
