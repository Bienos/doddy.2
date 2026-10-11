import AppKit
import DoddyCore
import SwiftUI

/// The menu under Doddy's icon in the menu bar. The rows come from `MenuBarMenu` (DoddyCore, tested),
/// so a row that doesn't work on the Mac is greyed out with its reason, never tappable.
struct MenuBarContent: View {
    let model: MacModel
    @Environment(\.openWindow) private var openWindow
    @State private var mode: Mode = .menu

    enum Mode { case menu, remember, find }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            switch mode {
            case .menu: rows
            case .remember: RememberPanel(model: model) { mode = .menu }
            case .find: FindPanel(model: model) { mode = .menu }
            }
            if let problem = model.storageProblem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(MacTheme.error)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 8)
            Button("Quit Doddy") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(MacTheme.secondaryText)
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
        .task { await model.reload() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            DoddyFace(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Doddy").font(.headline).foregroundStyle(MacTheme.ink)
                Text(model.menu.status.text).font(.caption).foregroundStyle(MacTheme.secondaryText)
            }
            Spacer()
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.menu.entries) { entry in
                row(entry)
            }
        }
    }

    private func row(_ entry: MenuBarEntry) -> some View {
        Button {
            perform(entry.action)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Image(systemName: symbol(entry.action)).frame(width: 20)
                    Text(entry.title)
                    Spacer()
                }
                if case .unavailable(let reason) = entry.availability {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(MacTheme.secondaryText)
                        .padding(.leading, 30)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.availability.isAvailable)
        .opacity(entry.availability.isAvailable ? 1 : 0.55)
        .accessibilityHint(hint(for: entry))
    }

    private func hint(for entry: MenuBarEntry) -> String {
        if case .unavailable(let reason) = entry.availability { return reason }
        return ""
    }

    private func symbol(_ action: MenuBarAction) -> String {
        switch action {
        case .openDoddy: "house"
        case .talk: "mic"
        case .remember: "square.and.pencil"
        case .find: "magnifyingglass"
        case .translate: "character.bubble"
        case .settings: "gearshape"
        }
    }

    private func perform(_ action: MenuBarAction) {
        switch action {
        case .openDoddy: open(WindowID.notes)
        case .settings: open(WindowID.settings)
        case .remember: mode = .remember
        case .find: mode = .find
        // Unavailable rows are disabled and never reach here; nothing happens if one ever did.
        case .talk, .translate: break
        }
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}

/// "Remember something": type, press Save. Nothing is stored until then, and "Saved" is shown only
/// after the repository committed the note (`MenuBarCapture`).
private struct RememberPanel: View {
    let model: MacModel
    let done: () -> Void
    @State private var text = ""
    @State private var result: MenuBarSaveResult?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remember something").font(.subheadline.weight(.semibold))
            TextField("What should Doddy keep?", text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                // Editing clears an old message; emptying the field after a save keeps "Saved".
                .onChange(of: text) { if !text.isEmpty { result = nil } }
            if let result {
                let message = feedback(for: result)
                Text(message.text).font(.caption).foregroundStyle(message.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Back", action: done)
                Spacer()
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { focused = true }
    }

    /// The field is cleared only after the note was stored; on any failure the words stay.
    private func save() async {
        let outcome = await model.save(text)
        result = outcome
        if case .saved = outcome { text = "" }
    }

    private func feedback(for result: MenuBarSaveResult) -> (text: String, color: Color) {
        switch result {
        case .saved: ("Saved on this Mac.", MacTheme.confirmed)
        case .rejected(.tooLong): ("That's too long to save as one note. Nothing was saved.", MacTheme.error)
        case .rejected: ("Type something to save.", MacTheme.error)
        case .notSaved(let message): (message, MacTheme.error)
        }
    }
}

/// "Find in my memories": the same word search the iPhone uses, over this Mac's notes only.
private struct FindPanel: View {
    let model: MacModel
    let done: () -> Void
    @State private var query = ""
    @State private var state: MacFindState = .idle
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find in my memories").font(.subheadline.weight(.semibold))
            TextField("Search your notes", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { Task { state = await model.find(query) } }
            switch state {
            case .idle: EmptyView()
            case .noMatch:
                Text(RecallCopy.noMatch).font(.caption).foregroundStyle(MacTheme.secondaryText)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(MacTheme.error)
            case .matches(let found):
                ForEach(found, id: \.memoryID) { candidate in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.record.currentText).lineLimit(3)
                        if let date = candidate.record.capturedAt {
                            Text("Saved \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(MacTheme.secondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack {
                Button("Back", action: done)
                Spacer()
            }
        }
        .onAppear { focused = true }
    }
}
