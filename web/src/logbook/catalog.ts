/**
 * What Logbook counts, by name (ADR-602, docs/product/WEB_LOGBOOK.md). Tool ids are the voice
 * agent's own (voice-agent/tools.json); what each is called, which app it belongs to, which job it
 * does and whether Doddy asks first come from here. The words are in i18n/logbookMessages.ts.
 * A tool this list doesn't know yet is shown under "Other" with its id, never dropped.
 */

export type AppId =
  | "notes"
  | "reminders"
  | "calendar"
  | "clock"
  | "maps"
  | "lists"
  | "weather"
  | "web"
  | "sums"
  | "gmail"
  | "messages"
  | "claude"
  | "errands"
  | "translator"
  | "other";

export type JobId = "remember" | "plan" | "lists" | "find" | "mail" | "handover" | "translate" | "other";
export type IconName = "note" | "clock" | "list" | "search" | "mail" | "hand" | "translate" | "dots";

export interface ToolInfo {
  app: AppId;
  job: JobId;
  /** Whether Doddy asks first (ASK-01): the yes and no counts only exist for these. */
  ask: boolean;
  /** How often the example person reaches for it (example data only). */
  weight: number;
}

export const TOOLS = {
  save_memory: { app: "notes", job: "remember", ask: false, weight: 8 },
  search_memories: { app: "notes", job: "remember", ask: false, weight: 7 },
  remind_me_about_note: { app: "notes", job: "remember", ask: true, weight: 2 },
  create_reminder: { app: "reminders", job: "plan", ask: true, weight: 6 },
  read_calendar: { app: "calendar", job: "plan", ask: false, weight: 6 },
  create_calendar_event: { app: "calendar", job: "plan", ask: true, weight: 3 },
  find_free_time: { app: "calendar", job: "plan", ask: false, weight: 1 },
  set_timer: { app: "clock", job: "plan", ask: false, weight: 4 },
  set_alarm: { app: "clock", job: "plan", ask: true, weight: 2 },
  start_stopwatch: { app: "clock", job: "plan", ask: true, weight: 0 },
  stop_stopwatch: { app: "clock", job: "plan", ask: true, weight: 0 },
  check_stopwatch: { app: "clock", job: "plan", ask: false, weight: 0 },
  remind_when_to_leave: { app: "maps", job: "plan", ask: false, weight: 1 },
  add_to_list: { app: "lists", job: "lists", ask: false, weight: 7 },
  read_list: { app: "lists", job: "lists", ask: false, weight: 3 },
  check_off: { app: "lists", job: "lists", ask: false, weight: 3 },
  get_weather: { app: "weather", job: "find", ask: false, weight: 8 },
  web_search: { app: "web", job: "find", ask: false, weight: 6 },
  wikipedia_summary: { app: "web", job: "find", ask: false, weight: 2 },
  news_search: { app: "web", job: "find", ask: false, weight: 2 },
  find_places: { app: "maps", job: "find", ask: false, weight: 2 },
  convert_currency: { app: "sums", job: "find", ask: false, weight: 2 },
  calculate: { app: "sums", job: "find", ask: false, weight: 2 },
  check_email: { app: "gmail", job: "mail", ask: false, weight: 3 },
  draft_message: { app: "messages", job: "mail", ask: true, weight: 2 },
  send_email: { app: "gmail", job: "mail", ask: true, weight: 1 },
  ask_claude: { app: "claude", job: "handover", ask: false, weight: 1 },
  make_document: { app: "claude", job: "handover", ask: false, weight: 0.5 },
  hand_over_errand: { app: "errands", job: "handover", ask: true, weight: 0 },
  start_translator: { app: "translator", job: "translate", ask: false, weight: 0 },
} as const satisfies Record<string, ToolInfo>;

export type ToolId = keyof typeof TOOLS;
export const TOOL_IDS = Object.keys(TOOLS) as ToolId[];

export function isKnownTool(id: string): id is ToolId {
  return Object.prototype.hasOwnProperty.call(TOOLS, id);
}

const UNKNOWN_TOOL: ToolInfo = { app: "other", job: "other", ask: false, weight: 0 };

export function toolInfo(id: string): ToolInfo {
  return isKnownTool(id) ? TOOLS[id] : UNKNOWN_TOOL;
}

/** The seven jobs in the order they are listed when counts tie, then "other". */
export const JOBS: { id: JobId; icon: IconName }[] = [
  { id: "remember", icon: "note" },
  { id: "plan", icon: "clock" },
  { id: "lists", icon: "list" },
  { id: "find", icon: "search" },
  { id: "mail", icon: "mail" },
  { id: "handover", icon: "hand" },
  { id: "translate", icon: "translate" },
  { id: "other", icon: "dots" },
];

/** Note types as the app names them (MemoryCategory). Lists are counted under Lists, not here. */
export const KINDS = ["fact", "preference", "commitment", "recommendation", "decision", "item", "place", "intention", "other"] as const;
export type KindId = (typeof KINDS)[number];

export const SOURCES = ["voice", "typed", "shared", "imported"] as const;
export type SourceId = (typeof SOURCES)[number];

export const ENDINGS = ["you", "doddy", "quiet", "dropped"] as const;
export type EndingId = (typeof ENDINGS)[number];

export const LENGTHS = ["under_1", "1_3", "3_5", "5_10"] as const;
export type LengthId = (typeof LENGTHS)[number];

export const WAYS = ["app", "back_tap", "action_button", "widget", "siri", "island"] as const;
export type WayId = (typeof WAYS)[number];
