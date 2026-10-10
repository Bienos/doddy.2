import DoddyCore
import SwiftUI

/// Settings → What Doddy knows → Remembered conversations (ADR-134). Shows exactly what is kept
/// on this iPhone, marks which conversations the next voice conversation will be handed, and lets
/// the user delete one or export them as text. Nothing here is sent anywhere.
struct RememberedConversationsView: View {
    let store: ConversationLogStore
    @State private var pendingDelete: ConversationLog?

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
                            ConversationLogDetailView(log: log, isSentNextTime: sentNextTime.contains(log.id)) {
                                store.remove(log.id)
                            }
                        } label: {
                            ConversationLogRow(log: log, isSentNextTime: sentNextTime.contains(log.id))
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDelete = log }
                        }
                    }
                } footer: {
                    Text("At most \(ConversationLogStore.maxLogs) are kept; the oldest goes when a new one is added. Older ones that don't fit are kept but not brought up.")
                }
            }

            if let problem = store.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
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
            Button("Delete", role: .destructive) {
                store.remove(log.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text(ConversationLogDeleteCopy.message)
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
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                StatusRow(title: "Started", value: log.startedAt.formatted(date: .abbreviated, time: .shortened))
                StatusRow(title: "Ended", value: log.endedAt.formatted(date: .omitted, time: .shortened))
                StatusRow(title: "Next conversation", value: isSentNextTime ? "Brought up" : "Not brought up")
            }
            Section("What was said") {
                ForEach(Array(log.lines.enumerated()), id: \.offset) { _, line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.fromUser ? "You" : "Doddy (AI)")
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
        .confirmationDialog("Delete this conversation?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ConversationLogDeleteCopy.message)
        }
    }
}

private enum ConversationLogDeleteCopy {
    static let message = "It is removed from this iPhone and won't be brought up again. Notes you saved during it stay, and ElevenLabs keeps its own record as described in Settings › Privacy."
}
