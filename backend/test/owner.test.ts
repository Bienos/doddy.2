import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES } from "../src/auth.js";
import { type DirectoryUser, type GetJson, SupabaseUserDirectory, type UserDirectory } from "../src/web/owner.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * The owner panel (decision 2026-11-09-usage-counts-on-by-default): totals of every account's
 * Logbook days and each account's own days, for the accounts in DODDY_OWNER_ACCOUNTS only.
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const ID_A = DEV_IDENTITIES[USER_A]!; // the owner in these tests
const ID_B = DEV_IDENTITIES[USER_B]!;
const TODAY = "2026-10-22"; // the rig's clock
const DAY = 86_400_000;
const iso = (offsetDays: number) => new Date(Date.parse(`${TODAY}T00:00:00Z`) + offsetDays * DAY).toISOString().slice(0, 10);

function day(date: string, conversations: number, tools: Record<string, Record<string, number>> = {}) {
  return {
    schema: "doddy.logbook.day.v1",
    day: date,
    conversations: {
      count: conversations,
      seconds: conversations * 120,
      by_hour: Array.from({ length: 24 }, (_, h) => (h === 9 ? conversations : 0)),
      lengths: { under_1: 0, "1_3": conversations, "3_5": 0, "5_10": 0 },
      ended: { you: conversations, doddy: 0, quiet: 0, dropped: 0 },
      languages: {},
      ways_in: { app: 0, back_tap: 0, action_button: 0, widget: 0, siri: 0, island: 0 },
    },
    tools,
    notes: { by_source: { voice: 1, typed: 0, shared: 0, imported: 0 }, by_kind: { fact: 1 }, edited: 0 },
    lists: { added_voice: 0, added_typed: 2, ticked: 0 },
    errands: { handed_over: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 },
    translator: { sessions: 0, minutes: 0 },
  };
}

async function send(r: WebRig, token: string, ...days: ReturnType<typeof day>[]) {
  assert.equal((await r.call("PUT", "/v1/web/logbook/state", { token, body: { enabled: true } })).status, 200);
  for (const d of days) {
    const res = await r.call("PUT", `/v1/web/logbook/days/${d.day}`, { token, body: d });
    assert.equal(res.status, 200, res.text);
  }
}

const directory = (users: DirectoryUser[] | null): UserDirectory => ({ list: async () => users });

const people: DirectoryUser[] = [
  { id: ID_A, email: "owner@example.com", name: "Owner", method: "apple", createdAt: "2026-10-01T08:00:00Z", lastSignInAt: "2026-10-22T07:00:00Z" },
  { id: ID_B, email: "tomek@example.com", name: "Tomek", method: "google", createdAt: "2026-10-20T12:00:00Z", lastSignInAt: "2026-10-21T18:00:00Z" },
];

test("anyone not named as an owner is told there is nothing here, from the iPhone or a browser", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  for (const path of ["/v1/web/owner", "/v1/web/owner/overview", "/v1/web/owner/accounts", `/v1/web/owner/accounts/${ID_A}/logbook`]) {
    const phone = await rig.call("GET", path, { token: USER_B });
    assert.equal(phone.status, 404, path);
    assert.equal(phone.body.error.code, "not_found");
    assert.equal((await rig.call("GET", path)).status, 401, `${path} signed out`);
  }
  const browserB = await rig.signIn(await rig.code(USER_B));
  assert.equal((await rig.call("GET", "/v1/web/owner/overview", { cookie: browserB })).status, 404);
});

test("without owner accounts the routes don't exist at all", async () => {
  rig = await startWeb();
  assert.equal((await rig.call("GET", "/v1/web/owner", { token: USER_A })).status, 404);
});

test("the owner sees totals across every account and who signed up how", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  await send(rig, USER_A, day(iso(-1), 2, { get_weather: { done: 2 } }), day(iso(0), 1));
  await send(rig, USER_B, day(iso(0), 3, { get_weather: { done: 1, failed: 1 }, create_reminder: { declined: 1 } }));

  const cookie = await rig.signIn(await rig.code(USER_A));
  assert.deepEqual((await rig.call("GET", "/v1/web/owner", { cookie })).body, { owner: true });
  const res = await rig.call("GET", "/v1/web/owner/overview?days=7", { cookie });
  assert.equal(res.status, 200, res.text);
  const o = res.body;
  assert.equal(o.periodDays, 7);
  assert.equal(o.directory, true);
  assert.equal(o.accounts.total, 2);
  assert.deepEqual(o.accounts.byMethod, { apple: 1, google: 1 });
  assert.equal(o.accounts.newByDay.find((d: { day: string }) => d.day === "2026-10-20").count, 1);
  assert.equal(o.logbook.on, 2);
  assert.equal(o.logbook.sending, 2);
  assert.deepEqual(o.logbook.activeByDay.slice(-2), [{ day: iso(-1), accounts: 1 }, { day: iso(0), accounts: 2 }]);
  assert.equal(o.logbook.totals.conversations, 6);
  assert.deepEqual(o.logbook.totals.tools.get_weather, { done: 3, declined: 0, unsure: 0, failed: 1, undone: 0 });
  assert.equal(o.logbook.totals.notes, 3);
  assert.equal(o.logbook.totals.listItems, 6);
});

test("the owner sees each account with its email, method and its own days", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  await send(rig, USER_B, day(iso(-2), 1), day(iso(0), 3, { get_weather: { failed: 2 } }));

  const res = await rig.call("GET", "/v1/web/owner/accounts?days=30", { token: USER_A });
  assert.equal(res.status, 200, res.text);
  const tomek = res.body.accounts.find((a: { email: string }) => a.email === "tomek@example.com");
  assert.equal(tomek.userId, ID_B);
  assert.equal(tomek.method, "google");
  assert.equal(tomek.name, "Tomek");
  assert.equal(tomek.logbook, "on");
  assert.equal(tomek.lastDay, iso(0));
  assert.equal(tomek.period.conversations, 4);
  assert.equal(tomek.period.activeDays, 2);
  assert.deepEqual(tomek.period.tools.get_weather, { done: 0, declined: 0, unsure: 0, failed: 2, undone: 0 });
  const owner = res.body.accounts.find((a: { email: string }) => a.email === "owner@example.com");
  assert.equal(owner.logbook, "never", "the owner's own iPhone never set it");

  const days = await rig.call("GET", `/v1/web/owner/accounts/${ID_B}/logbook`, { token: USER_A });
  assert.equal(days.status, 200);
  assert.deepEqual(days.body.days.map((d: { day: string }) => d.day), [iso(-2), iso(0)]);
});

test("an owner named by the Doddy account that took over an iPhone's earlier data is recognised", async () => {
  const account = "6b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
  rig = await startWeb({ owner: { accounts: [account] } });
  assert.equal((await rig.call("GET", "/v1/web/owner", { token: USER_A })).status, 404, "not linked yet");
  await rig.store.db.query("INSERT INTO account_links (subject, user_id, linked_at) VALUES ($1, $2, $3)", [account, ID_A, Date.now()]);
  assert.equal((await rig.call("GET", "/v1/web/owner", { token: USER_A })).status, 200);
  assert.equal((await rig.call("GET", "/v1/web/owner", { token: USER_B })).status, 404);
});

test("without Supabase's account list the panel says so and still counts Logbook", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(null) } });
  await send(rig, USER_B, day(iso(0), 1));
  const overview = (await rig.call("GET", "/v1/web/owner/overview", { token: USER_A })).body;
  assert.equal(overview.directory, false);
  assert.equal(overview.accounts.total, null);
  assert.equal(overview.periodDays, 30, "the default period");
  const accounts = (await rig.call("GET", "/v1/web/owner/accounts", { token: USER_A })).body;
  assert.equal(accounts.accounts.length, 1);
  assert.equal(accounts.accounts[0].userId, ID_B);
  assert.equal(accounts.accounts[0].email, null);
});

test("Supabase's admin list is read page by page with the secret key, and a failure is null, never a guess", async () => {
  const calls: { url: string; headers: Record<string, string> }[] = [];
  const user = (n: number) => ({ id: `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`, email: `p${n}@example.com`, app_metadata: { provider: "google" }, user_metadata: { full_name: `P ${n}` }, created_at: "2026-10-01T00:00:00Z", last_sign_in_at: null });
  const get: GetJson = async (url, init) => {
    calls.push({ url, headers: init.headers });
    const page = Number(new URL(url).searchParams.get("page"));
    const count = page === 1 ? SupabaseUserDirectory.perPage : 3;
    return { status: 200, body: { users: Array.from({ length: count }, (_, i) => user((page - 1) * 1000 + i)), aud: "authenticated" } };
  };
  const users = await new SupabaseUserDirectory("https://ref.supabase.co", "sb_secret_test", get).list(new AbortController().signal);
  assert.equal(users?.length, SupabaseUserDirectory.perPage + 3);
  assert.equal(calls.length, 2);
  assert.match(calls[0]!.url, /^https:\/\/ref\.supabase\.co\/auth\/v1\/admin\/users\?page=1&per_page=500$/);
  assert.equal(calls[0]!.headers.authorization, "Bearer sb_secret_test");
  assert.deepEqual(users?.[1], { id: user(1).id, email: "p1@example.com", name: "P 1", method: "google", createdAt: "2026-10-01T00:00:00Z", lastSignInAt: null });

  const refused = new SupabaseUserDirectory("https://ref.supabase.co", "sb_secret_test", async () => ({ status: 401, body: { msg: "no" } }));
  assert.equal(await refused.list(new AbortController().signal), null);
  const broken = new SupabaseUserDirectory("https://ref.supabase.co", "sb_secret_test", async () => {
    throw new Error("offline");
  });
  assert.equal(await broken.list(new AbortController().signal), null);
});
