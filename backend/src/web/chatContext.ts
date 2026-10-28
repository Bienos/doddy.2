import { MEMORY_KEPT_DAYS } from "../memory/contract.js";
import type { MemoryService } from "../memory/service.js";
import type { Store } from "../store.js";
import type { ToolkitView, ToolReceipt, ToolsCatalog } from "../tools/contracts.js";
import { readLogbookView } from "./logbook.js";
import { digestLogbook } from "./logbookDigest.js";
import { DOCUMENT_KEPT_DAYS, documentView } from "./routes.js";

/**
 * What Doddy Web's chat knows about the account besides kept notes and conversations (ADR-604):
 * the same things the iPhone's account has on Doddy's server, read fresh for each question, for
 * the caller's own user id only. Five parts, each one the model can cite by name:
 *  - `logbook`: Logbook's days added up (counts only, ADR-602), when the iPhone has it on;
 *  - `talk`: counts over the conversations kept on the server (ADR-603), from plain columns;
 *  - `apps`: the online accounts, their status and how many of Doddy's tools are on;
 *  - `documents`: the documents Doddy made (name, kind, status, date), kept 7 days;
 *  - `activity`: Doddy's latest receipts (the server's own short summaries).
 * Nothing here is new data: every part is what a page of Doddy Web already shows the person.
 * It is sent to the chat model as JSON data, never as instructions, and never logged.
 */

export const ACCOUNT_PARTS = ["logbook", "talk", "apps", "documents", "activity"] as const;
export type AccountPart = (typeof ACCOUNT_PARTS)[number];

const DOCUMENTS_FOR_CHAT = 15;
const RECEIPTS_FOR_CHAT = 20;

interface ToolsReader {
  catalog(userId: string): Promise<ToolsCatalog>;
  receipts(userId: string): Promise<ToolReceipt[]>;
}

/** What the page shows next to the chat: which parts Doddy can read now. Counts and names, never content. */
export interface ChatContextView {
  /** Whether this server has a chat model at all. */
  ready: boolean;
  memory: { configured: boolean; notes: boolean; conversations: boolean; noteCount: number; conversationCount: number };
  logbook: { enabled: boolean; days: number; updatedAt: string | null };
  apps: { connected: string[]; available: number };
  documents: { count: number };
  activity: { count: number; lastAt: string | null };
}

export class AccountContext {
  constructor(
    private readonly deps: {
      store: Store;
      memory: MemoryService;
      /** Online accounts and receipts. Without it, `apps` and `activity` say "not available". */
      tools: ToolsReader | null;
    },
  ) {}

  /** Each part as JSON-ready data for the model. A part that is off or empty says so in words. */
  async snapshot(userId: string, now: Date, today: string): Promise<Record<AccountPart, unknown>> {
    const [logbook, talk, apps, documents, activity] = await Promise.all([
      this.logbook(userId, now, today),
      this.talk(userId, now),
      this.catalog(userId),
      this.deps.store.listDocuments(userId, DOCUMENTS_FOR_CHAT),
      this.receipts(userId),
    ]);
    const titles = new Map((apps?.toolkits ?? []).map((k) => [k.id, k.title]));
    return {
      logbook,
      talk,
      apps: apps
        ? {
            accounts: apps.toolkits.map((k) => accountLine(k)),
            note: "Doddy asks before every look into an account and before every change.",
          }
        : { state: "not available on this server" },
      documents: {
        keptDays: DOCUMENT_KEPT_DAYS,
        ...(documents.length === 0
          ? { state: "none in the last 7 days" }
          : {
              documents: documents.map((row) => {
                const view = documentView(row, now);
                return { name: view.name, kind: view.kind, status: view.status, made: view.createdAt };
              }),
            }),
      },
      activity: activity
        ? activity.length === 0
          ? { state: "no receipts yet" }
          : {
              receipts: activity.slice(0, RECEIPTS_FOR_CHAT).map((r) => ({
                at: r.timestamp,
                what: r.operation,
                app: titles.get(r.toolkit) ?? r.toolkit,
                ...(r.tool ? { tool: r.tool } : {}),
                outcome: r.status,
                summary: r.summary,
              })),
            }
        : { state: "not available on this server" },
    };
  }

  /** The page's summary of what the chat can read. */
  async view(userId: string, now: Date, ready: boolean): Promise<ChatContextView> {
    const [overview, logbook, apps, documents, receipts] = await Promise.all([
      this.deps.memory.overview(userId),
      readLogbookView(this.deps.store, userId, now),
      this.catalog(userId),
      this.deps.store.listDocuments(userId, 100),
      this.receipts(userId),
    ]);
    // Accounts a person connects; web search (no account) isn't one of them.
    const toolkits = (apps?.toolkits ?? []).filter((k) => k.needsAccount);
    return {
      ready,
      memory: {
        configured: this.deps.memory.isConfigured(),
        notes: overview.notes,
        conversations: overview.conversations,
        noteCount: overview.noteCount,
        conversationCount: overview.conversationCount,
      },
      logbook: { enabled: logbook.enabled, days: logbook.days.length, updatedAt: logbook.updatedAt },
      apps: {
        connected: toolkits.filter((k) => k.status === "connected").map((k) => k.title),
        available: toolkits.filter((k) => k.status !== "unavailable").length,
      },
      documents: { count: documents.length },
      activity: { count: receipts?.length ?? 0, lastAt: receipts?.[0]?.timestamp ?? null },
    };
  }

  private async logbook(userId: string, now: Date, today: string): Promise<unknown> {
    const view = await readLogbookView(this.deps.store, userId, now);
    if (!view.enabled) return { state: "off: Logbook is switched off in the Doddy app on the iPhone, so there are no usage counts" };
    const digest = digestLogbook(view.days, today);
    if (!digest) return { state: "on, but the iPhone hasn't sent any days yet" };
    return { state: "on", keptDays: view.keptDays, lastReceived: view.updatedAt, ...digest };
  }

  private async talk(userId: string, now: Date): Promise<unknown> {
    const state = await this.deps.memory.state(userId);
    if (!state.conversations) return { state: "off: conversations aren't kept on Doddy's server, so there are no counts of them" };
    const since = now.getTime() - MEMORY_KEPT_DAYS * 86_400_000;
    const s = await this.deps.store.memoryConversationStats(userId, since, now.getTime());
    if (s.count === 0) return { state: "on, but no conversations are kept yet" };
    return {
      state: "on",
      keptDays: MEMORY_KEPT_DAYS,
      conversations: s.count,
      turns: s.turns,
      minutes: Math.round(s.seconds / 60),
      averageTurns: Math.round((s.turns / s.count) * 10) / 10,
      averageMinutes: Math.round((s.seconds / 60 / s.count) * 10) / 10,
      first: s.first === null ? null : new Date(s.first).toISOString(),
      last: s.last === null ? null : new Date(s.last).toISOString(),
      last7Days: s.last7Days,
      last30Days: s.last30Days,
    };
  }

  private async catalog(userId: string): Promise<ToolsCatalog | null> {
    return this.deps.tools ? this.deps.tools.catalog(userId) : null;
  }

  private async receipts(userId: string): Promise<ToolReceipt[] | null> {
    return this.deps.tools ? this.deps.tools.receipts(userId) : null;
  }
}

function accountLine(k: ToolkitView) {
  const on = k.tools.filter((t) => t.enabled).length;
  return {
    name: k.title,
    status: k.status === "unavailable" ? "not offered on this server" : k.status,
    ...(k.needsAccount ? {} : { needsAccount: false }),
    ...(k.connectedAt && k.status === "connected" ? { connectedSince: k.connectedAt } : {}),
    toolsSwitchedOn: on,
    toolsTotal: k.tools.length,
  };
}
