import type { DaySummary } from "./logbook.js";

/**
 * Logbook's days, added up for the chat (ADR-604): what the person asks about how they use Doddy
 * ("how much did we talk this week?", "when do I usually call you?") is answered from these totals,
 * never from a guess. Counts only, like Logbook itself (ADR-602): no word anyone said is in a day,
 * so none can be in a digest. Days are the iPhone's local calendar days.
 */

const DAY_MS = 86_400_000;
const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;
const TOP_TOOLS = 15;

type Counts = Record<string, number>;

export interface PeriodDigest {
  period: "last_7_days" | "last_30_days" | "all_kept";
  from: string;
  to: string;
  /** Days in the period the iPhone sent a summary for. A day without one has no data, not zero use. */
  daysWithData: number;
  conversations: {
    count: number;
    minutes: number;
    averageMinutes: number | null;
    lengths: Counts;
    ended: Counts;
    languages: Counts;
    waysIn: Counts;
    /** Local hours (0 to 23) with the most conversations, busiest first. */
    busiestHours: { hour: number; conversations: number }[];
    byWeekday: Counts;
  };
  /** Doddy's tools by how often they ran, with how each run ended. */
  tools: { id: string; uses: number; done: number; declined: number; unsure: number; failed: number; undone: number }[];
  notes: { saved: number; bySource: Counts; byKind: Counts; edited: number };
  lists: { addedByVoice: number; addedTyped: number; ticked: number };
  errands: { handedOver: number; finished: number; stopped: number; minutes: number; searches: number; pages: number };
  translator: { sessions: number; minutes: number };
}

export interface LogbookDigest {
  today: string;
  periods: PeriodDigest[];
  /** The last 14 days that have a summary, oldest first. */
  recentDays: { day: string; weekday: string; conversations: number; minutes: number; toolUses: number; notesSaved: number }[];
}

const add = (into: Counts, from: Record<string, number>) => {
  for (const [key, value] of Object.entries(from)) if (value > 0) into[key] = (into[key] ?? 0) + value;
};
const total = (values: Record<string, number>) => Object.values(values).reduce((sum, n) => sum + n, 0);
const weekday = (day: string) => WEEKDAYS[new Date(`${day}T00:00:00Z`).getUTCDay()]!;
const shift = (day: string, days: number) => new Date(Date.parse(`${day}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
const minutes = (seconds: number) => Math.round(seconds / 60);

function digestPeriod(period: PeriodDigest["period"], from: string, to: string, days: DaySummary[]): PeriodDigest {
  const inside = days.filter((d) => d.day >= from && d.day <= to);
  const lengths: Counts = {};
  const ended: Counts = {};
  const languages: Counts = {};
  const waysIn: Counts = {};
  const byWeekday: Counts = {};
  const hours = new Array<number>(24).fill(0);
  const tools = new Map<string, { done: number; declined: number; unsure: number; failed: number; undone: number }>();
  const bySource: Counts = {};
  const byKind: Counts = {};
  let count = 0;
  let seconds = 0;
  let edited = 0;
  const lists = { addedByVoice: 0, addedTyped: 0, ticked: 0 };
  const errands = { handedOver: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 };
  const translator = { sessions: 0, minutes: 0 };

  for (const day of inside) {
    const c = day.conversations;
    count += c.count;
    seconds += c.seconds;
    add(lengths, c.lengths);
    add(ended, c.ended);
    add(languages, c.languages);
    add(waysIn, c.ways_in);
    if (c.count > 0) byWeekday[weekday(day.day)] = (byWeekday[weekday(day.day)] ?? 0) + c.count;
    c.by_hour.forEach((n, hour) => (hours[hour]! += n));
    for (const [id, o] of Object.entries(day.tools)) {
      const t = tools.get(id) ?? { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 };
      t.done += o.done;
      t.declined += o.declined;
      t.unsure += o.unsure;
      t.failed += o.failed;
      t.undone += o.undone;
      tools.set(id, t);
    }
    add(bySource, day.notes.by_source);
    add(byKind, day.notes.by_kind);
    edited += day.notes.edited;
    lists.addedByVoice += day.lists.added_voice;
    lists.addedTyped += day.lists.added_typed;
    lists.ticked += day.lists.ticked;
    errands.handedOver += day.errands.handed_over;
    errands.finished += day.errands.finished;
    errands.stopped += day.errands.stopped;
    errands.minutes += day.errands.minutes;
    errands.searches += day.errands.searches;
    errands.pages += day.errands.pages;
    translator.sessions += day.translator.sessions;
    translator.minutes += day.translator.minutes;
  }

  const busiestHours = hours
    .map((conversations, hour) => ({ hour, conversations }))
    .filter((h) => h.conversations > 0)
    .sort((a, b) => b.conversations - a.conversations || a.hour - b.hour)
    .slice(0, 3);
  const toolList = [...tools.entries()]
    .map(([id, o]) => ({ id, uses: o.done + o.declined + o.unsure + o.failed + o.undone, ...o }))
    .filter((t) => t.uses > 0)
    .sort((a, b) => b.uses - a.uses || a.id.localeCompare(b.id))
    .slice(0, TOP_TOOLS);

  return {
    period,
    from,
    to,
    daysWithData: inside.length,
    conversations: {
      count,
      minutes: minutes(seconds),
      averageMinutes: count > 0 ? Math.round((seconds / 60 / count) * 10) / 10 : null,
      lengths,
      ended,
      languages,
      waysIn,
      busiestHours,
      byWeekday,
    },
    tools: toolList,
    notes: { saved: total(bySource), bySource, byKind, edited },
    lists,
    errands,
    translator,
  };
}

/**
 * The digest for `today` (the person's local date when the page sent a time zone, else UTC): the
 * last 7 and 30 days counting today, and everything kept. Null when there are no days at all.
 */
export function digestLogbook(days: DaySummary[], today: string): LogbookDigest | null {
  if (days.length === 0) return null;
  const sorted = [...days].sort((a, b) => a.day.localeCompare(b.day));
  const oldest = sorted[0]!.day;
  const newest = sorted[sorted.length - 1]!.day > today ? sorted[sorted.length - 1]!.day : today;
  return {
    today,
    periods: [
      digestPeriod("last_7_days", shift(today, -6), newest, sorted),
      digestPeriod("last_30_days", shift(today, -29), newest, sorted),
      digestPeriod("all_kept", oldest, newest, sorted),
    ],
    recentDays: sorted.slice(-14).map((d) => ({
      day: d.day,
      weekday: weekday(d.day),
      conversations: d.conversations.count,
      minutes: minutes(d.conversations.seconds),
      toolUses: Object.values(d.tools).reduce((sum, o) => sum + o.done + o.declined + o.unsure + o.failed + o.undone, 0),
      notesSaved: total(d.notes.by_source),
    })),
  };
}
