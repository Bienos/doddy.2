import DoddyCore
import SwiftUI

/// The diary (ADR-345). Off until switched on here. Lines by day, newest first; type one, or ask
/// Doddy to add one. Nothing here is given to the voice agent, search, widgets or the watch.
struct DiaryView: View {
    @AppStorage(Diary.enabledKey) private var isOn = false
    @State private var days: [(day: String, entries: [DiaryEntry])] = []
    @State private var line = ""
    @State private var problem: String?
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            Section {
                Toggle("Keep a diary", isOn: $isOn)
                    .accessibilityIdentifier("diary.toggle")
            } footer: {
                Text("One line about your day, when you want to. Type it here or say “add to my diary: …” and tap Save. It stays on this iPhone, apart from your notes: Doddy's voice can add to it but can't read it, and it isn't in search, widgets or the watch. Doddy won't ask you to write.")
            }
            if isOn {
                Section {
                    TextField("A line about today", text: $line, axis: .vertical)
                        .lineLimit(1...4)
                    Button("Save") { save() }
                        .disabled(line.allSatisfy(\.isWhitespace))
                        .frame(minHeight: 44)
                }
                if let problem { Section { Text(problem).foregroundStyle(Theme.error) } }
            }
            ForEach(days, id: \.day) { day in
                Section(DiaryText.dayTitle(day.day)) {
                    ForEach(day.entries) { entry in
                        Text(entry.text).frame(minHeight: 44, alignment: .leading)
                    }
                    .onDelete { offsets in
                        for index in offsets where !DiaryStore.remove(day.entries[index].id) {
                            problem = NSLocalizedString("That line couldn't be removed. Try again.", comment: "")
                        }
                        load()
                    }
                }
            }
            if !days.isEmpty {
                Section {
                    Button("Delete the whole diary", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .navigationTitle("Diary")
        .onAppear(perform: load)
        .confirmationDialog("Delete every line in your diary?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete the diary", role: .destructive) {
                if !DiaryStore.deleteAll() { problem = NSLocalizedString("The diary couldn't be deleted. Try again.", comment: "") }
                load()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func save() {
        switch DiaryStore.add(line) {
        case .saved:
            line = ""
            problem = nil
        case .problem(.tooLong):
            problem = String(format: NSLocalizedString("Keep it under %lld characters.", comment: ""), Diary.maxLength)
        case .problem:
            problem = NSLocalizedString("It wasn't saved. Try again.", comment: "")
        case .notSaved:
            problem = NSLocalizedString("It wasn't saved. Try again.", comment: "")
        }
        load()
    }

    private func load() { days = DiaryStore.current().days }
}

enum DiaryText {
    /// "Saturday, 11 October" for "2026-10-11".
    static func dayTitle(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return day }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
