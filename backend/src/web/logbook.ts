import { z } from "zod";
import { AppError } from "../errors.js";
import type { Store } from "../store.js";

/**
 * Logbook, the server's half (ADR-602, docs/product/WEB_LOGBOOK.md): one day's summary of how a
 * person used Doddy, as the iPhone sends it. Counts only. The shape is an allow-list in code: every
 * object is strict, every value is a whole number in range, and the only names that can appear as
 * keys are Doddy's own tool ids, a note's nine types and short language codes. A word anyone said
 * has nowhere to go, so a request that carries one is refused whole and nothing is stored.
 *
 * The web app has the same contract in web/src/logbook/schema.ts; the fixtures in contracts/web/
 * (written from this server's own replies) are what both are tested against.
 */

/** How long days are kept, counted back from today. The sweep deletes older ones. */
export const LOGBOOK_KEPT_DAYS = 365;
/** A day with every tool in use is about 7 KB; a body above this is not a summary. */
export const LOGBOOK_MAX_BODY_BYTES = 16 * 1024;
export const LOGBOOK_SCHEMA = "doddy.logbook.day.v1";

/**
 * The voice agent's tool ids (voice-agent/tools.json, 100 today). A test reads that file and fails
 * if this list and the file disagree, so a new tool can't be counted before it is listed here.
 */
export const LOGBOOK_TOOL_IDS = [
  "search_memories", "save_memory", "read_calendar", "find_free_time", "create_calendar_event", "create_reminder",
  "change_calendar_event", "change_reminder", "delete_calendar_event", "delete_reminder", "undo_last",
  "delete_calendar_events", "move_reminders", "remind_me_about_note", "lookup_contact", "upcoming_birthdays",
  "calculate", "convert_units", "convert_currency", "set_timer", "set_alarm", "start_stopwatch", "stop_stopwatch",
  "check_stopwatch", "list_alarms", "cancel_alarm",
  "propose_plan", "open_map", "parking_spot", "remind_when_to_leave", "run_shortcut", "draft_message",
  "draft_blik_transfer", "make_presentation", "read_steps", "read_health_week", "open_training_plan", "find_photos", "open_camera", "check_email",
  "read_email", "draft_email", "draft_email_reply", "send_email", "reply_to_email", "forward_email", "change_email",
  "trash_email", "find_drive_file", "create_drive_doc", "search_notion", "read_notion_page", "create_notion_page",
  "append_notion_page", "trash_notion_page", "check_outlook_email", "read_outlook_email", "draft_outlook_email",
  "read_outlook_calendar", "read_google_calendar", "create_google_event", "change_google_event",
  "delete_google_event", "answer_google_invite", "create_outlook_event", "change_outlook_event",
  "delete_outlook_event", "accept_outlook_invite", "decline_outlook_invite", "send_outlook_email",
  "reply_outlook_email", "forward_outlook_email", "move_outlook_email", "mark_outlook_email", "list_todoist_tasks",
  "add_todoist_task", "complete_todoist_task", "move_todoist_task", "rename_todoist_task", "web_search",
  "geocode_place", "get_weather", "wikipedia_search", "wikipedia_summary", "news_search", "find_places",
  "start_translator", "stop_translator", "add_to_list", "add_ingredients", "read_list", "check_off",
  "remove_from_list", "create_list", "hand_over_errand", "check_errands", "find_deals", "note_capability_gap", "ask_claude",
  "make_document",
] as const;

const LENGTHS = ["under_1", "1_3", "3_5", "5_10"] as const;
const ENDINGS = ["you", "doddy", "quiet", "dropped"] as const;
const WAYS = ["app", "back_tap", "action_button", "widget", "siri", "island"] as const;
const SOURCES = ["voice", "typed", "shared", "imported"] as const;
const KINDS = ["fact", "preference", "commitment", "recommendation", "decision", "item", "place", "intention", "other"] as const;

const count = z.number().int().min(0).max(10_000);
const seconds = z.number().int().min(0).max(86_400);

const named = <K extends readonly [string, ...string[]]>(keys: K) =>
  z.object(Object.fromEntries(keys.map((key) => [key, count])) as Record<K[number], typeof count>).strict();

const Outcomes = z
  .object({ done: count.default(0), declined: count.default(0), unsure: count.default(0), failed: count.default(0), undone: count.default(0) })
  .strict();

const sum = (values: Record<string, number>) => Object.values(values).reduce((total, n) => total + n, 0);

export const DaySummarySchema = z
  .object({
    schema: z.literal(LOGBOOK_SCHEMA),
    day: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/)
      .refine((day) => new Date(`${day}T00:00:00Z`).toISOString().slice(0, 10) === day, "not a calendar day"),
    conversations: z
      .object({
        count,
        seconds,
        by_hour: z.array(count).length(24),
        lengths: named(LENGTHS),
        ended: named(ENDINGS),
        languages: z.record(z.string().regex(/^[a-z]{2,3}(-[A-Za-z]{2,4})?$/), count).refine((v) => Object.keys(v).length <= 12, "too many languages"),
        ways_in: named(WAYS),
      })
      .strict(),
    tools: z.record(z.enum(LOGBOOK_TOOL_IDS), Outcomes),
    notes: z
      .object({
        by_source: named(SOURCES),
        by_kind: z.record(z.enum(KINDS), count),
        edited: count,
      })
      .strict(),
    lists: z.object({ added_voice: count, added_typed: count, ticked: count }).strict(),
    errands: z.object({ handed_over: count, finished: count, stopped: count, minutes: count, searches: count, pages: count }).strict(),
    translator: z.object({ sessions: count, minutes: count }).strict(),
  })
  .strict()
  .superRefine((day, ctx) => {
    const c = day.conversations;
    const expect = (ok: boolean, path: (string | number)[], message: string) => ok || ctx.addIssue({ code: "custom", path, message });
    // Every conversation has one hour, one length and one ending; language and way in may be unknown.
    expect(sum(Object.fromEntries(c.by_hour.map((n, h) => [h, n]))) === c.count, ["conversations", "by_hour"], "hours must add up to the count");
    expect(sum(c.lengths) === c.count, ["conversations", "lengths"], "lengths must add up to the count");
    expect(sum(c.ended) === c.count, ["conversations", "ended"], "endings must add up to the count");
    expect(sum(c.languages) <= c.count, ["conversations", "languages"], "languages can't exceed the count");
    expect(sum(c.ways_in) <= c.count, ["conversations", "ways_in"], "ways in can't exceed the count");
    expect(day.errands.finished + day.errands.stopped <= day.errands.handed_over, ["errands"], "finished and stopped can't exceed handed over");
  });
export type DaySummary = z.output<typeof DaySummarySchema>;

/** What the iPhone sends to turn Logbook on or off. Off deletes every stored day. */
export const LogbookStateSchema = z.object({ enabled: z.boolean() }).strict();

/** What the page reads: the state, how long days are kept, when the iPhone last sent one, and the days (oldest first). */
export const LogbookViewSchema = z
  .object({
    enabled: z.boolean(),
    keptDays: z.number().int().positive(),
    updatedAt: z.string().nullable(),
    days: z.array(DaySummarySchema).max(LOGBOOK_KEPT_DAYS + 2),
  })
  .strict();
export type LogbookView = z.output<typeof LogbookViewSchema>;

const SECTIONS = new Set(["schema", "day", "conversations", "tools", "notes", "lists", "errands", "translator"]);
const DAY_MS = 86_400_000;
export const isoDay = (ms: number) => new Date(ms).toISOString().slice(0, 10);

/** The oldest day kept at `now` (UTC calendar days, like the sweep). */
export const oldestKeptDay = (now: number) => isoDay(now - LOGBOOK_KEPT_DAYS * DAY_MS);

/**
 * What the page reads, and what the chat adds up (ADR-604). A row that no longer parses is left
 * out, never shown half-read.
 */
export async function readLogbookView(
  store: Pick<Store, "logbookEnabled" | "logbookDays">,
  userId: string,
  now: Date,
): Promise<LogbookView> {
  const enabled = await store.logbookEnabled(userId);
  const rows = enabled ? await store.logbookDays(userId, oldestKeptDay(now.getTime())) : [];
  const days: DaySummary[] = [];
  for (const row of rows) {
    try {
      const parsed = DaySummarySchema.safeParse(JSON.parse(row.summary));
      if (parsed.success) days.push(parsed.data);
    } catch {
      // Not JSON: skipped like any unreadable row.
    }
  }
  const latest = rows.reduce((max, row) => Math.max(max, row.received_at), 0);
  return { enabled, keptDays: LOGBOOK_KEPT_DAYS, updatedAt: latest > 0 ? new Date(latest).toISOString() : null, days };
}

/**
 * A day the iPhone may send: a real calendar day inside the kept window, no further ahead than
 * tomorrow (a phone east of UTC is already on the next date), and the one named in the address.
 * A refusal says which field, never its value.
 */
export function parseDaySummary(body: unknown, pathDay: string, now: number): DaySummary {
  const parsed = DaySummarySchema.safeParse(body);
  if (!parsed.success) {
    // Only a section's name, never a deeper path: an unknown key under "tools" is whatever was sent.
    const fields = [...new Set(parsed.error.issues.map((issue) => (SECTIONS.has(String(issue.path[0])) ? String(issue.path[0]) : "the summary as a whole")))].slice(0, 3);
    throw new AppError("invalid_request", { message: `The Logbook summary wasn't valid (${fields.join(", ")}). Nothing was stored.` });
  }
  const day = parsed.data;
  if (day.day !== pathDay) throw new AppError("invalid_request", { message: "The day in the summary isn't the day in the address. Nothing was stored." });
  if (day.day < oldestKeptDay(now) || day.day > isoDay(now + DAY_MS)) {
    throw new AppError("invalid_request", { message: `Logbook keeps ${LOGBOOK_KEPT_DAYS} days, up to tomorrow. Nothing was stored.` });
  }
  return day;
}
