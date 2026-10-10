import DoddyCore
import SwiftUI
import UIKit

/// Success is backed by a committed repository record, never a simulated timer.
/// `sharedText` comes from the "Save to Doddy" shortcut: it fills the editor and is still only
/// saved when the user taps Save (ADR-136).
struct CaptureView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isShared: Bool
    @State private var category: MemoryCategory = .other
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved: MemoryRecord?
    @State private var confirmDiscard = false
    /// A saved note with the same words (ADR-141). Shown instead of saving until the user picks.
    @State private var duplicate: MemoryRecord?
    @State private var allowDuplicate = false
    @FocusState private var editorFocused: Bool

    init(sharedText: String? = nil) {
        _text = State(initialValue: sharedText ?? "")
        _isShared = State(initialValue: sharedText != nil)
    }

    private var hasDraft: Bool { !text.allSatisfy(\.isWhitespace) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let saved {
                        if store.record(id: saved.id) != nil || store.loadError != nil {
                            SaveReceiptView(record: store.record(id: saved.id) ?? saved, onDone: { dismiss() }, onAnother: startAnother)
                            if let loadError = store.loadError {
                                ProblemView(message: "The note was saved, but the list couldn't refresh. \(loadError)")
                            }
                        } else {
                            Text("This note has been removed.")
                            Button("Save another detail", action: startAnother).buttonStyle(PrimaryButtonStyle())
                            Button("Done") { dismiss() }
                        }
                    } else {
                        JourneyHeading(eyebrow: "Before it slips away", title: "One less thing\nto remember.",
                                       subtitle: "A thought, a recommendation, where you put the spare keys.")
                        if isShared {
                            Label("Shared into Doddy from a shortcut. Check it, change it if you like, then tap Save. Nothing is saved until you do.", systemImage: "square.and.arrow.down")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("capture.sharedNotice")
                        }
                        Text("What would you like to keep?").font(.subheadline)
                        MemoryTextEditor(text: $text, label: "The detail").focused($editorFocused)
                            .accessibilityIdentifier("capture.text")
                            .disabled(isSaving)
                        // Apple's own paste control: iOS asks nothing, and only a tap reads the clipboard.
                        // The copied text goes in exactly as copied, after what is already there (ADR-146).
                        PasteButton(payloadType: String.self) { items in
                            text = DraftText.pasting(items, into: text)
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.ink)
                        .frame(minHeight: 44)
                        .disabled(isSaving)
                        .accessibilityIdentifier("capture.paste")
                        Text("No folders. Your words, exactly.").font(.caption).foregroundStyle(Theme.secondaryText)
                        DisclosureGroup("Optional note type") {
                            Picker("Type", selection: $category) {
                                ForEach(MemoryCategory.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }.pickerStyle(.menu)
                        }.font(.subheadline).disabled(isSaving)
                        Label("Only this detail is saved on this iPhone. You can edit or delete it later.", systemImage: "lock")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                        if let errorMessage {
                            ProblemView(message: errorMessage).accessibilityIdentifier("capture.error")
                        }
                        if let duplicate {
                            DuplicateNoticeView(record: duplicate) {
                                allowDuplicate = true
                                beginSave()
                            }
                        }
                        Button(action: beginSave) {
                            HStack { Text(isSaving ? "Saving…" : "Save this detail"); Spacer(); Image(systemName: "arrow.right") }
                        }
                        .buttonStyle(PrimaryButtonStyle()).disabled(isSaving || !store.isStorageAvailable)
                        .accessibilityIdentifier("capture.save")
                    }
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { DoddyWordmark() }
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved == nil ? "Cancel" : "Done", action: close)
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }.accessibilityIdentifier("capture.keyboardDone")
                }
            }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .onChange(of: text) {
                duplicate = nil
                allowDuplicate = false
                // Once the shared text is cleared, whatever is typed or pasted next is the user's
                // own, so it is saved as a typed note, not as "shared".
                if isShared && text.allSatisfy(\.isWhitespace) { isShared = false }
            }
            .confirmationDialog("Discard this note?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            } message: { Text("It hasn't been saved.") }
        }
        .interactiveDismissDisabled((hasDraft && saved == nil) || isSaving)
        .onAppear { ShortcutRouter.shared.captureScreenAppeared() }
        .onDisappear { ShortcutRouter.shared.captureScreenDisappeared() }
    }

    private func close() {
        guard !isSaving else { return }
        if saved == nil && hasDraft { confirmDiscard = true } else { dismiss() }
    }

    private func startAnother() {
        text = ""; category = .other; saved = nil; errorMessage = nil; isShared = false
        duplicate = nil; allowDuplicate = false
    }

    private func beginSave() {
        guard !isSaving else { return }
        if !allowDuplicate, let match = DuplicateNote.existing(for: text, in: store.memories) {
            duplicate = match
            UIAccessibility.post(notification: .announcement, argument: "You saved this already. View it, or save it again anyway.")
            editorFocused = false
            return
        }
        duplicate = nil
        editorFocused = false
        isSaving = true
        Task { await save() }
    }

    private func save() async {
        errorMessage = nil
        defer { isSaving = false }
        do { saved = try await store.save(text: text, category: category, source: isShared ? .sharedContent : .explicitText) }
        catch { errorMessage = UserFacingError.message(for: error) }
    }
}

/// "You saved this already" with the date, a link to that note and "Save anyway".
private struct DuplicateNoticeView: View {
    let record: MemoryRecord
    let onSaveAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("You saved this already, \(DateText.full(record.capturedAt)).", systemImage: "doc.on.doc")
                .font(.subheadline.weight(.medium))
            Text(record.currentText).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(3)
            NavigationLink(value: record.id) {
                HStack { Text("View the saved note"); Spacer(); Image(systemName: "arrow.up.right") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("capture.viewDuplicate")
            Button("Save it again anyway", action: onSaveAnyway)
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture.saveDuplicate")
        }
        .padding(14)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("capture.duplicate")
    }
}

private struct SaveReceiptView: View {
    let record: MemoryRecord
    let onDone: () -> Void
    let onAnother: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            UploadedCharacterView(assetName: "UploadedDoddy_Kept", height: 170)
            Text("Got it.").font(.largeTitle.weight(.medium)).accessibilityAddTraits(.isHeader)
            Label("Saved on this iPhone", systemImage: "checkmark.circle")
                .font(.subheadline).foregroundStyle(Theme.confirmed).accessibilityIdentifier("capture.saved")
            MemoryPaperCard(record: record)
            NavigationLink(value: record.id) {
                HStack { Text("View the note"); Spacer(); Image(systemName: "arrow.up.right") }
            }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("capture.viewNote")
            Button("Save another detail", action: onAnother).frame(minHeight: 44)
            Button("Done", action: onDone).buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("capture.done")
        }.frame(maxWidth: .infinity)
    }
}

#Preview("Local capture") {
    CaptureView().environment(MemoryStore(environment: .unavailable))
}
