import AppIntents
import DoddyCore
import SwiftUI
import WidgetKit

// Home and Lock Screen widgets (ADR-219). They only read the snapshot the app writes to the App
// Group (`WidgetSnapshotFile`); they never open the notes database. Note text is marked
// privacy-sensitive, so iOS hides it on the Lock Screen while the iPhone is locked. A tap on a
// note opens it in Doddy; a tap on a list item runs `ToggleListItemIntent` in the app.

// MARK: Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil: not set up (no App Group) or the file can't be read yet.
    let snapshot: WidgetSnapshot?
}

/// Pinned notes, the next reminder and Talk to Doddy. A new entry at each reminder time, so a
/// passed reminder drops off even before the app writes again.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .preview) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetSnapshotFile.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotFile.read()
        let now = Date()
        let times = [now] + (snapshot?.reminders(after: now).map(\.fireAt) ?? []).map { $0.addingTimeInterval(1) }
        let entries = times.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

// MARK: Pinned notes

struct PinnedNotesWidget: Widget {
    static let kind = "com.bienos.doddy2.pinned"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            PinnedNotesView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned notes")
        .description("Notes you pinned in Doddy. Tap one to open it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct PinnedNotesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let message = WidgetCopy.message(for: entry.snapshot) {
            WidgetMessage(text: message, turnedAway: WidgetCopy.isTurnedOff(entry.snapshot))
        } else if let notes = entry.snapshot?.pinned, !notes.isEmpty {
            let shown = Array(notes.prefix(family == .systemMedium ? 4 : family == .systemSmall ? 2 : 1))
            VStack(alignment: .leading, spacing: 6) {
                if family != .accessoryRectangular {
                    Label("Pinned", systemImage: "pin.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(shown) { note in
                    Link(destination: WidgetLink.open(note.id)) {
                        Text(note.text)
                            .font(family == .accessoryRectangular ? .body : .subheadline)
                            .lineLimit(family == .systemSmall ? 3 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .privacySensitive()
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(shown.first.map { WidgetLink.open($0.id) })
        } else {
            WidgetMessage(text: "Pin a note in Doddy to see it here.")
        }
    }
}

// MARK: Next reminder

struct NextReminderWidget: Widget {
    static let kind = "com.bienos.doddy2.nextreminder"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            NextReminderView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next reminder")
        .description("Your next note reminder at a time. Place reminders aren't shown.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct NextReminderView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SnapshotEntry

    var body: some View {
        if let message = WidgetCopy.message(for: entry.snapshot) {
            WidgetMessage(text: message, turnedAway: WidgetCopy.isTurnedOff(entry.snapshot))
        } else if let next = entry.snapshot?.reminders(after: entry.date).first {
            let what = next.text ?? "A note reminder"
            let when = Text(next.fireAt, format: .dateTime.weekday(.abbreviated).hour().minute())
            switch family {
            case .accessoryInline:
                Label { Text("\(when) · \(what)").privacySensitive() } icon: { Image(systemName: "bell") }
                    .widgetURL(WidgetLink.open(next.memoryID))
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 4) {
                        Label { when.font(.headline) } icon: { Image(systemName: "bell.fill") }
                        // Reaching for it (ADR-299): the island's pose for a reminder waiting.
                        if family == .systemSmall, renderingMode == .fullColor {
                            Spacer(minLength: 0)
                            WidgetPose(pose: .reachingHigh, height: 44)
                        }
                    }
                    Text(what).font(.subheadline).lineLimit(family == .systemSmall ? 4 : 2).privacySensitive()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(WidgetLink.open(next.memoryID))
            }
        } else {
            WidgetMessage(text: "No reminders coming up.")
        }
    }
}

// MARK: Where did I park

/// The parking spot (ADR-315): when it was saved and the user's note, never the position. A tap
/// opens Doddy, which opens the spot in Maps.
struct ParkingWidget: Widget {
    static let kind = "com.bienos.doddy2.parking"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            ParkingWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Where I parked")
        .description("When you saved your parking spot, and your note. Tap to open it in Maps.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct ParkingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let message = WidgetCopy.message(for: entry.snapshot) {
            WidgetMessage(text: message, turnedAway: WidgetCopy.isTurnedOff(entry.snapshot))
        } else if let parked = entry.snapshot?.parking {
            let when = Text(parked.savedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
            switch family {
            case .accessoryInline:
                Label { when } icon: { Image(systemName: "car") }
                    .widgetURL(DeepLink.parking.url)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Parked", systemImage: "car.fill").font(.headline)
                    when.font(.subheadline)
                    if let note = parked.note {
                        Text(note).font(.footnote).lineLimit(family == .systemSmall ? 3 : 1).privacySensitive()
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(DeepLink.parking.url)
            }
        } else {
            WidgetMessage(text: "No parking spot saved. Tell Doddy \u{201C}I parked here\u{201D}.")
        }
    }
}

// MARK: List, with ticks

struct ListEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Doddy list" }
    static var defaultQuery: ListEntityQuery { ListEntityQuery() }

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ListEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ListEntity] {
        lists().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ListEntity] { lists() }

    private func lists() -> [ListEntity] {
        (WidgetSnapshotFile.read()?.lists ?? []).map { ListEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct SelectListIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a list"
    static var description: IntentDescription { IntentDescription("The Doddy list this widget shows.") }

    @Parameter(title: "List") var list: ListEntity?

    init() {}
}

struct ListEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let list: WidgetSnapshot.List?
    /// A list was chosen but is gone (deleted in Doddy). Never swapped for another list.
    var chosenIsGone = false
}

struct ListProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListEntry {
        ListEntry(date: .now, snapshot: .preview, list: WidgetSnapshot.preview.lists.first)
    }

    func snapshot(for configuration: SelectListIntent, in context: Context) async -> ListEntry {
        context.isPreview ? placeholder(in: context) : entry(for: configuration)
    }

    func timeline(for configuration: SelectListIntent, in context: Context) async -> Timeline<ListEntry> {
        // The app reloads the widgets after every change; nothing here changes with time.
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: SelectListIntent) -> ListEntry {
        let snapshot = WidgetSnapshotFile.read()
        let chosen = configuration.list.flatMap { UUID(uuidString: $0.id) }
        guard let chosen else { return ListEntry(date: .now, snapshot: snapshot, list: snapshot?.lists.first) }
        let list = snapshot?.list(id: chosen)
        return ListEntry(date: .now, snapshot: snapshot, list: list, chosenIsGone: list == nil && snapshot != nil)
    }
}

struct ListWidget: Widget {
    static let kind = "com.bienos.doddy2.list"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectListIntent.self, provider: ListProvider()) { entry in
            ListWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("List")
        .description("One of your Doddy lists. Tap an item to tick it; your iPhone needs to be unlocked.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct ListWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ListEntry

    private var rows: Int {
        switch family {
        case .systemLarge: 10
        case .accessoryRectangular: 2
        default: 4
        }
    }

    var body: some View {
        if let message = WidgetCopy.message(for: entry.snapshot) {
            WidgetMessage(text: message, turnedAway: WidgetCopy.isTurnedOff(entry.snapshot))
        } else if let list = entry.list {
            VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 1 : 6) {
                HStack {
                    Text(list.name).font(.headline).lineLimit(1).privacySensitive()
                    Spacer()
                    Text(list.openCount == 0 ? "All done" : "\(list.openCount) to go")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if list.items.isEmpty {
                    Text("Nothing on this list yet.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(list.items.prefix(rows)) { item in
                    Button(intent: ToggleListItemIntent(listID: list.id, itemID: item.id, shownDone: item.isDone)) {
                        HStack(spacing: 6) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            Text(item.text).strikethrough(item.isDone).lineLimit(1).privacySensitive()
                            Spacer(minLength: 0)
                        }
                        .font(family == .accessoryRectangular ? .caption : .subheadline)
                        .foregroundStyle(item.isDone ? .secondary : .primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.isDone ? "\(item.text), ticked" : item.text)
                    .accessibilityHint(item.isDone ? "Untick" : "Tick")
                }
                Spacer(minLength: 0)
            }
            .widgetURL(WidgetLink.open(list.id))
        } else if entry.chosenIsGone {
            WidgetMessage(text: "This list isn't in Doddy any more. Choose another.")
        } else {
            WidgetMessage(text: "Make a list in Doddy, then choose it here.")
        }
    }
}

// MARK: Talk to Doddy

struct TalkToDoddyWidget: Widget {
    static let kind = "com.bienos.doddy2.talkwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { _ in
            TalkToDoddyWidgetView().containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Talk to Doddy")
        .description("Opens Doddy and starts a voice conversation.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct TalkToDoddyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Button(intent: TalkToDoddyIntent()) {
            if family == .accessoryCircular {
                // Doddy's face on the Lock Screen (ADR-313), the watch complication's crop. iOS draws
                // Lock Screen widgets in one tint, so the cream face reads light and his lines dark.
                ZStack {
                    AccessoryWidgetBackground()
                    if WidgetDoddyArt.isHidden {
                        // "Hide character artwork" is on in Doddy (ADR-331).
                        Image(systemName: "waveform").font(.title2)
                    } else {
                        Image("WidgetDoddy_face")
                            .resizable()
                            .scaledToFit()
                            .clipShape(Circle())
                            .padding(4)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("Talk to Doddy")
            } else {
                VStack(spacing: 8) {
                    // Doddy waving hello (ADR-299), as when "Hey Doddy" greets you. Tinted and
                    // clear Home Screens keep the symbol: the drawing doesn't tint well.
                    if renderingMode == .fullColor, !WidgetDoddyArt.isHidden {
                        WidgetPose(pose: .wave, height: 76)
                    } else {
                        Image(systemName: "waveform").font(.largeTitle)
                    }
                    Text("Talk to Doddy").font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: Doddy, resting (StandBy)

/// Made for StandBy (ADR-313): Doddy stretching, eyes closed, and the time of the next note
/// reminder. Only the time, never the note's words: StandBy is seen across the room. Works as
/// a small Home Screen widget too.
struct DoddyRestWidget: Widget {
    static let kind = "com.bienos.doddy2.rest"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            DoddyRestView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Doddy, resting")
        .description("Doddy and the time of your next reminder. Made for StandBy. No note words are shown.")
        .supportedFamilies([.systemSmall])
    }
}

struct DoddyRestView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SnapshotEntry

    var body: some View {
        VStack(spacing: 6) {
            // A tinted Home Screen flattens the drawing into one colour; there it is left out.
            if renderingMode != .accented {
                WidgetPose(pose: .yawnStretch, height: 92)
            }
            if let message = WidgetCopy.message(for: entry.snapshot) {
                Text(message).font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            } else if let next = entry.snapshot?.reminders(after: entry.date).first {
                Label { Text(next.fireAt, format: .dateTime.weekday(.abbreviated).hour().minute()) } icon: { Image(systemName: "bell") }
                    .font(.headline)
                    .monospacedDigit()
            } else {
                Text("No reminders coming up.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Shared pieces

/// Doddy in a Home Screen widget (ADR-299): a Whole Doddy pose from the owner's pack, the same
/// as the island's for the same meaning. Decorative; full-colour widgets only. In dark
/// appearance the outline gets the island's thin cream edge.
struct WidgetPose: View {
    let pose: IslandPose
    let height: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Nothing when "Hide character artwork" is on in Doddy (ADR-331).
        if !WidgetDoddyArt.isHidden {
            let box = pose.figure
            let width = height * CGFloat(box.width / box.height) / 1.5
            IslandPoseView(pose: pose, maxSize: CGSize(width: width, height: height), edged: colorScheme == .dark)
        }
    }
}

/// "Hide character artwork" in the app (ADR-331), passed on in the shared snapshot. Widgets and
/// Live Activities then leave Doddy's pictures out; the island falls back to its board. A build
/// without the App Group can't know, and shows him.
enum WidgetDoddyArt {
    static var isHidden: Bool { WidgetSnapshotFile.read()?.hidesPictures == true }
}

extension IslandScene {
    /// The scene as a widget draws it: no Whole Doddy pose when his pictures are hidden (ADR-331).
    var respectingHiddenArt: IslandScene {
        guard WidgetDoddyArt.isHidden else { return self }
        var scene = self
        scene.pose = nil
        return scene
    }
}

enum WidgetCopy {
    /// Widgets were turned off in Doddy's Settings: there is a snapshot, and it says off.
    static func isTurnedOff(_ snapshot: WidgetSnapshot?) -> Bool {
        WidgetSnapshotFile.url != nil && snapshot.map { !$0.isOn } == true
    }

    /// Why a widget shows none of the user's things, or nil when it can.
    static func message(for snapshot: WidgetSnapshot?) -> String? {
        guard WidgetSnapshotFile.url != nil else { return "Open Doddy to set up widgets." }
        guard let snapshot else { return "Open Doddy once to fill this widget." }
        return snapshot.isOn ? nil : "Turned off in Doddy's Settings."
    }
}

struct WidgetMessage: View {
    let text: String
    /// The user turned widgets off in Doddy (ADR-331): Doddy turned away, not looking. Home Screen
    /// sizes in full colour only; `WidgetPose` also respects "Hide character artwork".
    var turnedAway = false
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if turnedAway, renderingMode == .fullColor, family == .systemSmall || family == .systemMedium {
                WidgetPose(pose: .turnedAway, height: 60)
            }
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

extension WidgetSnapshot {
    /// Made-up content for the widget gallery only; never the user's.
    static let preview: WidgetSnapshot = {
        let list = UUID()
        return WidgetSnapshot(
            writtenAt: .now, isOn: true,
            pinned: [.init(id: UUID(), text: "Spare keys: blue tin, top shelf"), .init(id: UUID(), text: "Locker code 4512")],
            reminders: [.init(memoryID: UUID(), fireAt: .now.addingTimeInterval(3600), timeZoneID: TimeZone.current.identifier, text: "Call the dentist")],
            lists: [.init(id: list, name: "Shopping", openCount: 2, doneCount: 1, items: [
                .init(id: UUID(), text: "Oat milk", isDone: false),
                .init(id: UUID(), text: "Eggs", isDone: false),
                .init(id: UUID(), text: "Bread", isDone: true),
            ])],
            parking: .init(savedAt: .now.addingTimeInterval(-5400), note: "Level 2, row C"))
    }()
}
