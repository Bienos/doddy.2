import Foundation

// Open loops, step L0 (docs/product/KEEP_TRACK_AND_REMIND_DESIGN.md): one read-only list of what Doddy
// is holding for the person right now, built from things that already exist on this iPhone: reminders
// on notes, Apple Reminders, calendar events with a nudge, tasks handed over, price watches and
// parcels. It stores nothing, schedules nothing, sends nothing and invents nothing: every row is one
// source's own record, and a source that could not be read is named as unreadable, never shown as empty.
// Plain Swift so it is tested on Linux. Words for the screen come from the app's string catalogs.

/// Where a row comes from. A row always opens its source.
public enum OpenLoopSource: String, CaseIterable, Sendable {
    case noteReminder, appleReminder, calendarEvent, errand, priceWatch, parcel
}

/// Where a row is listed. The order is the order on the screen.
public enum OpenLoopSection: Int, CaseIterable, Comparable, Sendable {
    /// Needs the person today: due, overdue, ready to collect, finished, a price that was reached.
    case today
    /// Nothing for the person to do yet: a task running, a parcel on its way.
    case waiting
    /// Doddy is checking something for them: an active price watch.
    case watching
    /// Later: a reminder or an event with a nudge that isn't today, a place reminder.
    case later

    public static func < (lhs: OpenLoopSection, rhs: OpenLoopSection) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The words of a row.
public enum OpenLoopTitle: Equatable, Sendable {
    /// The person's own words, or the source's own title, exactly as stored.
    case text(String)
    /// No words to show: a private note's reminder (its words need Face ID), an item the person never
    /// named, a note that no longer exists. The screen uses the source's generic name instead.
    case hidden
}

/// What is true about a row, as a value. The screen turns it into a sentence; nothing here is text.
public enum OpenLoopStatus: Equatable, Sendable {
    case overdue
    case dueToday(hasTime: Bool)
    /// Set for a later time, or an event that is on today's calendar.
    case scheduled
    /// A Reminders item with no date.
    case noDate
    case repeating(ReminderRepeat)
    /// A reminder that fires when the person arrives at (or leaves) a place they picked.
    case atPlace(String)
    case nudgeSet(leadMinutes: Int)
    /// The event moved after the nudge was set, so the nudge would fire at the old time.
    case nudgeAtOldTime
    case queued
    case running
    /// A task that ended with `done`. The result is read from the task, never from here.
    case finished
    /// A task or a watch that ended without what the person asked for.
    case failed
    case watching(lastPrice: Money?, threshold: Money)
    /// The server confirmed a price at or below the person's number.
    case priceReached(Money?)
    case parcel(ParcelStatusKind)
    /// The source's answer is `unknown`, so nothing is claimed: never read as success or as active.
    case cannotConfirm
}

/// One row. `id` is stable for the same source record, so a row can keep its place on the screen.
public struct OpenLoopItem: Equatable, Sendable, Identifiable {
    public let source: OpenLoopSource
    /// The record's own id in its source.
    public let sourceID: String
    public let title: OpenLoopTitle
    public let section: OpenLoopSection
    public let status: OpenLoopStatus
    /// The moment that matters for ordering (due, start, next time, last answer), when the source has one.
    public let when: Date?

    public var id: String { "\(source.rawValue):\(sourceID)" }

    public init(source: OpenLoopSource, sourceID: String, title: OpenLoopTitle, section: OpenLoopSection,
                status: OpenLoopStatus, when: Date?) {
        self.source = source
        self.sourceID = sourceID
        self.title = title
        self.section = section
        self.status = status
        self.when = when
    }
}

/// A reminder on a note and the words to show for it. `title` is `.hidden` for a private note, a note
/// that was deleted, or when the person hid note words on the Lock Screen and Home.
public struct OpenLoopNoteReminder: Equatable, Sendable {
    public let reminder: MemoryReminder
    public let title: OpenLoopTitle

    public init(reminder: MemoryReminder, title: OpenLoopTitle) {
        self.reminder = reminder
        self.title = title
    }
}

/// Everything the builder may read. The caller fills only what it was allowed to read, and names in
/// `unavailable` any source it could not read now (a permission is off, a store failed to open).
public struct OpenLoopsInput: Sendable {
    public var noteReminders: [OpenLoopNoteReminder]
    public var appleReminders: [ReminderSummary]
    public var events: [CalendarEventSummary]
    /// The nudges iOS says it will fire (`ScheduledNudge`, read back from the pending list).
    public var nudges: [ScheduledNudge]
    public var errands: [StoredErrand]
    public var watches: [WatchSummary]
    public var parcels: [ParcelEntry]
    public var unavailable: Set<OpenLoopSource>

    public init(noteReminders: [OpenLoopNoteReminder] = [], appleReminders: [ReminderSummary] = [],
                events: [CalendarEventSummary] = [], nudges: [ScheduledNudge] = [], errands: [StoredErrand] = [],
                watches: [WatchSummary] = [], parcels: [ParcelEntry] = [], unavailable: Set<OpenLoopSource> = []) {
        self.noteReminders = noteReminders
        self.appleReminders = appleReminders
        self.events = events
        self.nudges = nudges
        self.errands = errands
        self.watches = watches
        self.parcels = parcels
        self.unavailable = unavailable
    }
}

/// The list the screen shows.
public struct OpenLoopsAgenda: Equatable, Sendable {
    /// Rows per section on the full page. Home's small card asks for fewer.
    public static let defaultLimit = 20

    public let sections: [OpenLoopSection: [OpenLoopItem]]
    /// Rows cut by the limit, per section: "And N more".
    public let more: [OpenLoopSection: Int]
    /// Sources that could not be read now, in `OpenLoopSource.allCases` order. The screen says so for
    /// each; it is never the same as "nothing there".
    public let unavailable: [OpenLoopSource]

    public func items(in section: OpenLoopSection) -> [OpenLoopItem] { sections[section] ?? [] }

    public var allItems: [OpenLoopItem] { OpenLoopSection.allCases.flatMap { items(in: $0) } }

    /// No row and nothing unreadable. An agenda with an unreadable source is not "empty".
    public var isEmpty: Bool { allItems.isEmpty && unavailable.isEmpty }
}

public enum OpenLoopsBuilder {
    /// Finished tasks and watches stay in "Today" this long, as `ThreadTaskResults` does for tasks.
    public static let finishedWindow: TimeInterval = ThreadTaskResults.window

    public static func build(_ input: OpenLoopsInput, now: Date, calendar: Calendar,
                             limitPerSection: Int = OpenLoopsAgenda.defaultLimit) -> OpenLoopsAgenda {
        let context = Context(now: now, calendar: calendar,
                              endOfDay: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)
        let readable = { (source: OpenLoopSource) in !input.unavailable.contains(source) }

        var items: [OpenLoopItem] = []
        if readable(.noteReminder) { items += input.noteReminders.compactMap { noteReminder($0, context) } }
        if readable(.appleReminder) { items += input.appleReminders.map { appleReminder($0, context) } }
        if readable(.calendarEvent) { items += input.events.compactMap { event($0, nudges: input.nudges, context) } }
        if readable(.errand) { items += input.errands.compactMap { errand($0, context) } }
        if readable(.priceWatch) { items += input.watches.compactMap { watch($0, context) } }
        if readable(.parcel) { items += input.parcels.compactMap { parcel($0, context) } }

        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }

        let limit = max(0, limitPerSection)
        var sections: [OpenLoopSection: [OpenLoopItem]] = [:]
        var more: [OpenLoopSection: Int] = [:]
        for section in OpenLoopSection.allCases {
            let rows = items.filter { $0.section == section }.sorted(by: order)
            sections[section] = Array(rows.prefix(limit))
            more[section] = max(0, rows.count - limit)
        }
        let unreadable = OpenLoopSource.allCases.filter { input.unavailable.contains($0) }
        return OpenLoopsAgenda(sections: sections, more: more, unavailable: unreadable)
    }

    // MARK: Order

    /// Earliest moment first, rows without one last, then by source, words and id, so the same input
    /// always gives the same list whatever order the sources returned it in.
    private static func order(_ a: OpenLoopItem, _ b: OpenLoopItem) -> Bool {
        let at = a.when ?? .distantFuture, bt = b.when ?? .distantFuture
        if at != bt { return at < bt }
        let ai = OpenLoopSource.allCases.firstIndex(of: a.source) ?? 0, bi = OpenLoopSource.allCases.firstIndex(of: b.source) ?? 0
        if ai != bi { return ai < bi }
        let atitle = sortKey(a.title), btitle = sortKey(b.title)
        if atitle != btitle { return atitle < btitle }
        return a.id < b.id
    }

    private static func sortKey(_ title: OpenLoopTitle) -> String {
        if case .text(let text) = title { return text.lowercased() }
        return ""
    }

    // MARK: Sources

    private struct Context {
        let now: Date
        let calendar: Calendar
        let endOfDay: Date
    }

    /// A moment the person is waiting for: past, today, or later.
    private static func placing(_ due: Date, hasTime: Bool, _ c: Context) -> (OpenLoopSection, OpenLoopStatus) {
        let overdue = hasTime ? due < c.now : due < c.calendar.startOfDay(for: c.now)
        if overdue { return (.today, .overdue) }
        if due < c.endOfDay { return (.today, .dueToday(hasTime: hasTime)) }
        return (.later, .scheduled)
    }

    private static func noteReminder(_ entry: OpenLoopNoteReminder, _ c: Context) -> OpenLoopItem? {
        let reminder = entry.reminder
        let id = reminder.id.uuidString
        func item(_ section: OpenLoopSection, _ status: OpenLoopStatus, _ when: Date?) -> OpenLoopItem {
            OpenLoopItem(source: .noteReminder, sourceID: id, title: entry.title, section: section, status: status, when: when)
        }
        if let place = reminder.place { return item(.later, .atPlace(place.name), nil) }
        if let rule = reminder.repeats {
            if reminder.isDue(at: c.now) {
                // The occurrence that is waiting (or the snooze that has come), not the first one ever set.
                let waiting = reminder.snoozedUntil.flatMap { $0 <= c.now ? $0 : nil }
                    ?? reminder.timeZoneID.flatMap { zone in
                        reminder.fireAt.flatMap { ReminderSchedule.previous(atOrBefore: c.now, rule, anchor: $0, timeZoneID: zone) }
                    }
                return item(.today, .overdue, waiting ?? reminder.fireAt)
            }
            let next = reminder.nextFire(after: c.now)
            let section: OpenLoopSection = (next.map { $0 < c.endOfDay } ?? false) ? .today : .later
            return item(section, .repeating(rule), next)
        }
        guard let fireAt = reminder.fireAt else { return nil }
        if reminder.isDue(at: c.now) { return item(.today, .overdue, fireAt) }
        let (section, status) = placing(fireAt, hasTime: true, c)
        return item(section, status, fireAt)
    }

    private static func appleReminder(_ reminder: ReminderSummary, _ c: Context) -> OpenLoopItem {
        guard let due = reminder.due else {
            return OpenLoopItem(source: .appleReminder, sourceID: reminder.id, title: .text(reminder.title), section: .later,
                                status: .noDate, when: nil)
        }
        let (section, status) = placing(due, hasTime: reminder.dueHasTime, c)
        return OpenLoopItem(source: .appleReminder, sourceID: reminder.id, title: .text(reminder.title), section: section,
                            status: status, when: due)
    }

    /// An event is listed when it is still to come today, or later when Doddy holds a nudge for it.
    private static func event(_ event: CalendarEventSummary, nudges: [ScheduledNudge], _ c: Context) -> OpenLoopItem? {
        guard event.end > c.now else { return nil }
        let id = event.id ?? "\(Int(event.start.timeIntervalSince1970))-\(event.title)"
        let mine = event.id.map { eventID in nudges.filter { $0.eventID == eventID } } ?? []
        let status: OpenLoopStatus
        if let right = mine.first(where: { $0.fits(event) == true }), let lead = right.leadMinutes {
            status = .nudgeSet(leadMinutes: lead)
        } else if !mine.isEmpty {
            status = .nudgeAtOldTime
        } else {
            status = .scheduled
        }
        let today = event.start < c.endOfDay
        guard today || !mine.isEmpty else { return nil }
        return OpenLoopItem(source: .calendarEvent, sourceID: id, title: .text(event.title), section: today ? .today : .later,
                            status: status, when: event.start)
    }

    private static func errand(_ errand: StoredErrand, _ c: Context) -> OpenLoopItem? {
        func item(_ section: OpenLoopSection, _ status: OpenLoopStatus) -> OpenLoopItem {
            OpenLoopItem(source: .errand, sourceID: errand.id.uuidString, title: .text(errand.title), section: section,
                         status: status, when: errand.updatedAt)
        }
        let recent = c.now.timeIntervalSince(errand.updatedAt) <= finishedWindow
        switch errand.state {
        case .queued: return item(.waiting, .queued)
        case .running: return item(.waiting, .running)
        case .done: return recent ? item(.today, .finished) : nil
        case .failed: return recent ? item(.today, .failed) : nil
        // Never read as success, never dropped: the answer to the approval didn't come back.
        case .unknown: return item(.waiting, .cannotConfirm)
        // A draft was never handed over, and a cancelled task was the person's own choice.
        case .draft, .cancelled: return nil
        }
    }

    private static func watch(_ watch: WatchSummary, _ c: Context) -> OpenLoopItem? {
        func item(_ section: OpenLoopSection, _ status: OpenLoopStatus, _ when: Date?) -> OpenLoopItem {
            OpenLoopItem(source: .priceWatch, sourceID: watch.id.uuidString, title: .text(watch.title), section: section,
                         status: status, when: when)
        }
        func money(_ minor: Int?) -> Money? { minor.map { Money(minor: $0, currency: watch.currency) } }
        switch watch.state {
        case .active:
            return item(.watching, .watching(lastPrice: money(watch.lastPriceMinor), threshold: Money(minor: watch.thresholdMinor, currency: watch.currency)),
                        watch.endsAt)
        case .triggered:
            let at = watch.triggeredAt ?? watch.lastCheckedAt ?? watch.createdAt
            return c.now.timeIntervalSince(at) <= finishedWindow ? item(.today, .priceReached(money(watch.triggeredPriceMinor)), at) : nil
        case .failed:
            let at = watch.lastCheckedAt ?? watch.createdAt
            return c.now.timeIntervalSince(at) <= finishedWindow ? item(.today, .failed, at) : nil
        // Not shown as active: the app doesn't know this server state.
        case .unknown: return item(.watching, .cannotConfirm, watch.endsAt)
        // Never approved, over by time, or stopped by the person.
        case .draft, .expired, .stopped: return nil
        }
    }

    private static func parcel(_ entry: ParcelEntry, _ c: Context) -> OpenLoopItem? {
        let title: OpenLoopTitle = entry.label.map { .text($0) } ?? .hidden
        let kind = entry.lastStatus.map { ParcelStatuses.text(for: $0).kind } ?? .unknown
        func item(_ section: OpenLoopSection) -> OpenLoopItem {
            OpenLoopItem(source: .parcel, sourceID: entry.id.uuidString, title: title, section: section,
                         status: .parcel(kind), when: entry.lastChecked ?? entry.addedAt)
        }
        switch kind {
        case .readyForPickup, .problem: return item(.today)
        case .preparing, .inTransit, .unknown: return item(.waiting)
        // The carrier's own answer closes it.
        case .delivered, .returned: return nil
        }
    }
}
