import assert from "node:assert/strict";
import { test } from "node:test";
import { isSupportedTimeZone, isValidDateString, localDayWindow, rfc3339Local } from "../src/time.js";

const hours = (w: { startMs: number; endMs: number }) => (w.endMs - w.startMs) / 3_600_000;

test("ordinary day is 24 h from local midnight to local midnight", () => {
  const w = localDayWindow("2026-10-10", "Europe/Warsaw");
  assert.equal(rfc3339Local(w.startMs, w.timeZone), "2026-10-10T00:00:00+02:00");
  assert.equal(rfc3339Local(w.endMs, w.timeZone), "2026-10-11T00:00:00+02:00");
  assert.equal(hours(w), 24);
});

test("DST end (autumn) makes tomorrow 25 h long", () => {
  const w = localDayWindow("2026-10-25", "Europe/Warsaw");
  assert.equal(rfc3339Local(w.startMs, w.timeZone), "2026-10-25T00:00:00+02:00");
  assert.equal(rfc3339Local(w.endMs, w.timeZone), "2026-10-26T00:00:00+01:00");
  assert.equal(hours(w), 25);
});

test("DST start (spring) makes the day 23 h long", () => {
  assert.equal(hours(localDayWindow("2026-03-29", "Europe/Warsaw")), 23);
  assert.equal(hours(localDayWindow("2026-03-08", "America/New_York")), 23);
});

test("when midnight is skipped the day starts at the transition (01:00 local)", () => {
  // Brazil started DST at 00:00 on 2018-11-04: clocks jumped from 00:00 to 01:00.
  const w = localDayWindow("2018-11-04", "America/Sao_Paulo");
  assert.equal(rfc3339Local(w.startMs, w.timeZone), "2018-11-04T01:00:00-02:00");
  assert.equal(hours(w), 23);
});

test("a skipped calendar date produces an empty window, not a wrong day", () => {
  // Samoa skipped 30 December 2011 entirely.
  const w = localDayWindow("2011-12-30", "Pacific/Apia");
  assert.equal(w.endMs - w.startMs, 0);
});

test("negative offsets and UTC", () => {
  const la = localDayWindow("2026-10-10", "America/Los_Angeles");
  assert.equal(rfc3339Local(la.startMs, la.timeZone), "2026-10-10T00:00:00-07:00");
  const utc = localDayWindow("2026-10-10", "UTC");
  assert.equal(new Date(utc.startMs).toISOString(), "2026-10-10T00:00:00.000Z");
  const kolkata = localDayWindow("2026-10-10", "Asia/Kolkata");
  assert.equal(rfc3339Local(kolkata.startMs, kolkata.timeZone), "2026-10-10T00:00:00+05:30");
});

test("only IANA zone names and real dates are accepted", () => {
  for (const tz of ["Europe/Warsaw", "UTC", "America/Argentina/Buenos_Aires"]) assert.ok(isSupportedTimeZone(tz), tz);
  for (const tz of ["+02:00", "UTC+2", "PST", "CEST", "Mars/Olympus", "", "../../etc/passwd"]) assert.ok(!isSupportedTimeZone(tz), tz);
  assert.ok(isValidDateString("2028-02-29"));
  for (const d of ["2026-02-29", "2026-13-01", "2026-1-01", "tomorrow"]) assert.ok(!isValidDateString(d), d);
});
