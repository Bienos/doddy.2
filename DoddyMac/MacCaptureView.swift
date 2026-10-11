import AppKit
import DoddyCore
import SwiftUI

/// Click the menu bar icon, type, then Save or Cancel (ADR-435). Typing only: Doddy's voice isn't
/// on the Mac, so this window never uses the microphone. "Saved" only from the database's
/// read-back; an unconfirmed save says so and points at Recent.
struct MacCaptureView: View {
    @Environment(MacCaptureModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var text = ""
    @State private var isSaving = false
    @State private var result: MacSaveResult?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New note").font(.headline)
            if let problem = model.openProblem {
                Text(problem).foregroundStyle(.secondary)
            } else {
                TextField("Your note", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .accessibilityIdentifier("mac.note")
                HStack {
                    Button("Cancel") {
                        text = ""
                        result = nil
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSaving || !model.canSave || text.allSatisfy(\.isWhitespace))
                        .accessibilityIdentifier("mac.save")
                }
            }
            MacSaveResultView(result: result)
            if !model.recent.isEmpty {
                Divider()
                Text("Recent on this Mac").font(.caption).foregroundStyle(.secondary)
                ForEach(model.recent) { note in
                    Text(note.currentText).font(.callout).lineLimit(2)
                }
            }
            if let problem = model.recentProblem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Notes saved here stay on this Mac. They aren't on your iPhone, and your iPhone's notes aren't here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                // The bigger window (ADR-441), for a longer note and every note on this Mac.
                Button("Open Doddy window") {
                    openWindow(id: MacNotesWindow.id)
                    NSApplication.shared.activate()
                }
                Spacer()
                Button("Quit Doddy") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
        }
        .padding(14)
        .frame(width: 320)
        .task {
            await model.refresh()
            typing = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let outcome = await model.save(text) else { return }
        result = MacSaveResult(outcome)
        if result == .saved { text = "" }
    }
}

/// What the last Save said, in both Mac windows. Saved only from the read-back.
enum MacSaveResult: Equatable {
    case saved
    case problem(String)

    init(_ outcome: QuickCaptureOutcome) {
        switch outcome {
        case .saved: self = .saved
        case .needsChange(let message): self = .problem(message)
        case .unconfirmed: self = .problem(QuickCapture.unconfirmedMessage)
        }
    }
}

struct MacSaveResultView: View {
    let result: MacSaveResult?

    var body: some View {
        switch result {
        case .saved:
            Label("Saved on this Mac.", systemImage: "checkmark.circle")
        case .problem(let message):
            Text(message).foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }
}
