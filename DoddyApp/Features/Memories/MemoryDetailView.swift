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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let record = store.record(id: memoryID) {
                    JourneyHeading(eyebrow: "Straight from your note", title: "The original\nis right here.")
                    MemoryPaperCard(record: record, textIdentifier: "detail.currentText")
                    if record.userEdited {
                        Text("Edited \(DateText.full(record.updatedAt))").font(.caption).foregroundStyle(Theme.secondaryText)
                        DisclosureGroup("Original capture") {
                            Text(record.rawText).frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled).padding(.top, 12)
                                .accessibilityIdentifier("detail.originalText")
                        }.tint(Theme.ink)
                    }
                    Text("Your note, your choice. No inferred facts.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                    if let errorMessage { ProblemView(message: errorMessage) }
                    NoteReminderSection(memoryID: memoryID)
                    Button { correction = record } label: {
                        HStack { Text("Edit this note"); Spacer(); Image(systemName: "pencil") }
                    }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("detail.edit")
                    Button { copy(record) } label: {
                        HStack { Text(copied ? "Copied" : "Copy text"); Spacer(); Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    }.buttonStyle(SecondaryButtonStyle())
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

    private var deleteMessage: String {
        let base = "Both current and original text are removed from this iPhone."
        guard let reminder = noteReminders.reminder(forMemory: memoryID) else {
            return base + " Exports and older backups aren't affected."
        }
        let when = ReminderFormat.dateTime(reminder.fireAt, timeZoneID: reminder.timeZoneID)
        return base + " Its reminder for \(when) is cancelled too. Exports and older backups aren't affected."
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
