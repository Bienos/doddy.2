import { describe, expect, test } from "vitest";
import { insights, matchesFilter, percent, retention, stateOf, troubleRate, daysBetween, valueRow } from "../src/admin/logic.js";
import { OwnerAccounts, OwnerOverview, type OwnerAccount } from "../src/owner/schema.js";
import { fixture } from "./fakeServer.js";

/** The admin dashboard's rules, on the server's own replies (backend: npm run fixtures:owner). */

const overview = OwnerOverview.parse(fixture("web/owner-overview"));
const accounts = OwnerAccounts.parse(fixture("web/owner-accounts")).accounts;
const TODAY = "2026-10-22";
const account = (over: Partial<OwnerAccount>): OwnerAccount => ({ ...accounts[0]!, ...over });

describe("how an account is classed", () => {
  test("by the last day it used Doddy, with Logbook off winning over everything", () => {
    expect(stateOf(account({ lastActiveDay: TODAY }), TODAY)).toBe("today");
    expect(stateOf(account({ lastActiveDay: "2026-10-16" }), TODAY)).toBe("active");
    expect(stateOf(account({ lastActiveDay: "2026-10-15" }), TODAY)).toBe("quiet");
    expect(stateOf(account({ lastActiveDay: null }), TODAY)).toBe("never");
    expect(stateOf(account({ lastActiveDay: TODAY, logbook: "off" }), TODAY)).toBe("off");
  });

  test("the filters group those states", () => {
    expect(matchesFilter("today", "active")).toBe(true);
    expect(matchesFilter("active", "active")).toBe(true);
    expect(matchesFilter("quiet", "active")).toBe(false);
    expect(matchesFilter("quiet", "quiet")).toBe(true);
    expect(matchesFilter("never", "never")).toBe(true);
    expect(matchesFilter("off", "never")).toBe(false);
    expect(matchesFilter("off", "all")).toBe(true);
  });

  test("the fixture's four accounts: two used it today or this week, one a few days ago, one never", () => {
    const states = Object.fromEntries(accounts.map((a) => [a.email, stateOf(a, TODAY)]));
    expect(states["tomek@example.com"]).toBe("today");
    expect(states["owner@example.com"]).toBe("active");
    expect(states["kasia@example.com"]).toBe("active");
    expect(states["x7k2p9q4@privaterelay.appleid.com"]).toBe("never");
  });
});

describe("small helpers", () => {
  test("days between, percent and retention don't divide by zero", () => {
    expect(daysBetween("2026-10-20", "2026-10-22")).toBe(2);
    expect(daysBetween("2026-10-22", "2026-10-22")).toBe(0);
    expect(percent(1, 3)).toBe(33);
    expect(percent(1, 0)).toBe(0);
    expect(retention(4, 3)).toBe(75);
    expect(retention(0, 0)).toBeNull();
  });

  test("trouble is what didn't work or wasn't sure, never what the person said no to", () => {
    expect(troubleRate({ done: 6, declined: 10, unsure: 2, failed: 2, undone: 0 })).toBeCloseTo(4 / 20);
    expect(troubleRate({ done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 })).toBe(0);
  });
});

describe("the Needs attention list is computed from the numbers", () => {
  test("on the fixture: good news and notes, nothing alarming, most serious first", () => {
    const list = insights(overview, accounts);
    const ids = list.map((i) => i.id);
    expect(ids).toContain("activation");
    expect(list.find((i) => i.id === "activation")).toMatchObject({ level: "good", values: { percent: 75, joined: 4 } });
    expect(ids).toContain("new");
    expect(ids).not.toContain("never"); // joined two days ago: too soon to say
    expect(ids).not.toContain("dropped"); // 4 of 72 is under 10%
    const levels = list.map((i) => i.level);
    expect(levels).toEqual([...levels].sort((a, b) => ["bad", "warn", "good", "info"].indexOf(a) - ["bad", "warn", "good", "info"].indexOf(b)));
  });

  test("a tool that fails often is a problem, a tool run twice is not a finding", () => {
    const broken = structuredClone(overview);
    broken.logbook.totals.tools = {
      send_email: { done: 4, declined: 0, unsure: 4, failed: 2, undone: 0 }, // 60%
      read_calendar: { done: 8, declined: 0, unsure: 0, failed: 2, undone: 0 }, // 20%
      rare_tool: { done: 0, declined: 0, unsure: 0, failed: 2, undone: 0 }, // 100% but only twice
      get_weather: { done: 9, declined: 5, unsure: 0, failed: 0, undone: 0 }, // saying no is not trouble
    };
    const found = insights(broken, accounts).filter((i) => i.id.startsWith("tool:"));
    expect(found.map((i) => [i.id, i.level, i.values.percent])).toEqual([
      ["tool:send_email", "bad", 60],
      ["tool:read_calendar", "warn", 20],
    ]);
  });

  test("dropped connections, a low activation and accounts that went quiet are all noticed", () => {
    const poor = structuredClone(overview);
    poor.conversations.ended = { you: 5, doddy: 2, quiet: 1, dropped: 4 };
    poor.activation = { joined: 10, activated: 3 };
    const quiet = [account({ userId: "q", lastActiveDay: "2026-10-01" }), account({ userId: "n", lastActiveDay: null, createdAt: "2026-10-10T00:00:00Z" }), account({ userId: "o", logbook: "off", lastActiveDay: null })];
    const list = insights(poor, quiet);
    const byId = Object.fromEntries(list.map((i) => [i.id, i]));
    expect(byId.dropped).toMatchObject({ level: "warn", values: { percent: 33, n: 12 } });
    expect(byId.activation).toMatchObject({ level: "warn", values: { percent: 30, joined: 10 } });
    expect(byId.quiet).toMatchObject({ values: { n: 1 }, tab: "users", filter: "quiet" });
    expect(byId.never).toMatchObject({ values: { n: 1 }, filter: "never" });
    expect(byId.off).toMatchObject({ level: "info", values: { n: 1 }, filter: "off" });
  });

  test("without Supabase's account list it says so instead of inventing sign-up numbers", () => {
    const blind = structuredClone(overview);
    blind.directory = false;
    blind.accounts.total = null;
    blind.cohorts = [];
    const ids = insights(blind, accounts).map((i) => i.id);
    expect(ids).toContain("directory");
    expect(ids).not.toContain("activation");
    expect(ids).not.toContain("new");
  });
});

describe("tasks that worked out (decision 2026-11-14-tasks-that-worked-out)", () => {
  const week = (over: Partial<{ active: number; withWorkedOut: number; workedOut: number }>, outcomes: Partial<Record<"done" | "declined" | "unsure" | "failed" | "undone", number>> = {}) => ({
    week: "2026-10-19", active: 0, withWorkedOut: 0, workedOut: 0, ...over,
    outcomes: { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0, ...outcomes },
  });

  test("per account that used Doddy, to one decimal, with each guardrail over what it can fairly be a share of", () => {
    const row = valueRow(week({ active: 3, withWorkedOut: 2, workedOut: 10 }, { done: 12, undone: 2, unsure: 2, failed: 1, declined: 5 }));
    expect(row.perAccount).toBe(3.3);
    expect(row.withWorkedOut).toBe(67);
    // Tries that ran: 12 done + 2 not sure + 1 didn't work = 15. Said no never ran.
    expect(row.notSure).toBe(13);
    expect(row.failed).toBe(7);
    expect(row.undone).toBe(17); // of the 12 done
    expect(row.declined).toBe(25); // of the 20 asked
  });

  test("a week with nobody or nothing in it is a dash, never a made-up 0", () => {
    expect(valueRow(week({}))).toEqual({ week: "2026-10-19", active: 0, workedOut: 0, perAccount: null, withWorkedOut: null, notSure: null, failed: null, undone: null, declined: null });
    const onlyNo = valueRow(week({ active: 1 }, { declined: 2 }));
    expect(onlyNo.perAccount).toBe(0);
    expect(onlyNo.declined).toBe(100);
    expect(onlyNo.notSure).toBeNull();
    expect(onlyNo.undone).toBeNull();
  });

  test("on the fixture: this week so far and last week, per account", () => {
    const rows = overview.value.weeks.map(valueRow);
    expect(rows).toHaveLength(8);
    expect(rows[7]).toMatchObject({ week: "2026-10-19", active: 3, workedOut: 13, perAccount: 4.3 });
    expect(rows[6]).toMatchObject({ week: "2026-10-12", active: 3, workedOut: 59, perAccount: 19.7 });
  });
});
