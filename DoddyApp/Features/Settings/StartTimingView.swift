import DoddyCore
import SwiftUI

/// Settings › About › Advanced › Start timing (decision 2026-11-14-start-timing-on-the-phone): the timing lines of
/// Doddy's last starts, for reading how long an Action Button press took without a Mac. They are the lines the
/// log already has, kept on this iPhone by `StartTimingStore`: only seconds and fixed words, nothing that was said
/// or typed. "Copy" puts them on the clipboard the way every copy from Doddy is made (this iPhone only, gone after
/// two minutes, `NoteClipboard`), so they can be pasted to whoever reads them.
struct StartTimingView: View {
    @State private var journal = StartTimingStore.shared.journal()
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                if journal.isEmpty {
                    Text("Nothing yet. Press the Action Button once, then pull down here to refresh.")
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("startTiming.empty")
                } else {
                    ForEach(Array(journal.entries.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.at.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            Text(verbatim: entry.text)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } footer: {
                Text("The timing of Doddy's last starts, as he measured it. Only seconds and fixed words are kept, and only on this iPhone. Erase everything removes them.")
            }
            if !journal.isEmpty {
                Section {
                    Button("Copy") { copy() }
                        .accessibilityIdentifier("startTiming.copy")
                    Button("Clear", role: .destructive) { clear() }
                        .accessibilityIdentifier("startTiming.clear")
                } footer: {
                    if copied {
                        Text("Copied. It leaves the clipboard after two minutes.")
                    }
                }
            }
        }
        .settingsPage()
        .navigationTitle("Start timing")
        .refreshable { reload() }
        .onAppear { reload() }
    }

    /// What is stored now: a start that finished while this page was open shows after a pull down.
    private func reload() {
        journal = StartTimingStore.shared.journal()
    }

    private func copy() {
        reload()
        NoteClipboard.copy(journal.copyText())
        copied = true
    }

    /// Removes the lines, then reads them back, so the page shows empty only if they are.
    private func clear() {
        StartTimingStore.shared.clear()
        reload()
        copied = false
    }
}
