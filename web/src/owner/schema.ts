import { z } from "zod";

/**
 * The owner panel's replies (decision 2026-11-09-usage-counts-on-by-default; the server is
 * backend/src/web/owner.ts). Counts and the accounts' sign-in details only; every object is strict,
 * so a reply with a field this page doesn't know is shown as unreadable, never half-read.
 */

const count = z.number().int().min(0);
const Day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const Outcomes = z.object({ done: count, declined: count, unsure: count, failed: count, undone: count }).strict();
export type Outcomes = z.output<typeof Outcomes>;

export const UsageTotals = z
  .object({
    activeDays: count,
    conversations: count,
    seconds: count,
    notes: count,
    listItems: count,
    errands: count,
    tools: z.record(z.string(), Outcomes),
  })
  .strict();
export type UsageTotals = z.output<typeof UsageTotals>;

export const OwnerFlag = z.object({ owner: z.literal(true) }).strict();

const Lengths = z.object({ under_1: count, "1_3": count, "3_5": count, "5_10": count }).strict();
const Endings = z.object({ you: count, doddy: count, quiet: count, dropped: count }).strict();

export const ConversationShape = z
  .object({
    lengths: Lengths,
    ended: Endings,
    languages: z.record(z.string(), count),
    /** Monday first, then the phone's local hour: 7 rows of 24. */
    heatmap: z.array(z.array(count).length(24)).length(7),
  })
  .strict();
export type ConversationShape = z.output<typeof ConversationShape>;

/** `w4`: of the accounts whose days 22 to 28 after joining are over, how many had a task that worked out then. */
export const Cohort = z
  .object({ week: Day, size: count, active: z.array(count), w4: z.object({ eligible: count, kept: count }).strict() })
  .strict();
export type Cohort = z.output<typeof Cohort>;

/** Accounts by the week of their first task that worked out, and how many had another one each week after. */
export const FirstTaskCohort = z.object({ week: Day, size: count, active: z.array(count) }).strict();
export type FirstTaskCohort = z.output<typeof FirstTaskCohort>;

/**
 * One week of tasks that worked out (decision 2026-11-14-tasks-that-worked-out): Logbook's "done" less
 * "undone", which still holds look-ups, opened apps and cards shown, so it is not "confirmed".
 */
export const ValueWeek = z
  .object({ week: Day, active: count, withWorkedOut: count, workedOut: count, outcomes: Outcomes })
  .strict();
export type ValueWeek = z.output<typeof ValueWeek>;

export const OwnerOverview = z
  .object({
    generatedAt: z.string(),
    periodDays: count,
    directory: z.boolean(),
    accounts: z
      .object({
        total: count.nullable(),
        byMethod: z.record(z.string(), count),
        newByDay: z.array(z.object({ day: Day, count }).strict()),
      })
      .strict(),
    logbook: z
      .object({
        on: count,
        off: count,
        sending: count,
        activeByDay: z.array(z.object({ day: Day, accounts: count }).strict()),
        totals: UsageTotals,
      })
      .strict(),
    engagement: z.object({ today: count, week: count, month: count, dailyAverage: z.number().min(0) }).strict(),
    conversations: ConversationShape,
    errands: z.object({ handedOver: count, finished: count, stopped: count }).strict(),
    activation: z.object({ joined: count, activated: count }).strict(),
    cohorts: z.array(Cohort),
    value: z.object({ weeks: z.array(ValueWeek), firstTaskCohorts: z.array(FirstTaskCohort) }).strict(),
  })
  .strict();
export type OwnerOverview = z.output<typeof OwnerOverview>;

export const OwnerAccount = z
  .object({
    userId: z.string(),
    accountId: z.string().nullable(),
    email: z.string().nullable(),
    name: z.string().nullable(),
    method: z.string().nullable(),
    createdAt: z.string().nullable(),
    lastSignInAt: z.string().nullable(),
    logbook: z.enum(["on", "off", "never"]),
    lastDay: Day.nullable(),
    lastSentAt: z.string().nullable(),
    lastActiveDay: Day.nullable(),
    /** Conversations on each of the last 14 days, oldest first. */
    trend: z.array(count).length(14),
    period: UsageTotals,
  })
  .strict();
export type OwnerAccount = z.output<typeof OwnerAccount>;

export const OwnerAccounts = z
  .object({ generatedAt: z.string(), periodDays: count, directory: z.boolean(), accounts: z.array(OwnerAccount) })
  .strict();
export type OwnerAccounts = z.output<typeof OwnerAccounts>;

export const OWNER_PERIODS = [7, 30, 90, 365] as const;

/** A tool's rows, most used first, with how often it didn't work out. */
export function toolRows(tools: Record<string, Outcomes>) {
  return Object.entries(tools)
    .map(([tool, o]) => {
      const total = o.done + o.declined + o.unsure + o.failed;
      return { tool, ...o, total, failRate: total > 0 ? (o.failed + o.unsure) / total : 0 };
    })
    .filter((row) => row.total > 0)
    .sort((a, b) => b.total - a.total || a.tool.localeCompare(b.tool));
}
