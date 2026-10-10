import DoddyCore
import SwiftUI
import UIKit

/// One stored memory: current text, immutable original, provenance, correct/copy/delete.
struct MemoryDetailView: View {
    let memoryID: UUID

    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showCorrection = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var showReminder = false

    var body: some View {
        Group {
            if let record = store.record(id: memoryID) {
                detail(record)
            } else {
                Text("This memory no longer exists.")
                    .foregroundStyle(Theme.secondaryText)
                    .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .navigationTitle("Your memory")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Theme.ink)
    }

    private func detail(_ record: MemoryRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(record.currentText)
                    .font(.title2)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("detail.currentText")

                VStack(spacing: 8) {
                    StatusRow(title: "Saved", value: DateText.full(record.capturedAt))
                    StatusRow(title: "Source", value: record.source.displayName)
                    StatusRow(title: "Type", value: record.category.displayName)
                    if record.userEdited {
                        StatusRow(title: "Corrected", value: DateText.full(record.updatedAt))
                    }
                }
                .font(.subheadline)

                if record.userEdited {
                    DisclosureGroup("Original capture") {
                        Text(record.rawText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, 8)
                    }
                    .tint(Theme.ink)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("This is your note.")
                        .font(.subheadline.bold())
                    Text("No guessed details. Corrections keep the original capture; deleting removes both versions.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.orangeCue).frame(width: 3).accessibilityHidden(true)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                }

                VStack(spacing: 12) {
                    Button { showCorrection = true } label: {
                        HStack { Text("Correct this detail"); Spacer(); Image(systemName: "pencil") }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button { showReminder = true } label: {
                        HStack { Text("Remind me"); Spacer(); Image(systemName: "bell") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("detail.remind")

                    Button {
                        UIPasteboard.general.string = record.currentText
                        copied = true
                    } label: {
                        HStack {
                            Text(copied ? "Copied" : "Copy text")
                            Spacer()
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(role: .destructive) { confirmDelete = true } label: {
                        HStack { Text("Delete this memory"); Spacer(); Image(systemName: "trash") }
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.error))
                    .accessibilityIdentifier("detail.delete")
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showCorrection) { CorrectionView(record: record) }
        .sheet(isPresented: $showReminder) {
            ReminderProposalView(initialTitle: record.currentText, initialDue: .none, sourceMemoryID: record.id) { _ in }
        }
        .confirmationDialog("Delete this memory?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current text and the original capture are removed from this iPhone. Copies you exported aren't affected.")
        }
    }

    private func delete() async {
        do {
            try await store.delete(id: memoryID)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
