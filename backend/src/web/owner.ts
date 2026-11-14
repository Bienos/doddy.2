import { z } from "zod";
import { AppError } from "../errors.js";
import type { OwnerAction, Store } from "../store.js";
import { type DaySummary, DaySummarySchema, isoDay, LOGBOOK_KEPT_DAYS, type LogbookView, readLogbookView } from "./logbook.js";
import type { WebSessionContext } from "./sessions.js";

/**
 * The owner panel (decision 2026-11-09-usage-counts-on-by-default): totals of every account's Logbook
 * days, and each account's own days with its sign-in method, email and dates. Counts only, exactly
 * what Logbook holds (`logbook.ts`); no words exist here to show. Only the accounts named in
 * DODDY_OWNER_ACCOUNTS see it; everyone else gets "not found", so the routes don't announce
 * themselves. One person still sees only their own Logbook page.
 *
 * Because it names every person who uses Doddy, it is stricter than the rest of the web app
 * (decision 2026-11-14-owner-panel-fresh-sign-in): a browser only, never the iPhone's own session;
 * only within `OWNER_FRESH_MS` of that browser signing in; and every use is recorded
 * (`Store.recordOwnerUse`) before anything is shown.
 */

/**
 * The panel opens only for a browser that signed in this recently (a code from the iPhone, or Apple or
 * Google). The same window as deleting the account or changing sign-in methods from a browser
 * (`LINK_REAUTH_MS`): long enough to read the dashboard, short enough that a session cookie left
 * behind or copied later opens nothing. Counted from the sign-in, not from the last request.
 */
export const OWNER_FRESH_MS = 15 * 60_000;

/** How long a record of owner-panel use is kept. The housekeeping sweep prunes older ones. */
export const OWNER_AUDIT_KEPT_DAYS = 365;

export type { OwnerAction };

/** One Doddy account as Supabase Auth knows it. */
export interface DirectoryUser {
  id: string;
  email: string | null;
  name: string | null;
  /** apple, google, email… (`app_metadata.provider`). */
  method: string | null;
  createdAt: string | null;
  lastSignInAt: string | null;
}

/** Where the accounts' emails and sign-in dates come from. */
export interface UserDirectory {
  /** Every account, or null when the list can't be read now (the panel then says so). */
  list(signal: AbortSignal): Promise<DirectoryUser[] | null>;
}

export type GetJson = (url: string, init: { headers: Record<string, string>; signal: AbortSignal }) => Promise<{ status: number; body: unknown }>;

const defaultGet: GetJson = async (url, init) => {
  const response = await fetch(url, { headers: { ...init.headers, accept: "application/json" }, signal: init.signal, redirect: "error" });
  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  return { status: response.status, body };
};

const AdminUserSchema = z.object({
  id: z.string(),
  email: z.string().nullish(),
  created_at: z.string().nullish(),
  last_sign_in_at: z.string().nullish(),
  app_metadata: z.object({ provider: z.string().nullish() }).passthrough().nullish(),
  user_metadata: z.object({ full_name: z.string().nullish(), name: z.string().nullish() }).passthrough().nullish(),
});
const AdminUsersSchema = z.object({ users: z.array(AdminUserSchema) }).passthrough();

/** Supabase Auth's admin list of users, read with the project's secret key, on the server only. */
export class SupabaseUserDirectory implements UserDirectory {
  static readonly perPage = 500;
  private readonly get: GetJson;

  constructor(
    private readonly projectUrl: string,
    private readonly secretKey: string,
    get?: GetJson,
    private readonly maxPages = 20,
  ) {
    this.get = get ?? defaultGet;
  }

  async list(signal: AbortSignal): Promise<DirectoryUser[] | null> {
    const users: DirectoryUser[] = [];
    try {
      for (let page = 1; page <= this.maxPages; page++) {
        const { status, body } = await this.get(`${this.projectUrl}/auth/v1/admin/users?page=${page}&per_page=${SupabaseUserDirectory.perPage}`, {
          headers: { apikey: this.secretKey, authorization: `Bearer ${this.secretKey}` },
          signal,
        });
        const parsed = status === 200 ? AdminUsersSchema.safeParse(body) : null;
        if (!parsed?.success) return null;
        for (const user of parsed.data.users) {
          users.push({
            id: user.id.toLowerCase(),
            email: user.email || null,
            name: user.user_metadata?.full_name || user.user_metadata?.name || null,
            method: user.app_metadata?.provider || null,
            createdAt: user.created_at || null,
            lastSignInAt: user.last_sign_in_at || null,
          });
        }
        if (parsed.data.users.length < SupabaseUserDirectory.perPage) break;
      }
    } catch {
      return null;
    }
    return users;
  }
}

export interface Outcomes {
  done: number;
  declined: number;
  unsure: number;
  failed: number;
  undone: number;
}

/** What one account (or everyone) did over the period, added up from Logbook days. */
export interface UsageTotals {
  /** Days with any use at all (a day of zeros the iPhone sent doesn't count). */
  activeDays: number;
  conversations: number;
  seconds: number;
  notes: number;
  listItems: number;
  errands: number;
  tools: Record<string, Outcomes>;
}

/** Who used Doddy recently, counted by account (a day of zeros the iPhone sent is not use). */
export interface Engagement {
  /** Accounts that used Doddy today, in the last 7 days and in the last 30 days. */
  today: number;
  week: number;
  month: number;
  /** The average of accounts per day over the period, to one decimal. */
  dailyAverage: number;
}

export interface ConversationShape {
  lengths: { under_1: number; "1_3": number; "3_5": number; "5_10": number };
  ended: { you: number; doddy: number; quiet: number; dropped: number };
  languages: Record<string, number>;
  /** Conversations by weekday (Monday first) and the phone's local hour: 7 rows of 24. */
  heatmap: number[][];
}

/** Of the accounts that joined in one week, how many used Doddy in that week and each one after. */
export interface Cohort {
  /** The Monday the week starts on. */
  week: string;
  size: number;
  /** `active[k]`: how many used Doddy in week k after joining (0 is the week they joined). */
  active: number[];
}

export interface OwnerAccount {
  /** This server's user id: the key for the account's own Logbook. */
  userId: string;
  /** The Supabase account id, when the account is one. */
  accountId: string | null;
  email: string | null;
  name: string | null;
  method: string | null;
  createdAt: string | null;
  lastSignInAt: string | null;
  /** on, off, or never (the iPhone never set it). */
  logbook: "on" | "off" | "never";
  /** The latest day this account's iPhone sent, and when it last sent one. */
  lastDay: string | null;
  lastSentAt: string | null;
  /** The latest day with any use. */
  lastActiveDay: string | null;
  /** Conversations on each of the last 14 days, oldest first. */
  trend: number[];
  period: UsageTotals;
}

export interface OwnerOverview {
  generatedAt: string;
  periodDays: number;
  /** False when Supabase's account list couldn't be read (no secret key, or it failed): counts below are Logbook's only. */
  directory: boolean;
  accounts: {
    /** Every account Supabase knows, or null without the directory. */
    total: number | null;
    byMethod: Record<string, number>;
    newByDay: { day: string; count: number }[];
  };
  logbook: {
    on: number;
    off: number;
    /** Accounts that sent at least one day in the period. */
    sending: number;
    /** For each day of the period: how many accounts used Doddy that day. */
    activeByDay: { day: string; accounts: number }[];
    totals: UsageTotals;
  };
  engagement: Engagement;
  conversations: ConversationShape;
  errands: { handedOver: number; finished: number; stopped: number };
  /** New accounts in the period, and how many of them used Doddy within 7 days of joining. */
  activation: { joined: number; activated: number };
  /** The last 8 weeks, oldest first. */
  cohorts: Cohort[];
}

const DAY_MS = 86_400_000;
const TREND_DAYS = 14;
const COHORT_WEEKS = 8;

/** The Monday of the week a day (YYYY-MM-DD, read as a calendar day) is in. */
function mondayOf(day: string): string {
  const ms = Date.parse(`${day}T00:00:00Z`);
  const weekday = (new Date(ms).getUTCDay() + 6) % 7; // Monday 0
  return isoDay(ms - weekday * DAY_MS);
}

/** Monday 0 … Sunday 6. */
function weekdayOf(day: string): number {
  return (new Date(Date.parse(`${day}T00:00:00Z`)).getUTCDay() + 6) % 7;
}
export const OWNER_PERIODS = [7, 30, 90, 365] as const;

/** Was anything used that day? A day the iPhone sent with only zeros is not use. */
function used(day: DaySummary): boolean {
  if (day.conversations.count > 0 || day.errands.handed_over > 0) return true;
  if (Object.values(day.notes.by_source).some((n) => n > 0) || day.lists.added_voice + day.lists.added_typed + day.lists.ticked > 0) return true;
  return Object.values(day.tools).some((o) => o.done + o.declined + o.unsure + o.failed > 0);
}

function emptyTotals(): UsageTotals {
  return { activeDays: 0, conversations: 0, seconds: 0, notes: 0, listItems: 0, errands: 0, tools: {} };
}

function add(totals: UsageTotals, day: DaySummary): void {
  if (used(day)) totals.activeDays += 1;
  totals.conversations += day.conversations.count;
  totals.seconds += day.conversations.seconds;
  totals.notes += Object.values(day.notes.by_source).reduce((sum, n) => sum + n, 0);
  totals.listItems += day.lists.added_voice + day.lists.added_typed;
  totals.errands += day.errands.handed_over;
  for (const [tool, o] of Object.entries(day.tools)) {
    const row = totals.tools[tool] ?? (totals.tools[tool] = { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 });
    row.done += o.done;
    row.declined += o.declined;
    row.unsure += o.unsure;
    row.failed += o.failed;
    row.undone += o.undone;
  }
}

export class OwnerPanel {
  private readonly owners: ReadonlySet<string>;

  /** The account list as last read, kept briefly: the overview and the list of accounts both ask, and each refresh would too. */
  private cached: { at: number; users: DirectoryUser[] } | null = null;

  constructor(
    private readonly store: Store,
    owners: readonly string[],
    private readonly directory: UserDirectory | null,
    private readonly timeoutMs = 10_000,
    /** How long a successful read of the account list is reused. 0: always ask. */
    private readonly directoryTtlMs = 60_000,
  ) {
    this.owners = new Set(owners.map((id) => id.toLowerCase()));
  }

  /** The caller is an owner: named directly, or the Doddy account named is this user. */
  async isOwner(userId: string): Promise<boolean> {
    if (this.owners.size === 0) return false;
    if (this.owners.has(userId.toLowerCase())) return true;
    const links = await this.store.accountUsers();
    return links.some((link) => this.owners.has(link.subject.toLowerCase()) && link.user_id === userId);
  }

  /** Anyone else is told there is nothing here. */
  async requireOwner(userId: string): Promise<void> {
    if (!(await this.isOwner(userId))) throw new AppError("not_found");
  }

  /**
   * The gate in front of everything the panel shows. An owner's browser that signed in within
   * `OWNER_FRESH_MS` passes, and the use is recorded first: if the record can't be written this throws
   * and nothing is shown. Anyone else is "not found" (nothing recorded); an owner's older sign-in is
   * asked to sign in again (nothing shown, nothing recorded: no data left the server).
   * `targetId` is the account whose own Logbook is opened, for `account_logbook`.
   */
  async open(caller: { userId: string; session: WebSessionContext | null }, action: OwnerAction, targetId: string | null, now: Date): Promise<void> {
    await this.requireOwner(caller.userId);
    const session = caller.session;
    if (!session || now.getTime() - session.createdAt > OWNER_FRESH_MS) {
      throw new AppError("refused", { message: `For safety, the owner panel opens only within ${OWNER_FRESH_MS / 60_000} minutes of signing in. Sign out, sign in again, then open it.` });
    }
    await this.store.recordOwnerUse({ at: now.getTime(), actorId: caller.userId, sessionId: session.sessionId, action, targetId });
  }

  static period(raw: string | undefined): number {
    const days = Number(raw ?? 30);
    return (OWNER_PERIODS as readonly number[]).includes(days) ? days : 30;
  }

  async overview(now: Date, periodDays: number): Promise<OwnerOverview> {
    const today = isoDay(now.getTime());
    const since = isoDay(now.getTime() - (periodDays - 1) * DAY_MS);
    // Engagement and the cohorts look further back than the period: the last 30 days and 8 whole weeks.
    const cohortFrom = isoDay(now.getTime() - (COHORT_WEEKS * 7 + 6) * DAY_MS);
    const fetchFrom = [since, cohortFrom, isoDay(now.getTime() - 29 * DAY_MS)].sort()[0]!;
    const [directory, links, states, rows] = await Promise.all([
      this.listDirectory(),
      this.store.accountUsers(),
      this.store.logbookStates(),
      this.store.allLogbookDays(fetchFrom),
    ]);
    const userFor = new Map(links.map((link) => [link.subject.toLowerCase(), link.user_id]));

    const byMethod: Record<string, number> = {};
    const newByDay = new Map<string, number>();
    for (const user of directory ?? []) {
      const method = user.method ?? "unknown";
      byMethod[method] = (byMethod[method] ?? 0) + 1;
      const created = user.createdAt ? isoDay(Date.parse(user.createdAt)) : null;
      if (created && created >= since) newByDay.set(created, (newByDay.get(created) ?? 0) + 1);
    }

    const totals = emptyTotals();
    const shape: ConversationShape = {
      lengths: { under_1: 0, "1_3": 0, "3_5": 0, "5_10": 0 },
      ended: { you: 0, doddy: 0, quiet: 0, dropped: 0 },
      languages: {},
      heatmap: Array.from({ length: 7 }, () => Array<number>(24).fill(0)),
    };
    const errands = { handedOver: 0, finished: 0, stopped: 0 };
    const activeOn = new Map<string, Set<string>>(); // day -> accounts that used Doddy
    const activeDays = new Map<string, string[]>(); // account -> days it used Doddy (for activation and cohorts)
    const sending = new Set<string>();
    for (const row of rows) {
      const day = parse(row.summary);
      if (!day) continue;
      if (used(day)) {
        const accounts = activeOn.get(row.day) ?? new Set<string>();
        accounts.add(row.user_id);
        activeOn.set(row.day, accounts);
        const list = activeDays.get(row.user_id) ?? [];
        list.push(row.day);
        activeDays.set(row.user_id, list);
      }
      if (row.day < since) continue;
      sending.add(row.user_id);
      add(totals, day);
      const c = day.conversations;
      for (const key of Object.keys(shape.lengths) as (keyof ConversationShape["lengths"])[]) shape.lengths[key] += c.lengths[key];
      for (const key of Object.keys(shape.ended) as (keyof ConversationShape["ended"])[]) shape.ended[key] += c.ended[key];
      for (const [language, n] of Object.entries(c.languages)) shape.languages[language] = (shape.languages[language] ?? 0) + n;
      const weekday = weekdayOf(row.day);
      c.by_hour.forEach((n, hour) => {
        shape.heatmap[weekday]![hour]! += n;
      });
      errands.handedOver += day.errands.handed_over;
      errands.finished += day.errands.finished;
      errands.stopped += day.errands.stopped;
    }

    const days = Array.from({ length: periodDays }, (_, i) => isoDay(now.getTime() - (periodDays - 1 - i) * DAY_MS));
    const activeByDay = days.map((day) => ({ day, accounts: activeOn.get(day)?.size ?? 0 }));
    const within = (back: number) => {
      const from = isoDay(now.getTime() - (back - 1) * DAY_MS);
      const accounts = new Set<string>();
      for (const [day, users] of activeOn) if (day >= from && day <= today) for (const user of users) accounts.add(user);
      return accounts.size;
    };
    const engagement: Engagement = {
      today: activeOn.get(today)?.size ?? 0,
      week: within(7),
      month: within(30),
      dailyAverage: Math.round((activeByDay.reduce((sum, d) => sum + d.accounts, 0) / periodDays) * 10) / 10,
    };

    // Activation and cohorts need to know when each account joined, so they need the account list.
    let joined = 0;
    let activated = 0;
    const mondays = Array.from({ length: COHORT_WEEKS }, (_, i) => mondayOf(isoDay(now.getTime() - (COHORT_WEEKS - 1 - i) * 7 * DAY_MS)));
    const cohortUsers = new Map<string, string[]>(mondays.map((m) => [m, []]));
    for (const user of directory ?? []) {
      if (!user.createdAt) continue;
      const created = isoDay(Date.parse(user.createdAt));
      const userId = userFor.get(user.id) ?? user.id;
      if (created >= since) {
        joined += 1;
        const limit = isoDay(Date.parse(`${created}T00:00:00Z`) + 7 * DAY_MS);
        if ((activeDays.get(userId) ?? []).some((d) => d >= created && d <= limit)) activated += 1;
      }
      cohortUsers.get(mondayOf(created))?.push(userId);
    }
    const cohorts: Cohort[] = mondays.map((week, index) => {
      const users = cohortUsers.get(week) ?? [];
      const weeksSince = mondays.length - 1 - index;
      const active = Array.from({ length: weeksSince + 1 }, (_, k) => {
        const target = isoDay(Date.parse(`${week}T00:00:00Z`) + k * 7 * DAY_MS);
        return users.filter((userId) => (activeDays.get(userId) ?? []).some((d) => mondayOf(d) === target)).length;
      });
      return { week, size: users.length, active };
    });

    return {
      generatedAt: now.toISOString(),
      periodDays,
      directory: directory !== null,
      accounts: {
        total: directory ? directory.length : null,
        byMethod,
        newByDay: days.map((day) => ({ day, count: newByDay.get(day) ?? 0 })),
      },
      logbook: {
        on: states.filter((s) => s.enabled).length,
        off: states.filter((s) => !s.enabled).length,
        sending: sending.size,
        activeByDay,
        totals,
      },
      engagement,
      conversations: shape,
      errands,
      activation: { joined, activated },
      cohorts: directory ? cohorts : [],
    };
  }

  async accounts(now: Date, periodDays: number): Promise<{ generatedAt: string; periodDays: number; directory: boolean; accounts: OwnerAccount[] }> {
    const today = isoDay(now.getTime());
    const since = isoDay(now.getTime() - (periodDays - 1) * DAY_MS);
    const kept = isoDay(now.getTime() - LOGBOOK_KEPT_DAYS * DAY_MS);
    const [directory, links, states, rows] = await Promise.all([
      this.listDirectory(),
      this.store.accountUsers(),
      this.store.logbookStates(),
      this.store.allLogbookDays(kept),
    ]);
    const userFor = new Map(links.map((link) => [link.subject.toLowerCase(), link.user_id]));
    const accounts = new Map<string, OwnerAccount>();
    const blank = (userId: string): OwnerAccount => ({
      userId,
      accountId: null,
      email: null,
      name: null,
      method: null,
      createdAt: null,
      lastSignInAt: null,
      logbook: "never",
      lastDay: null,
      lastSentAt: null,
      lastActiveDay: null,
      trend: Array<number>(TREND_DAYS).fill(0),
      period: emptyTotals(),
    });
    for (const user of directory ?? []) {
      const userId = userFor.get(user.id) ?? user.id;
      accounts.set(userId, { ...blank(userId), accountId: user.id, email: user.email, name: user.name, method: user.method, createdAt: user.createdAt, lastSignInAt: user.lastSignInAt });
    }
    for (const state of states) {
      const account = accounts.get(state.user_id) ?? blank(state.user_id);
      account.logbook = state.enabled ? "on" : "off";
      accounts.set(state.user_id, account);
    }
    for (const row of rows) {
      const account = accounts.get(row.user_id) ?? blank(row.user_id);
      if (!account.lastDay || row.day > account.lastDay) account.lastDay = row.day;
      const sent = new Date(Number(row.received_at)).toISOString();
      if (!account.lastSentAt || sent > account.lastSentAt) account.lastSentAt = sent;
      const day = parse(row.summary);
      if (day) {
        if (used(day) && (!account.lastActiveDay || row.day > account.lastActiveDay)) account.lastActiveDay = row.day;
        if (row.day >= since) add(account.period, day);
        const back = Math.round((Date.parse(`${today}T00:00:00Z`) - Date.parse(`${row.day}T00:00:00Z`)) / DAY_MS);
        if (back >= 0 && back < TREND_DAYS) account.trend[TREND_DAYS - 1 - back]! += day.conversations.count;
      }
      accounts.set(row.user_id, account);
    }
    const order = (a: OwnerAccount) => a.lastSentAt ?? a.lastSignInAt ?? a.createdAt ?? "";
    return {
      generatedAt: now.toISOString(),
      periodDays,
      directory: directory !== null,
      accounts: [...accounts.values()].sort((a, b) => order(b).localeCompare(order(a))),
    };
  }

  /** One account's own Logbook, as that person's page reads it. */
  accountLogbook(userId: string, now: Date): Promise<LogbookView> {
    return readLogbookView(this.store, userId, now);
  }

  private async listDirectory(): Promise<DirectoryUser[] | null> {
    if (!this.directory) return null;
    if (this.cached && Date.now() - this.cached.at < this.directoryTtlMs) return this.cached.users;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const users = await this.directory.list(controller.signal);
      // Only a read that worked is kept: a failure is asked again at the next request.
      this.cached = users ? { at: Date.now(), users } : null;
      return users;
    } finally {
      clearTimeout(timer);
    }
  }
}

function parse(summary: string): DaySummary | null {
  try {
    const parsed = DaySummarySchema.safeParse(JSON.parse(summary));
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}
