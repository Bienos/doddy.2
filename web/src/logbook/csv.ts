import { sumDays } from "./aggregate.js";
import type { DaySummary } from "./schema.js";

/**
 * The numbers shown for a period as a CSV file: one row per day, counts only, plain English
 * column names so a spreadsheet reads them in any language. There are no words in it that a
 * person said, and no value that isn't a number or a calendar day, so nothing in it can be read
 * as a formula. Every tool's own count is in "Download everything" (the JSON file).
 */
export const CSV_COLUMNS = [
  "day",
  "conversations",
  "seconds_talking",
  "notes_saved",
  "list_items_added",
  "things_done",
  "done_right_away",
  "done_after_yes",
  "asked_first",
  "yes",
  "no",
  "could_not_confirm",
  "did_not_work",
  "tasks_handed_over",
  "translator_sessions",
  "translator_minutes",
] as const;

export function logbookCsv(days: DaySummary[]): string {
  const rows = days.map((day) => {
    const t = sumDays([day]);
    return [
      day.day,
      t.conversations,
      t.seconds,
      t.notesSaved,
      t.listAdded,
      t.done,
      t.doneNow,
      t.doneAfterYes,
      t.asked,
      t.yes,
      t.no,
      t.unsure,
      t.failed,
      t.errands.handedOver,
      t.translator.sessions,
      t.translator.minutes,
    ];
  });
  return `${[CSV_COLUMNS.join(","), ...rows.map((row) => row.join(","))].join("\r\n")}\r\n`;
}
