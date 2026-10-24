import Foundation

// Important reminders that ring like an alarm (ADR-641; owner, 24 Oct 2026: "budujemy dzwoni jak
// budzik"). A note reminder the user marks "Ring like an alarm" keeps everything it has (the
// notification with Open note, In 1 hour and Done, Home's "Due now", the database row) and also
// gets an AlarmKit alarm at the same moment, so it rings through Silent mode and a Focus. The
// alarm is a projection, like the notification: the database reminder is the truth, and
// `RingingReminderSync` makes AlarmKit match it whenever the reminders are read. The wish to
// ring is kept per note (a snooze or a new time makes a new reminder row for the same note).
// Plain Swift for the Linux tests; AlarmKit is only in the app (`ReminderRinger`).

/// When an important reminder rings, in the form AlarmKit takes.
public enum ReminderRingPlan: Equatable, Sendable {
    /// Once, at this moment.
    case once(Date)
    /// Every week at this clock time on these weekdays (1 = Sunday … 7 = Saturday).
    case weekly(hour: Int, minute: Int, weekdays: [Int])

    /// Two plans with the same signature ring at the same times.
    public var signature: String {
        switch self {
        case .once(let date): "once:\(Int(date.timeIntervalSince1970))"
        case .weekly(let hour, let minute, let weekdays): "weekly:\(hour):\(minute):" + weekdays.sorted().map(String.init).joined(separator: ",")
        }
    }
}

public enum ReminderRingSupport: Equatable, Sendable {
    case supported
    /// A place reminder: AlarmKit rings at times only.
    case place
    /// Every month: AlarmKit repeats by weekday only.
    case monthly
}

public enum ReminderRing {
    /// The alarm's own snooze ("In 10 min" on the ringing screen).
    public static let snoozeMinutes = 10
    /// AlarmKit's title is short; a longer note is cut with "…".
    public static let maxTitleLength = 40

    public static func support(repeats: ReminderRepeat?, isPlace: Bool) -> ReminderRingSupport {
        if isPlace { return .place }
        if repeats == .monthly { return .monthly }
        return .supported
    }

    public static func support(_ reminder: MemoryReminder) -> ReminderRingSupport {
        support(repeats: reminder.repeats, isPlace: reminder.place != nil)
    }

    /// When the reminder should ring now: nil for a one-off already past, a place, or monthly.
    /// The clock time and weekday are the reminder's own, in the zone it was set in.
    public static func plan(for reminder: MemoryReminder, now: Date) -> ReminderRingPlan? {
        guard support(reminder) == .supported, case .time(let anchor, let zone) = reminder.trigger else { return nil }
        guard let repeats = reminder.repeats else { return anchor > now ? .once(anchor) : nil }
        let calendar = ReminderSchedule.calendar(zone)
        let hour = calendar.component(.hour, from: anchor), minute = calendar.component(.minute, from: anchor)
        switch repeats {
        case .daily: return .weekly(hour: hour, minute: minute, weekdays: Array(1...7))
        case .weekdays: return .weekly(hour: hour, minute: minute, weekdays: Array(2...6))
        case .weekly: return .weekly(hour: hour, minute: minute, weekdays: [calendar.component(.weekday, from: anchor)])
        case .monthly: return nil
        }
    }

    /// The ringing screen's title. The note's words only with "Show note text in notifications" on,
    /// as for the notification (ADR-190); otherwise "Reminder" / "Przypomnienie".
    public static func title(noteText: String, showNoteText: Bool, language: NotificationLanguage) -> String {
        let firstLine = noteText.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard showNoteText, !firstLine.isEmpty else { return NoteReminderCopy.title(language) }
        guard firstLine.count > maxTitleLength else { return firstLine }
        return String(firstLine.prefix(maxTitleLength - 1)) + "…"
    }

    public static func snoozeButton(_ language: NotificationLanguage) -> String {
        language == .polish ? "Za \(snoozeMinutes) min" : "In \(snoozeMinutes) min"
    }

    public static func stopButton(_ language: NotificationLanguage) -> String {
        language == .polish ? "Zatrzymaj" : "Stop"
    }

    /// What the card and the sheet say about ringing, so nobody is promised a ring that can't happen.
    public static func unsupportedReason(_ support: ReminderRingSupport, _ language: NotificationLanguage) -> String? {
        switch (support, language) {
        case (.supported, _): nil
        case (.place, .polish): "Przypomnienie przy miejscu nie może dzwonić jak budzik."
        case (.place, .english): "A reminder at a place can't ring like an alarm."
        case (.monthly, .polish): "Przypomnienie co miesiąc nie może dzwonić jak budzik."
        case (.monthly, .english): "A monthly reminder can't ring like an alarm."
        }
    }
}

/// One note the user wants to ring, and the AlarmKit alarm that does it.
public struct RingingReminderEntry: Codable, Equatable, Sendable {
    public let memoryID: UUID
    /// The alarm set for it; empty until one is set.
    public var alarmIDs: [UUID]
    /// The plan those alarms ring on; nil until one is set.
    public var signature: String?

    public init(memoryID: UUID, alarmIDs: [UUID] = [], signature: String? = nil) {
        self.memoryID = memoryID
        self.alarmIDs = alarmIDs
        self.signature = signature
    }
}

/// What it takes to make AlarmKit match the reminders.
public enum RingingReminderSync {
    public enum Step: Equatable, Sendable {
        /// Turn these alarms off.
        case cancel([UUID])
        /// Set an alarm for this note on this plan (and note it).
        case schedule(memoryID: UUID, plan: ReminderRingPlan)
        /// The note no longer wants ringing (its reminder is gone, or can't ring).
        case forget(memoryID: UUID)
    }

    /// What an entry stores: the plan, and the ringing screen's title, so a changed note or a
    /// changed "Show note text" setting sets the alarm again with the new words.
    public static func signature(_ plan: ReminderRingPlan, title: String = "") -> String {
        title.isEmpty ? plan.signature : plan.signature + "|" + title
    }

    /// `listed` is every alarm id AlarmKit lists for Doddy; nil when the list can't be read, and
    /// then nothing is touched (a ringing or snoozed alarm is never cancelled on a guess).
    /// A one-off that has passed is left alone: its alarm has rung, or is ringing or snoozed now;
    /// if the note gets a new time (In 1 hour, a new date), it rings at that one.
    public static func steps(
        entries: [RingingReminderEntry], reminders: [MemoryReminder], listed: Set<UUID>?, now: Date,
        title: (UUID) -> String = { _ in "" }
    ) -> [Step] {
        guard let listed else { return [] }
        var steps: [Step] = []
        for entry in entries {
            guard let reminder = reminders.first(where: { $0.memoryID == entry.memoryID }),
                  ReminderRing.support(reminder) == .supported else {
                let running = entry.alarmIDs.filter(listed.contains)
                if !running.isEmpty { steps.append(.cancel(running)) }
                steps.append(.forget(memoryID: entry.memoryID))
                continue
            }
            guard let plan = ReminderRing.plan(for: reminder, now: now) else { continue }
            let inPlace = !entry.alarmIDs.isEmpty && entry.alarmIDs.allSatisfy(listed.contains)
            if entry.signature == signature(plan, title: title(entry.memoryID)) && inPlace { continue }
            let old = entry.alarmIDs.filter(listed.contains)
            if !old.isEmpty { steps.append(.cancel(old)) }
            steps.append(.schedule(memoryID: entry.memoryID, plan: plan))
        }
        return steps
    }

    /// Whether the note's reminder rings right now: its alarm is set on the current plan and listed.
    public static func isRinging(
        _ entry: RingingReminderEntry?, reminder: MemoryReminder?, listed: Set<UUID>?, now: Date, title: String = ""
    ) -> Bool {
        guard let entry, let reminder, let listed, let plan = ReminderRing.plan(for: reminder, now: now) else { return false }
        return entry.signature == signature(plan, title: title) && !entry.alarmIDs.isEmpty && entry.alarmIDs.allSatisfy(listed.contains)
    }
}
