import Foundation

// Sport mode, step 1 (ADR-621): what Doddy reads from Apple Health and how it sums it up for the
// "What Doddy sees" screen. The iPhone reads Health (HealthKit, app code only); the rules here turn
// those samples into the few numbers the screen shows. Step 1 shows them on the iPhone only: none
// of it is sent anywhere, spoken, or kept (ADR-620, decision 2: later only a short summary may go
// to Claude, after the person's consent).

/// The window the screen covers: the last seven days, today included.
public enum HealthWindow {
    public static let days = 7

    /// From midnight six days ago to `now`.
    public static func lastDays(now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return (start, now)
    }

    /// The night that ended on the morning of `day`: 18:00 the evening before until 12:00 that
    /// day, cut at `now` when `day` is today.
    public static func night(wakingOn day: Date, now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let morning = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .hour, value: -6, to: morning) ?? morning
        let noon = calendar.date(byAdding: .hour, value: 12, to: morning) ?? morning
        return (start, min(noon, max(now, start)))
    }
}

// MARK: Workouts

/// The kinds of workout the screen names. Everything else is `other`.
public enum WorkoutActivity: String, CaseIterable, Sendable {
    case running, walking, hiking, cycling, swimming, strength, hiit, yoga, other

    /// Pace (minutes per kilometre) means something for these.
    public var showsPace: Bool { self == .running || self == .walking || self == .hiking }
}

/// One workout as Health recorded it. The numbers are Health's own; missing ones stay missing.
public struct HealthWorkout: Equatable, Sendable {
    public let activity: WorkoutActivity
    public let start: Date
    public let end: Date
    public let distanceMeters: Double?
    public let activeKilocalories: Double?
    public let averageHeartRate: Double?

    public init(activity: WorkoutActivity, start: Date, end: Date, distanceMeters: Double?,
                activeKilocalories: Double?, averageHeartRate: Double?) {
        self.activity = activity
        self.start = start
        self.end = end
        self.distanceMeters = distanceMeters.flatMap { $0 > 0 ? $0 : nil }
        self.activeKilocalories = activeKilocalories.flatMap { $0 > 0 ? $0 : nil }
        self.averageHeartRate = averageHeartRate.flatMap { $0 > 0 ? $0 : nil }
    }

    public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// Seconds per kilometre, for running, walking and hiking of at least 100 m. Nothing otherwise:
    /// a pace for a swim or a bike ride would read wrong.
    public var paceSecondsPerKilometre: Double? {
        guard activity.showsPace, let meters = distanceMeters, meters >= 100, duration > 0 else { return nil }
        return duration / (meters / 1000)
    }

    /// The workouts the screen lists: those that ended inside the window, newest first, at most
    /// `limit`. A workout that started before the window but ended in it counts.
    public static func recent(_ workouts: [HealthWorkout], in window: (start: Date, end: Date),
                              limit: Int = 20) -> [HealthWorkout] {
        let inside = workouts.filter { $0.end > window.start && $0.end <= window.end && $0.duration > 0 }
        let sorted = inside.sorted { $0.end != $1.end ? $0.end > $1.end : $0.start > $1.start }
        return Array(sorted.prefix(max(0, limit)))
    }
}

// MARK: Sleep

/// Health's sleep stages. `asleepUnspecified` is sleep without a stage (an iPhone's sleep
/// schedule, older watches, many other apps).
public enum SleepStage: Sendable {
    case inBed, awake, core, deep, rem, asleepUnspecified

    var isStaged: Bool { self == .core || self == .deep || self == .rem }
    var isAsleep: Bool { isStaged || self == .asleepUnspecified }
}

public struct SleepSample: Equatable, Sendable {
    public let stage: SleepStage
    public let start: Date
    public let end: Date

    public init(stage: SleepStage, start: Date, end: Date) {
        self.stage = stage
        self.start = start
        self.end = end
    }
}

/// One night, added up so no minute counts twice even when a watch and the iPhone (or another
/// app) both wrote sleep for the same hours.
public struct SleepNight: Equatable, Sendable {
    /// Time asleep: every minute some source called asleep.
    public let asleep: TimeInterval
    /// Minutes per stage, only when a source recorded stages. They add up to `asleep`.
    public let core: TimeInterval?
    public let deep: TimeInterval?
    public let rem: TimeInterval?
    /// The first and last asleep minute.
    public let fellAsleep: Date
    public let wokeUp: Date

    public init(asleep: TimeInterval, core: TimeInterval?, deep: TimeInterval?, rem: TimeInterval?,
                fellAsleep: Date, wokeUp: Date) {
        self.asleep = asleep
        self.core = core
        self.deep = deep
        self.rem = rem
        self.fellAsleep = fellAsleep
        self.wokeUp = wokeUp
    }

    /// Adds up the samples inside `window`. When any sample has a stage, only staged samples count
    /// (the watch's night is the detailed one) and a minute two sources stage differently counts
    /// once, as deep before REM before core. Without stages, unstaged sleep counts. In bed and
    /// awake never count as sleep. Nothing asleep in the window: nil.
    public static func summarize(_ samples: [SleepSample], window: (start: Date, end: Date)) -> SleepNight? {
        let clipped = samples.compactMap { sample -> SleepSample? in
            let start = max(sample.start, window.start)
            let end = min(sample.end, window.end)
            guard sample.stage.isAsleep, end > start else { return nil }
            return SleepSample(stage: sample.stage, start: start, end: end)
        }
        let staged = clipped.filter { $0.stage.isStaged }
        let counted = staged.isEmpty ? clipped : staged
        guard !counted.isEmpty else { return nil }

        // Cut the night at every sample edge; each piece is asleep or not, and has one stage.
        let edges = Array(Set(counted.flatMap { [$0.start, $0.end] })).sorted()
        var asleep: TimeInterval = 0
        var byStage: [SleepStage: TimeInterval] = [:]
        var first: Date?
        var last: Date?
        for (from, to) in zip(edges, edges.dropFirst()) {
            let covering = counted.filter { $0.start <= from && $0.end >= to }.map(\.stage)
            guard !covering.isEmpty else { continue }
            let piece = to.timeIntervalSince(from)
            asleep += piece
            first = first ?? from
            last = to
            if !staged.isEmpty {
                let stage: SleepStage = covering.contains(.deep) ? .deep : covering.contains(.rem) ? .rem : .core
                byStage[stage, default: 0] += piece
            }
        }
        guard let fellAsleep = first, let wokeUp = last, asleep > 0 else { return nil }
        let hasStages = !staged.isEmpty
        return SleepNight(asleep: asleep,
                          core: hasStages ? byStage[.core, default: 0] : nil,
                          deep: hasStages ? byStage[.deep, default: 0] : nil,
                          rem: hasStages ? byStage[.rem, default: 0] : nil,
                          fellAsleep: fellAsleep, wokeUp: wokeUp)
    }
}

// MARK: Resting heart rate, HRV, VO2 max

/// One value Health recorded at a time: beats per minute, milliseconds (HRV) or ml/kg/min (VO2 max).
public struct HealthReading: Equatable, Sendable {
    public let value: Double
    public let date: Date

    public init(value: Double, date: Date) {
        self.value = value
        self.date = date
    }
}

/// The newest reading and the week's average. The average is of each day's own average, so a day
/// with many readings (HRV is measured several times on some days) doesn't outweigh the others.
public struct ReadingGlance: Equatable, Sendable {
    public let latest: HealthReading
    public let average: Double
    /// Days with at least one reading.
    public let days: Int

    public init(latest: HealthReading, average: Double, days: Int) {
        self.latest = latest
        self.average = average
        self.days = days
    }

    public static func of(_ readings: [HealthReading], calendar: Calendar) -> ReadingGlance? {
        let valid = readings.filter { $0.value.isFinite && $0.value > 0 }
        guard let latest = valid.max(by: { $0.date < $1.date }) else { return nil }
        let byDay = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.date) }
        let dayMeans = byDay.values.map { day in day.map(\.value).reduce(0, +) / Double(day.count) }
        let average = dayMeans.reduce(0, +) / Double(dayMeans.count)
        return ReadingGlance(latest: latest, average: average, days: byDay.count)
    }
}

// MARK: The screen's whole picture

/// Everything "What Doddy sees" shows for the last seven days.
public struct HealthGlance: Equatable, Sendable {
    public let workouts: [HealthWorkout]
    /// All workouts of the last seven days added up, and of the seven days before (ADR-622).
    public let thisWeek: WeekTotals
    public let previousWeek: WeekTotals
    public let lastNight: SleepNight?
    public let restingHeartRate: ReadingGlance?
    public let heartRateVariability: ReadingGlance?
    public let vo2Max: HealthReading?

    public init(workouts: [HealthWorkout], thisWeek: WeekTotals = .none, previousWeek: WeekTotals = .none,
                lastNight: SleepNight?, restingHeartRate: ReadingGlance?,
                heartRateVariability: ReadingGlance?, vo2Max: HealthReading?) {
        self.workouts = workouts
        self.thisWeek = thisWeek
        self.previousWeek = previousWeek
        self.lastNight = lastNight
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.vo2Max = vo2Max
    }

    /// Health gives an app no way to tell "not allowed" from "nothing recorded": both read as
    /// empty. The screen says so instead of guessing which.
    public var isEmpty: Bool {
        workouts.isEmpty && previousWeek.workouts == 0 && lastNight == nil && restingHeartRate == nil && heartRateVariability == nil && vo2Max == nil
    }
}

// MARK: Numbers the way runners write them

public enum HealthFormat {
    /// "47:10" or "1:05:20": hours only when there are some. Seconds are rounded.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        let mmss = (hours > 0 && minutes < 10 ? "0" : "") + "\(minutes):" + (secs < 10 ? "0" : "") + "\(secs)"
        return hours > 0 ? "\(hours):\(mmss)" : mmss
    }

    /// "5:45", minutes and seconds per kilometre.
    public static func pace(_ secondsPerKilometre: Double) -> String {
        clock(secondsPerKilometre)
    }
}
