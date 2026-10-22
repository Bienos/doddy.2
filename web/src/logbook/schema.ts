import { z } from "zod";
import { ENDINGS, KINDS, LENGTHS, SOURCES, WAYS } from "./catalog.js";

/**
 * One day's summary, as the iPhone will send it and the server will keep it (ADR-593,
 * docs/product/WEB_LOGBOOK.md, "The daily summary"): whole numbers and fixed names, never a word
 * anyone said. Every object is strict, so a field this list doesn't name is refused rather than
 * shown, and a text where a number belongs is refused too. Tool ids only need the shape of an id
 * here; the server holds the real allow-list.
 */

const count = z.number().int().min(0).max(10_000);
const secondsInADay = z.number().int().min(0).max(86_400);

const byName = <K extends readonly [string, ...string[]]>(keys: K) =>
  z.object(Object.fromEntries(keys.map((key) => [key, count])) as Record<K[number], typeof count>).strict();

const Outcomes = z
  .object({
    done: count.default(0),
    declined: count.default(0),
    unsure: count.default(0),
    failed: count.default(0),
    undone: count.default(0),
  })
  .strict();

const ToolId = z.string().regex(/^[a-z][a-z0-9_]{2,47}$/);
const LanguageCode = z.string().regex(/^[a-z]{2,3}(-[A-Za-z]{2,4})?$/);

export const DaySummary = z
  .object({
    schema: z.literal("doddy.logbook.day.v1"),
    day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    conversations: z
      .object({
        count,
        seconds: secondsInADay,
        by_hour: z.array(count).length(24),
        lengths: byName(LENGTHS),
        ended: byName(ENDINGS),
        languages: z.record(LanguageCode, count),
        ways_in: byName(WAYS),
      })
      .strict(),
    tools: z.record(ToolId, Outcomes),
    notes: z
      .object({
        by_source: byName(SOURCES),
        by_kind: z.record(z.enum(KINDS), count),
        edited: count,
      })
      .strict(),
    lists: z.object({ added_voice: count, added_typed: count, ticked: count }).strict(),
    errands: z.object({ handed_over: count, finished: count, stopped: count, minutes: count, searches: count, pages: count }).strict(),
    translator: z.object({ sessions: count, minutes: count }).strict(),
  })
  .strict();

export type DaySummary = z.output<typeof DaySummary>;
export type ToolOutcomes = z.output<typeof Outcomes>;

/** What a Logbook reply holds: the days, oldest first, and when the iPhone last sent them. */
export const LogbookDays = z.object({ days: z.array(DaySummary).max(400), updatedAt: z.string().nullable() }).strict();
export type LogbookDays = z.output<typeof LogbookDays>;

/**
 * What GET /v1/web/logbook answers (backend/src/web/logbook.ts, LogbookViewSchema): whether the
 * iPhone has Logbook on, how long days are kept, when it last sent one, and the days. Days stay
 * strict; the envelope drops fields a newer server may add.
 */
export const LogbookView = z.object({
  enabled: z.boolean(),
  keptDays: z.number().int().positive(),
  updatedAt: z.string().nullable(),
  days: z.array(DaySummary).max(400),
});
export type LogbookView = z.output<typeof LogbookView>;

/** What DELETE /v1/web/logbook answers: how many stored days it removed. */
export const LogbookDeleted = z.object({ deletedDays: z.number().int().nonnegative() });
