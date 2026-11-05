import Foundation

// Sport mode step 4, on the iPhone (ADR-625): the plan the person chose to keep, and where they are in
// it. One plan at a time, as a file in the app's protected container; nothing here leaves the phone.

/// The Monday a plan starts, as a calendar day rather than an instant, so a time-zone change doesn't
/// move the plan by a day.
public struct PlanStart: Equatable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The Monday of the week `date` falls in. With `weeksLater` 1, the Monday after.
    public static func monday(of date: Date, weeksLater: Int = 0, calendar: Calendar) -> PlanStart {
        let today = calendar.startOfDay(for: date)
        let back = PlanCalendar.weekday(of: today, calendar: calendar) - 1
        let monday = calendar.date(byAdding: .day, value: 7 * weeksLater - back, to: today) ?? today
        let parts = calendar.dateComponents([.year, .month, .day], from: monday)
        return PlanStart(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The start of that day in `calendar`'s time zone.
    public func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// Where today falls in a plan.
public enum PlanPosition: Equatable, Sendable {
    /// The plan starts on a later Monday.
    case startsIn(days: Int)
    /// Week `week` of the plan, `day` 1 for Monday to 7 for Sunday.
    case inPlan(week: Int, day: Int)
    /// Every week is over.
    case finished
}

public enum PlanCalendar {
    /// 1 for Monday to 7 for Sunday, whatever the calendar's first weekday.
    public static func weekday(of date: Date, calendar: Calendar) -> Int {
        // Calendar's weekday is 1 for Sunday to 7 for Saturday.
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    public static func position(of plan: TrainingPlan, start: PlanStart, now: Date, calendar: Calendar) -> PlanPosition {
        guard let first = start.date(in: calendar) else { return .finished }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: first, to: today).day ?? 0
        if days < 0 { return .startsIn(days: -days) }
        let week = days / 7 + 1
        guard week <= plan.weeks.count else { return .finished }
        return .inPlan(week: week, day: days % 7 + 1)
    }
}

/// What a read of the kept file found.
public enum SavedPlanRead: Equatable, Sendable {
    case plan(SavedTrainingPlan)
    /// Not a file this version of Doddy can read. The caller sets it aside rather than writing over it.
    case unreadable
    /// It reads, but it isn't the plan this version of Doddy makes for those answers, or it breaks a
    /// safety rule (an older Doddy made it, or the file was changed). Never shown as Doddy's plan.
    case notThisDoddysPlan
}

/// The plan as kept on the iPhone: the engine's plan for the person's answers, the Monday it starts
/// and when it was saved. The answers inside are the ones that allowed a plan (every screening
/// question "no") and the age.
public struct SavedTrainingPlan: Equatable, Sendable, Codable {
    public static let version = 1

    public private(set) var version: Int
    public let plan: TrainingPlan
    public let start: PlanStart
    public let savedAt: Date

    public init(plan: TrainingPlan, start: PlanStart, savedAt: Date) {
        self.version = Self.version
        self.plan = plan
        self.start = start
        self.savedAt = savedAt
    }

    public func encoded() throws -> Data {
        // Dates as the default number, so they read back exactly and the write can be checked.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// A plan is shown as Doddy's only when it is exactly what the engine makes for its answers and
    /// breaks none of the rules: a file edited by hand, or made by an older engine, is not.
    public static func read(_ data: Data) -> SavedPlanRead {
        guard let saved = try? JSONDecoder().decode(SavedTrainingPlan.self, from: data), saved.version == version else {
            return .unreadable
        }
        guard PlanEngine.make(saved.plan.request) == .plan(saved.plan), PlanRules.violations(saved.plan).isEmpty else {
            return .notThisDoddysPlan
        }
        return .plan(saved)
    }
}
