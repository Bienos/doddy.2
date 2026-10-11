import Foundation

// Watch complications and the Smart Stack (ADR-257). The watch app already receives the iPhone's
// widget snapshot (ADR-232); it now also writes it to the watch's own App Group folder, and a
// watch widget extension draws it on the watch face and in the Smart Stack. A watch face is seen
// by anyone nearby and stays on with Always On, so a complication shows only times, counts and
// list names: never the words of a note or a reminder, and never list items.

public struct ComplicationContent: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// No snapshot on the watch yet (or no App Group): "Open Doddy on your iPhone".
        case notReady
        /// "Show in widgets" is off on the iPhone: nothing of the user's is shown.
        case off
        case ready
    }

    public struct ListLine: Equatable, Sendable {
        public let name: String
        public let openCount: Int

        public init(name: String, openCount: Int) {
            self.name = name
            self.openCount = openCount
        }
    }

    public let state: State
    /// The next Doddy note reminder still ahead, as a time only.
    public let nextReminder: Date?
    /// Open items across the lists in the snapshot.
    public let openItems: Int
    /// The list with the most open items, for the larger complications.
    public let topList: ListLine?

    /// The Smart Stack raises the widget in the hour before a reminder.
    public static let soonWindow: TimeInterval = 3600

    public static func make(_ snapshot: WidgetSnapshot?, at date: Date) -> ComplicationContent {
        guard let snapshot else { return ComplicationContent(state: .notReady, nextReminder: nil, openItems: 0, topList: nil) }
        guard snapshot.isOn else { return ComplicationContent(state: .off, nextReminder: nil, openItems: 0, topList: nil) }
        let top = snapshot.lists.filter { $0.openCount > 0 }
            .max { $0.openCount != $1.openCount ? $0.openCount < $1.openCount : $0.name > $1.name }
        return ComplicationContent(
            state: .ready,
            nextReminder: snapshot.reminders(after: date).map(\.fireAt).min(),
            openItems: snapshot.lists.reduce(0) { $0 + $1.openCount },
            topList: top.map { ListLine(name: $0.name, openCount: $0.openCount) })
    }

    /// How much the Smart Stack should want this widget at `date`, 0 to 1: high in the hour
    /// before the next reminder, a little when lists have things left, otherwise nothing.
    public func relevance(at date: Date) -> Double {
        guard state == .ready else { return 0 }
        if let next = nextReminder, next > date, next.timeIntervalSince(date) <= Self.soonWindow {
            return 1 - 0.5 * next.timeIntervalSince(date) / Self.soonWindow
        }
        return openItems > 0 ? 0.1 : 0
    }

    /// Timeline entries: now, an hour before each reminder (the Smart Stack raises it), and just
    /// after each one (so it drops off). At most 12, in order.
    public static func timelineDates(_ snapshot: WidgetSnapshot?, from now: Date) -> [Date] {
        let fires = snapshot?.reminders(after: now).map(\.fireAt) ?? []
        let dates = fires.flatMap { [$0.addingTimeInterval(-soonWindow), $0.addingTimeInterval(1)] }.filter { $0 > now }
        return Array(([now] + Set(dates).sorted()).prefix(12))
    }
}
