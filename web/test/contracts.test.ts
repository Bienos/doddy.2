import { describe, expect, test } from "vitest";
import { CurrentSession, DocumentList, ErrorBody, ReceiptList, SessionList, ToolsCatalog } from "../src/api/schemas.js";
import { LogbookDeleted, LogbookView } from "../src/logbook/schema.js";
import { ChatReply, ConversationDeleted, ConversationDetail, ConversationList, MemoryDeleted, MemoryOverview, NotesList } from "../src/memory/schema.js";
import { fixture } from "./fakeServer.js";

/** The server writes these files from its own replies (backend: npm run fixtures:web / fixtures). */
describe("the page reads what the server actually sends", () => {
  test("web sign-in and sessions", () => {
    expect(CurrentSession.parse(fixture("web/session-signed-in")).session.current).toBe(true);
    expect(CurrentSession.parse(fixture("web/session-current")).session.browser).toBe("chrome");
    expect(SessionList.parse(fixture("web/sessions-phone")).sessions[0]?.current).toBe(false);
    expect(ErrorBody.parse(fixture("web/error-code-invalid")).error.code).toBe("unauthenticated");
    expect(ErrorBody.parse(fixture("web/error-signed-out")).error.code).toBe("unauthenticated");
  });

  test("documents in every state", () => {
    expect(DocumentList.parse(fixture("web/documents-empty")).documents).toEqual([]);
    expect(DocumentList.parse(fixture("web/documents-working")).documents.map((d) => d.status)).toEqual(["working", "working"]);
    expect(DocumentList.parse(fixture("web/documents-ready")).documents.map((d) => d.status)).toEqual(["ready", "ready"]);
    expect(DocumentList.parse(fixture("web/documents-interrupted")).documents.map((d) => d.status)).toEqual(["ready", "interrupted", "ready"]);
  });

  test("connected apps and receipts (the iPhone's contract, shared)", () => {
    const catalog = ToolsCatalog.parse(fixture("online-accounts/catalog-gmail-on"));
    expect(catalog.toolkits.find((k) => k.id === "gmail")?.status).toBe("connected");
    ToolsCatalog.parse(fixture("online-accounts/catalog-disconnected"));
    expect(ReceiptList.parse(fixture("online-accounts/receipts")).receipts.length).toBeGreaterThan(0);
  });

  test("Logbook: off, on and empty, with days, the file, the delete and the refusals", () => {
    expect(LogbookView.parse(fixture("web/logbook-off"))).toEqual({ enabled: false, keptDays: 365, updatedAt: null, days: [] });
    expect(LogbookView.parse(fixture("web/logbook-empty"))).toMatchObject({ enabled: true, days: [] });
    const view = LogbookView.parse(fixture("web/logbook-view"));
    expect(view.days.map((d) => d.day)).toEqual(["2026-10-20", "2026-10-21", "2026-10-22"]);
    expect(view.updatedAt).toBe("2026-10-22T10:00:00.000Z");
    // The downloaded file is the same view with the time it was made.
    const file = fixture("web/logbook-export") as { exportedAt: string };
    expect(LogbookView.parse(file).days).toHaveLength(3);
    expect(file.exportedAt).toBe("2026-10-22T10:00:00.000Z");
    expect(LogbookDeleted.parse(fixture("web/logbook-deleted"))).toEqual({ deletedDays: 3 });
    expect(ErrorBody.parse(fixture("web/error-logbook-off")).error.code).toBe("capability_disabled");
    expect(ErrorBody.parse(fixture("web/error-logbook-invalid")).error.code).toBe("invalid_request");
  });

  test("kept notes and conversations, the file, the deletes, chat and the refusals", () => {
    expect(MemoryOverview.parse(fixture("web/memory-off"))).toEqual({ notes: false, conversations: false, noteCount: 0, conversationCount: 0, keptDays: 365, lastSyncedAt: null });
    expect(MemoryOverview.parse(fixture("web/memory-empty"))).toMatchObject({ notes: true, conversations: true, noteCount: 0 });
    const overview = MemoryOverview.parse(fixture("web/memory-overview"));
    expect(overview).toMatchObject({ noteCount: 3, conversationCount: 1 });
    const notes = NotesList.parse(fixture("web/memory-notes"));
    expect(notes.notes.map((n) => n.text)[0]).toBe("Anna's birthday is 14 March");
    expect(notes).toMatchObject({ total: 3, nextOffset: null, unreadable: 0 });
    expect(NotesList.parse(fixture("web/memory-notes-search")).notes).toHaveLength(1);
    const talks = ConversationList.parse(fixture("web/memory-conversations"));
    expect(talks.conversations[0]).toMatchObject({ turnCount: 3, language: "pl", endedBy: "you", preview: "Kiedy są urodziny Anny?" });
    expect(ConversationDetail.parse(fixture("web/memory-conversation")).turns.map((t) => t.role)).toEqual(["user", "doddy", "user"]);
    expect(ConversationDeleted.parse(fixture("web/memory-conversation-deleted"))).toEqual({ deleted: 1 });
    expect(MemoryDeleted.parse(fixture("web/memory-deleted"))).toEqual({ notes: false, conversations: false, deletedNotes: 3, deletedConversations: 0 });
    // The downloaded file is the overview plus every note and conversation in full.
    const file = fixture("web/memory-export") as { exportedAt: string; switches: object; notes: unknown[]; conversations: { turns: unknown[] }[] };
    expect(file.switches).toEqual({ notes: true, conversations: true });
    expect(file.notes).toHaveLength(3);
    expect(file.conversations[0]?.turns).toHaveLength(3);
    const reply = ChatReply.parse(fixture("web/chat-reply"));
    expect(reply.sources[0]).toMatchObject({ kind: "note", text: "Anna's birthday is 14 March" });
    expect(ErrorBody.parse(fixture("web/error-memory-off")).error.code).toBe("capability_disabled");
    expect(ErrorBody.parse(fixture("web/error-chat-off")).error.code).toBe("capability_disabled");
    expect(ErrorBody.parse(fixture("web/error-chat-invalid")).error.code).toBe("invalid_request");
  });
});
