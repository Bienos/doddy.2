import {
  ENDINGS,
  JOBS,
  KINDS,
  LENGTHS,
  SOURCES,
  WAYS,
  toolInfo,
  type EndingId,
  type JobId,
  type KindId,
  type LengthId,
  type SourceId,
  type WayId,
} from "./catalog.js";
import type { DaySummary, ToolOutcomes } from "./schema.js";

/**
 * Adding days up. Pure functions, no clock and no language, so the numbers on both tabs come from
 * one place and a test can check them against hand-added days. Nothing here compares one period
 * with another: Logbook shows counts, never a trend arrow or a score (ADR-306's rule, DOD-10).
 */

export interface Totals {
  conversations: number;
  seconds: number;
  byHour: number[];
  lengths: Record<LengthId, number>;
  ended: Record<EndingId, number>;
  languages: Record<string, number>;
  waysIn: Record<WayId, number>;
  tools: Record<string, ToolOutcomes>;
  /** Everything Doddy did, and the part that ran at once versus after the person's yes. */
  done: number;
  doneNow: number;
  doneAfterYes: number;
  /** Asked first (ASK-01): the person said yes (the action ran, with any result) or no. */
  asked: number;
  yes: number;
  no: number;
  /** Across every tool: couldn't confirm, didn't work. */
  unsure: number;
  failed: number;
  /** After asking first: the outcomes of the yes. */
  askDone: number;
  askUnsure: number;
  askFailed: number;
  jobs: Record<JobId, { count: number; tools: Record<string, number> }>;
  notesSaved: number;
  notesBySource: Record<SourceId, number>;
  notesByKind: Record<KindId, number>;
  notesEdited: number;
  listAdded: number;
  addedVoice: number;
  addedTyped: number;
  listsTicked: number;
  errands: { handedOver: number; finished: number; stopped: number; minutes: number; searches: number; pages: number };
  translator: { sessions: number; minutes: number };
}

function zeroed<K extends string>(keys: readonly K[]): Record<K, number> {
  return Object.fromEntries(keys.map((k) => [k, 0])) as Record<K, number>;
}

/** A tool's run count: it ran (done, couldn't confirm or failed). A no is counted apart. */
export function ran(outcomes: ToolOutcomes): number {
  return outcomes.done + outcomes.unsure + outcomes.failed;
}

export function sumDays(days: readonly DaySummary[]): Totals {
  const t: Totals = {
    conversations: 0,
    seconds: 0,
    byHour: new Array<number>(24).fill(0),
    lengths: zeroed(LENGTHS),
    ended: zeroed(ENDINGS),
    languages: {},
    waysIn: zeroed(WAYS),
    tools: {},
    done: 0,
    doneNow: 0,
    doneAfterYes: 0,
    asked: 0,
    yes: 0,
    no: 0,
    unsure: 0,
    failed: 0,
    askDone: 0,
    askUnsure: 0,
    askFailed: 0,
    jobs: Object.fromEntries(JOBS.map((j) => [j.id, { count: 0, tools: {} }])) as Totals["jobs"],
    notesSaved: 0,
    notesBySource: zeroed(SOURCES),
    notesByKind: zeroed(KINDS),
    notesEdited: 0,
    listAdded: 0,
    addedVoice: 0,
    addedTyped: 0,
    listsTicked: 0,
    errands: { handedOver: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 },
    translator: { sessions: 0, minutes: 0 },
  };

  for (const d of days) {
    const c = d.conversations;
    t.conversations += c.count;
    t.seconds += c.seconds;
    c.by_hour.forEach((n, hour) => {
      t.byHour[hour] = (t.byHour[hour] ?? 0) + n;
    });
    for (const k of LENGTHS) t.lengths[k] += c.lengths[k];
    for (const k of ENDINGS) t.ended[k] += c.ended[k];
    for (const k of WAYS) t.waysIn[k] += c.ways_in[k];
    for (const [code, n] of Object.entries(c.languages)) t.languages[code] = (t.languages[code] ?? 0) + n;

    for (const [id, o] of Object.entries(d.tools)) {
      const row = t.tools[id] ?? (t.tools[id] = { done: 0, declined: 0, unsure: 0, failed: 0, undone: 0 });
      row.done += o.done;
      row.declined += o.declined;
      row.unsure += o.unsure;
      row.failed += o.failed;
      row.undone += o.undone;
    }

    for (const k of SOURCES) t.notesBySource[k] += d.notes.by_source[k];
    for (const [kind, n] of Object.entries(d.notes.by_kind)) if (n) t.notesByKind[kind as KindId] += n;
    t.notesEdited += d.notes.edited;
    t.addedVoice += d.lists.added_voice;
    t.addedTyped += d.lists.added_typed;
    t.listsTicked += d.lists.ticked;
    t.errands.handedOver += d.errands.handed_over;
    t.errands.finished += d.errands.finished;
    t.errands.stopped += d.errands.stopped;
    t.errands.minutes += d.errands.minutes;
    t.errands.searches += d.errands.searches;
    t.errands.pages += d.errands.pages;
    t.translator.sessions += d.translator.sessions;
    t.translator.minutes += d.translator.minutes;
  }

  for (const [id, o] of Object.entries(t.tools)) {
    const info = toolInfo(id);
    t.done += o.done;
    t.unsure += o.unsure;
    t.failed += o.failed;
    if (info.ask) {
      t.doneAfterYes += o.done;
      t.yes += ran(o);
      t.no += o.declined;
      t.asked += ran(o) + o.declined;
      t.askDone += o.done;
      t.askUnsure += o.unsure;
      t.askFailed += o.failed;
    } else {
      t.doneNow += o.done;
    }
    const job = t.jobs[info.job];
    job.count += ran(o);
    job.tools[id] = ran(o);
  }
  t.notesSaved = SOURCES.reduce((sum, k) => sum + t.notesBySource[k], 0);
  t.listAdded = t.addedVoice + t.addedTyped;
  return t;
}

/** Monday = 0 … Sunday = 6, for a day written "2026-10-21". */
export function weekdayIndex(day: string): number {
  return (new Date(`${day}T00:00:00Z`).getUTCDay() + 6) % 7;
}

/** ISO week number (weeks start on Monday; week 1 holds the year's first Thursday). */
export function isoWeek(day: string): number {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - weekdayIndex(day) + 3);
  const firstThursday = new Date(Date.UTC(d.getUTCFullYear(), 0, 4));
  return 1 + Math.round(((d.getTime() - firstThursday.getTime()) / 86_400_000 - 3 + weekdayIndex(firstThursday.toISOString().slice(0, 10))) / 7);
}

/** Groups days (oldest first) into Monday-to-Sunday weeks; the first and last may be partial. */
export function groupWeeks(days: readonly DaySummary[]): DaySummary[][] {
  const weeks: DaySummary[][] = [];
  for (const d of days) {
    const last = weeks[weeks.length - 1];
    if (!last || weekdayIndex(d.day) === 0) weeks.push([d]);
    else last.push(d);
  }
  return weeks;
}

/** The weeks At a glance steps through: whole weeks, then this week so far. A leading partial week is dropped. */
export function glanceWeeks(days: readonly DaySummary[]): DaySummary[][] {
  const weeks = groupWeeks(days);
  const first = weeks[0];
  if (first && first.length < 7) weeks.shift();
  return weeks;
}

/** Counts for a weekday-by-hour heatmap: 7 rows (Monday first) of 24 hours. */
export function weekdayHourGrid(days: readonly DaySummary[]): number[][] {
  const grid = Array.from({ length: 7 }, () => new Array<number>(24).fill(0));
  for (const d of days) {
    const row = grid[weekdayIndex(d.day)];
    if (row) d.conversations.by_hour.forEach((n, hour) => (row[hour] = (row[hour] ?? 0) + n));
  }
  return grid;
}
