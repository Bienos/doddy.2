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
                    Text("The original capture stays exactly as it was and remains viewable.")
                        .foregroundStyle(Theme.secondaryText)
                    MemoryTextEditor(text: $text, label: "Corrected detail")
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || text == record.currentText)
                }
            }
        }
        .interactiveDismissDisabled(text != record.currentText)
        .foregroundStyle(Theme.ink)
    }

    private func save() async {
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
