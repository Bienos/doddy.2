import DoddyCore
import SwiftUI

/// Edits `currentText` only. On failure the edited draft stays in place.
struct CorrectionView: View {
    let record: MemoryRecord

    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(record: MemoryRecord) {
        self.record = record
        _text = State(initialValue: record.currentText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    JourneyHeading(eyebrow: "Your words, updated", title: "Change the detail.\nKeep the original.")
                    Text("The original capture stays exactly as it was and remains viewable.")
                        .foregroundStyle(Theme.secondaryText)
                    MemoryTextEditor(text: $text, label: "Corrected detail")
                        .accessibilityIdentifier("correction.text")
                        .disabled(isSaving)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .accessibilityIdentifier("correction.error")
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .navigationTitle("Correct this detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || text == record.currentText)
                        .accessibilityIdentifier("correction.save")
                }
            }
        }
        .interactiveDismissDisabled(text != record.currentText || isSaving)
        .foregroundStyle(Theme.ink)
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await store.correct(id: record.id, text: text)
            dismiss()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
