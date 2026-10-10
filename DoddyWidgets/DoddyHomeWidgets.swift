import AppIntents
import DoddyCore
import SwiftUI
import WidgetKit

// Home Screen and Lock Screen widgets (ADR-215).
// - Talk to Doddy: buttons that run the same intents as the controls and Siri, so no web link can
//   open the microphone. No data.
// - Pinned notes and Next note reminder: read the app's snapshot (`WidgetSnapshotFile`). Note words
//   are `.privacySensitive()`, so iOS hides them on a locked Lock Screen. Taps open the note.
// Nothing here goes on the network, and the widgets never write anything.

private enum WidgetPalette {
    static let card = Color("CardBackground")
    static let ink = Color("Ink")
    static let secondary = Color("SecondaryText")
    static let accentText = Color("AccentText")
}

// MARK: Talk to Doddy

struct TalkWidget: Widget {
    static let kind = "com.bienos.doddy2.widget.talk"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StaticProvider()) { _ in
            TalkWidgetView()
        }
        .configurationDisplayName("Talk to Doddy")
        .description("Start a voice conversation, or write a new note. Doddy opens first; he listens only while the conversation is open.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct StaticEntry: TimelineEntry { let date: Date }

struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) { completion(StaticEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

private struct TalkWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Button(intent: TalkToDoddyIntent()) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .accessibilityLabel("Talk to Doddy")
            }
            .buttonStyle(.plain)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .systemMedium:
            HStack(spacing: 12) {
                actionButton("Talk to Doddy", systemImage: "waveform", intent: TalkToDoddyIntent())
                actionButton("New note", systemImage: "square.and.pencil", intent: NewNoteIntent())
            }
            .containerBackground(WidgetPalette.card, for: .widget)
        default:
            actionButton("Talk to Doddy", systemImage: "waveform", intent: TalkToDoddyIntent())
                .containerBackground(WidgetPalette.card, for: .widget)
        }
    }

    private func actionButton(_ title: String, systemImage: String, intent: some AppIntent) -> some View {
        Button(intent: intent) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(WidgetPalette.accentText)
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Snapshot timeline (pinned notes, next reminder)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let read: WidgetSnapshotFile.ReadResult
    /// The widget gallery's placeholder: drawn as grey bars, never invented notes.
    var isPlaceholder = false
}

struct SnapshotProvider: TimelineProvider {
    private static let placeholderSnapshot = WidgetSnapshot(
        generatedAt: .now, showsNoteWords: true,
        pinned: [WidgetSnapshot.Note(id: UUID(), text: "Your pinned notes appear here", savedAt: nil)],
        upcoming: [WidgetSnapshot.Reminder(memoryID: UUID(), fireAt: .now.addingTimeInterval(3600), text: "Your next note reminder")],
        placeReminders: 0)

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, read: .snapshot(Self.placeholderSnapshot), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapshotEntry(date: .now, read: WidgetSnapshotFile.read()))
    }

    /// One entry now and one at each reminder time, so "next" moves on by itself. The app asks
    /// WidgetKit to redraw whenever notes, pins or reminders change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let read = WidgetSnapshotFile.read()
        var dates = [now]
        if case .snapshot(let snapshot) = read { dates += snapshot.redrawTimes(after: now) }
        completion(Timeline(entries: dates.map { SnapshotEntry(date: $0, read: read) }, policy: .never))
    }
}

/// What a note widget says when it has nothing from the app.
private struct SnapshotProblemView: View {
    let read: WidgetSnapshotFile.ReadResult

    var body: some View {
        Text(read == .notSetUp
             ? "This Doddy build isn't set up to share notes with widgets."
             : "Open Doddy once to show this here.")
            .font(.caption)
            .foregroundStyle(WidgetPalette.secondary)
    }
}

// MARK: Pinned notes

struct PinnedNotesWidget: Widget {
    static let kind = "com.bienos.doddy2.widget.pinned"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            PinnedNotesView(entry: entry)
        }
        .configurationDisplayName("Pinned notes")
        .description("Notes you pinned in Doddy. Their words are hidden on a locked Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PinnedNotesView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pinned", systemImage: "pin.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.accentText)
            switch entry.read {
            case .snapshot(let snapshot):
                if snapshot.pinned.isEmpty {
                    Text("Pin a note in Doddy to see it here.")
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.secondary)
                } else {
                    let shown = family == .systemSmall ? Array(snapshot.pinned.prefix(1)) : snapshot.pinned
                    ForEach(shown) { note in
                        Link(destination: NoteLink.url(for: note.id)) {
                            Text(note.text ?? "Pinned note")
                                .font(family == .systemSmall ? .callout : .footnote)
                                .foregroundStyle(WidgetPalette.ink)
                                .lineLimit(family == .systemSmall ? 5 : 2)
                                .privacySensitive()
                        }
                    }
                }
            default:
                SnapshotProblemView(read: entry.read)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .widgetURL(firstNoteURL)
        .containerBackground(WidgetPalette.card, for: .widget)
    }

    private var firstNoteURL: URL? {
        guard case .snapshot(let snapshot) = entry.read, let first = snapshot.pinned.first else { return DeepLink.memories.url }
        return NoteLink.url(for: first.id)
    }
}

// MARK: Next note reminder

struct NextReminderWidget: Widget {
    static let kind = "com.bienos.doddy2.widget.nextReminder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            NextReminderView(entry: entry)
        }
        .configurationDisplayName("Next note reminder")
        .description("When Doddy reminds you of a note next. The note's words are hidden on a locked Lock Screen.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

private struct NextReminderView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var next: WidgetSnapshot.Reminder? {
        guard case .snapshot(let snapshot) = entry.read else { return nil }
        return snapshot.next(after: entry.date)
    }

    private var placeCount: Int {
        guard case .snapshot(let snapshot) = entry.read else { return 0 }
        return snapshot.placeReminders
    }

    var body: some View {
        content
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
            .widgetURL(next.map { NoteLink.url(for: $0.memoryID) } ?? DeepLink.memories.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let next {
                Text("Doddy: note at \(next.fireAt, style: .time)")
            } else {
                Text("Doddy: no note reminders")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let next {
                    Text("Note · \(next.fireAt, style: .time)")
                        .font(.headline)
                    Text(next.text ?? "Open Doddy to see it")
                        .font(.caption)
                        .lineLimit(2)
                        .privacySensitive()
                } else if case .snapshot = entry.read {
                    Text("No note reminders")
                        .font(.headline)
                    if placeCount > 0 { Text(placeText).font(.caption) }
                } else {
                    SnapshotProblemView(read: entry.read)
                }
            }
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label("Next reminder", systemImage: "bell")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.accentText)
                if let next {
                    Text(next.fireAt, style: .time)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(WidgetPalette.ink)
                    Text(next.fireAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(WidgetPalette.secondary)
                    Text(next.text ?? "Open Doddy to see it")
                        .font(.footnote)
                        .foregroundStyle(WidgetPalette.ink)
                        .lineLimit(3)
                        .privacySensitive()
                } else if case .snapshot = entry.read {
                    Text("No note reminders coming up.")
                        .font(.footnote)
                        .foregroundStyle(WidgetPalette.secondary)
                    if placeCount > 0 {
                        Text(placeText).font(.caption).foregroundStyle(WidgetPalette.secondary)
                    }
                } else {
                    SnapshotProblemView(read: entry.read)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(WidgetPalette.card, for: .widget)
        }
    }

    private var placeText: String {
        placeCount == 1 ? "1 place reminder set" : "\(placeCount) place reminders set"
    }
}
