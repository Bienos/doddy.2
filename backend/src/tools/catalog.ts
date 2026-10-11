import { z } from "zod";
import { ProviderError } from "../errors.js";
import type { ResultItem } from "./contracts.js";

/**
 * Online accounts through Composio: the fixed list of tools Doddy may run. Each tool has a
 * Doddy name (the voice agent's tool name), one Composio tool slug, a strict input schema, the
 * exact arguments sent to Composio, and a normalizer that keeps only a few bounded fields.
 * There is no generic "run any Composio tool" path: anything not listed here is refused.
 *
 * Tool slugs and input/output shapes were read from Composio's tool schemas on 2026-10-10
 * (COMPOSIO_GET_TOOL_SCHEMAS). None of these tools has been run against a real account yet.
 */

export type ToolkitId = "gmail" | "googledrive" | "notion" | "todoist";
export const TOOLKIT_IDS: readonly ToolkitId[] = ["gmail", "googledrive", "notion", "todoist"];

export interface ToolkitDefinition {
  id: ToolkitId;
  title: string;
  /** Composio toolkit slug. */
  composioToolkit: string;
  /** Scopes the Composio auth config should request (set when creating the auth config). */
  requestedScopes: readonly string[];
  /**
   * Granted scopes must all be in this set. `null`: the service has no OAuth scopes Doddy can
   * check (Notion) or Composio's scope report is not relied on (Todoist); documented as such.
   */
  allowedGrants: ReadonlySet<string> | null;
  /** Plain description of what Doddy can do with the account, shown in the app. */
  access: string;
}

const GOOGLE_IDENTITY = [
  "openid",
  "email",
  "profile",
  "https://www.googleapis.com/auth/userinfo.email",
  "https://www.googleapis.com/auth/userinfo.profile",
];
const GMAIL_READONLY = "https://www.googleapis.com/auth/gmail.readonly";
const GMAIL_COMPOSE = "https://www.googleapis.com/auth/gmail.compose";
const DRIVE_METADATA_READONLY = "https://www.googleapis.com/auth/drive.metadata.readonly";
const DRIVE_READONLY = "https://www.googleapis.com/auth/drive.readonly";

export const TOOLKITS: Readonly<Record<ToolkitId, ToolkitDefinition>> = {
  gmail: {
    id: "gmail",
    title: "Gmail",
    composioToolkit: "gmail",
    requestedScopes: [GMAIL_READONLY, GMAIL_COMPOSE],
    allowedGrants: new Set([GMAIL_READONLY, GMAIL_COMPOSE, ...GOOGLE_IDENTITY]),
    access:
      "Doddy can list your recent emails (sender, subject, a short preview) and create drafts after you tap Create. " +
      "Doddy never sends, deletes or labels email. Google's draft permission also allows sending; Doddy has no send tool.",
  },
  googledrive: {
    id: "googledrive",
    title: "Google Drive",
    composioToolkit: "googledrive",
    requestedScopes: [DRIVE_METADATA_READONLY],
    allowedGrants: new Set([DRIVE_METADATA_READONLY, DRIVE_READONLY, ...GOOGLE_IDENTITY]),
    access: "Doddy can find files by name (name, type, last change). It can't open, change, share or delete files.",
  },
  notion: {
    id: "notion",
    title: "Notion",
    composioToolkit: "notion",
    requestedScopes: [],
    allowedGrants: null,
    access: "Doddy can search the titles of pages you shared with it. It doesn't read page content and can't change anything.",
  },
  todoist: {
    id: "todoist",
    title: "Todoist",
    composioToolkit: "todoist",
    requestedScopes: [],
    allowedGrants: null,
    access: "Doddy can list your open tasks and add a task after you tap Add. It can't complete, change or delete tasks.",
  },
};

export type Risk = "read" | "write";

/** What the phone shows before a write. Plain strings only; the app renders them as given. */
export interface ConfirmationPreview {
  title: string;
  lines: string[];
  confirmLabel: string;
}

/** What the agent hears. `text` states only what the provider returned. */
export interface ToolOutcome {
  text: string;
  count: number;
  truncated: boolean;
  /** Listed emails or tasks as data for app screens (ADR-231); no previews or bodies. */
  items?: ResultItem[];
  /** One line for the receipt. No message bodies. */
  summary: string;
  /** Writes: the provider's id for what was made (Gmail draft id, Todoist task id), ADR-303. */
  externalId?: string;
}

export interface Context {
  timeZone: string;
}

export interface CloudToolDefinition {
  name: string;
  toolkit: ToolkitId;
  composioSlug: string;
  risk: Risk;
  /** At least one of these must be granted (Google toolkits). Empty: no scope requirement. */
  requiredAnyGrant: readonly string[];
  input: z.ZodType<Record<string, unknown>>;
  /** Writes are never retried automatically. Reads may retry once on a transient failure. */
  maxRetries: number;
  toArguments(args: Record<string, unknown>): Record<string, unknown>;
  preview?(args: Record<string, unknown>): ConfirmationPreview;
  normalize(raw: unknown, args: Record<string, unknown>, context: Context): ToolOutcome;
  /**
   * Writes (ADR-303): the answer for a repeated run of an approval that already succeeded, built
   * from the same arguments (the server keeps no email or task text) and the provider's id.
   */
  replay?(args: Record<string, unknown>, externalId: string | null): ToolOutcome;
  /**
   * Writes that can be looked for (ADR-303): a read that lists what is there, and whether one
   * listed item is this write. Used only after an earlier try whose outcome is unknown, and only
   * when the user has that read switched on. Found is proof; not found proves nothing.
   */
  findExisting?: { tool: CloudToolDefinition; arguments(args: Record<string, unknown>): Record<string, unknown>; matches(item: ResultItem, args: Record<string, unknown>): boolean };
}

// ------------------------------------------------------------------ helpers

const text = (min: number, max: number) => z.string().trim().min(min).max(max);

/** Keeps the first `max` characters and drops control characters, so nothing odd reaches speech. */
export function clip(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const clean = value.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim();
  if (clean === "") return null;
  return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
}

/** "YYYY-MM-DD HH:MM" in the user's zone, or null for anything that isn't a time. */
export function localTime(value: unknown, timeZone: string): string | null {
  let ms: number;
  if (typeof value === "number") ms = value;
  else if (typeof value === "string" && /^\d{10,13}$/.test(value)) ms = Number(value) < 1e12 ? Number(value) * 1000 : Number(value);
  else if (typeof value === "string") ms = Date.parse(value);
  else return null;
  if (!Number.isFinite(ms)) return null;
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(ms));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")} ${get("hour")}:${get("minute")}`;
}

/** The tool envelope Composio returns: `{successful, data, error}`. Anything else is malformed. */
const Envelope = z.object({ successful: z.boolean(), data: z.unknown(), error: z.unknown().optional() }).passthrough();

function dataOf(raw: unknown): Record<string, unknown> {
  const parsed = Envelope.safeParse(raw);
  if (!parsed.success) throw new ProviderError("malformed_provider_result");
  if (!parsed.data.successful) throw new ProviderError("provider_unavailable");
  const data = parsed.data.data;
  if (typeof data !== "object" || data === null || Array.isArray(data)) throw new ProviderError("malformed_provider_result");
  return data as Record<string, unknown>;
}

/** An optional list field: absent or null means none; anything else that isn't a list is malformed. */
function listOf(data: Record<string, unknown>, key: string): unknown[] {
  const value = data[key];
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new ProviderError("malformed_provider_result");
  return value;
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new ProviderError("malformed_provider_result");
  return value as Record<string, unknown>;
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

// ------------------------------------------------------------------ Gmail

const CheckEmailInput = z
  .object({
    /** Gmail search words, e.g. "from:anna" or "is:unread". Defaults to the inbox. */
    query: text(1, 200).optional(),
    max: z.number().int().min(1).max(10).optional(),
  })
  .strict();

export const CHECK_EMAIL: CloudToolDefinition = {
  name: "check_email",
  toolkit: "gmail",
  composioSlug: "GMAIL_FETCH_EMAILS",
  risk: "read",
  requiredAnyGrant: [GMAIL_READONLY],
  input: CheckEmailInput,
  maxRetries: 1,
  toArguments: (args) => ({
    user_id: "me",
    query: (args.query as string | undefined) ?? "in:inbox",
    max_results: (args.max as number | undefined) ?? 5,
    // Metadata only: Doddy never fetches full bodies or attachments.
    verbose: false,
    include_payload: false,
    include_spam_trash: false,
  }),
  normalize: (raw, args, context) => {
    const data = dataOf(raw);
    const limit = (args.max as number | undefined) ?? 5;
    const messages = listOf(data, "messages").map((m) => {
      const item = record(m);
      const preview = typeof item.preview === "object" && item.preview !== null ? (item.preview as Record<string, unknown>).body : undefined;
      const at = typeof item.messageTimestamp === "string" ? Date.parse(item.messageTimestamp) : Number.NaN;
      return {
        from: clip(item.sender, 80) ?? "unknown sender",
        subject: clip(item.subject, 120) ?? "(no subject)",
        when: localTime(item.messageTimestamp, context.timeZone),
        preview: clip(preview, 140),
        at: Number.isFinite(at) ? at : 0,
      };
    });
    // Composio does not sort by date; newest first here.
    messages.sort((a, b) => b.at - a.at);
    const shown = messages.slice(0, limit);
    if (shown.length === 0) {
      return { text: "No emails matched. Say so; do not guess.", count: 0, truncated: false, items: [], summary: "Checked email: none matched." };
    }
    const items: ResultItem[] = shown.map((m) => ({ kind: "email", title: m.subject, from: m.from, when: m.when, urgent: false }));
    const lines = [`Found ${plural(shown.length, "email")} (newest first; sender, subject, received, preview):`];
    for (const m of shown) {
      lines.push(`- From ${JSON.stringify(m.from)}: ${JSON.stringify(m.subject)}${m.when ? ` (${m.when})` : ""}${m.preview ? ` preview: ${JSON.stringify(m.preview)}` : ""}`);
    }
    return { text: lines.join("\n"), count: shown.length, truncated: messages.length > shown.length, items, summary: `Checked email: ${plural(shown.length, "message")} listed.` };
  },
};

const DraftEmailInput = z
  .object({
    to: z.string().trim().email().max(254),
    subject: text(1, 200),
    body: text(1, 5000),
  })
  .strict();

export const DRAFT_EMAIL: CloudToolDefinition = {
  name: "draft_email",
  toolkit: "gmail",
  composioSlug: "GMAIL_CREATE_EMAIL_DRAFT",
  risk: "write",
  requiredAnyGrant: [GMAIL_COMPOSE],
  input: DraftEmailInput,
  maxRetries: 0,
  toArguments: (args) => ({
    user_id: "me",
    recipient_email: args.to,
    subject: args.subject,
    body: args.body,
    is_html: false,
  }),
  preview: (args) => ({
    title: "Create this Gmail draft?",
    lines: [`To: ${args.to as string}`, `Subject: ${args.subject as string}`, args.body as string],
    confirmLabel: "Create draft",
  }),
  normalize: (raw, args) => {
    const data = dataOf(raw);
    if (typeof data.id !== "string" || data.id === "") throw new ProviderError("malformed_provider_result");
    return { ...draftOutcome(args), externalId: data.id };
  },
  replay: (args, externalId) => ({ ...draftOutcome(args), ...(externalId ? { externalId } : {}) }),
};

function draftOutcome(args: Record<string, unknown>): ToolOutcome {
  return {
    text: `drafted: Gmail draft to ${args.to as string} with subject ${JSON.stringify(args.subject)} was created. It was NOT sent; the user sends it from Gmail.`,
    count: 1,
    truncated: false,
    summary: "Gmail draft created (not sent).",
  };
}

// ------------------------------------------------------------------ Google Drive

/** Drive query strings quote with single quotes; backslash-escape quotes and backslashes. */
export function driveQuoted(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
}

function fileKind(mimeType: unknown): string {
  if (typeof mimeType !== "string") return "file";
  if (mimeType === "application/vnd.google-apps.folder") return "folder";
  if (mimeType === "application/vnd.google-apps.document") return "Google Doc";
  if (mimeType === "application/vnd.google-apps.spreadsheet") return "Google Sheet";
  if (mimeType === "application/vnd.google-apps.presentation") return "Google Slides";
  if (mimeType === "application/pdf") return "PDF";
  if (mimeType.startsWith("image/")) return "image";
  return "file";
}

export const FIND_DRIVE_FILE: CloudToolDefinition = {
  name: "find_drive_file",
  toolkit: "googledrive",
  composioSlug: "GOOGLEDRIVE_FIND_FILE",
  risk: "read",
  requiredAnyGrant: [DRIVE_METADATA_READONLY, DRIVE_READONLY],
  input: z.object({ name: text(1, 100) }).strict(),
  maxRetries: 1,
  toArguments: (args) => ({
    q: `name contains '${driveQuoted(args.name as string)}' and trashed = false`,
    pageSize: 10,
    fields: "files(name,mimeType,modifiedTime),nextPageToken",
  }),
  normalize: (raw, args, context) => {
    const data = dataOf(raw);
    const files = listOf(data, "files").map((f) => {
      const item = record(f);
      return { name: clip(item.name, 120) ?? "Untitled", kind: fileKind(item.mimeType), modified: localTime(item.modifiedTime, context.timeZone) };
    });
    const shown = files.slice(0, 10);
    if (shown.length === 0) {
      return {
        text: `No Drive files with ${JSON.stringify(args.name)} in the name. Say so; do not guess.`,
        count: 0,
        truncated: false,
        summary: "Searched Drive: nothing found.",
      };
    }
    const lines = [`Found ${plural(shown.length, "Drive file")} (name, type, last changed):`];
    for (const f of shown) lines.push(`- ${JSON.stringify(f.name)} (${f.kind}${f.modified ? `, changed ${f.modified}` : ""})`);
    const truncated = files.length > shown.length || typeof data.nextPageToken === "string";
    if (truncated) lines.push("…there may be more. Ask the user for a more specific name if needed.");
    return { text: lines.join("\n"), count: shown.length, truncated, summary: `Searched Drive: ${plural(shown.length, "file")} found.` };
  },
};

// ------------------------------------------------------------------ Notion

/** Page titles live in the one property of type "title"; database titles in `title`. */
function notionTitle(item: Record<string, unknown>): string | null {
  const join = (value: unknown) =>
    Array.isArray(value)
      ? value.map((t) => (typeof t === "object" && t !== null ? (t as { plain_text?: unknown }).plain_text : "")).filter((t) => typeof t === "string").join("")
      : null;
  if (Array.isArray(item.title)) return clip(join(item.title), 120);
  if (typeof item.properties === "object" && item.properties !== null) {
    for (const value of Object.values(item.properties as Record<string, unknown>)) {
      if (typeof value === "object" && value !== null && (value as { type?: unknown }).type === "title") {
        return clip(join((value as { title?: unknown }).title), 120);
      }
    }
  }
  return null;
}

export const SEARCH_NOTION: CloudToolDefinition = {
  name: "search_notion",
  toolkit: "notion",
  composioSlug: "NOTION_SEARCH_NOTION_PAGE",
  risk: "read",
  requiredAnyGrant: [],
  input: z.object({ query: text(1, 100) }).strict(),
  maxRetries: 1,
  toArguments: (args) => ({ query: args.query, page_size: 10, filter_value: "page", filter_property: "object" }),
  normalize: (raw, args, context) => {
    const data = dataOf(raw);
    const pages = listOf(data, "results")
      .map((r) => record(r))
      .filter((r) => r.archived !== true && r.in_trash !== true)
      .map((r) => ({ title: notionTitle(r) ?? "Untitled", edited: localTime(r.last_edited_time, context.timeZone) }));
    const shown = pages.slice(0, 10);
    if (shown.length === 0) {
      return {
        text: `No Notion pages matched ${JSON.stringify(args.query)}. Notion only finds pages shared with Doddy, and new pages can take a while to appear. Say so; do not guess.`,
        count: 0,
        truncated: false,
        summary: "Searched Notion: nothing found.",
      };
    }
    const lines = [`Found ${plural(shown.length, "Notion page")} (titles only; Doddy did not read the pages):`];
    for (const p of shown) lines.push(`- ${JSON.stringify(p.title)}${p.edited ? ` (edited ${p.edited})` : ""}`);
    const truncated = pages.length > shown.length || data.has_more === true;
    if (truncated) lines.push("…there are more matches.");
    return { text: lines.join("\n"), count: shown.length, truncated, summary: `Searched Notion: ${plural(shown.length, "page")} found.` };
  },
};

// ------------------------------------------------------------------ Todoist

/** Todoist filter syntax treats these as operators; a search word keeps letters, digits and spaces. */
export function todoistSearchWord(value: string): string {
  return value.replace(/[&|!()#@,:\\*]/g, " ").replace(/\s+/g, " ").trim();
}

const WHEN_FILTER: Record<string, string | undefined> = { today: "today | overdue", overdue: "overdue", upcoming: "7 days", all: undefined };

export const LIST_TODOIST_TASKS: CloudToolDefinition = {
  name: "list_todoist_tasks",
  toolkit: "todoist",
  composioSlug: "TODOIST_GET_ALL_TASKS",
  risk: "read",
  requiredAnyGrant: [],
  input: z
    .object({
      when: z.enum(["today", "overdue", "upcoming", "all"]).optional(),
      search: text(1, 60).optional(),
    })
    .strict(),
  maxRetries: 1,
  toArguments: (args) => {
    const parts: string[] = [];
    const when = WHEN_FILTER[(args.when as string | undefined) ?? "today"];
    if (when) parts.push(`(${when})`);
    const word = typeof args.search === "string" ? todoistSearchWord(args.search) : "";
    if (word) parts.push(`search: ${word}`);
    return { limit: 20, ...(parts.length > 0 ? { filter: parts.join(" & ") } : {}) };
  },
  normalize: (raw, args) => {
    const data = dataOf(raw);
    const tasks = listOf(data, "tasks").map((t) => {
      const item = record(t);
      const due = typeof item.due === "object" && item.due !== null ? (item.due as Record<string, unknown>) : null;
      return {
        content: clip(item.content, 120) ?? "Untitled task",
        due: due ? clip(due.string, 40) ?? clip(due.date, 25) : null,
        // Todoist's API counts 4 as the most urgent (shown as p1 in the app).
        urgent: item.priority === 4,
      };
    });
    const shown = tasks.slice(0, 15);
    const which = (args.when as string | undefined) ?? "today";
    if (shown.length === 0) {
      return { text: `No open Todoist tasks for ${which}. Say so; do not guess.`, count: 0, truncated: false, items: [], summary: "Checked Todoist: no open tasks." };
    }
    const items: ResultItem[] = shown.map((t) => ({ kind: "task", title: t.content, from: null, when: t.due, urgent: t.urgent }));
    const lines = [`Found ${plural(shown.length, "open Todoist task")} (${which}):`];
    for (const t of shown) lines.push(`- ${JSON.stringify(t.content)}${t.due ? ` due ${t.due}` : ""}${t.urgent ? " (priority 1)" : ""}`);
    const truncated = tasks.length > shown.length || typeof data.next_cursor === "string";
    if (truncated) lines.push("…and more in Todoist.");
    return { text: lines.join("\n"), count: shown.length, truncated, items, summary: `Checked Todoist: ${plural(shown.length, "task")} listed.` };
  },
};

export const ADD_TODOIST_TASK: CloudToolDefinition = {
  name: "add_todoist_task",
  toolkit: "todoist",
  composioSlug: "TODOIST_CREATE_TASK",
  risk: "write",
  requiredAnyGrant: [],
  input: z
    .object({
      content: text(1, 300),
      /** Todoist's own words for dates, e.g. "tomorrow 9am" or "every Friday". */
      due: text(1, 60).optional(),
      /** Language of `due` when it isn't English, e.g. "pl". */
      due_lang: z.enum(["en", "pl", "de", "fr", "es", "it", "nl", "pt"]).optional(),
    })
    .strict(),
  maxRetries: 0,
  toArguments: (args) => ({
    content: args.content,
    ...(args.due ? { due_string: args.due } : {}),
    ...(args.due && args.due_lang && args.due_lang !== "en" ? { due_lang: args.due_lang } : {}),
  }),
  preview: (args) => ({
    title: "Add this Todoist task?",
    lines: [args.content as string, ...(args.due ? [`Due: ${args.due as string}`] : ["No due date"])],
    confirmLabel: "Add task",
  }),
  normalize: (raw, args) => {
    const data = dataOf(raw);
    if (typeof data.id !== "string" || data.id === "") throw new ProviderError("malformed_provider_result");
    const due = typeof data.due === "object" && data.due !== null ? (data.due as Record<string, unknown>) : null;
    const dueText = due ? clip(due.string, 40) ?? clip(due.date, 25) : null;
    const content = clip(data.content, 300) ?? (args.content as string);
    return { ...taskOutcome(content, dueText), externalId: data.id };
  },
  replay: (args, externalId) => ({
    ...taskOutcome(args.content as string, (args.due as string | undefined) ?? null),
    ...(externalId ? { externalId } : {}),
  }),
  findExisting: {
    tool: LIST_TODOIST_TASKS,
    arguments: (args) => ({ when: "all", search: todoistSearchWord(args.content as string).slice(0, 60) || undefined }),
    matches: (item, args) => sameWords(item.title, args.content as string),
  },
};

function taskOutcome(content: string, due: string | null): ToolOutcome {
  return {
    text: `added: Todoist task ${JSON.stringify(content)}${due ? ` due ${due}` : " with no due date"}.`,
    count: 1,
    truncated: false,
    summary: "Todoist task added.",
  };
}

/** The same words, ignoring case and spacing; a listed title is clipped at 120 characters. */
function sameWords(listed: string, content: string): boolean {
  const fold = (value: string) => value.toLocaleLowerCase().replace(/\s+/g, " ").trim();
  return fold(listed) === fold(clip(content, 120) ?? "");
}

export const CLOUD_TOOLS: readonly CloudToolDefinition[] = [
  CHECK_EMAIL,
  DRAFT_EMAIL,
  FIND_DRIVE_FILE,
  SEARCH_NOTION,
  LIST_TODOIST_TASKS,
  ADD_TODOIST_TASK,
];

/** What Settings shows for each switch. Plain words about what the tool does and does not do. */
export const TOOL_COPY: Readonly<Record<string, { title: string; blurb: string }>> = {
  check_email: { title: "Check my email", blurb: "Lists your newest emails: sender, subject and a short preview. Doddy doesn't open full messages." },
  draft_email: { title: "Draft an email", blurb: "Creates a draft in Gmail after you tap Create on the card. Doddy never sends it." },
  find_drive_file: { title: "Find a Drive file", blurb: "Looks up files by name and shows name, type and last change. It can't open or change files." },
  search_notion: { title: "Search Notion", blurb: "Finds page titles shared with Doddy. It doesn't read the pages." },
  list_todoist_tasks: { title: "List my tasks", blurb: "Lists your open Todoist tasks, for example what's due today." },
  add_todoist_task: { title: "Add a task", blurb: "Adds a Todoist task after you tap Add on the card." },
};

export function cloudTool(name: string): CloudToolDefinition | undefined {
  return CLOUD_TOOLS.find((t) => t.name === name);
}

export type GrantVerdict = "ok" | "missing" | "too_broad" | "unverifiable";

/**
 * Google toolkits must prove their grants: every granted scope is in the allowlist. For a tool,
 * at least one of its required scopes must also be present. Toolkits without an allowlist pass.
 */
export function evaluateToolkitGrant(toolkit: ToolkitDefinition, granted: readonly string[] | null): GrantVerdict {
  if (toolkit.allowedGrants === null) return "ok";
  if (granted === null) return "unverifiable";
  return granted.every((s) => toolkit.allowedGrants!.has(s)) ? "ok" : "too_broad";
}

export function toolHasGrant(tool: CloudToolDefinition, granted: readonly string[] | null): boolean {
  if (tool.requiredAnyGrant.length === 0) return true;
  return granted !== null && tool.requiredAnyGrant.some((s) => granted.includes(s));
}
