import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DEV_IDENTITIES } from "../src/auth.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb } from "./webRig.js";

/**
 * Writes contracts/web/owner-*.json from the real server (fixed clock, a fake Supabase account list),
 * so the web app's owner panel reads actual replies (decision 2026-11-09-usage-counts-on-by-default).
 * Its own script because these replies carry no random ids, so running it changes nothing else.
 * Run: npm run fixtures:owner
 */
const out = join(process.cwd(), "..", "contracts", "web");
mkdirSync(out, { recursive: true });
const write = (name: string, body: unknown) => writeFileSync(join(out, `${name}.json`), `${JSON.stringify(body, null, 2)}\n`);

const ID_A = DEV_IDENTITIES[USER_A]!;
const ID_B = DEV_IDENTITIES[USER_B]!;
const rig = await startWeb({
  owner: {
    accounts: [ID_A],
    directory: {
      list: async () => [
        { id: ID_A, email: "owner@example.com", name: "Owner", method: "apple", createdAt: "2026-10-01T08:00:00Z", lastSignInAt: "2026-10-22T07:00:00Z" },
        { id: ID_B, email: "tomek@example.com", name: "Tomek", method: "google", createdAt: "2026-10-20T12:00:00Z", lastSignInAt: "2026-10-21T18:00:00Z" },
      ],
    },
  },
});

const day = (date: string, n: number) => ({
  schema: "doddy.logbook.day.v1",
  day: date,
  conversations: {
    count: n,
    seconds: n * 150,
    by_hour: Array.from({ length: 24 }, (_, h) => (h === 9 ? n : 0)),
    lengths: { under_1: 0, "1_3": n, "3_5": 0, "5_10": 0 },
    ended: { you: n, doddy: 0, quiet: 0, dropped: 0 },
    languages: { pl: n },
    ways_in: { app: 0, back_tap: 0, action_button: 0, widget: 0, siri: 0, island: 0 },
  },
  tools: { get_weather: { done: n, failed: 1 }, create_reminder: { done: 1, declined: 1 } },
  notes: { by_source: { voice: 1, typed: 1, shared: 0, imported: 0 }, by_kind: { fact: 2 }, edited: 0 },
  lists: { added_voice: 1, added_typed: 1, ticked: 0 },
  errands: { handed_over: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 },
  translator: { sessions: 0, minutes: 0 },
});
for (const [token, days] of [[USER_A, [["2026-10-21", 2]]], [USER_B, [["2026-10-20", 1], ["2026-10-22", 3]]]] as const) {
  await rig.call("PUT", "/v1/web/logbook/state", { token, body: { enabled: true } });
  for (const [date, n] of days) await rig.call("PUT", `/v1/web/logbook/days/${date}`, { token, body: day(date, n) });
}

write("owner-flag", (await rig.call("GET", "/v1/web/owner", { token: USER_A })).body);
write("owner-overview", (await rig.call("GET", "/v1/web/owner/overview?days=30", { token: USER_A })).body);
write("owner-accounts", (await rig.call("GET", "/v1/web/owner/accounts?days=30", { token: USER_A })).body);
write("owner-account-logbook", (await rig.call("GET", `/v1/web/owner/accounts/${ID_B}/logbook`, { token: USER_A })).body);
await rig.close();
