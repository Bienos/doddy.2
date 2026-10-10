import DoddyCore
import SwiftUI
import UIKit

/// Current and immutable original wording remain attached to the same stored ID.
struct MemoryDetailView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(\.dismiss) private var dismiss
    let memoryID: UUID
    @State private var correction: MemoryRecord?
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var copied = false
    @AppStorage(PreferenceKey.pinnedNotes) private var pinnedRaw = "[]"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let record = store.record(id: memoryID) {
                    JourneyHeading(eyebrow: "Straight from your note", title: "The original\nis right here.")
                    MemoryPaperCard(record: record, textIdentifier: "detail.currentText")
                    NotePhotoSection(memoryID: memoryID)
                    if record.userEdited {
                        Text("Edited \(DateText.full(record.updatedAt))").font(.caption).foregroundStyle(Theme.secondaryText)
                        DisclosureGroup("Original capture") {
                            Text(record.rawText).frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled).padding(.top, 12)
                                .accessibilityIdentifier("detail.originalText")
                        }.tint(Theme.ink)
                    }
                    // File the note under another type. Only the type changes (ADR-192).
                    Picker("Type", selection: Binding(
                        get: { record.category },
                        set: { newType in Task { await setType(newType, for: record) } })
                    ) {
                        ForEach(MemoryCategory.noteCategories, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("detail.type")
                    Text("Your note, your choice. No inferred facts.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                    if let errorMessage { ProblemView(message: errorMessage) }
                    NoteReminderSection(memoryID: memoryID)
                    Button { correction = record } label: {
                        HStack { Text("Edit this note"); Spacer(); Image(systemName: "pencil") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("detail.edit")
                    Button { togglePin(record) } label: {
                        let pinned = PinnedNotes(stored: pinnedRaw).isPinned(record.id)
                        HStack { Text(pinned ? "Unpin from the top" : "Pin to the top"); Spacer(); Image(systemName: pinned ? "pin.slash" : "pin") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("detail.pin")
                    Button { copy(record) } label: {
                        HStack { Text(copied ? "Copied" : "Copy text"); Spacer(); Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    }.buttonStyle(SecondaryButtonStyle())
                    // Only the note's current words, nothing about when or how it was saved (ADR-185).
                    ShareLink(item: record.currentText, preview: SharePreview("Doddy note")) {
                        HStack { Text("Share text"); Spacer(); Image(systemName: "square.and.arrow.up") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("detail.share")
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text(isDeleting ? "Deleting…" : "Delete this memory").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .tint(Theme.error).disabled(isDeleting).accessibilityIdentifier("detail.delete")
                } else {
                    Text("This memory no longer exists.").foregroundStyle(Theme.secondaryText)
                }
            }.padding(24)
        }
        .background(Theme.canvas).foregroundStyle(Theme.ink)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) { DoddyWordmark() } }
        .sheet(item: $correction) { CorrectionView(record: $0) }
        .confirmationDialog("Delete this memory?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: beginDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    /// Undo (ADR-183) brings the note back, not its reminder, so the message says so.
    private var deleteMessage: String {
        let base = "Both current and original text are removed from this iPhone. You can undo for a few seconds afterwards."
        guard let reminder = noteReminders.reminder(forMemory: memoryID) else {
            return base + " Exports and older backups aren't affected."
        }
        return base + " Its reminder (\(ReminderFormat.short(reminder))) is cancelled too, and undo doesn't bring the reminder back. Exports and older backups aren't affected."
    }

    private func setType(_ category: MemoryCategory, for record: MemoryRecord) async {
        guard category != record.category else { return }
        do {
            try await store.setCategory(id: record.id, to: category)
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func togglePin(_ record: MemoryRecord) {
        let change = PinnedNotes.toggle(record.id, stored: &pinnedRaw, existing: store.memories)
        errorMessage = change == .full ? PinnedNotes.fullMessage : nil
    }

    private func copy(_ record: MemoryRecord) {
        UIPasteboard.general.string = record.currentText
        copied = true
    }

    private func beginDelete() {
        guard !isDeleting else { return }
        isDeleting = true
        Task { await delete() }
    }

    private func delete() async {
        defer { isDeleting = false }
        do {
            try await store.delete(id: memoryID)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
