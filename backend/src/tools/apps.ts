import { z } from "zod";
import { AppError } from "../errors.js";
import { isValidDateString } from "../time.js";
import { CLOUD_TOOLS, type CloudToolDefinition, cloudTool, TOOLKIT_IDS, TOOLKITS, type ToolkitId } from "./catalog.js";

/**
 * Generic app tools (ADR-699, milestone A1; docs/architecture/ANY_APP_CONNECTIONS_PROPOSAL.md).
 *
 * Two voice-facing tools, `find_in_app` and `read_from_app`, take the app as an argument instead of
 * one tool per app. They are a thin, reviewed mapping onto the hand-built tools in catalog.ts:
 * the registry below says which existing READ tool answers a generic call for which app, and how
 * the generic words become that tool's own strict arguments. After the mapping the existing path
 * runs unchanged: tool switch, account and grant checks, ASK-01 approval bound to the translated
 * arguments, caps, normalizer, receipt. Nothing here reaches the provider, knows a Composio slug, or
 * can run a tool that is not listed.
 *
 * Only tools with risk "read" can be registered (checked when the module loads and in tests), so a
 * generic call can never become a write. Writes stay on their own named tools and their tap cards.
 *
 * A1 limits, deliberately: the apps are the toolkits already in catalog.ts (Gmail and Google
 * Calendar are the pilot); no new app can be added from data alone yet; no voice-agent change.
 */

export const FIND_IN_APP = "find_in_app";
export const READ_FROM_APP = "read_from_app";
export type AppsToolName = typeof FIND_IN_APP | typeof READ_FROM_APP;
export const isAppsTool = (name: string): name is AppsToolName => name === FIND_IN_APP || name === READ_FROM_APP;

// ------------------------------------------------------------------ registry

/** Turns the generic words into the mapped tool's arguments, or null when they can't be used. */
type Translate = (query: string) => Record<string, unknown> | null;

export interface AppRoleEntry {
  /** The existing tool that answers this role. Must be a read. */
  tool: string;
  translate: Translate;
  /** Said to the agent when `translate` returns null. */
  usage: string;
}

export interface AppEntry {
  app: ToolkitId;
  find?: AppRoleEntry;
  read?: AppRoleEntry;
}

/** "2026-11-04" is that day; "2026-11-04..2026-11-06" is a range. Anything else is refused. */
const calendarRange: Translate = (query) => {
  const [from, to, ...rest] = query.split("..").map((part) => part.trim());
  if (from === undefined || rest.length > 0) return null;
  const end = to === undefined ? from : to;
  return isValidDateString(from) && isValidDateString(end) ? { from, to: end } : null;
};

export const APP_REGISTRY: readonly AppEntry[] = [
  {
    app: "gmail",
    find: {
      tool: "check_email",
      translate: (query) => ({ query }),
      usage: "Pass Gmail search words, for example from:anna or is:unread.",
    },
    read: {
      tool: "read_email",
      translate: (query) => ({ query }),
      usage: "Pass Gmail search words that pick one email, for example from:marta subject:invoice.",
    },
  },
  {
    app: "gcalendar",
    find: {
      tool: "read_google_calendar",
      translate: calendarRange,
      usage: "Pass a day as YYYY-MM-DD, or a range as YYYY-MM-DD..YYYY-MM-DD (at most 31 days).",
    },
  },
];

/** Apps the generic tools accept: only those in the registry. */
export const APP_IDS: readonly ToolkitId[] = APP_REGISTRY.map((entry) => entry.app);

export interface RegistryProblem {
  app: string;
  role: "find" | "read";
  problem: string;
}

/**
 * Every entry must name an existing tool of the same app whose risk is "read". Run when the module
 * loads (a bad registry stops the server and the tests), and directly by tests with bad entries.
 */
export function registryProblems(entries: readonly AppEntry[], lookup: (name: string) => CloudToolDefinition | undefined = cloudTool): RegistryProblem[] {
  const problems: RegistryProblem[] = [];
  const seen = new Set<string>();
  for (const entry of entries) {
    if (seen.has(entry.app)) problems.push({ app: entry.app, role: "find", problem: "the app is listed twice" });
    seen.add(entry.app);
    if (!(TOOLKIT_IDS as readonly string[]).includes(entry.app)) problems.push({ app: entry.app, role: "find", problem: "not a known toolkit" });
    for (const role of ["find", "read"] as const) {
      const mapped = entry[role];
      if (!mapped) continue;
      const tool = lookup(mapped.tool);
      if (!tool) problems.push({ app: entry.app, role, problem: `tool ${mapped.tool} does not exist` });
      else if (tool.toolkit !== entry.app) problems.push({ app: entry.app, role, problem: `tool ${mapped.tool} belongs to ${tool.toolkit}` });
      else if (tool.risk !== "read") problems.push({ app: entry.app, role, problem: `tool ${mapped.tool} is not a read` });
    }
  }
  return problems;
}

{
  const problems = registryProblems(APP_REGISTRY);
  if (problems.length > 0) throw new Error(`invalid app registry: ${problems.map((p) => `${p.app}/${p.role}: ${p.problem}`).join("; ")}`);
}

// ------------------------------------------------------------------ the two generic tools

const AppId = z.enum(APP_IDS as [string, ...string[]]);
const GenericInput = z.object({ app: AppId, query: z.string().trim().min(1).max(200) }).strict();

export interface TranslatedCall {
  /** The existing tool that will really run. */
  tool: string;
  arguments: Record<string, unknown>;
}

/**
 * The call a generic request stands for. Throws invalid_request for unknown apps, apps with no such
 * role, extra fields, and words the mapped tool can't use. The result still goes through that
 * tool's own strict input schema, so nothing the mapping builds is trusted on its own.
 */
export function translateAppsCall(name: AppsToolName, args: Record<string, unknown>): TranslatedCall {
  const parsed = GenericInput.safeParse(args);
  if (!parsed.success) throw new AppError("invalid_request", { message: "Pass the app and what to look for, and nothing else." });
  const role = name === FIND_IN_APP ? "find" : "read";
  const entry = APP_REGISTRY.find((e) => e.app === parsed.data.app);
  const mapped = entry?.[role];
  if (!mapped) {
    throw new AppError("invalid_request", {
      message: `${TOOLKITS[parsed.data.app as ToolkitId].title} can't be used with ${name}.`,
    });
  }
  const translated = mapped.translate(parsed.data.query);
  if (translated === null) throw new AppError("invalid_request", { message: mapped.usage });
  return { tool: mapped.tool, arguments: translated };
}

// ------------------------------------------------------------------ access per app

export const APP_ACCESS_MODES = ["off", "read", "act"] as const;
export type AppAccess = (typeof APP_ACCESS_MODES)[number];

/** One choice per app instead of a switch per tool. `app` can be any account toolkit. */
export const AccessRequestSchema = z
  .object({ app: z.enum(TOOLKIT_IDS as [string, ...string[]]), mode: z.enum(APP_ACCESS_MODES) })
  .strict();

export const appTools = (app: ToolkitId): CloudToolDefinition[] => CLOUD_TOOLS.filter((tool) => tool.toolkit === app);

/** The tools that should be on for a mode: off none, read every read, act every tool of the app. */
export function toolsForAccess(app: ToolkitId, mode: AppAccess): { on: string[]; off: string[] } {
  const all = appTools(app);
  const wanted = (tool: CloudToolDefinition) => mode === "act" || (mode === "read" && tool.risk === "read");
  return { on: all.filter(wanted).map((t) => t.name), off: all.filter((t) => !wanted(t)).map((t) => t.name) };
}

/**
 * The mode a set of switches amounts to: act if any write is on, else read if any read is on, else
 * off. A hand-made mix (a few reads only) reads as "read", the nearest of the three.
 */
export function accessOf(app: ToolkitId, enabled: ReadonlySet<string>): AppAccess {
  const tools = appTools(app).filter((tool) => enabled.has(tool.name));
  if (tools.some((tool) => tool.risk === "write")) return "act";
  return tools.length > 0 ? "read" : "off";
}
