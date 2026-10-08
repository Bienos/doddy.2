import DoddyCore
import SwiftUI

/// Explicit capture. "Saved" appears only after the repository confirmed the write;
/// on any failure the draft stays in the editor.
struct CaptureView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var category: MemoryCategory = .other
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved: MemoryRecord?
    @State private var confirmDiscard = false
    @FocusState private var editorFocused: Bool

    private var hasDraft: Bool { !text.allSatisfy(\.isWhitespace) }

    var body: some View {
        NavigationStack {
            Group {
                if let saved {
                    SaveReceiptView(record: saved) { dismiss() }
                } else {
                    editor
                }
            }
            .background(Theme.canvas)
            .navigationTitle(saved == nil ? "New memory" : "Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if saved == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if hasDraft { confirmDiscard = true } else { dismiss() }
                        }
                    }
                }
            }
            .confirmationDialog("Discard this note?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("It hasn't been saved.")
            }
        }
        .interactiveDismissDisabled(hasDraft && saved == nil)
        .foregroundStyle(Theme.ink)
    }

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What shall we keep?")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Something useful, in your own words. Only what you save is kept.")
                    .foregroundStyle(Theme.secondaryText)

                MemoryTextEditor(text: $text, label: "The detail")
                    .focused($editorFocused)
                    .accessibilityIdentifier("capture.text")

                Picker("Type", selection: $category) {
                    ForEach(MemoryCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Theme.ink)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.error)
                        .accessibilityIdentifier("capture.error")
                }

                Label("Written by you · stored on this iPhone only. You can correct or delete it later.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(isSaving ? "Saving…" : "Save this memory")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || !store.isStorageAvailable)
                .accessibilityIdentifier("capture.save")
            }
            .padding(24)
        }
        .onAppear { editorFocused = true }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            saved = try await store.save(text: text, category: category)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// Shown only with a committed record.
struct SaveReceiptView: View {
    let record: MemoryRecord
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("Saved on this iPhone", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.confirmed)
                    .accessibilityIdentifier("capture.saved")
                Text(record.currentText)
                    .font(.title3)
                Text("\(record.source.displayName) · \(DateText.full(record.capturedAt))")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Button("Done", action: onDone)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
            }
            .padding(24)
        }
    }
}
