import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { MockClaudeProvider } from "../src/tools/claude.js";
import { USER_A } from "./helpers.js";
import { CHROME_MAC, startWeb } from "./webRig.js";

/**
 * Writes contracts/web/*.json from the real server (mock tools, fixed clock), so the iPhone's
 * decoder tests (DoddyCore) and the web app's schema tests read actual output (ADR-579).
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
