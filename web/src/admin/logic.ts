import type { MessageKey } from "../i18n/messages.js";
import { type OwnerAccount, type OwnerOverview, type Outcomes, toolRows, type ValueWeek } from "../owner/schema.js";

/**
 * The admin dashboard's rules, with no screen in them (decision 2026-11-09-usage-counts-on-by-default):
 * how an account is classed, how long ago a day was, and the "Needs attention" list, which is computed
 * from the numbers rather than written by hand. Counts only come in, so only counts go out.
 */

export type Tab = "overview" | "users" | "tools" | "conversations" | "growth";
export const TABS: Tab[] = ["overview", "users", "tools", "conversations", "growth"];

/** Who is in the Users table: everyone, or one kind of account. */
export type UserFilter = "all" | "active" | "quiet" | "never" | "off";
export const USER_FILTERS: UserFilter[] = ["all", "active", "quiet", "never", "off"];

/** An account's state today, from the days its iPhone sent. */
export type AccountState = "today" | "active" | "quiet" | "never" | "off";

const DAY_MS = 86_400_000;

/** Whole days from `day` to `today` (both YYYY-MM-DD). Negative when `day` is later. */
export function daysBetween(day: string, today: string): number {
  return Math.round((Date.parse(`${today}T00:00:00Z`) - Date.parse(`${day}T00:00:00Z`)) / DAY_MS);
}

/** An ISO time or day as its day, or null. */
export function dayOf(iso: string | null): string | null {
  return iso ? iso.slice(0, 10) : null;
}

/** "Off" wins: when Logbook is off nothing is sent, so nothing can be said about use. */
export function stateOf(account: OwnerAccount, today: string): AccountState {
  if (account.logbook === "off") return "off";
  if (!account.lastActiveDay) return "never";
  const ago = daysBetween(account.lastActiveDay, today);
  if (ago <= 0) return "today";
  return ago < 7 ? "active" : "quiet";
}

export function matchesFilter(state: AccountState, filter: UserFilter): boolean {
  switch (filter) {
    case "all": return true;
    case "active": return state === "today" || state === "active";
    case "quiet": return state === "quiet";
    case "never": return state === "never";
    case "off": return state === "off";
  }
}

export const percent = (part: number, whole: number): number => (whole > 0 ? Math.round((part / whole) * 100) : 0);
export const minutesOf = (seconds: number): number => Math.round(seconds / 60);

export function sumOutcomes(tools: Record<string, Outcomes>): Outcomes {
  const sum = { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 };
  for (const o of Object.values(tools)) {
    sum.done += o.done;
    sum.declined += o.declined;
    sum.unsure += o.unsure;
    sum.failed += o.failed;
    sum.undone += o.undone;
  }
  return sum;
}

/** A share of a tool's uses that did not work out: "didn't work" and "not sure", never "said no". */
export function troubleRate(o: Outcomes): number {
  const total = o.done + o.declined + o.unsure + o.failed;
  return total > 0 ? (o.failed + o.unsure) / total : 0;
}

export type Level = "bad" | "warn" | "good" | "info";

export interface Insight {
  id: string;
  level: Level;
  text: MessageKey;
  values: Record<string, string | number>;
  /** Where the details are. */
  tab?: Tab;
  filter?: UserFilter;
}

const ORDER: Record<Level, number> = { bad: 0, warn: 1, good: 2, info: 3 };

/** Tools used at least this often are judged; a tool run twice that failed once is not a finding. */
export const MIN_USES = 5;

export function insights(overview: OwnerOverview, accounts: OwnerAccount[]): Insight[] {
  const today = overview.generatedAt.slice(0, 10);
  const found: Insight[] = [];
  const add = (insight: Insight) => found.push(insight);

  const rows = toolRows(overview.logbook.totals.tools);
  for (const row of rows) {
    if (row.total < MIN_USES || row.failRate < 0.2) continue;
    add({ id: `tool:${row.tool}`, level: row.failRate >= 0.35 ? "bad" : "warn", text: "admin.insight.tool", values: { tool: row.tool, percent: Math.round(row.failRate * 100), n: row.total }, tab: "tools" });
  }

  const ended = overview.conversations.ended;
  const conversations = ended.you + ended.doddy + ended.quiet + ended.dropped;
  if (conversations >= 10 && ended.dropped / conversations >= 0.1) {
    add({ id: "dropped", level: "warn", text: "admin.insight.dropped", values: { percent: percent(ended.dropped, conversations), n: conversations }, tab: "conversations" });
  }

  const { joined, activated } = overview.activation;
  if (overview.directory && joined >= 3) {
    const rate = percent(activated, joined);
    add(rate < 50
      ? { id: "activation", level: "warn", text: "admin.insight.activation", values: { percent: rate, joined }, tab: "growth" }
      : { id: "activation", level: "good", text: "admin.insight.activationGood", values: { percent: rate, joined }, tab: "growth" });
  }

  const never = accounts.filter((a) => a.createdAt && !a.lastActiveDay && a.logbook !== "off" && daysBetween(a.createdAt.slice(0, 10), today) >= 3);
  if (never.length > 0) add({ id: "never", level: "warn", text: "admin.insight.neverUsed", values: { n: never.length }, tab: "users", filter: "never" });

  const quiet = accounts.filter((a) => stateOf(a, today) === "quiet");
  if (quiet.length > 0) add({ id: "quiet", level: "warn", text: "admin.insight.quiet", values: { n: quiet.length }, tab: "users", filter: "quiet" });

  const off = accounts.filter((a) => a.logbook === "off");
  if (off.length > 0) add({ id: "off", level: "info", text: "admin.insight.off", values: { n: off.length }, tab: "users", filter: "off" });

  const fresh = overview.accounts.newByDay.reduce((sum, d) => sum + d.count, 0);
  if (overview.directory && fresh > 0) add({ id: "new", level: "good", text: "admin.insight.newAccounts", values: { n: fresh, days: overview.periodDays }, tab: "growth" });

  const top = rows[0];
  if (top) add({ id: "top", level: "info", text: "admin.insight.topTool", values: { tool: top.tool, n: top.total }, tab: "tools" });

  if (!overview.directory) add({ id: "directory", level: "info", text: "admin.insight.noDirectory", values: {} });

  return found.sort((a, b) => ORDER[a.level] - ORDER[b.level] || a.id.localeCompare(b.id));
}

/** What share of a cohort was active k weeks after joining, 0 to 100, or null when nobody joined. */
export function retention(size: number, active: number): number | null {
  return size > 0 ? Math.round((active / size) * 100) : null;
}

/**
 * One week's row of "Tasks that worked out" (decision 2026-11-14-tasks-that-worked-out). `perAccount` is
 * per account that used Doddy that week, to one decimal. The guardrails are shares 0 to 100: not sure and
 * didn't work of the tries that ran (said no never ran), undone of the done ones, said no of everything
 * Doddy asked. Every share is null when there is nothing to divide by, never a made-up 0.
 */
export interface ValueRow {
  week: string;
  active: number;
  workedOut: number;
  perAccount: number | null;
  withWorkedOut: number | null;
  notSure: number | null;
  failed: number | null;
  undone: number | null;
  declined: number | null;
}

export function valueRow(w: ValueWeek): ValueRow {
  const { done, declined, unsure, failed, undone } = w.outcomes;
  const ran = done + unsure + failed;
  return {
    week: w.week,
    active: w.active,
    workedOut: w.workedOut,
    perAccount: w.active > 0 ? Math.round((w.workedOut / w.active) * 10) / 10 : null,
    withWorkedOut: retention(w.active, w.withWorkedOut),
    notSure: retention(ran, unsure),
    failed: retention(ran, failed),
    undone: retention(done, undone),
    declined: retention(ran + declined, declined),
  };
}
