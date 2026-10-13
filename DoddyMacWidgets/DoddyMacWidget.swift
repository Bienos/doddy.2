import DoddyCore
import SwiftUI
import WidgetKit

// The Mac desktop widget (ADR-439; the owner's review deck, slide 10: "Cicha półka na biurku Maca").
// How many notes are saved in Doddy on this Mac, and when that was counted. It reads only the
// count file the menu bar app writes in their App Group folder: never a note's words, which a
// desktop would show to anyone nearby. A click opens Doddy (system behaviour only).

struct MacCountEntry: TimelineEntry {
    let date: Date
    let count: MacNoteCount?
}

struct MacCountProvider: TimelineProvider {
    /// Made-up, for the widget gallery only; never the user's.
    private static let sample = MacNoteCount(count: 12, countedAt: .now)

    func placeholder(in context: Context) -> MacCountEntry { MacCountEntry(date: .now, count: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (MacCountEntry) -> Void) {
        completion(MacCountEntry(date: .now, count: context.isPreview ? Self.sample : read()))
    }

    /// The app reloads the widget after each count it wrote and read back, so no schedule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MacCountEntry>) -> Void) {
        completion(Timeline(entries: [MacCountEntry(date: .now, count: read())], policy: .never))
    }

    private func read() -> MacNoteCount? {
        MacGroupFolder.url.flatMap(MacNoteCountFile.read(in:))
    }
}

struct MacCountView: View {
    let entry: MacCountEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Doddy's face from the owner's pack (ADR-438), a copy of the widgets' crop.
                Image("MacDoddy_face")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Text("Doddy").font(.headline)
            }
            Spacer(minLength: 0)
            if let count = entry.count {
                Text(count.count, format: .number)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                Text("Saved on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(count.countedAt, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open Doddy from the menu bar to count your notes here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct DoddyMacCountWidget: Widget {
    static let kind = "com.bienos.doddy2.mac.notecount"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MacCountProvider()) { entry in
            MacCountView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Doddy")
        .description("How many notes are saved in Doddy on this Mac. No note words are shown.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct DoddyMacWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DoddyMacCountWidget()
    }
}

#Preview(as: .systemSmall) {
    DoddyMacCountWidget()
} timeline: {
    MacCountEntry(date: .now, count: MacNoteCount(count: 12, countedAt: .now))
    MacCountEntry(date: .now, count: nil)
}
