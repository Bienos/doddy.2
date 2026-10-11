import AppKit
import SwiftUI

/// The helper palette (ADR-445; the owner's review deck, slide 12, "Mała paleta wewnątrz pracy z
/// Doddy"): a small floating panel with a quick note field. It floats over Doddy's own windows
/// and hides as soon as Doddy isn't the active app (`hidesOnDeactivate`), so it never sits over
/// another app's work. Shown and hidden from the Doddy window; it is never shown by itself.
@MainActor
final class MacPaletteController {
    static let shared = MacPaletteController()
    private var panel: NSPanel?

    func toggle(model: MacCaptureModel) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            let panel = self.panel ?? make(model: model)
            self.panel = panel
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func make(model: MacCaptureModel) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Doddy"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: MacPaletteView().environment(model))
        panel.center()
        return panel
    }
}

/// A quick note: type, Save or Cancel. The same save and "Saved on this Mac." rule as the menu
/// bar (ADR-435).
struct MacPaletteView: View {
    @Environment(MacCaptureModel.self) private var model
    @State private var text = ""
    @State private var isSaving = false
    @State private var result: MacSaveResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.openProblem {
                Text(problem).foregroundStyle(.secondary)
            } else {
                TextField("Your note", text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("mac.palette.note")
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
                        .accessibilityIdentifier("mac.palette.save")
                }
                MacSaveResultView(result: result).font(.caption)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let shown = await model.saveForDisplay(text) else { return }
        result = shown
        if shown == .saved { text = "" }
    }
}
