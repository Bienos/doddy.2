import DoddyCore
import SwiftUI

/// The Doddy window on the Mac (ADR-451; the owner's review deck, slide 11, "Miejsce, by rozwinąć
/// myśl"): more room for a note, and every note saved on this Mac, still in Doddy's own window.
/// Opened only from the menu bar window. Typing only, Save or Cancel, as there (ADR-435).
struct MacNotesWindow: View {
    static let id = "doddy"

    @Environment(MacCaptureModel.self) private var model
    @State private var text = ""
    @State private var isSaving = false
    @State private var result: MacSaveResult?
    @FocusState private var typing: Bool

    var body: some View {
        HSplitView {
            capture
                .frame(minWidth: 320, idealWidth: 420)
            notesList
                .frame(minWidth: 220, idealWidth: 280)
        }
        .frame(minWidth: 560, minHeight: 360)
        .toolbar {
            // The helper palette (ADR-455): a small floating note field while you use Doddy.
            Button {
                MacPaletteController.shared.toggle(model: model)
            } label: {
                Label("Palette", systemImage: "rectangle.on.rectangle")
            }
            .help("Show or hide a small floating palette for quick notes. It hides when you switch to another app.")
        }
        .task {
            typing = true
            await model.refreshAll()
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New note").font(.title2.weight(.semibold))
            if let problem = model.openProblem {
                Text(problem).foregroundStyle(.secondary)
                Spacer()
            } else {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .font(.body)
                        .focused($typing)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                        .accessibilityLabel("Your note")
                        .accessibilityIdentifier("mac.window.note")
                    if text.isEmpty {
                        Text("Your note")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                HStack {
                    Button("Cancel") {
                        text = ""
                        result = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || !model.canSave || text.allSatisfy(\.isWhitespace))
                        .accessibilityIdentifier("mac.window.save")
                }
                MacSaveResultView(result: result)
            }
            Text("Notes saved here stay on this Mac. They aren't on your iPhone, and your iPhone's notes aren't here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var notesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notes on this Mac")
                .font(.headline)
                .padding([.horizontal, .top], 12)
                .padding(.bottom, 6)
            if model.isOpeningStore || (model.isRefreshingAllNotes && model.notes.isEmpty) {
                ProgressView("Opening notes…")
                    .controlSize(.small)
                    .padding(12)
                Spacer()
            } else if let problem = model.openProblem {
                Text(problem)
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            } else if model.notes.isEmpty, let problem = model.recentProblem {
                Text(problem)
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            } else if model.notes.isEmpty {
                Text("Nothing saved on this Mac yet.")
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            } else {
                List(model.notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.currentText).lineLimit(4).textSelection(.enabled)
                        // Notes typed here always have a date; an unknown one is never made up.
                        if let saved = note.capturedAt {
                            Text(saved, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if !model.notes.isEmpty, let problem = model.recentProblem {
                Text(problem).font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let shown = await model.saveForDisplay(text, refreshAllNotes: true) else { return }
        result = shown
        if shown == .saved { text = "" }
    }
}
