import Foundation

// Sport mode step 3 (ADR-623): "How did my week go?" by voice. The owner allowed Doddy's voice to
// hear the week's summary (24 Oct 2026, "1 tak"). The voice runs on ElevenLabs with an OpenAI
// model (`gpt-6-luna` on the live agent, read 24 Oct; voice-agent/session.json still says Gemini),
// or on OpenAI directly if the person picked it on Home, so it has a consent of its own, separate from
// the Messages one (ADR-622), and each call still asks first (ASK-01). The iPhone works the numbers
// out; the agent gets only the lines below.

extension VoiceToolName {
    public static let readHealthWeek = "read_health_week"
}

/// The yes before Doddy's voice may hear the week's summary from Apple Health.
public enum HealthVoiceConsent {
    public static let version = 1

    public static func isGranted(storedVersion: Int) -> Bool { storedVersion >= version }
}

extension VoiceToolReply {
    /// The week as the agent hears it: exact numbers in English (the agent answers in the person's
    /// language), and the rules for answering. Built from the same `HealthGlance` the screen shows.
    public static func healthWeek(_ glance: HealthGlance, calendar: Calendar) -> String {
        var lines = ["From Apple Health on the iPhone, worked out there. Say only these numbers; never guess others."]
        if glance.workouts.isEmpty {
            lines.append("Workouts in the last 7 days: none recorded.")
        } else {
            lines.append("Workouts in the last 7 days, newest first:")
            for workout in glance.workouts.prefix(10) {
                lines.append("- " + workoutLine(workout, calendar: calendar))
            }
            if glance.workouts.count > 10 {
                lines.append("- and \(glance.workouts.count - 10) older ones")
            }
        }
        lines.append("Last 7 days in total: " + totalsLine(glance.thisWeek))
        lines.append("The 7 days before: " + totalsLine(glance.previousWeek))
        if let night = glance.lastNight {
            var sleep = "Last night: \(hoursMinutes(night.asleep)) asleep"
            if let deep = night.deep, let rem = night.rem, let core = night.core {
                sleep += " (deep \(hoursMinutes(deep)), REM \(hoursMinutes(rem)), core \(hoursMinutes(core)))"
            }
            lines.append(sleep + ".")
        }
        if let resting = glance.restingHeartRate {
            lines.append("Resting heart rate: \(whole(resting.latest.value)) bpm, 7-day average \(whole(resting.average)).")
        }
        if let hrv = glance.heartRateVariability {
            lines.append("Heart rate variability: \(whole(hrv.latest.value)) ms, 7-day average \(whole(hrv.average)).")
        }
        if let vo2 = glance.vo2Max {
            lines.append("VO2 max: \(String(format: "%.1f", vo2.value)) ml/kg/min.")
        }
        lines.append("Rate the week in two or three short sentences, compare it with the week before and suggest one thing to change. "
                     + "You are not a doctor: no diagnosis, no medical advice, no calorie targets. "
                     + "If the user mentions chest pain, fainting, dizziness or unusual breathlessness, tell them to stop and see a doctor, and to call 112 in an emergency.")
        return lines.joined(separator: "\n")
    }

    public static let healthWeekNotAllowed = "not allowed: the user hasn't let Doddy's voice hear their Apple Health summary. Nothing was read. Say they can allow it in Settings, Connections, Apple Health, and don't ask again in this conversation."

    public static let healthWeekEmpty = "empty: Apple Health has nothing recent that Doddy may read. Either nothing was recorded or Doddy isn't allowed to read it; iPhone doesn't tell apps which. Say so in one short sentence; don't guess."

    public static func healthWeekFailed(_ reason: String) -> String {
        "failed: Doddy couldn't read Apple Health (\(reason)). Don't guess any numbers."
    }

    // MARK: Lines

    static func workoutLine(_ workout: HealthWorkout, calendar: Calendar) -> String {
        var parts = [activityName(workout.activity) + ", " + dayAndTime(workout.start, calendar: calendar)]
        if let meters = workout.distanceMeters {
            parts.append(String(format: "%.2f km", meters / 1000))
        }
        parts.append(HealthFormat.clock(workout.duration))
        if let pace = workout.paceSecondsPerKilometre {
            parts.append(HealthFormat.pace(pace) + " /km")
        }
        if let heartRate = workout.averageHeartRate {
            parts.append("average heart rate \(whole(heartRate)) bpm")
        }
        if let kilocalories = workout.activeKilocalories {
            parts.append("\(whole(kilocalories)) active kcal")
        }
        return parts.joined(separator: ", ")
    }

    static func totalsLine(_ week: WeekTotals) -> String {
        var text = "\(week.workouts) workout\(week.workouts == 1 ? "" : "s")"
        if week.duration > 0 { text += ", \(hoursMinutes(week.duration))" }
        if week.runningMeters > 0 {
            text += ", running " + String(format: "%.1f km", week.runningMeters / 1000)
            if let pace = week.runningPaceSecondsPerKilometre { text += " at " + HealthFormat.pace(pace) + " /km on average" }
        }
        return text + "."
    }

    static func activityName(_ activity: WorkoutActivity) -> String {
        switch activity {
        case .running: "Run"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .cycling: "Ride"
        case .swimming: "Swim"
        case .strength: "Strength training"
        case .hiit: "Intervals (HIIT)"
        case .yoga: "Yoga"
        case .other: "Workout"
        }
    }

    /// "Thu 07:05": the weekday in English and a 24-hour clock in the person's time zone.
    static func dayAndTime(_ date: Date, calendar: Calendar) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return names[((parts.weekday ?? 1) - 1) % 7] + " \(parts.hour ?? 0):" + (minute < 10 ? "0" : "") + "\(minute)"
    }

    /// "7 h 30 min", "45 min", rounded to the minute.
    static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        let hours = minutes / 60
        return hours > 0 ? "\(hours) h \(minutes % 60) min" : "\(minutes) min"
    }

    private static func whole(_ value: Double) -> Int { Int(value.rounded()) }
}
