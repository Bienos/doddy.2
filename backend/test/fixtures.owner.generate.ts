import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DEV_IDENTITIES } from "../src/auth.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb } from "./webRig.js";

/**
 * Writes contracts/web/owner-*.json from the real server (fixed clock 2026-10-22T10:00:00Z, a fake
 * Supabase account list, four accounts with seeded days), so the web app's admin dashboard reads
 * actual replies (decision 2026-11-09-usage-counts-on-by-default). Its own script: these replies
 * carry no random ids, so running it changes nothing else.
 * Run: npm run fixtures:owner
 */
const out = join(process.cwd(), "..", "contracts", "web");
mkdirSync(out, { recursive: true });
const write = (name: string, body: unknown) => writeFileSync(join(out, `${name}.json`), `${JSON.stringify(body, null, 2)}\n`);

const ID_A = DEV_IDENTITIES[USER_A]!; // the owner
const ID_B = DEV_IDENTITIES[USER_B]!; // Tomek, Google
const ID_C = "00000000-0000-4000-8000-0000000000c3"; // Kasia, email: used it twice
const ID_D = "00000000-0000-4000-8000-0000000000c4"; // an Apple relay address: joined, never used
const NOW = Date.parse("2026-10-22T10:00:00Z");
const DAY = 86_400_000;
const iso = (offset: number) => new Date(NOW + offset * DAY).toISOString().slice(0, 10);

const rig = await startWeb({
  owner: {
    accounts: [ID_A],
    directory: {
      list: async () => [
        { id: ID_A, email: "owner@example.com", name: "Owner", method: "apple", createdAt: "2026-10-01T08:00:00Z", lastSignInAt: "2026-10-22T07:00:00Z" },
        { id: ID_B, email: "tomek@example.com", name: "Tomek Nowak", method: "google", createdAt: "2026-10-12T12:00:00Z", lastSignInAt: "2026-10-21T18:00:00Z" },
        { id: ID_C, email: "kasia@example.com", name: null, method: "email", createdAt: "2026-10-14T17:05:00Z", lastSignInAt: "2026-10-19T18:00:00Z" },
        { id: ID_D, email: "x7k2p9q4@privaterelay.appleid.com", name: null, method: "apple", createdAt: "2026-10-20T20:00:00Z", lastSignInAt: "2026-10-20T20:00:00Z" },
      ],
    },
  },
});

// A small deterministic generator, so the fixtures are the same every run.
let seed = 11;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const pick = (n: number) => Math.floor(rand() * n);
const TOOLS = ["get_weather", "create_reminder", "save_memory", "search_memories", "read_calendar", "set_timer", "add_to_list", "web_search", "draft_message", "send_email"];
const HOURS = [7, 8, 12, 17, 19, 21];
const LANGUAGES = ["pl", "pl", "pl", "en"];

function day(date: string, count: number) {
  const by_hour = Array<number>(24).fill(0);
  const lengths = { under_1: 0, "1_3": 0, "3_5": 0, "5_10": 0 };
  const ended = { you: 0, doddy: 0, quiet: 0, dropped: 0 };
  const languages: Record<string, number> = {};
  let seconds = 0;
  for (let i = 0; i < count; i++) {
    by_hour[HOURS[pick(HOURS.length)]!]! += 1;
    const s = 30 + pick(420);
    seconds += s;
    lengths[s < 60 ? "under_1" : s < 180 ? "1_3" : s < 300 ? "3_5" : "5_10"] += 1;
    ended[rand() < 0.7 ? "you" : rand() < 0.6 ? "doddy" : rand() < 0.5 ? "quiet" : "dropped"] += 1;
    const language = LANGUAGES[pick(LANGUAGES.length)]!;
    languages[language] = (languages[language] ?? 0) + 1;
  }
  const tools: Record<string, { done: number; declined: number; unsure: number; failed: number; undone: number }> = {};
  for (let i = 0; i < count * 2; i++) {
    const tool = TOOLS[pick(TOOLS.length)]!;
    const row = (tools[tool] ??= { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 });
    const r = rand();
    if (tool === "read_calendar" && r < 0.3) row.failed += 1;
    else if (tool === "send_email" && r < 0.3) row.unsure += 1;
    else if (r < 0.06) row.declined += 1;
    else if (r < 0.09) row.failed += 1;
    else row.done += 1;
  }
  const notes = count > 0 ? pick(3) : 0;
  const handed = count > 2 ? 1 : 0;
  return {
    schema: "doddy.logbook.day.v1",
    day: date,
    conversations: { count, seconds, by_hour, lengths, ended, languages, ways_in: { app: 0, back_tap: 0, action_button: 0, widget: 0, siri: 0, island: 0 } },
    tools,
    notes: { by_source: { voice: notes, typed: 0, shared: 0, imported: 0 }, by_kind: notes ? { fact: notes } : {}, edited: 0 },
    lists: { added_voice: count > 0 ? pick(3) : 0, added_typed: 0, ticked: 0 },
    errands: { handed_over: handed, finished: handed, stopped: 0, minutes: handed * 4, searches: handed * 5, pages: handed * 2 },
    translator: { sessions: 0, minutes: 0 },
  };
}

async function send(user: string, first: number, chance: number, only?: number[]) {
  await rig.store.setLogbookEnabled(user, true, NOW);
  for (let offset = first; offset <= 0; offset++) {
    const used = only ? only.includes(offset) : rand() < chance;
    const d = day(iso(offset), used ? 1 + pick(4) : 0);
    // A day with nothing counted at all is a day the iPhone sent as zeros.
    if (!used) {
      d.notes = { by_source: { voice: 0, typed: 0, shared: 0, imported: 0 }, by_kind: {}, edited: 0 };
      d.lists = { added_voice: 0, added_typed: 0, ticked: 0 };
      d.tools = {};
    }
    await rig.store.putLogbookDay(user, d.day, JSON.stringify(d), NOW);
  }
}

await send(ID_A, -21, 0.9);
await send(ID_B, -10, 0.8);
await send(ID_C, -8, 0, [-7, -3]);
// ID_D never turned Logbook on.

// The panel is for a browser that has just signed in (decision 2026-11-14-owner-panel-fresh-sign-in).
const cookie = await rig.signIn(await rig.code(USER_A));
write("owner-flag", (await rig.call("GET", "/v1/web/owner", { cookie })).body);
write("owner-overview", (await rig.call("GET", "/v1/web/owner/overview?days=30", { cookie })).body);
write("owner-accounts", (await rig.call("GET", "/v1/web/owner/accounts?days=30", { cookie })).body);
write("owner-account-logbook", (await rig.call("GET", `/v1/web/owner/accounts/${ID_B}/logbook`, { cookie })).body);
await rig.close();
