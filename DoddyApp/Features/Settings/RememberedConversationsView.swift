import DoddyCore
import SwiftUI

/// Settings → What Doddy knows → Remembered conversations (ADR-177). Shows exactly what is kept
/// on this iPhone, marks which conversations the next voice conversation will be handed, and lets
/// the user delete one or export them as text. Nothing here is sent anywhere.
struct RememberedConversationsView: View {
    let store: ConversationLogStore
    @Environment(MemoryStore.self) private var memories
    @State private var pendingDelete: ConversationLog?
    @State private var notice: String?

    /// Deletes the conversation and, when the person chose it, the recap note made from it.
    private func delete(_ log: ConversationLog, alsoRecap: Bool) {
        Task {
            let outcome = await ConversationDeletion.delete(log, alsoRecap: alsoRecap, logs: store, memories: memories)
            notice = outcome == .recapNotDeleted ? ConversationLogDeleteCopy.recapNotDeleted : nil
        }
    }

    private var newestFirst: [ConversationLog] {
        store.logs.sorted { $0.startedAt > $1.startedAt }
    }

    private var sentNextTime: Set<UUID> {
        store.isEnabled ? VoiceContext.conversationsSentNextTime(store.logs) : []
    }

    var body: some View {
        List {
            Section {
                Text(store.isEnabled
                     ? "These are kept only on this iPhone. The ones marked \"Brought up next time\" are handed to Doddy when your next voice conversation starts, so he can carry on where you left off. Written down from the conversation's text; no audio is kept."
                     : "Remembering conversations is off, so none of these are handed to Doddy. They stay on this iPhone until you delete them.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.canvas)

            if newestFirst.isEmpty {
                Section {
                    Text("No conversations kept. Private conversations and empty ones are never kept.")
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("conversations.empty")
                }
            } else {
                Section {
                    ForEach(newestFirst) { log in
                        NavigationLink {
                            ConversationLogDetailView(
                                log: log, isSentNextTime: sentNextTime.contains(log.id),
                                hasRecap: ConversationDeletion.linkedRecapID(for: log, store: memories) != nil
                            ) { alsoRecap in
                                delete(log, alsoRecap: alsoRecap)
                            }
                        } label: {
                            ConversationLogRow(log: log, isSentNextTime: sentNextTime.contains(log.id))
                        }
                        // Not `.destructive`: that role removes the row before the user confirms.
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Delete") { pendingDelete = log }.tint(Theme.error)
                        }
                    }
                } footer: {
                    Text(verbatim: String(format: NSLocalizedString("At most %lld are kept; the oldest goes when a new one is added. Older ones that don't fit are kept but not brought up.", comment: ""),
                                         ConversationLogStore.maxLogs))
                }
            }

            if let problem = store.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
            }
            if let notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("conversations.recapNotDeleted")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .navigationTitle("Remembered conversations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.logs.isEmpty {
                ShareLink(
                    item: ConversationLogExport.plainText(store.logs, exportedAt: .now),
                    preview: SharePreview("Doddy conversations (text)")
                ) {
                    Label("Export as text", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("conversations.export")
            }
        }
        .confirmationDialog(
            "Delete this conversation?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { log in
            if ConversationDeletion.linkedRecapID(for: log, store: memories) != nil {
                Button("Delete conversation and recap note", role: .destructive) {
                    delete(log, alsoRecap: true)
                    pendingDelete = nil
                }
                Button("Delete conversation, keep recap note", role: .destructive) {
                    delete(log, alsoRecap: false)
                    pendingDelete = nil
                }
            } else {
                Button("Delete", role: .destructive) {
                    delete(log, alsoRecap: false)
                    pendingDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { log in
            Text(ConversationDeletion.linkedRecapID(for: log, store: memories) != nil
                 ? ConversationLogDeleteCopy.messageWithRecap : ConversationLogDeleteCopy.message)
        }
    }
}

private struct ConversationLogRow: View {
    let log: ConversationLog
    let isSentNextTime: Bool

    private var preview: String {
        (log.lines.first(where: \.fromUser) ?? log.lines.first)?.text ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(log.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            // Which voice ran it. Older logs have none, and some from before 9 Nov 2026 say OpenAI.
            if let voice = log.voiceName {
                Text(verbatim: "Voice: \(voice)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(preview)
                .lineLimit(2)
                .foregroundStyle(Theme.secondaryText)
            Text(isSentNextTime ? "Brought up next time" : "Not brought up")
                .font(.caption)
                .foregroundStyle(isSentNextTime ? Theme.accentText : Theme.secondaryText)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ConversationLogDetailView: View {
    let log: ConversationLog
    let isSentNextTime: Bool
    let hasRecap: Bool
    let onDelete: (_ alsoRecap: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var alsoRecap = false
    /// Deleting removes the row that pushed this screen, which pops it by itself; so the screen
    /// closes first and the delete happens once it has gone, to avoid popping twice.
    @State private var deleteWhenGone = false

    var body: some View {
        List {
            Section {
                StatusRow(title: "Started", value: log.startedAt.formatted(date: .abbreviated, time: .shortened))
                StatusRow(title: "Ended", value: log.endedAt.formatted(date: .omitted, time: .shortened))
                if let voice = log.voiceName {
                    StatusRow(title: "Voice", value: voice)
                }
                StatusRow(title: "Next conversation", value: isSentNextTime ? "Brought up" : "Not brought up")
            }
            Section("What was said") {
                ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.fromUser ? "You" : "Doddy")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(line.fromUser ? Theme.accentText : Theme.secondaryText)
                        Text(line.text)
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button("Delete this conversation", role: .destructive) { confirmDelete = true }
                    .accessibilityIdentifier("conversations.delete")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .navigationTitle("Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { if deleteWhenGone { onDelete(alsoRecap) } }
        .confirmationDialog("Delete this conversation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            if hasRecap {
                Button("Delete conversation and recap note", role: .destructive) {
                    alsoRecap = true
                    deleteWhenGone = true
                    dismiss()
                }
                Button("Delete conversation, keep recap note", role: .destructive) {
                    alsoRecap = false
                    deleteWhenGone = true
                    dismiss()
                }
            } else {
                Button("Delete", role: .destructive) {
                    deleteWhenGone = true
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(hasRecap ? ConversationLogDeleteCopy.messageWithRecap : ConversationLogDeleteCopy.message)
        }
    }
}

private enum ConversationLogDeleteCopy {
    static let message = NSLocalizedString("This removes the conversation history from this iPhone. Saved notes and recap notes stay and may still be used. Copies on Doddy's server or ElevenLabs may remain.", comment: "")
    static let messageWithRecap = NSLocalizedString("This removes the conversation history from this iPhone. Doddy also made a recap note from it: you can delete that too, or keep it. Copies on Doddy's server or ElevenLabs may remain.", comment: "")
    static let recapNotDeleted = NSLocalizedString("The conversation was deleted, but its recap note couldn't be deleted and is still kept. You can delete it from Notes.", comment: "")
}
