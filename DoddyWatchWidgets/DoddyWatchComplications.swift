import DoddyCore
import SwiftUI
import WidgetKit

// Watch face complications and the Smart Stack (ADR-262). They read only the snapshot the watch
// app saved in the watch's App Group folder (from what the iPhone sent, ADR-232), and show only
// times, counts and list names: a watch face is seen by anyone nearby. A tap opens Doddy.

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let content: ComplicationContent
    let relevance: TimelineEntryRelevance?
    /// "Hide character artwork" is on in Doddy on the iPhone (ADR-331): no face.
    var hidesDoddy = false
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { entry(.previewContent, at: .now) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? entry(.previewContent, at: .now) : entry(read(at: .now), at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snapshot = WidgetSnapshotFile.read()
        let now = Date()
        let entries = ComplicationContent.timelineDates(snapshot, from: now).map { date in
            entry(ComplicationContent.make(snapshot, at: date), at: date)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }

    private func read(at date: Date) -> ComplicationContent {
        ComplicationContent.make(WidgetSnapshotFile.read(), at: date)
    }

    private func entry(_ content: ComplicationContent, at date: Date) -> ComplicationEntry {
        let score = content.relevance(at: date)
        return ComplicationEntry(
            date: date, content: content,
            relevance: score > 0 ? TimelineEntryRelevance(score: Float(score), duration: ComplicationContent.soonWindow) : nil,
            hidesDoddy: WidgetSnapshotFile.read()?.hidesPictures == true)
    }
}

struct DoddyComplication: Widget {
    static let kind = "com.bienos.doddy2.watch.complication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Doddy")
        .description("Your next Doddy reminder time and what's left on your lists. No note words are shown.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: ComplicationEntry

    private var content: ComplicationContent { entry.content }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if content.state == .ready, let next = content.nextReminder {
                VStack(spacing: 0) {
                    Image(systemName: "bell")
                    Text(next, format: .dateTime.hour().minute()).font(.system(size: 11)).minimumScaleFactor(0.6)
                }
            } else if content.state == .ready, content.openItems > 0 {
                VStack(spacing: 0) {
                    Image(systemName: "checklist")
                    Text("\(content.openItems)").font(.headline)
                }
            } else if !entry.hidesDoddy, WatchDoddyFace.shows(in: renderingMode) {
                WatchDoddyFace(size: 34)
            } else {
                Image(systemName: "bubble.left")
            }
        }
        .widgetAccentable()
    }

    private var corner: some View {
        Image(systemName: content.nextReminder == nil ? "checklist" : "bell")
            .font(.title3)
            .widgetLabel {
                if let next = content.nextReminder {
                    Text(next, format: .dateTime.hour().minute())
                } else if content.openItems > 0 {
                    Text(String(format: NSLocalizedString("%lld left", comment: ""), content.openItems))
                } else {
                    Text("Doddy")
                }
            }
    }

    @ViewBuilder
    private var inline: some View {
        if let next = content.nextReminder {
            Label {
                Text(String(format: NSLocalizedString("Doddy reminder %@", comment: ""), next.formatted(date: .omitted, time: .shortened)))
            } icon: { Image(systemName: "bell") }
        } else if let list = content.topList {
            Label("\(list.name) · \(list.openCount)", systemImage: "checklist")
        } else {
            Label("Doddy", systemImage: "bubble.left")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if !entry.hidesDoddy, WatchDoddyFace.shows(in: renderingMode) { WatchDoddyFace(size: 18) }
                Text("Doddy").font(.headline).widgetAccentable()
            }
            switch content.state {
            case .notReady:
                Text("Open Doddy on your iPhone.").font(.caption)
            case .off:
                Text("Turned off in Doddy's Settings.").font(.caption)
            case .ready:
                if let next = content.nextReminder {
                    Label {
                        Text(String(format: NSLocalizedString("Reminder at %@", comment: ""), next.formatted(date: .omitted, time: .shortened)))
                    } icon: { Image(systemName: "bell") }
                    .font(.caption)
                }
                if let list = content.topList {
                    Label("\(list.name) · \(list.openCount)", systemImage: "checklist").font(.caption)
                }
                if content.nextReminder == nil, content.topList == nil {
                    Text("Nothing coming up.").font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Doddy's face (ADR-299): a crop of the listening pose from the owner's pack
/// (`WatchDoddy_face`, made by tools/whole_doddy/build_imagesets.py). Drawn only where it keeps
/// its colours: full-colour faces, and tinted faces from watchOS 11 (full-colour rendering).
/// On monochrome faces, and tinted ones before watchOS 11, the symbol or name stays alone.
struct WatchDoddyFace: View {
    let size: CGFloat

    static func shows(in mode: WidgetRenderingMode) -> Bool {
        if mode == .fullColor { return true }
        if mode == .accented {
            if #available(watchOS 11.0, *) { return true }
        }
        return false
    }

    var body: some View {
        face
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    /// On the watchOS SDK `widgetAccentedRenderingMode` returns `some View`, not `Image`, so it
    /// comes after `resizable()`.
    @ViewBuilder private var face: some View {
        let image = Image("WatchDoddy_face").resizable()
        if #available(watchOS 11.0, *) {
            image.widgetAccentedRenderingMode(.fullColor)
        } else {
            image
        }
    }
}

extension ComplicationContent {
    /// Made-up content for the watch face gallery only; never the user's.
    static let previewContent = ComplicationContent.make(
        WidgetSnapshot(
            writtenAt: .now, isOn: true, pinned: [],
            reminders: [.init(memoryID: UUID(), fireAt: .now.addingTimeInterval(3600), timeZoneID: TimeZone.current.identifier, text: nil)],
            lists: [.init(id: UUID(), name: "Shopping", openCount: 4, doneCount: 1, items: [])]),
        at: .now)
}

/// "New note" (ADR-434): a complication that only opens the watch app on its note screen. It
/// shows nothing of the user's, so it never changes and never reads the snapshot. Nothing is
/// recorded until the person taps the text field there.
struct NewNoteComplication: Widget {
    static let kind = "com.bienos.doddy2.watch.newnote"

    struct Entry: TimelineEntry { let date: Date }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .never))
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { _ in
            NewNoteComplicationView()
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WatchCaptureLink.url)
        }
        .configurationDisplayName("New note")
        .description("Opens Doddy's new note. Nothing is recorded until you tap to write or dictate.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct NewNoteComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "square.and.pencil").font(.title3)
            }
            .widgetAccentable()
            .accessibilityLabel("New note in Doddy")
        case .accessoryCorner:
            Image(systemName: "square.and.pencil")
                .font(.title3)
                .widgetLabel { Text("New note") }
                .accessibilityLabel("New note in Doddy")
        case .accessoryInline:
            Label("New note", systemImage: "square.and.pencil")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("Doddy").font(.headline).widgetAccentable()
                Label("New note", systemImage: "square.and.pencil").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct DoddyWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DoddyComplication()
        NewNoteComplication()
    }
}

// Xcode canvas previews (ADR-336): Doddy's face on the complications. Made-up content only.
#Preview("Circular", as: .accessoryCircular) {
    DoddyComplication()
} timeline: {
    ComplicationEntry(date: .now, content: .previewContent, relevance: nil)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    DoddyComplication()
} timeline: {
    ComplicationEntry(date: .now, content: .previewContent, relevance: nil)
}

#Preview("New note", as: .accessoryCircular) {
    NewNoteComplication()
} timeline: {
    NewNoteComplication.Entry(date: .now)
}
