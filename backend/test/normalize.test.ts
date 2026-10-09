import assert from "node:assert/strict";
import { test } from "node:test";
import { maskLabel, normalizePage, sortEvents } from "../src/calendar.js";
import { ProviderError } from "../src/errors.js";
import { localDayWindow } from "../src/time.js";

const window = localDayWindow("2026-10-10", "Europe/Warsaw");
const page = (items: unknown[], extra: Record<string, unknown> = {}) => ({ successful: true, error: null, data: { items, ...extra } });

test("keeps only title, times and recurrence; drops description, attendees, location, links", () => {
  const result = normalizePage(
    page([
      {
        status: "confirmed",
        summary: "Dentist",
        description: "secret notes",
        location: "Main St 1",
        attendees: [{ email: "x@example.com" }],
        hangoutLink: "https://meet.example/abc",
        start: { dateTime: "2026-10-10T14:00:00+02:00" },
        end: { dateTime: "2026-10-10T14:45:00+02:00" },
      },
    ]),
    window,
    200,
  );
  assert.deepEqual(result.events, [
    { title: "Dentist", allDay: false, start: "2026-10-10T12:00:00.000Z", end: "2026-10-10T12:45:00.000Z", isRecurring: false },
  ]);
  const serialized = JSON.stringify(result);
  for (const leaked of ["secret notes", "Main St", "x@example.com", "meet.example"]) assert.ok(!serialized.includes(leaked), leaked);
});

test("all-day events: kept when they cover the date, dropped when adjacent", () => {
  const result = normalizePage(
    page([
      { summary: "Birthday", start: { date: "2026-10-10" }, end: { date: "2026-10-11" } },
      { summary: "Trip", start: { date: "2026-10-08" }, end: { date: "2026-10-12" } },
      { summary: "Yesterday", start: { date: "2026-10-09" }, end: { date: "2026-10-10" } },
      { summary: "Day after", start: { date: "2026-10-11" }, end: { date: "2026-10-12" } },
    ]),
    window,
    200,
  );
  assert.deepEqual(result.events.map((e) => e.title), ["Birthday", "Trip"]);
  assert.ok(result.events.every((e) => e.allDay));
});

test("timed overlap uses local day bounds: spanning midnight is in, ending at midnight is out", () => {
  const result = normalizePage(
    page([
      { summary: "Night shift", start: { dateTime: "2026-10-09T22:00:00+02:00" }, end: { dateTime: "2026-10-10T06:00:00+02:00" } },
      { summary: "Ends at midnight", start: { dateTime: "2026-10-09T23:00:00+02:00" }, end: { dateTime: "2026-10-10T00:00:00+02:00" } },
      { summary: "Starts next day", start: { dateTime: "2026-10-11T00:00:00+02:00" }, end: { dateTime: "2026-10-11T01:00:00+02:00" } },
    ]),
    window,
    200,
  );
  assert.deepEqual(result.events.map((e) => e.title), ["Night shift"]);
});

test("recurring instances are flagged and cancelled instances are hidden and counted", () => {
  const result = normalizePage(
    page([
      { summary: "Stand-up", recurringEventId: "s1", start: { dateTime: "2026-10-10T09:30:00+02:00" }, end: { dateTime: "2026-10-10T09:45:00+02:00" } },
      { status: "cancelled", summary: "Yoga", recurringEventId: "y1", start: { dateTime: "2026-10-10T18:00:00+02:00" }, end: { dateTime: "2026-10-10T19:00:00+02:00" } },
    ]),
    window,
    200,
  );
  assert.equal(result.events.length, 1);
  assert.equal(result.events[0]!.isRecurring, true);
  assert.equal(result.cancelled, 1);
});

test("titles are bounded, control characters stripped, missing titles labelled", () => {
  const long = "x".repeat(500);
  const result = normalizePage(
    page([
      { summary: long, start: { date: "2026-10-10" }, end: { date: "2026-10-11" } },
      { summary: "a\u0000b\u001b[31m", start: { date: "2026-10-10" }, end: { date: "2026-10-11" } },
      { start: { date: "2026-10-10" }, end: { date: "2026-10-11" } },
    ]),
    window,
    200,
  );
  assert.equal([...result.events[0]!.title].length, 200);
  assert.ok(!/[\u0000-\u001f]/.test(result.events[1]!.title));
  assert.equal(result.events[2]!.title, "(No title)");
});

test("malformed provider results are errors, never empty results", () => {
  const malformed: unknown[] = [
    null,
    "nope",
    { successful: true },
    { successful: true, data: { items: "x" } },
    page([{ summary: "No start" }]),
    page([{ start: { date: "2026-10-10" }, end: { date: "2026-10-10" } }]),
    page([{ start: { dateTime: "not a date" }, end: { dateTime: "2026-10-10T10:00:00Z" } }]),
    page([{ start: { dateTime: "2026-10-10T10:00:00Z" }, end: { dateTime: "2026-10-10T09:00:00Z" } }]),
  ];
  for (const raw of malformed) {
    assert.throws(() => normalizePage(raw, window, 200), (e: unknown) => e instanceof ProviderError && e.code === "malformed_provider_result", JSON.stringify(raw));
  }
  assert.throws(
    () => normalizePage({ successful: false, error: "boom", data: {} }, window, 200),
    (e: unknown) => e instanceof ProviderError && e.code === "provider_unavailable",
  );
});

test("an empty list is a valid result", () => {
  const result = normalizePage(page([]), window, 200);
  assert.deepEqual(result.events, []);
  assert.equal(result.nextPageToken, null);
});

test("sorting puts all-day first, then start time", () => {
  const sorted = sortEvents([
    { title: "b", allDay: false, start: "2026-10-10T10:00:00.000Z", end: "x", isRecurring: false },
    { title: "a", allDay: false, start: "2026-10-10T08:00:00.000Z", end: "x", isRecurring: false },
    { title: "c", allDay: true, start: "2026-10-10", end: "2026-10-11", isRecurring: false },
  ]);
  assert.deepEqual(sorted.map((e) => e.title), ["c", "a", "b"]);
});

test("labels are masked", () => {
  assert.equal(maskLabel("alex.smith@gmail.com"), "a•••@g•••.com");
  assert.equal(maskLabel("Family"), "F•••y");
  assert.equal(maskLabel(null), null);
});
