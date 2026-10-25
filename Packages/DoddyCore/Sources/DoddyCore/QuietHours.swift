import Foundation

// Quiet hours and one of Doddy's own notifications a day (ADR-651; owner, 24 Oct 2026: quiet
// hours yes; a notification "out of nowhere" is limited, but a timer or anything that is an
// action item always shows).
//  - Action items always come, at any hour: timers, alarms, reminders, time to leave, before an
//    event, focus done, an errand done. Nothing here touches them.
//  - Routines the user turned on (morning check-in, evening wrap-up, weekly plan, look-back,
//    tidy-up) come at the time they picked, never in quiet hours: a time inside them moves to
//    the nearest edge (07:00, or 21:30 in the evening).
//  - Doddy's own tips, which nobody set a time for (today only "Open Doddy faster", ADR-559):
//    never on a day a routine already comes, so Doddy says at most one thing a day of its own.

public enum QuietHours {
    /// 22:00 to 07:00.
    public static let startHour = 22
    public static let endHour = 7
    /// Where an evening time inside quiet hours goes.
    public static let lateEvening = (hour: 21, minute: 30)

    public static func contains(hour: Int, minute: Int) -> Bool {
        hour >= startHour || hour < endHour
    }

    /// The routine's time outside quiet hours: from midnight to 07:00 it moves to 07:00; from
    /// 22:00 to midnight, to 21:30. A time outside quiet hours is kept as it is.
    public static func adjusted(hour: Int, minute: Int) -> (hour: Int, minute: Int) {
        guard contains(hour: hour, minute: minute) else { return (hour, minute) }
        return hour < endHour ? (endHour, 0) : lateEvening
    }
}

/// The days Doddy's routines come on, and where its own tips may go.
public enum OwnNotificationDays {
    /// Gregorian weekdays (1 = Sunday) on which a routine the user turned on comes.
    public static func routineWeekdays(
        morning: MorningCheckInSettings, evening: EveningWrapUpSettings, plan: WeeklyPlanSettings,
        lookBack: WeeklyLookBackSettings, tidyUp: TidyUpSettings
    ) -> Set<Int> {
        var days = Set<Int>()
        if morning.isOn { days.formUnion(morning.weekdaysOnly ? Set(2...6) : Set(1...7)) }
        if evening.isOn { days.formUnion(1...7) }
        if plan.isOn { days.insert(plan.weekday) }
        if lookBack.isOn { days.insert(lookBack.weekday) }
        if tidyUp.isOn { days.insert(tidyUp.weekday) }
        return days
    }

    /// A tip's planned dates, each moved to the first later day in its week (up to six days on, at
    /// the same time) on which no routine comes. A week in which a routine comes every day gets no
    /// tip at all.
    public static func tipDates(_ planned: [Date], routineWeekdays: Set<Int>, calendar: Calendar) -> [Date] {
        planned.compactMap { date in
            (0...6).lazy.compactMap { calendar.date(byAdding: .day, value: $0, to: date) }
                .first { !routineWeekdays.contains(calendar.component(.weekday, from: $0)) }
        }
    }
}
