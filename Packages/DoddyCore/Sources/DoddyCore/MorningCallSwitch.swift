import Foundation

// MARK: The Morning call switch (owner, 15 Nov 2026: "make button in app to switch calling", "Morning call switch")
//
// Settings › Phone calls › Doddy calls you › Morning call sets up the same morning call as the voice card
// (decision 2026-11-14-morning-call) from a time picker and a days choice. What needs no UI is here, so it is tested
// on Linux: the picker's limits, the days choice, the draft they make, what the switch shows for each answer of
// Doddy's server, and what stands in the way. The switch never shows a guess: it is on only while the server's last
// answer listed an active morning call. Turning it on only opens the pickers and then the card; the card's own button
// books exactly what the card shows (`MorningCallDraft.approvalHash`, the same server endpoint as the voice card).
// Turning it off stops at once (`stopMorningCalls`), and is never held back. Nothing here places a call.

/// The days choice next to the time picker: every day, weekdays, the weekend, or days the person ticks.
public struct MorningCallDayChoice: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case everyDay, weekdays, weekend, chosen
    }

    public var kind: Kind
    /// ISO weekdays, Monday 1 to Sunday 7, for `.chosen`. Kept while another kind is picked, so going back to chosen
    /// days doesn't lose the ticks.
    public var chosen: Set<Int>

    public init(kind: Kind, chosen: Set<Int> = []) {
        self.kind = kind
        self.chosen = chosen
    }

    /// The choice that shows `days`: every day, weekdays and the weekend as themselves, any other days as ticked days.
    public init(_ days: MorningCallDays) {
        switch days {
        case .everyDay: self.init(kind: .everyDay)
        case .weekdays: self.init(kind: .weekdays)
        case .weekend: self.init(kind: .weekend)
        default: self.init(kind: .chosen, chosen: Set(days.isoWeekdays))
        }
    }

    /// The days the approval binds, or nil while no day is ticked (or a ticked number isn't a weekday).
    public var days: MorningCallDays? {
        switch kind {
        case .everyDay: return .everyDay
        case .weekdays: return .weekdays
        case .weekend: return .weekend
        case .chosen:
            guard chosen.allSatisfy((1...7).contains) else { return nil }
            return MorningCallDays(digits: chosen.sorted().map(String.init).joined())
        }
    }

    /// Ticks or unticks one ISO weekday.
    public mutating func set(_ day: Int, _ on: Bool) {
        guard (1...7).contains(day) else { return }
        if on { chosen.insert(day) } else { chosen.remove(day) }
    }
}

/// The time picker of a morning call: 05:00 to 11:59 on the iPhone's clock (`MorningCallLimits`).
public enum MorningCallTime {
    /// Where the picker starts when no morning call is set up: 08:00, the end of the standard quiet hours.
    public static let suggested = "08:00"

    /// "HH:MM" of `date` on `calendar`'s clock, or nil when that is not a morning (before 05:00 or after 11:59).
    public static func text(of date: Date, calendar: Calendar) -> String? {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        let text = String(format: "%02d:%02d", hour, minute)
        return MorningCallLimits.isMorning(text) ? text : nil
    }

    /// The picker's range on the day of `date`: 05:00 to 11:59 on `calendar`'s clock.
    public static func range(on date: Date, calendar: Calendar) -> ClosedRange<Date> {
        let from = clock(MorningCallLimits.earliest, on: date, calendar: calendar) ?? date
        let to = clock(MorningCallLimits.latest, on: date, calendar: calendar) ?? from
        return from...max(from, to)
    }

    /// Where the picker starts: `time` (the active morning call's, "HH:MM") on the day of `date`, or 08:00 when there
    /// is none or it isn't a morning time.
    public static func start(_ time: String?, on date: Date, calendar: Calendar) -> Date {
        let wanted = time.flatMap { MorningCallLimits.isMorning($0) ? $0 : nil } ?? suggested
        return clock(wanted, on: date, calendar: calendar) ?? range(on: date, calendar: calendar).lowerBound
    }

    private static func clock(_ time: String, on date: Date, calendar: Calendar) -> Date? {
        guard let minutes = CallQuietHours.minutes(time) else { return nil }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: date)
    }
}

extension MorningCallDraft {
    /// The draft the pickers make: the time on the iPhone's clock and its zone, as the voice card's draft has them
    /// (`parseCallMeEveryMorning`). Nil while the time isn't a morning or no day is ticked; nothing can be booked then.
    public init?(pickedTime: Date, days: MorningCallDayChoice, calendar: Calendar) {
        guard let time = MorningCallTime.text(of: pickedTime, calendar: calendar), let days = days.days else { return nil }
        self.init(time: time, days: days, timeZoneID: calendar.timeZone.identifier)
    }
}

/// Why the switch can't be turned on, in the order the page says it.
public enum MorningCallBlocker: Equatable, Sendable {
    /// `MORNING_CALLS_ENABLED` is off on Doddy's messaging server (`enabled` false).
    case serverOff
    /// Doddy's phone line isn't set up on the server (`available` false).
    case lineNotSetUp
    /// No verified number.
    case noVerifiedPhone
    /// "Doddy may call me" is off.
    case callsOff
}

/// What the Morning call switch shows, from the server's last answers only.
public struct MorningCallSwitch: Equatable, Sendable {
    /// On only while the server listed an active morning call.
    public let isOn: Bool
    /// Why it can't be turned on (or its time and days changed); nil when nothing is in the way.
    public let blocker: MorningCallBlocker?

    public init(settings: CallSettings, status: MorningCallStatus) {
        isOn = status.call?.state == "active"
        if !status.enabled {
            blocker = .serverOff
        } else if !settings.available.outbound || !status.available {
            blocker = .lineNotSetUp
        } else if !settings.phoneVerified {
            blocker = .noVerifiedPhone
        } else if !settings.outboundConsent {
            blocker = .callsOff
        } else {
            blocker = nil
        }
    }

    /// Whether a tap can move it: off always works (stopping is accepted whatever the server's switch or phone line);
    /// on only with nothing in the way.
    public var isEnabled: Bool { isOn || blocker == nil }

    /// Whether the time and days of the active one can be changed: a new card whose booking replaces it.
    public var canChange: Bool { isOn && blocker == nil }

    /// Shown on the Doddy calls you page while the phone line is there, and while a morning call is still set up, so it
    /// can always be stopped.
    public static func isShown(settings: CallSettings, status: MorningCallStatus) -> Bool {
        settings.available.outbound || status.call?.state == "active"
    }
}

/// What the card needs, read from the server just before it is shown: the draft, the number it calls, quiet hours,
/// and the morning call it replaces. The same checks as the voice card's (`CallReadiness` and the server's switch).
public struct MorningCallProposal: Equatable, Sendable {
    public let draft: MorningCallDraft
    public let to: String
    public let quietHours: CallQuietHours
    /// The active one this booking replaces, as the card says; nil when there is none.
    public let replaces: MorningCall?

    public init(draft: MorningCallDraft, to: String, quietHours: CallQuietHours, replaces: MorningCall?) {
        self.draft = draft
        self.to = to
        self.quietHours = quietHours
        self.replaces = replaces
    }

    public enum Check: Equatable, Sendable {
        case ready(MorningCallProposal)
        case blocked(MorningCallBlocker)
    }

    public static func check(
        _ draft: MorningCallDraft, settings: CallSettings, phone: PhoneStatus, status: MorningCallStatus
    ) -> Check {
        if let blocker = MorningCallSwitch(settings: settings, status: status).blocker { return .blocked(blocker) }
        switch CallReadiness(settings: settings, phone: phone) {
        case .ready(let to, let quietHours):
            let active = status.call?.state == "active" ? status.call : nil
            return .ready(MorningCallProposal(draft: draft, to: to, quietHours: quietHours, replaces: active))
        case .noPhone: return .blocked(.noVerifiedPhone)
        case .callsOff: return .blocked(.callsOff)
        case .notSetUp: return .blocked(.lineNotSetUp)
        }
    }

    /// Whether the card's button may book it: a time inside quiet hours needs the card's switch, as on the voice card.
    public func canBook(allowQuietHours: Bool) -> Bool {
        allowQuietHours || !draft.inQuietHours(quietHours)
    }
}

/// The server's refusal of a morning call booked from Settings, as the page says it (the app's strings).
public enum MorningCallRefusal: Equatable, Sendable {
    case quietHours, numberChanged, anotherSetUp, alreadySetUp, stoppedSince, serverFull, serverOff, callsOff
    case noVerifiedPhone, countryNotAllowed, lineNotSetUp, tooManyTries, notAccepted, other

    /// The error code `bookMorningCall` returns in `.refused`.
    public init(code: String) {
        self = switch code {
        case "quiet_hours": .quietHours
        case "approval_mismatch": .numberChanged
        case "already_active": .anotherSetUp
        case "already_booked": .alreadySetUp
        case "already_done": .stoppedSince
        case "server_limit": .serverFull
        case "morning_calls_off": .serverOff
        case "outbound_not_enabled": .callsOff
        case "no_verified_phone": .noVerifiedPhone
        case "phone_not_allowed": .countryNotAllowed
        case "not_configured": .lineNotSetUp
        case "rate_limited": .tooManyTries
        case "invalid", "idempotency_mismatch": .notAccepted
        default: .other
        }
    }
}
