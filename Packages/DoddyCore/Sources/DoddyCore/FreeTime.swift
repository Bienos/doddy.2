import Foundation

// "When am I free?" (ADR-332). Read-only: the app reads the iPhone's calendars for the days asked
// and works out the gaps between timed events on this iPhone. All-day events don't block time
// (they are often birthdays or holidays) but are named. Nothing is booked; making an event is
// still create_calendar_event and its card.

public struct FreeTimeRequest: Equatable, Sendable {
    public static let maxDays = 7
    /// First day, at midnight in the phone's zone.
    public let firstDay: Date
    public let days: Int
    public let minMinutes: Int
    /// Minutes after midnight.
    public let earliest: Int
    public let latest: Int

    public init(firstDay: Date, days: Int, minMinutes: Int = 30, earliest: Int = 8 * 60, latest: Int = 20 * 60) {
        self.firstDay = firstDay
        self.days = days
        self.minMinutes = minMinutes
        self.earliest = earliest
        self.latest = latest
    }

    /// The calendar range to read.
    public func range(calendar: Calendar) -> VoiceTimeRange {
        VoiceTimeRange(start: firstDay, end: calendar.date(byAdding: .day, value: days, to: firstDay) ?? firstDay)
    }
}

public struct FreeDay: Equatable, Sendable {
    public struct Slot: Equatable, Sendable {
        public let start: Date
        public let end: Date
    }

    public let day: Date
    public let slots: [Slot]
    public let allDayTitles: [String]
}

public enum FreeTime {
    /// The free gaps of at least `minMinutes` in each day's window, after `now`.
    public static func days(_ request: FreeTimeRequest, events: [CalendarEventSummary], now: Date, calendar: Calendar) -> [FreeDay] {
        (0..<request.days).compactMap { offset -> FreeDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: request.firstDay),
                  let windowStart = calendar.date(byAdding: .minute, value: request.earliest, to: day),
                  let windowEnd = calendar.date(byAdding: .minute, value: request.latest, to: day) else { return nil }
            let start = max(windowStart, now)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? windowEnd
            let allDay = events.filter { $0.allDay && $0.start < dayEnd && $0.end > day }.map(\.title)
            guard start < windowEnd else { return FreeDay(day: day, slots: [], allDayTitles: allDay) }
            let busy = events.filter { !$0.allDay && $0.end > start && $0.start < windowEnd }
                .map { (max($0.start, start), min($0.end, windowEnd)) }
                .sorted { $0.0 < $1.0 }
            var slots: [FreeDay.Slot] = []
            var cursor = start
            for (busyStart, busyEnd) in busy {
                if busyStart > cursor { slots.append(FreeDay.Slot(start: cursor, end: busyStart)) }
                cursor = max(cursor, busyEnd)
            }
            if cursor < windowEnd { slots.append(FreeDay.Slot(start: cursor, end: windowEnd)) }
            let minimum = TimeInterval(request.minMinutes * 60)
            return FreeDay(day: day, slots: slots.filter { $0.end.timeIntervalSince($0.start) >= minimum }, allDayTitles: allDay)
        }
    }

    /// "HH:MM" to minutes after midnight; nil for anything else.
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute), hour * 60 + minute <= 24 * 60 else { return nil }
        return hour * 60 + minute
    }

    /// "YYYY-MM-DD" to that day's midnight in `calendar`'s zone.
    static func day(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        return calendar.startOfDay(for: date)
    }
}

extension VoiceToolName {
    public static let findFreeTime = "find_free_time"
}

extension VoiceToolRequest {
    static func parseFreeTime(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let fromText = args.text("from"), let first = FreeTime.day(fromText, calendar: calendar) else {
            return .invalid(name: name, reason: "from must be a day as YYYY-MM-DD")
        }
        var last = first
        if let toText = args.text("to") {
            guard let to = FreeTime.day(toText, calendar: calendar) else { return .invalid(name: name, reason: "to must be a day as YYYY-MM-DD") }
            last = to
        }
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        guard days >= 1 else { return .invalid(name: name, reason: "to must not be before from") }
        guard days <= FreeTimeRequest.maxDays else { return .invalid(name: name, reason: "at most \(FreeTimeRequest.maxDays) days at a time") }
        guard last >= calendar.startOfDay(for: now) else { return .invalid(name: name, reason: "those days have passed") }
        let minMinutes = args.number("min_minutes").map { Int($0) } ?? 30
        guard (5...600).contains(minMinutes) else { return .invalid(name: name, reason: "min_minutes must be 5 to 600") }
        var earliest = 8 * 60, latest = 20 * 60
        if let text = args.text("earliest") {
            guard let value = FreeTime.minutes(text) else { return .invalid(name: name, reason: "earliest must be HH:MM") }
            earliest = value
        }
        if let text = args.text("latest") {
            guard let value = FreeTime.minutes(text) else { return .invalid(name: name, reason: "latest must be HH:MM") }
            latest = value
        }
        guard latest > earliest else { return .invalid(name: name, reason: "latest must be after earliest") }
        return .findFreeTime(FreeTimeRequest(firstDay: first, days: days, minMinutes: minMinutes, earliest: earliest, latest: latest))
    }
}

extension VoiceToolReply {
    /// The free gaps per day, in the phone's local time. Only from the iPhone's calendars.
    public static func freeTime(_ days: [FreeDay], request: FreeTimeRequest, calendar: Calendar) -> String {
        let dayFormat = DateFormatter()
        dayFormat.calendar = calendar
        dayFormat.timeZone = calendar.timeZone
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "EEEE yyyy-MM-dd"
        let timeFormat = DateFormatter()
        timeFormat.calendar = calendar
        timeFormat.timeZone = calendar.timeZone
        timeFormat.locale = Locale(identifier: "en_US_POSIX")
        timeFormat.dateFormat = "HH:mm"
        func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
        var lines = ["free time: gaps of at least \(request.minMinutes) minutes between \(clock(request.earliest)) and \(clock(request.latest)), local time, from the calendars on this iPhone only:"]
        for day in days {
            let slots = day.slots.map { "\(timeFormat.string(from: $0.start))–\(timeFormat.string(from: $0.end))" }
            var line = "- \(dayFormat.string(from: day.day)): " + (slots.isEmpty ? "no free gap" : slots.joined(separator: ", "))
            if !day.allDayTitles.isEmpty {
                line += " (all-day: " + day.allDayTitles.map { "\"\($0)\"" }.joined(separator: ", ") + ")"
            }
            lines.append(line)
        }
        lines.append("Say only these gaps. Events in calendars not on this iPhone aren't counted. Nothing was booked; to add an event, use create_calendar_event.")
        return lines.joined(separator: "\n")
    }
}
