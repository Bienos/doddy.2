import DoddyCore
import Foundation
import WidgetKit

/// Keeps the widgets' snapshot equal to what the app has (ADR-233): rewritten when notes, pins,
/// note reminders or the "note words in widgets" setting change, then WidgetKit is asked to
/// redraw. Does nothing in a build without an App Group, or in UI-test launches.
@MainActor
enum WidgetSync {
    static func update(memories: [MemoryRecord], reminders: [MemoryReminder], defaults: UserDefaults = .standard, now: Date = .now) {
        guard WidgetSnapshotFile.appGroup != nil, !ProcessInfo.processInfo.arguments.contains("-inMemoryStore") else { return }
        let snapshot = WidgetSnapshot.make(
            memories: memories,
            pins: PinnedNotes(stored: defaults.string(forKey: PreferenceKey.pinnedNotes)),
            reminders: reminders,
            showsNoteWords: defaults.object(forKey: PreferenceKey.widgetNoteWords) as? Bool ?? true,
            now: now)
        guard WidgetSnapshotFile.write(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
