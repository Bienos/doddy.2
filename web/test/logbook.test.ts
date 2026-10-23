import { describe, expect, test } from "vitest";
import { MESSAGES } from "../src/i18n/messages.js";
import { CSV_COLUMNS, logbookCsv } from "../src/logbook/csv.js";
import { defaultWeekIndex, emptyDay, fillGaps, glanceWeeks, groupWeeks, isoWeek, ran, sumDays, weekdayHourGrid, weekdayIndex } from "../src/logbook/aggregate.js";
import { ENDINGS, JOBS, KINDS, LENGTHS, SOURCES, TOOLS, TOOL_IDS, WAYS, isKnownTool, toolInfo } from "../src/logbook/catalog.js";
import { exampleLogbook, makeExampleDays } from "../src/logbook/exampleData.js";
import { makeFormats } from "../src/logbook/format.js";
import { DaySummary, LogbookDays } from "../src/logbook/schema.js";

/** A day with only the fields a test cares about; the rest is zero, in the contract's shape. */
const blank = () => day("2026-01-01");

function day(iso: string, patch: Partial<DaySummary> = {}): DaySummary {
  return DaySummary.parse({
    schema: "doddy.logbook.day.v1",
    day: iso,
    conversations: {
      count: 0,
      seconds: 0,
      by_hour: new Array(24).fill(0),
      lengths: Object.fromEntries(LENGTHS.map((k) => [k, 0])),
      ended: Object.fromEntries(ENDINGS.map((k) => [k, 0])),
      languages: {},
      ways_in: Object.fromEntries(WAYS.map((k) => [k, 0])),
    },
    tools: {},
    notes: { by_source: Object.fromEntries(SOURCES.map((k) => [k, 0])), by_kind: {}, edited: 0 },
    lists: { added_voice: 0, added_typed: 0, ticked: 0 },
    errands: { handed_over: 0, finished: 0, stopped: 0, minutes: 0, searches: 0, pages: 0 },
    translator: { sessions: 0, minutes: 0 },
    ...patch,
  });
}

describe("the daily summary contract", () => {
  const days = makeExampleDays();

  test("every example day is a valid summary, and there are 91 of them ending the day before 'today'", () => {
    expect(days).toHaveLength(91);
    expect(days[0]?.day).toBe("2026-07-23");
    expect(days[90]?.day).toBe("2026-10-21");
    for (const d of days) expect(() => DaySummary.parse(d), d.day).not.toThrow();
    expect(() => LogbookDays.parse(exampleLogbook())).not.toThrow();
  });

  test("a field the contract doesn't name is refused, not shown", () => {
    const base = days[0] as DaySummary;
    expect(DaySummary.safeParse({ ...base, transcript: "hello" }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, notes: { ...base.notes, text: "buy milk" } }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, conversations: { ...base.conversations, title: "x" } }).success).toBe(false);
  });

  test("words where numbers belong, and out-of-range numbers, are refused", () => {
    const base = days[0] as DaySummary;
    expect(DaySummary.safeParse({ ...base, lists: { ...base.lists, ticked: "milk" } }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, lists: { ...base.lists, ticked: 1.5 } }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, lists: { ...base.lists, ticked: -1 } }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, lists: { ...base.lists, ticked: 10_001 } }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, conversations: { ...base.conversations, by_hour: [1, 2, 3] } }).success).toBe(false);
    // A tool name that is a sentence, not an id, is refused: words can't ride in as keys.
    expect(DaySummary.safeParse({ ...base, tools: { "Buy milk at the shop": { done: 1 } } }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, tools: { get_weather: { done: "yes" } } }).success).toBe(false);
    // A language key must be a code, a note kind must be one of the nine.
    expect(DaySummary.safeParse({ ...base, conversations: { ...base.conversations, languages: { "Polish, mostly": 1 } } }).success).toBe(false);
    expect(DaySummary.safeParse({ ...base, notes: { ...base.notes, by_kind: { secrets: 1 } } }).success).toBe(false);
  });

  test("a tool the list doesn't know yet is accepted by shape and shown under Other", () => {
    const parsed = DaySummary.parse({ ...(days[0] as DaySummary), tools: { some_new_tool: { done: 2 } } });
    expect(parsed.tools.some_new_tool).toEqual({ done: 2, declined: 0, unsure: 0, failed: 0, undone: 0 });
    expect(isKnownTool("some_new_tool")).toBe(false);
    expect(toolInfo("some_new_tool")).toMatchObject({ app: "other", job: "other", ask: false });
    const totals = sumDays([parsed]);
    expect(totals.jobs.other.count).toBe(2);
    expect(totals.done).toBe(2);
  });
});

describe("adding days up", () => {
  test("by hand: two days, every receipt line", () => {
    const a = day("2026-10-19", {
      conversations: { ...blank().conversations, count: 2, seconds: 300, by_hour: [...new Array(8).fill(0), 1, ...new Array(4).fill(0), 1, ...new Array(10).fill(0)] },
      tools: {
        get_weather: { done: 2, declined: 0, unsure: 0, failed: 0, undone: 0 },
        create_reminder: { done: 1, declined: 1, unsure: 0, failed: 0, undone: 0 },
      },
      notes: { by_source: { voice: 1, typed: 0, shared: 0, imported: 0 }, by_kind: { place: 1 }, edited: 0 },
      lists: { added_voice: 2, added_typed: 1, ticked: 1 },
    });
    const b = day("2026-10-20", {
      conversations: { ...blank().conversations, count: 1, seconds: 120, by_hour: [...new Array(21).fill(0), 1, 0, 0] },
      tools: {
        create_reminder: { done: 0, declined: 0, unsure: 1, failed: 1, undone: 0 },
        add_to_list: { done: 3, declined: 0, unsure: 0, failed: 0, undone: 1 },
      },
      notes: { by_source: { voice: 0, typed: 2, shared: 0, imported: 0 }, by_kind: { place: 1, fact: 1 }, edited: 1 },
      errands: { handed_over: 1, finished: 1, stopped: 0, minutes: 6, searches: 5, pages: 9 },
    });
    const t = sumDays([a, b]);
    expect(t.conversations).toBe(3);
    expect(t.seconds).toBe(420);
    expect(t.byHour[8]).toBe(1);
    expect(t.byHour[13]).toBe(1);
    expect(t.byHour[21]).toBe(1);
    // done: weather 2 + reminder 1 + list 3; the reminder is the only tool that asks first.
    expect(t.done).toBe(6);
    expect(t.doneNow).toBe(5);
    expect(t.doneAfterYes).toBe(1);
    // Asked first: 1 done + 1 couldn't confirm + 1 failed ran after a yes, 1 was a no.
    expect(t.yes).toBe(3);
    expect(t.no).toBe(1);
    expect(t.asked).toBe(4);
    expect(t.unsure).toBe(1);
    expect(t.failed).toBe(1);
    expect(t.askDone + t.askUnsure + t.askFailed).toBe(t.yes);
    expect(t.notesSaved).toBe(3);
    expect(t.notesBySource).toEqual({ voice: 1, typed: 2, shared: 0, imported: 0 });
    expect(t.notesByKind.place).toBe(2);
    expect(t.notesByKind.fact).toBe(1);
    expect(t.notesEdited).toBe(1);
    expect(t.listAdded).toBe(3);
    expect(t.addedVoice).toBe(2);
    expect(t.listsTicked).toBe(1);
    expect(t.errands.handedOver).toBe(1);
    expect(t.errands.pages).toBe(9);
    expect(t.tools.add_to_list?.undone).toBe(1);
    // Jobs: plan = reminder 3 ran (a no isn't a run); find = weather 2; lists = 3.
    expect(t.jobs.plan.count).toBe(3);
    expect(t.jobs.find.count).toBe(2);
    expect(t.jobs.lists.count).toBe(3);
    expect(t.jobs.find.tools).toEqual({ get_weather: 2 });
  });

  test("the example's lines agree with each other in every week and every period", () => {
    const days = makeExampleDays();
    const groups = [...groupWeeks(days), days.slice(-7), days.slice(-30), days.slice(-90), days];
    for (const g of groups) {
      const t = sumDays(g);
      expect(t.done).toBe(t.doneNow + t.doneAfterYes);
      expect(t.asked).toBe(t.yes + t.no);
      expect(t.yes).toBe(t.askDone + t.askUnsure + t.askFailed);
      expect(t.byHour.reduce((s, n) => s + n, 0)).toBe(t.conversations);
      expect(LENGTHS.reduce((s, k) => s + t.lengths[k], 0)).toBe(t.conversations);
      expect(ENDINGS.reduce((s, k) => s + t.ended[k], 0)).toBe(t.conversations);
      expect(WAYS.reduce((s, k) => s + t.waysIn[k], 0)).toBe(t.conversations);
      expect(Object.values(t.languages).reduce((s, n) => s + n, 0)).toBe(t.conversations);
      expect(KINDS.reduce((s, k) => s + t.notesByKind[k], 0)).toBe(t.notesSaved);
      const jobTotal = JOBS.reduce((s, j) => s + t.jobs[j.id].count, 0);
      const ranTotal = Object.values(t.tools).reduce((s, o) => s + ran(o), 0);
      expect(jobTotal).toBe(ranTotal);
      // A tool that runs without asking never has a "no".
      for (const [id, o] of Object.entries(t.tools)) if (!toolInfo(id).ask) expect(o.declined, id).toBe(0);
    }
  });

  test("the example's week of 12 to 18 October, as the receipt shows it", () => {
    const week = makeExampleDays().filter((d) => d.day >= "2026-10-12" && d.day <= "2026-10-18");
    expect(week).toHaveLength(7);
    const t = sumDays(week);
    expect(t.conversations).toBe(28);
    expect(Math.round(t.seconds / 60)).toBe(88);
    expect(t.notesSaved).toBe(9);
    expect(t.listAdded).toBe(15);
    expect([t.done, t.doneNow, t.doneAfterYes]).toEqual([38, 27, 11]);
    expect([t.asked, t.yes, t.no]).toEqual([15, 14, 1]);
    expect([t.unsure, t.failed]).toEqual([2, 1]);
    expect(t.errands.handedOver).toBe(3);
  });

  test("the same seed gives the same days every time", () => {
    expect(makeExampleDays()).toEqual(makeExampleDays());
    expect(makeExampleDays(1)).not.toEqual(makeExampleDays(2));
  });

  test("the example has no tool that the catalog can't name, and the catalog has no tool without a weight problem", () => {
    for (const d of makeExampleDays()) for (const id of Object.keys(d.tools)) expect(isKnownTool(id), id).toBe(true);
    for (const id of TOOL_IDS) expect(TOOLS[id].weight).toBeGreaterThanOrEqual(0);
  });
});

describe("weeks and weekdays", () => {
  test("ISO weeks, including the year's edges", () => {
    expect(isoWeek("2026-10-12")).toBe(42);
    expect(isoWeek("2026-10-18")).toBe(42);
    expect(isoWeek("2026-10-19")).toBe(43);
    expect(isoWeek("2026-01-01")).toBe(1); // a Thursday: week 1
    expect(isoWeek("2025-12-29")).toBe(1); // a Monday that belongs to 2026's week 1
    expect(isoWeek("2027-01-03")).toBe(53); // 2026 has 53 weeks
  });

  test("Monday is 0", () => {
    expect(weekdayIndex("2026-10-19")).toBe(0);
    expect(weekdayIndex("2026-10-25")).toBe(6);
  });

  test("grouping: weeks start on Monday; At a glance keeps the short first week and this week so far", () => {
    const days = makeExampleDays(); // Thu 23 Jul to Wed 21 Oct
    const all = groupWeeks(days);
    expect(all[0]?.map((d) => d.day)).toEqual(["2026-07-23", "2026-07-24", "2026-07-25", "2026-07-26"]);
    expect(all[all.length - 1]?.map((d) => d.day)).toEqual(["2026-10-19", "2026-10-20", "2026-10-21"]);
    const weeks = glanceWeeks(days);
    expect(weeks[0]?.map((d) => d.day)).toEqual(["2026-07-23", "2026-07-24", "2026-07-25", "2026-07-26"]);
    expect(weeks.slice(1, -1).every((w) => w.length === 7)).toBe(true);
    expect(weeks).toHaveLength(14); // the short first week, 12 whole weeks and this week so far
    // It opens on the latest whole week.
    expect(defaultWeekIndex(weeks)).toBe(12);
    expect(weeks[12]?.[0]?.day).toBe("2026-10-12");
  });

  test("the week it opens on: the latest whole week, else the week so far", () => {
    const run = (from: string, n: number) => Array.from({ length: n }, (_, i) => day(new Date(Date.parse(`${from}T00:00:00Z`) + i * 86_400_000).toISOString().slice(0, 10)));
    // Thu 15 Oct to Sat 17 Oct: one short week.
    expect(defaultWeekIndex(glanceWeeks(run("2026-10-15", 3)))).toBe(0);
    // Thu 8 Oct to Wed 14 Oct: a short first week, then two days of this one: no whole week yet.
    expect(defaultWeekIndex(glanceWeeks(run("2026-10-08", 7)))).toBe(1);
    // Mon 5 Oct to Tue 20 Oct: a whole week, a whole week, two days.
    expect(defaultWeekIndex(glanceWeeks(run("2026-10-05", 16)))).toBe(1);
    expect(defaultWeekIndex([])).toBe(0);
  });

  test("days the iPhone sent nothing for are days with nothing counted: gaps are filled, nothing before or after", () => {
    const sent = [
      day("2026-10-14", { conversations: { ...blank().conversations, count: 2, seconds: 120, by_hour: [...new Array(9).fill(0), 2, ...new Array(14).fill(0)], lengths: { ...blank().conversations.lengths, "1_3": 2 }, ended: { ...blank().conversations.ended, you: 2 } } }),
      day("2026-10-19"),
    ];
    const filled = fillGaps([sent[1] as DaySummary, sent[0] as DaySummary]);
    expect(filled.map((d) => d.day)).toEqual(["2026-10-14", "2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18", "2026-10-19"]);
    expect(filled[0]).toBe(sent[0]);
    expect(filled[1]).toEqual(emptyDay("2026-10-15"));
    expect(DaySummary.safeParse(emptyDay("2026-10-15")).success).toBe(true);
    expect(sumDays(filled).conversations).toBe(2);
    // The Monday-less week still groups by the calendar: 14 to 18 Oct are Wed to Sun, 19 Oct starts a week.
    expect(groupWeeks(filled).map((w) => w.length)).toEqual([5, 1]);
    expect(fillGaps([])).toEqual([]);
    expect(fillGaps([sent[0] as DaySummary])).toEqual([sent[0]]);
  });

  test("a span far beyond what the server keeps is not stretched out", () => {
    const filled = fillGaps([day("2020-01-01"), day("2026-01-01")]);
    expect(filled.map((d) => d.day)).toEqual(["2020-01-01", "2026-01-01"]);
  });

  test("the CSV has one row per day, English column names, numbers only", () => {
    const rows = logbookCsv(makeExampleDays().slice(-7)).trim().split("\r\n");
    expect(rows[0]).toBe(CSV_COLUMNS.join(","));
    expect(rows).toHaveLength(8);
    for (const row of rows.slice(1)) {
      const cells = row.split(",");
      expect(cells).toHaveLength(CSV_COLUMNS.length);
      expect(cells[0]).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      for (const cell of cells.slice(1)) expect(cell).toMatch(/^\d+$/);
    }
    // The pinned example week 12 to 18 Oct adds up to the receipt's 28 conversations and 38 things done.
    const week = makeExampleDays().filter((d) => d.day >= "2026-10-12" && d.day <= "2026-10-18");
    const csv = logbookCsv(week).trim().split("\r\n").slice(1).map((r) => r.split(",").map(Number));
    const column = (name: (typeof CSV_COLUMNS)[number]) => CSV_COLUMNS.indexOf(name);
    expect(csv.reduce((s, r) => s + (r[column("conversations")] ?? 0), 0)).toBe(28);
    expect(csv.reduce((s, r) => s + (r[column("things_done")] ?? 0), 0)).toBe(38);
    expect(logbookCsv([])).toBe(`${CSV_COLUMNS.join(",")}\r\n`);
  });

  test("the weekday-by-hour grid holds exactly the conversations", () => {
    const days = makeExampleDays();
    const grid = weekdayHourGrid(days);
    expect(grid).toHaveLength(7);
    expect(grid.every((row) => row.length === 24)).toBe(true);
    expect(grid.flat().reduce((s, n) => s + n, 0)).toBe(sumDays(days).conversations);
    // The example person talks on weekday mornings at 8, so Monday 8:00 has some.
    expect(grid[0]?.[8]).toBeGreaterThan(0);
  });
});

describe("formats", () => {
  const en = makeFormats("en", (key, values) => MESSAGES.en[key].replace(/\{(\w+)\}/g, (_, k: string) => String(values?.[k] ?? `{${k}}`)));
  const pl = makeFormats("pl", (key, values) => MESSAGES.pl[key].replace(/\{(\w+)\}/g, (_, k: string) => String(values?.[k] ?? `{${k}}`)));

  test("durations in both languages", () => {
    expect(en.minutes(52 * 60)).toBe("52 min");
    expect(en.minutes(88 * 60 + 5)).toBe("1 h 28 min");
    expect(pl.minutes(88 * 60 + 5)).toBe("1 godz. 28 min");
    expect(en.minutes(61 * 60)).toBe("1 h 01 min");
    expect(en.average(188)).toBe("3 min 08 s");
    expect(pl.average(45)).toBe("45 s");
  });

  test("ranges, with the month in the form that follows a day number", () => {
    expect(en.range("2026-10-12", "2026-10-18", true)).toBe("12–18 October 2026");
    expect(pl.range("2026-10-12", "2026-10-18", true)).toBe("12–18 października 2026");
    expect(en.range("2026-09-28", "2026-10-04")).toBe("28 Sept – 4 Oct");
    expect(pl.range("2026-10-21", "2026-10-21", true)).toBe("21 paź 2026");
  });

  test("weekday names start on Monday and aren't shifted by the time zone", () => {
    expect(en.weekdayShortByIndex(0)).toBe("Mon");
    expect(pl.weekdayShortByIndex(0)).toBe("pon.");
    expect(en.weekdayLongByIndex(6)).toBe("Sunday");
    expect(pl.dayLong("2026-10-21")).toBe("środa, 21 października");
  });

  test("hours and language names", () => {
    expect(en.hour(8)).toBe("08:00");
    expect(en.hourRange(23)).toBe("23:00–00:00");
    expect(en.language("pl")).toBe("Polish");
    expect(pl.language("pl")).toBe("Polski");
    expect(pl.language("en")).toBe("Angielski");
    expect(en.language("zz")).toBe("zz");
  });
});
