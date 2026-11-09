import { z } from "zod";
import { AppError } from "../errors.js";
import type { Store } from "../store.js";
import { type DaySummary, DaySummarySchema, isoDay, LOGBOOK_KEPT_DAYS, type LogbookView, readLogbookView } from "./logbook.js";

/**
 * The owner panel (decision 2026-11-09-usage-counts-on-by-default): totals of every account's Logbook
 * days, and each account's own days with its sign-in method, email and dates. Counts only, exactly
 * what Logbook holds (`logbook.ts`); no words exist here to show. Only the accounts named in
 * DODDY_OWNER_ACCOUNTS see it; everyone else gets "not found", so the routes don't announce
 * themselves. One person still sees only their own Logbook page.
 */

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
}

const DAY_MS = 86_400_000;
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

  constructor(
    private readonly store: Store,
    owners: readonly string[],
    private readonly directory: UserDirectory | null,
    private readonly timeoutMs = 10_000,
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

  static period(raw: string | undefined): number {
    const days = Number(raw ?? 30);
    return (OWNER_PERIODS as readonly number[]).includes(days) ? days : 30;
  }

  async overview(now: Date, periodDays: number): Promise<OwnerOverview> {
    const since = isoDay(now.getTime() - (periodDays - 1) * DAY_MS);
    const [directory, states, rows] = await Promise.all([this.listDirectory(), this.store.logbookStates(), this.store.allLogbookDays(since)]);
    const byMethod: Record<string, number> = {};
    const newByDay = new Map<string, number>();
    for (const user of directory ?? []) {
      const method = user.method ?? "unknown";
      byMethod[method] = (byMethod[method] ?? 0) + 1;
      const created = user.createdAt ? isoDay(Date.parse(user.createdAt)) : null;
      if (created && created >= since) newByDay.set(created, (newByDay.get(created) ?? 0) + 1);
    }
    const totals = emptyTotals();
    const active = new Map<string, Set<string>>();
    const sending = new Set<string>();
    for (const row of rows) {
      const day = parse(row.summary);
      if (!day) continue;
      sending.add(row.user_id);
      add(totals, day);
      if (used(day)) {
        const users = active.get(row.day) ?? new Set<string>();
        users.add(row.user_id);
        active.set(row.day, users);
      }
    }
    // activeDays across everyone counts account-days, which is what "days of use" means here.
    const days = Array.from({ length: periodDays }, (_, i) => isoDay(now.getTime() - (periodDays - 1 - i) * DAY_MS));
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
        activeByDay: days.map((day) => ({ day, accounts: active.get(day)?.size ?? 0 })),
        totals,
      },
    };
  }

  async accounts(now: Date, periodDays: number): Promise<{ generatedAt: string; periodDays: number; directory: boolean; accounts: OwnerAccount[] }> {
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
      if (row.day >= since) {
        const day = parse(row.summary);
        if (day) add(account.period, day);
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
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      return await this.directory.list(controller.signal);
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
