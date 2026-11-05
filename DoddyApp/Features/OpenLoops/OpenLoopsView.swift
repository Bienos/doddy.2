import DoddyCore
import SwiftUI

/// "Na oku" (working name, ADR-728): one read-only list of what Doddy is holding for the person, from the
/// reminders, calendar, tasks, price watches and parcels the app already has. Nothing is created, changed
/// or sent from here, and a source that couldn't be read is named, never shown as empty.
/// NOT COMPILED in the session that wrote it (no Xcode), and not seen on a device: the hosted Mac job is its first build.
struct OpenLoopsView: View {
    @Environment(NoteReminderStore.self) private var reminders
    @Environment(MemoryStore.self) private var store
    @State private var model: OpenLoopsModel?

    private enum Destination: Hashable {
        case note(UUID)
        case task(UUID)
    }

    private var language: NotificationLanguage { NotificationLanguage.preferred(Bundle.main.preferredLocalizations) }

    var body: some View {
        Group {
            if let agenda = model?.agenda {
                list(agenda)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("openLoops.loading")
            }
        }
        .navigationTitle(OpenLoopsText.screenTitle(language))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .note(let id): MemoryOrListView(id: id)
            case .task(let id): ErrandDetailView(id: id)
            }
        }
        .task {
            if model == nil {
                let sources = OpenLoopsSources(noteReminders: reminders, memories: store)
                model = OpenLoopsModel(provider: { await sources.read() })
            }
            await model?.refresh()
        }
    }

    private func list(_ agenda: OpenLoopsAgenda) -> some View {
        List {
            if !agenda.unavailable.isEmpty {
                Section {
                    ForEach(agenda.unavailable, id: \.self) { source in
                        Label(OpenLoopsText.unavailableLine(source, language), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .accessibilityIdentifier("openLoops.unavailable")
                    }
                }
            }
            if agenda.allItems.isEmpty && agenda.unavailable.isEmpty {
                Section {
                    Text(OpenLoopsText.emptyLine(language))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("openLoops.empty")
                }
            }
            ForEach(OpenLoopSection.allCases, id: \.self) { section in
                let items = agenda.items(in: section)
                if !items.isEmpty {
                    Section(OpenLoopsText.sectionTitle(section, language)) {
                        ForEach(items) { row($0) }
                        if let more = agenda.more[section], more > 0 {
                            Text(OpenLoopsText.moreLine(more, language)).font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("openLoops.list")
        .refreshable { await model?.refresh() }
    }

    @ViewBuilder
    private func row(_ item: OpenLoopItem) -> some View {
        switch destination(for: item) {
        case let destination?:
            NavigationLink(value: destination) { OpenLoopRow(item: item, language: language) }
                .accessibilityIdentifier("openLoops.row")
        case nil:
            OpenLoopRow(item: item, language: language)
                .accessibilityIdentifier("openLoops.row")
        }
    }

    /// Only notes and tasks have a screen of their own to open from here; the other sources' rows are read-only.
    private func destination(for item: OpenLoopItem) -> Destination? {
        switch item.source {
        case .noteReminder:
            reminders.reminders.first { $0.id.uuidString == item.sourceID }.map { .note($0.memoryID) }
        case .errand:
            UUID(uuidString: item.sourceID).map { .task($0) }
        default:
            nil
        }
    }
}

private struct OpenLoopRow: View {
    let item: OpenLoopItem
    let language: NotificationLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(OpenLoopsText.title(item, language))
                .font(.body)
                .lineLimit(3)
            Text(OpenLoopsText.status(item.status, language))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            if let when = timeText {
                Text(when).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The moment that matters, in the iPhone's own format. Only for sources whose moment is one the person set;
    /// a parcel's or a task's time is when it was last checked, which isn't news. A midnight start is a day, not a time.
    private var timeText: String? {
        guard let when = item.when, [.noteReminder, .appleReminder, .calendarEvent].contains(item.source) else { return nil }
        let midnight = Calendar.current.startOfDay(for: when) == when
        return when.formatted(date: .abbreviated, time: midnight ? .omitted : .shortened)
    }
}
