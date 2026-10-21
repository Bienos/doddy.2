import Foundation

// "How many steps today?" (ADR-567). The iPhone counts steps, walking distance and floors climbed
// in Motion & Fitness and keeps the last seven days. Doddy reads one day's totals when asked,
// after the user's yes (ASK-01), and keeps nothing: the numbers go to the voice agent in that
// conversation only. No Health data is read (HealthKit needs a paid Apple team and Apple's review).

extension VoiceToolName {
    public static let readSteps = "read_steps"
}

/// One day of the last seven, today included: 0 is today, 6 is six days ago.
public struct StepDay: Equatable, Sendable {
    public let daysAgo: Int

    public init?(daysAgo: Int) {
        guard (0...StepDay.maxDaysAgo).contains(daysAgo) else { return nil }
        self.daysAgo = daysAgo
    }

    /// Motion & Fitness keeps seven days.
    public static let maxDaysAgo = 6

    /// From midnight of that day to the next midnight, or to `now` for today.
    public func range(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        let end = daysAgo == 0 ? now : (calendar.date(byAdding: .day, value: 1, to: start) ?? now)
        return (start, end)
    }

    public var text: String {
        switch daysAgo {
        case 0: "Today"
        case 1: "Yesterday"
        default: "\(daysAgo) days ago"
        }
    }
}

/// What Motion & Fitness reported for a day. Distance and floors are missing on iPhones that
/// can't measure them.
public struct StepTotals: Equatable, Sendable {
    public let steps: Int
    public let distanceMeters: Double?
    public let floorsUp: Int?

    public init(steps: Int, distanceMeters: Double?, floorsUp: Int?) {
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.floorsUp = floorsUp
    }
}

extension VoiceToolRequest {
    /// `day`: "today" (the default), "yesterday", or a date "YYYY-MM-DD" in the last seven days.
    static func parseSteps(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let said = args.text("day")?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return .readSteps(StepDay(daysAgo: 0)!)
        }
        let daysAgo: Int
        switch said {
        case "today": daysAgo = 0
        case "yesterday": daysAgo = 1
        default:
            let parts = said.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  let offset = calendar.dateComponents([.day], from: date, to: calendar.startOfDay(for: now)).day else {
                return .invalid(name: name, reason: "day must be today, yesterday or a date written YYYY-MM-DD")
            }
            daysAgo = offset
        }
        guard let day = StepDay(daysAgo: daysAgo) else {
            return .invalid(name: name, reason: "the iPhone keeps steps for the last 7 days only, today included; a future day has none")
        }
        return .readSteps(day)
    }
}

extension VoiceToolReply {
    /// Exact numbers from Motion & Fitness. Distance is rounded to tens of metres.
    public static func steps(_ totals: StepTotals, day: StepDay, until: Date?, calendar: Calendar) -> String {
        var lines = ["\(day.text)\(until.map { " until " + clock($0, calendar: calendar) } ?? ""), from the iPhone's Motion & Fitness:"]
        lines.append("Steps: \(totals.steps)")
        if let meters = totals.distanceMeters {
            let tens = (meters / 10).rounded() * 10
            lines.append(tens >= 1000 ? "Walking distance: \(String(format: "%.1f", tens / 1000)) km" : "Walking distance: \(Int(tens)) m")
        }
        if let floors = totals.floorsUp { lines.append("Floors climbed: \(floors)") }
        lines.append("Say these numbers as they are; don't guess other days, calories or health advice.")
        return lines.joined(separator: "\n")
    }

    public static let stepsUnavailable = "unavailable: this device doesn't count steps (an iPad, for example). Nothing was read. Tell the user in one short sentence."

    public static func stepsFailed(_ reason: String) -> String {
        "failed: Doddy couldn't read the steps (\(reason)). Don't guess a number."
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return "\(parts.hour ?? 0):\(minute < 10 ? "0" : "")\(minute)"
    }
}
