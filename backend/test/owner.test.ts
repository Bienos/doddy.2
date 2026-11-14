import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DEV_IDENTITIES } from "../src/auth.js";
import { type DirectoryUser, type GetJson, OWNER_AUDIT_KEPT_DAYS, OWNER_FRESH_MS, SupabaseUserDirectory, type UserDirectory } from "../src/web/owner.js";
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

function day(date: string, conversations: number, tools: Record<string, Record<string, number>> = {}, over: Record<string, unknown> = {}) {
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
    ...over,
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

/**
 * The owner at a browser that has just signed in. The panel is for a browser only, and only for one
 * that signed in recently (`OWNER_FRESH_MS`); the rig's clock stands still unless a test moves it.
 */
const ownerCookies = new WeakMap<WebRig, string>();
async function ownerCookie(r: WebRig): Promise<string> {
  let cookie = ownerCookies.get(r);
  if (!cookie) {
    cookie = await r.signIn(await r.code(USER_A));
    ownerCookies.set(r, cookie);
  }
  return cookie;
}
const ownerGet = async (r: WebRig, path: string) => r.call("GET", path, { cookie: await ownerCookie(r) });

const people: DirectoryUser[] = [
  { id: ID_A, email: "owner@example.com", name: "Owner", method: "apple", createdAt: "2026-10-01T08:00:00Z", lastSignInAt: "2026-10-22T07:00:00Z" },
  { id: ID_B, email: "tomek@example.com", name: "Tomek", method: "google", createdAt: "2026-10-20T12:00:00Z", lastSignInAt: "2026-10-21T18:00:00Z" },
];

const PANEL_PATHS = ["/v1/web/owner", "/v1/web/owner/overview", "/v1/web/owner/accounts", `/v1/web/owner/accounts/${ID_B}/logbook`];

test("anyone not named as an owner is told there is nothing here, and nothing is recorded", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  const browserB = await rig.signIn(await rig.code(USER_B));
  for (const path of PANEL_PATHS) {
    const browser = await rig.call("GET", path, { cookie: browserB });
    assert.equal(browser.status, 404, path);
    assert.equal(browser.body.error.code, "not_found");
    assert.equal((await rig.call("GET", path)).status, 401, `${path} signed out`);
  }
  assert.deepEqual((await rig.store.db.query("SELECT * FROM owner_audit")).rows, [], "a refused caller leaves no row");
});

test("the panel is for a browser only: the iPhone's own session can't open it, not even the owner's", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  for (const path of PANEL_PATHS) {
    for (const token of [USER_A, USER_B]) {
      const phone = await rig.call("GET", path, { token });
      assert.equal(phone.status, 401, `${path} with ${token}`);
      assert.equal(phone.body.error.code, "unauthenticated");
      assert.ok(!phone.text.includes("example.com"), "no account is named in the refusal");
    }
  }
  assert.deepEqual((await rig.store.db.query("SELECT * FROM owner_audit")).rows, [], "nothing was shown, so nothing is recorded");
});

test(`the panel opens only within ${OWNER_FRESH_MS / 60_000} minutes of the browser signing in, and a refused request shows nothing`, async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  const cookie = await rig.signIn(await rig.code(USER_A));
  const paths = ["/v1/web/owner/overview", "/v1/web/owner/accounts", `/v1/web/owner/accounts/${ID_B}/logbook`];

  rig.clock.advance(OWNER_FRESH_MS);
  for (const path of paths) assert.equal((await rig.call("GET", path, { cookie })).status, 200, `${path} at the last moment of the window`);
  const shown = (await rig.store.db.query("SELECT count(*) AS n FROM owner_audit")).rows[0] as { n: string };
  assert.equal(Number(shown.n), 3);

  rig.clock.advance(1);
  for (const path of paths) {
    const late = await rig.call("GET", path, { cookie });
    assert.equal(late.status, 422, path);
    assert.equal(late.body.error.code, "refused");
    assert.match(late.body.error.message, /sign in again/i);
    assert.ok(!late.text.includes("example.com") && !late.text.includes("Tomek"), "no account is named in the refusal");
  }
  assert.equal(Number((await rig.store.db.query("SELECT count(*) AS n FROM owner_audit")).rows[0]!.n), 3, "a refusal shows nothing, so records nothing");

  // The menu's question (is this an owner?) holds no data, so it still answers: the page then says why it is shut.
  assert.deepEqual((await rig.call("GET", "/v1/web/owner", { cookie })).body, { owner: true });

  // Signing in again opens it again, for a new window.
  const again = await rig.signIn(await rig.code(USER_A));
  assert.equal((await rig.call("GET", "/v1/web/owner/overview", { cookie: again })).status, 200);
});

test("each use of the panel is recorded with who, which browser, what and when, and holds no content or secret", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  await send(rig, USER_B, day(iso(0), 3, { get_weather: { done: 1 } }));
  const cookie = await rig.signIn(await rig.code(USER_A));
  const session = (await rig.call("GET", "/v1/web/session", { cookie })).body.session.id as string;
  const t0 = rig.clock.ms;

  assert.equal((await rig.call("GET", "/v1/web/owner", { cookie })).status, 200, "the menu's question is not a use of the data");
  assert.equal((await rig.call("GET", "/v1/web/owner/overview?days=7", { cookie })).status, 200);
  rig.clock.advance(1_000);
  assert.equal((await rig.call("GET", "/v1/web/owner/accounts", { cookie })).status, 200);
  rig.clock.advance(1_000);
  assert.equal((await rig.call("GET", `/v1/web/owner/accounts/${ID_B}/logbook`, { cookie })).status, 200);

  const rows = (await rig.store.db.query<{ at: string; actor_id: string; session_id: string; action: string; target_id: string | null }>("SELECT at, actor_id, session_id, action, target_id FROM owner_audit ORDER BY id")).rows;
  assert.deepEqual(
    rows.map((r) => ({ at: Number(r.at), actor_id: r.actor_id, session_id: r.session_id, action: r.action, target_id: r.target_id })),
    [
      { at: t0, actor_id: ID_A, session_id: session, action: "overview", target_id: null },
      { at: t0 + 1_000, actor_id: ID_A, session_id: session, action: "accounts", target_id: null },
      { at: t0 + 2_000, actor_id: ID_A, session_id: session, action: "account_logbook", target_id: ID_B },
    ],
  );

  // The record has no column that could hold a word, a count, an email or a credential, and none of those is in it.
  const columns = (await rig.store.db.query<{ column_name: string }>("SELECT column_name FROM information_schema.columns WHERE table_name = 'owner_audit' ORDER BY column_name")).rows.map((c) => c.column_name);
  assert.deepEqual(columns, ["action", "actor_id", "at", "id", "session_id", "target_id"]);
  const dump = JSON.stringify((await rig.store.db.query("SELECT * FROM owner_audit")).rows);
  for (const secret of ["example.com", "Tomek", "owner@", "get_weather", cookie, USER_A, USER_B]) assert.ok(!dump.includes(secret), `leaked: ${secret}`);
});

test("the panel shows nothing it could not record: a failed record is a failed request", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  const cookie = await rig.signIn(await rig.code(USER_A));
  await rig.store.db.query("DROP TABLE owner_audit");
  for (const path of ["/v1/web/owner/overview", "/v1/web/owner/accounts", `/v1/web/owner/accounts/${ID_B}/logbook`]) {
    const res = await rig.call("GET", path, { cookie });
    assert.equal(res.status, 500, path);
    assert.ok(!res.text.includes("example.com"), "no account in the failure");
  }
});

test(`records older than ${OWNER_AUDIT_KEPT_DAYS} days are pruned, newer ones stay`, async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  const now = Date.parse("2026-10-22T10:00:00Z");
  const old = now - (OWNER_AUDIT_KEPT_DAYS + 1) * DAY;
  const edge = now - OWNER_AUDIT_KEPT_DAYS * DAY;
  for (const at of [old, edge, now]) await rig.store.recordOwnerUse({ at, actorId: ID_A, sessionId: "s", action: "overview", targetId: null });
  assert.equal(await rig.store.pruneOwnerAudit(now - OWNER_AUDIT_KEPT_DAYS * DAY), 1);
  assert.deepEqual((await rig.store.db.query<{ at: string }>("SELECT at FROM owner_audit ORDER BY at")).rows.map((r) => Number(r.at)), [edge, now]);
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

  const res = await ownerGet(rig, "/v1/web/owner/accounts?days=30");
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

  const days = await ownerGet(rig, `/v1/web/owner/accounts/${ID_B}/logbook`);
  assert.equal(days.status, 200);
  assert.deepEqual(days.body.days.map((d: { day: string }) => d.day), [iso(-2), iso(0)]);
});

test("an owner named by the Doddy account that took over an iPhone's earlier data is recognised", async () => {
  const account = "6b0c8f7e-2a41-4c3d-9e6f-0123456789ab";
  rig = await startWeb({ owner: { accounts: [account] } });
  const browserA = await rig.signIn(await rig.code(USER_A));
  const browserB = await rig.signIn(await rig.code(USER_B));
  assert.equal((await rig.call("GET", "/v1/web/owner", { cookie: browserA })).status, 404, "not linked yet");
  await rig.store.db.query("INSERT INTO account_links (subject, user_id, linked_at) VALUES ($1, $2, $3)", [account, ID_A, Date.now()]);
  assert.equal((await rig.call("GET", "/v1/web/owner", { cookie: browserA })).status, 200);
  assert.equal((await rig.call("GET", "/v1/web/owner", { cookie: browserB })).status, 404);
});

test("without Supabase's account list the panel says so and still counts Logbook", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(null) } });
  await send(rig, USER_B, day(iso(0), 1));
  const overview = (await ownerGet(rig, "/v1/web/owner/overview")).body;
  assert.equal(overview.directory, false);
  assert.equal(overview.accounts.total, null);
  assert.equal(overview.periodDays, 30, "the default period");
  const accounts = (await ownerGet(rig, "/v1/web/owner/accounts")).body;
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

// ------------------------------------------------------------------ the dashboard's own numbers

const U3 = "00000000-0000-4000-8000-0000000000c3";
const U4 = "00000000-0000-4000-8000-0000000000c4";
/** A user the dev tokens don't stand for: its days go straight into the store, as the iPhone's PUT would. */
async function sendFor(r: WebRig, user: string, ...days: ReturnType<typeof day>[]) {
  await r.store.setLogbookEnabled(user, true, Date.parse(`${TODAY}T10:00:00Z`));
  for (const d of days) assert.equal(await r.store.putLogbookDay(user, d.day, JSON.stringify(d), Date.parse(`${TODAY}T10:00:00Z`)), true);
}
const person = (id: string, email: string, createdAt: string): DirectoryUser => ({ id, email, name: null, method: "google", createdAt, lastSignInAt: null });

test("engagement counts accounts that used Doddy today, this week and this month, from days of real use only", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory([]) } });
  // A day the iPhone sent with nothing in it at all: no conversations, no tools, no notes, no list items.
  const nothing = day(iso(-8), 0, {}, {
    notes: { by_source: { voice: 0, typed: 0, shared: 0, imported: 0 }, by_kind: {}, edited: 0 },
    lists: { added_voice: 0, added_typed: 0, ticked: 0 },
  });
  await send(rig, USER_A, day(iso(0), 1), day(iso(-5), 1), day(iso(-12), 1), nothing);
  await send(rig, USER_B, day(iso(0), 2), day(iso(-20), 1));
  await sendFor(rig, U3, day(iso(-25), 1));

  const o = (await ownerGet(rig, "/v1/web/owner/overview?days=30")).body;
  assert.deepEqual(o.engagement, { today: 2, week: 2, month: 3, dailyAverage: 0.2 });
  // The day of zeros (iso(-8)) is not use: one account on iso(-12), none on iso(-8).
  const at = (offset: number) => o.logbook.activeByDay.find((d: { day: string }) => d.day === iso(offset)).accounts;
  assert.equal(at(-8), 0);
  assert.equal(at(-12), 1);
});

test("the shape of conversations: lengths, endings, languages, and when people talk by weekday and hour", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory([]) } });
  const thursday = day(iso(0), 3, {}, {
    conversations: {
      count: 3,
      seconds: 700,
      by_hour: Array.from({ length: 24 }, (_, h) => (h === 8 ? 1 : h === 20 ? 2 : 0)),
      lengths: { under_1: 1, "1_3": 1, "3_5": 0, "5_10": 1 },
      ended: { you: 2, doddy: 1, quiet: 0, dropped: 0 },
      languages: { pl: 2, en: 1 },
      ways_in: { app: 0, back_tap: 0, action_button: 0, widget: 0, siri: 0, island: 0 },
    },
    errands: { handed_over: 2, finished: 1, stopped: 1, minutes: 5, searches: 3, pages: 2 },
  });
  const wednesday = day(iso(-1), 1, {}, {
    conversations: {
      count: 1,
      seconds: 200,
      by_hour: Array.from({ length: 24 }, (_, h) => (h === 9 ? 1 : 0)),
      lengths: { under_1: 0, "1_3": 0, "3_5": 1, "5_10": 0 },
      ended: { you: 0, doddy: 0, quiet: 1, dropped: 0 },
      languages: {},
      ways_in: { app: 0, back_tap: 0, action_button: 0, widget: 0, siri: 0, island: 0 },
    },
  });
  await send(rig, USER_A, wednesday, thursday);

  const c = (await ownerGet(rig, "/v1/web/owner/overview?days=7")).body;
  assert.deepEqual(c.conversations.lengths, { under_1: 1, "1_3": 1, "3_5": 1, "5_10": 1 });
  assert.deepEqual(c.conversations.ended, { you: 2, doddy: 1, quiet: 1, dropped: 0 });
  assert.deepEqual(c.conversations.languages, { pl: 2, en: 1 });
  assert.equal(c.conversations.heatmap.length, 7);
  assert.ok(c.conversations.heatmap.every((row: number[]) => row.length === 24));
  assert.equal(c.conversations.heatmap[3][8], 1, "Thursday 08:00");
  assert.equal(c.conversations.heatmap[3][20], 2, "Thursday 20:00");
  assert.equal(c.conversations.heatmap[2][9], 1, "Wednesday 09:00");
  assert.equal(c.conversations.heatmap.flat().reduce((sum: number, n: number) => sum + n, 0), 4);
  assert.deepEqual(c.errands, { handedOver: 2, finished: 1, stopped: 1 });
});

test("activation: of the accounts that joined in the period, how many used Doddy within a week; and weekly cohorts", async () => {
  const users = [
    person(ID_A, "a@example.com", "2026-10-20T09:00:00Z"), // used on the 22nd: activated
    person(ID_B, "b@example.com", "2026-10-02T09:00:00Z"), // used on the 2nd itself: activated
    person(U3, "c@example.com", "2026-09-28T09:00:00Z"), // only used on the 27th, before joining: not activated
    person(U4, "d@example.com", "2026-10-21T09:00:00Z"), // never used
  ];
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(users) } });
  await send(rig, USER_A, day(iso(0), 1));
  await send(rig, USER_B, day(iso(0), 1), day("2026-10-02", 1));
  await sendFor(rig, U3, day("2026-09-27", 1));

  const o = (await ownerGet(rig, "/v1/web/owner/overview?days=30")).body;
  assert.deepEqual(o.activation, { joined: 4, activated: 2 });
  assert.equal(o.cohorts.length, 8);
  assert.deepEqual(o.cohorts.map((c: { week: string }) => c.week), ["2026-08-31", "2026-09-07", "2026-09-14", "2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19"]);
  const week = (monday: string) => o.cohorts.find((c: { week: string }) => c.week === monday);
  // Joined the week of the 19th: A and D. A used Doddy that week; D didn't.
  assert.deepEqual(week("2026-10-19"), { week: "2026-10-19", size: 2, active: [1] });
  // Joined the week of 28 Sep: B and C. B used it that week and again three weeks later; C never after joining.
  assert.deepEqual(week("2026-09-28"), { week: "2026-09-28", size: 2, active: [1, 0, 0, 1] });
  assert.deepEqual(week("2026-10-05"), { week: "2026-10-05", size: 0, active: [0, 0, 0] });
});

test("no cohorts or activation without Supabase's account list, because nobody's join date is known", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(null) } });
  await send(rig, USER_A, day(iso(0), 1));
  const o = (await ownerGet(rig, "/v1/web/owner/overview")).body;
  assert.deepEqual(o.cohorts, []);
  assert.deepEqual(o.activation, { joined: 0, activated: 0 });
  assert.equal(o.engagement.today, 1, "engagement still comes from Logbook");
});

test("each account carries its last day of use and its conversations over the last 14 days", async () => {
  rig = await startWeb({ owner: { accounts: [ID_A], directory: directory(people) } });
  await send(rig, USER_B, day(iso(-2), 1), day(iso(0), 3), day(iso(-1), 0));
  const res = (await ownerGet(rig, "/v1/web/owner/accounts?days=30")).body;
  const tomek = res.accounts.find((a: { email: string }) => a.email === "tomek@example.com");
  assert.equal(tomek.lastActiveDay, iso(0));
  assert.equal(tomek.trend.length, 14);
  assert.equal(tomek.trend[13], 3, "today is last");
  assert.equal(tomek.trend[12], 0);
  assert.equal(tomek.trend[11], 1);
  const owner = res.accounts.find((a: { email: string }) => a.email === "owner@example.com");
  assert.equal(owner.lastActiveDay, null);
  assert.deepEqual(owner.trend, Array(14).fill(0));
});

test("the account list is read once for a minute, and a failed read is asked again", async () => {
  let reads = 0;
  let fail = false;
  const counting: UserDirectory = {
    list: async () => {
      reads += 1;
      return fail ? null : people;
    },
  };
  rig = await startWeb({ owner: { accounts: [ID_A], directory: counting } });
  await ownerGet(rig, "/v1/web/owner/overview");
  await ownerGet(rig, "/v1/web/owner/accounts");
  await ownerGet(rig, "/v1/web/owner/overview?days=7");
  assert.equal(reads, 1, "one read serves the overview, the accounts and a new period");
  assert.equal((await ownerGet(rig, "/v1/web/owner/overview")).body.directory, true);
  await rig.close();

  reads = 0;
  fail = true;
  rig = await startWeb({ owner: { accounts: [ID_A], directory: counting } });
  assert.equal((await ownerGet(rig, "/v1/web/owner/overview")).body.directory, false);
  fail = false;
  assert.equal((await ownerGet(rig, "/v1/web/owner/overview")).body.directory, true, "a failure wasn't kept");
  assert.equal(reads, 2);
});
