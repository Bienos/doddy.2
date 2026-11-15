import Foundation

// MARK: call_me_every_morning and stop_morning_calls (decision 2026-11-14-morning-call)
//
// "Dzwoń do mnie codziennie o 8 z planem dnia." The agent proposes a time and the days; the card shows them, the zone,
// the last digits of the number, what the call says and a "Call even in quiet hours" switch, and a tap or the person's
// own spoken yes approves exactly that (ApprovalHash.morningCall). It is a standing permission to call them, so every
// field is bound: a different time, day, zone, number, switch or language is a new card. Doddy's messaging server
// keeps the schedule and, on each chosen day, makes it a normal booked call that goes through every check of
// `call_me_later` when it is due. "Przestań dzwonić rano" stops it at once, with no card. Nothing here places a call.

extension VoiceToolName {
    /// A call from Doddy's number to the user's verified number on chosen days at one time, with a plan of the day.
    public static let callMeEveryMorning = "call_me_every_morning"
    /// Stops it at once: taking a permission away needs no card.
    public static let stopMorningCalls = "stop_morning_calls"
}

/// Mirrored in `docs/trust/config/doddy_rules.yaml` (contact_policy) and the server's `morningCalls.ts`;
/// `MorningCallTests` keeps them equal.
public enum MorningCallLimits {
    public static let earliest = "05:00"
    public static let latest = "11:59"
    public static let perAccount = 1
    public static let perServerDefault = 10

    /// Whether "HH:MM" is a morning, 05:00 to 11:59.
    public static func isMorning(_ time: String) -> Bool {
        guard let minutes = CallQuietHours.minutes(time),
              let from = CallQuietHours.minutes(earliest), let to = CallQuietHours.minutes(latest) else { return false }
        return minutes >= from && minutes <= to
    }
}

/// The days of a morning call as ISO weekdays, Monday 1 to Sunday 7, ascending ("12345" for weekdays), exactly as the
/// approval and the server have them.
public struct MorningCallDays: Equatable, Sendable, Hashable {
    public let digits: String

    public init?(digits: String) {
        guard !digits.isEmpty, digits.range(of: "^1?2?3?4?5?6?7?$", options: .regularExpression) != nil else { return nil }
        self.digits = digits
    }

    public static let everyDay = MorningCallDays(digits: "1234567")!
    public static let weekdays = MorningCallDays(digits: "12345")!
    public static let weekend = MorningCallDays(digits: "67")!

    private static let names: [(Int, [String])] = [
        (1, ["mon", "monday"]), (2, ["tue", "tues", "tuesday"]), (3, ["wed", "wednesday"]), (4, ["thu", "thur", "thurs", "thursday"]),
        (5, ["fri", "friday"]), (6, ["sat", "saturday"]), (7, ["sun", "sunday"]),
    ]

    /// The tool's `days`: `every_day`, `weekdays`, `weekend`, or weekday names separated by commas (`mon,wed,fri`).
    /// Anything else is nil, and the agent is asked again; nothing is guessed.
    public init?(spoken: String) {
        let text = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        switch text {
        case "every_day", "everyday", "daily": self = .everyDay
        case "weekdays": self = .weekdays
        case "weekend", "weekends": self = .weekend
        default:
            var picked = Set<Int>()
            for part in text.split(separator: ",") {
                let word = part.trimmingCharacters(in: .whitespaces)
                guard let day = Self.names.first(where: { $0.1.contains(word) })?.0 else { return nil }
                picked.insert(day)
            }
            guard let days = MorningCallDays(digits: picked.sorted().map(String.init).joined()) else { return nil }
            self = days
        }
    }

    public var isoWeekdays: [Int] { digits.compactMap { Int(String($0)) } }

    /// "every day", "on weekdays", "on Mondays, Wednesdays and Fridays"; Polish "codziennie", "w dni robocze", "w poniedziałki, środy i piątki".
    public func text(_ language: NotificationLanguage) -> String {
        let polish = language == .polish
        if self == .everyDay { return polish ? "codziennie" : "every day" }
        if self == .weekdays { return polish ? "w dni robocze" : "on weekdays" }
        if self == .weekend { return polish ? "w weekendy" : "at weekends" }
        let english = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"]
        let polishNames = ["poniedziałki", "wtorki", "środy", "czwartki", "piątki", "soboty", "niedziele"]
        let words = isoWeekdays.map { (polish ? polishNames : english)[$0 - 1] }
        let joined = words.count <= 1 ? words.joined()
            : words.dropLast().joined(separator: ", ") + (polish ? " i " : " and ") + words[words.count - 1]
        // "we wtorki": Polish needs "we" before a word that starts with "w".
        let preposition = polish ? (words.first?.hasPrefix("w") == true ? "we" : "w") : "on"
        return "\(preposition) \(joined)"
    }
}

extension ApprovalHash {
    /// A morning call (decision 2026-11-14-morning-call): to `to` (E.164), at `time` (HH:MM) on the clock of `zone`, on
    /// `days` (ISO weekdays as digits), whether quiet hours may be rung through, and the language the plan is said in.
    public static func morningCall(to: String, time: String, days: String, zone: String, allowQuietHours: Bool, language: String) -> String {
        hex([version, "morning_call", to, time, days, zone, allowQuietHours ? "1" : "0", language])
    }
}

/// A morning call the agent proposed. Nothing is set up until the user says yes or taps on the card.
public struct MorningCallDraft: Equatable, Sendable {
    /// "HH:MM" on the user's clock, from 05:00 to 11:59.
    public let time: String
    public let days: MorningCallDays
    /// The iPhone's zone when it was proposed; the calls follow its clock (08:00 stays 08:00 across summer time).
    public let timeZoneID: String

    public init(time: String, days: MorningCallDays, timeZoneID: String) {
        self.time = time
        self.days = days
        self.timeZoneID = timeZoneID
    }

    /// What the card approves: this number, time, days, zone, quiet-hours choice and language.
    public func approvalHash(to: String, allowQuietHours: Bool, language: NotificationLanguage) -> String {
        ApprovalHash.morningCall(to: to, time: time, days: days.digits, zone: timeZoneID, allowQuietHours: allowQuietHours,
                                 language: language.serverCode)
    }

    /// The same schedule whatever the switch says, for "an earlier try was unclear".
    public func identity(to: String, language: NotificationLanguage) -> String {
        approvalHash(to: to, allowQuietHours: false, language: language)
    }

    /// Whether the time is inside quiet hours on any day (they are a time of day).
    public func inQuietHours(_ quiet: CallQuietHours) -> Bool {
        guard let minutes = CallQuietHours.minutes(time) else { return false }
        let start = CallQuietHours.minutes(quiet.start) ?? 21 * 60
        let end = CallQuietHours.minutes(quiet.end) ?? 8 * 60
        guard start != end else { return false }
        return start < end ? (minutes >= start && minutes < end) : (minutes >= start || minutes < end)
    }

    /// "every day at 08:00" / "codziennie o 08:00".
    public func scheduleText(_ language: NotificationLanguage) -> String {
        language == .polish ? "\(days.text(language)) o \(time)" : "\(days.text(language)) at \(time)"
    }

    /// How the call opens (the server's `callOpening` for a morning call), and what follows it.
    public static func opening(_ language: NotificationLanguage) -> String {
        language == .polish
            ? "Dzień dobry, tu Doddy, asystent AI, z Twoim planem dnia."
            : "Good morning, this is Doddy, an AI assistant, with your plan for the day."
    }

    /// What the plan covers, as the card says it: only what Doddy's server holds, counts and times; the calendar stays on the iPhone.
    public static func covers(_ language: NotificationLanguage) -> String {
        language == .polish
            ? "Data, Twoje telefony od Doddy’ego na później tego dnia, notatki czekające w aplikacji, gotowe wyniki zadań, nowe artykuły na radarze i godzina wiadomości dnia. Kalendarza i przypomnień serwer Doddy’ego nie zna, bo są tylko na iPhonie."
            : "The date, Doddy's calls you booked for later that day, notes waiting in the app, results of tasks you handed over, new stories on your radar and when the daily news comes. Doddy's server can't see your calendar or reminders: they are only on your iPhone."
    }
}

extension VoiceToolRequest {
    /// `time` (HH:MM on the user's clock, 05:00 to 11:59) and `days` (every_day, weekdays, weekend or `mon,wed,fri`; every
    /// day when left out).
    static func parseCallMeEveryMorning(_ args: Arguments, name: String, calendar: Calendar) -> VoiceToolRequest {
        guard let time = args.text("time") else { return .invalid(name: name, reason: "missing time") }
        guard CallQuietHours.minutes(time) != nil else {
            return .invalid(name: name, reason: "time must be HH:MM in 24 hours, for example 08:00")
        }
        guard MorningCallLimits.isMorning(time) else {
            return .needsClarification(name: name, ReminderClarification(
                kind: .unreadable,
                problem: "a morning call can be from \(MorningCallLimits.earliest) to \(MorningCallLimits.latest); for one call at another time use call_me_later",
                question: "for a time in the morning"))
        }
        // Left out means every day; sent but empty is unclear, so it is refused like any other unreadable days.
        if args.has("days"), args.text("days") == nil {
            return .invalid(name: name, reason: "days must be every_day, weekdays, weekend, or weekday names such as mon,wed,fri")
        }
        guard let days = MorningCallDays(spoken: args.text("days") ?? "every_day") else {
            return .invalid(name: name, reason: "days must be every_day, weekdays, weekend, or weekday names such as mon,wed,fri")
        }
        return .callMeEveryMorning(MorningCallDraft(time: time, days: days, timeZoneID: calendar.timeZone.identifier))
    }
}

// MARK: Server

/// The morning call the server keeps for this account.
public struct MorningCall: Equatable, Sendable, Decodable, Identifiable {
    public let id: UUID
    public let time: String
    public let days: String
    public let timeZone: String
    public let allowQuietHours: Bool
    public let language: String
    /// active or stopped.
    public let state: String
    /// The next day's call, UTC; nil once stopped.
    public let nextCallAt: String?

    public var dayList: MorningCallDays? { MorningCallDays(digits: days) }
    public var nextDate: Date? { nextCallAt.flatMap(ServerDates.parse) }
}

/// One day's morning call as the server lists it: the state is a booked call's (`ScheduledCall.state`).
public struct MorningCallDay: Equatable, Sendable, Decodable {
    public let at: String
    public let state: String
    public let errorCode: String?
}

/// `GET /v1/calls/morning`: whether the server makes morning calls (`enabled` its switch, `available` also its phone
/// line), the active one, and the last days' calls.
public struct MorningCallStatus: Equatable, Sendable, Decodable {
    public let enabled: Bool
    public let available: Bool
    public let call: MorningCall?
    public let recent: [MorningCallDay]
}

/// What became of "stop the morning calls".
public enum StopMorningOutcome: Equatable, Sendable {
    /// Stopped. `calling`: that day's call was already being placed, so it may still ring once.
    case stopped(calling: Bool)
    /// There was none to stop.
    case noneActive
    /// The request may have reached the server but no answer came back. Stopping again is safe.
    case unknown
}

extension DoddyServerClient {
    public func morningCall() async throws -> MorningCallStatus {
        try await getJSON("/v1/calls/morning")
    }

    /// A morning call the user approved on a card. `replaces`: the active one the card said this replaces. One
    /// idempotency key per approval, kept until the server answered, so a try-again after an unclear outcome sets it up
    /// at most once. Throws `ServerError` when it certainly wasn't set up.
    public func bookMorningCall(
        _ draft: MorningCallDraft, to: String, allowQuietHours: Bool, language: NotificationLanguage, replaces: UUID?
    ) async throws -> ScheduleCallOutcome {
        let hash = draft.approvalHash(to: to, allowQuietHours: allowQuietHours, language: language)
        let key = pendingCallKey(hash)
        let request = try Self.json(MorningBody(
            time: draft.time, days: draft.days.digits, timeZone: draft.timeZoneID, allowQuietHours: allowQuietHours,
            language: language.serverCode, approvalHash: hash, idempotencyKey: key, replaces: replaces?.uuidString.lowercased()))
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/calls/morning", body: request, startsSomething: true)
        } catch is OutcomeUnknown {
            return .unknown
        }
        if response.status == 202, let booked = try? JSONDecoder().decode(MorningBooked.self, from: response.body) {
            forgetCallKey(hash)
            return booked.state == "active" ? .booked(id: booked.id) : .refused("already_done")
        }
        let code = (try? JSONDecoder().decode(MorningError.self, from: response.body))?.error
        // The server says the booking under this key is over (stopped or replaced since): a later card of the same
        // schedule is a new booking, so it gets a new key, or every try would be answered `already_done`. No duplicate
        // can follow: the server keeps one active morning call per account and refuses an equal one (`already_booked`).
        if response.status == 409, code == "already_done" { forgetCallKey(hash) }
        switch (response.status, code) {
        case (400, _): return .refused("invalid")
        case (409, _): return .refused(code ?? "status_409")
        case (429, _): return .refused(code ?? "rate_limited")
        case (503, _): return .refused(code ?? "not_configured")
        // Any other server error may come after the server set it up: unknown, never "not set up".
        case (500..., _): return .unknown
        default: throw Self.error(from: response)
        }
    }

    /// "Przestań dzwonić rano" or the Stop button. Always accepted by the server; safe to send twice.
    public func stopMorningCalls() async throws -> StopMorningOutcome {
        let response: ServerResponse
        do {
            response = try await authorized(.delete, "/v1/calls/morning", body: nil, startsSomething: true)
        } catch is OutcomeUnknown {
            return .unknown
        }
        guard response.status == 200, let answer = try? JSONDecoder().decode(MorningStopped.self, from: response.body) else {
            if response.status >= 500 { return .unknown }
            throw Self.error(from: response)
        }
        return answer.stopped ? .stopped(calling: answer.calling) : .noneActive
    }
}

private struct MorningBody: Encodable {
    let time: String
    let days: String
    let timeZone: String
    let allowQuietHours: Bool
    let language: String
    let approvalHash: String
    let idempotencyKey: String
    let replaces: String?
}
private struct MorningBooked: Decodable { let id: UUID; let state: String }
private struct MorningError: Decodable { let error: String? }
private struct MorningStopped: Decodable { let stopped: Bool; let calling: Bool }

// MARK: What the agent hears

extension VoiceToolReply {
    public static let morningCallDeclined = "declined: the user chose not to set up morning calls. Nothing was set up."

    /// Before the card: the server's switch for morning calls is off.
    public static let morningCallsOff =
        "failed: morning calls aren't switched on on Doddy's server yet, so Doddy can't call the user every morning. Nothing was set up. "
        + "For one call at a set time, offer call_me_later."

    /// The server set it up. Not a call yet: each day's call is checked again when it is due.
    public static func morningCallBooked(_ draft: MorningCallDraft, next: Date?, calendar: Calendar) -> String {
        var local = calendar
        local.timeZone = TimeZone(identifier: draft.timeZoneID) ?? calendar.timeZone
        let first = next.map { " The first one is \(localText($0, hasTime: true, calendar: local))." } ?? ""
        return "booked: Doddy's server will call the user's number \(draft.scheduleText(.english)) (\(draft.timeZoneID) time).\(first) "
            + "Each call starts with the date and only what Doddy's server holds for that day: calls the user booked for later, notes "
            + "waiting in the app, results of tasks they handed over, new stories on their radar and when the daily news comes. It "
            + "can't see their calendar or reminders, and it says so. If it can't call one day (quiet hours in their iPhone's time "
            + "zone, the limit on calls, their number or consent changed), it doesn't call and sends a notification if notifications "
            + "are on. They stop it by saying so (stop_morning_calls) or in Settings, Phone calls."
    }

    /// `mayBeBooked`: an earlier try had an unclear outcome, so a refusal now doesn't mean nothing is set up.
    public static func morningCallRefused(_ code: String, quietHours: CallQuietHours = .standard, mayBeBooked: Bool = false) -> String {
        let reason = switch code {
        case "quiet_hours":
            "that time is inside quiet hours (\(quietHours.start) to \(quietHours.end)). Ask for a later time, or whether to call even in quiet hours, which the user can switch on on the card."
        case "approval_mismatch":
            "the user's number changed after the card was shown, so the approval didn't match."
        case "already_active":
            "another morning call was set up in the meantime. Ask the user again so the card shows which one it replaces."
        case "already_booked":
            "exactly this morning call is already set up. The user can see it in Settings, Phone calls."
        case "already_done":
            "this exact morning call was set up earlier and has been stopped since. Ask the user again for a new one."
        case "server_limit":
            "Doddy's server already makes as many morning calls as it may. Offer call_me_later for one call instead."
        case "morning_calls_off":
            "morning calls aren't switched on on Doddy's server yet."
        case "outbound_not_enabled":
            "calls from Doddy are switched off in Settings, Phone calls."
        case "no_verified_phone":
            "the user has no verified number in Settings, Notifications and texts."
        case "phone_not_allowed":
            "the user's number is in a country Doddy doesn't call."
        case "not_configured":
            "Doddy's phone line isn't set up on its server yet."
        case "rate_limited":
            "there were too many tries in the last hour. Try again later."
        case "idempotency_mismatch":
            "the server saw a different morning call under the same approval. Ask the user to ask again."
        case "invalid":
            "the server didn't accept the time or the days as written."
        default:
            "the server refused it (\(code))."
        }
        if code == "already_booked" { return "failed: \(reason) Nothing new was set up." }
        if mayBeBooked {
            return "failed: \(reason) Nothing new was set up, but Doddy couldn't confirm an earlier try, so it may already be set up. "
                + "Tell the user to check Settings, Phone calls."
        }
        return "failed: \(reason) Nothing was set up."
    }

    public static let morningCallUnknown = """
        unknown: Doddy couldn't confirm whether its server set up the morning calls. Don't say they are set up, and don't call \
        call_me_every_morning again on your own. The user can check in Settings, Phone calls. If they ask to try again, call it \
        with exactly the same time and days: the server sets up the same schedule at most once.
        """

    public static func morningCallsStopped(calling: Bool) -> String {
        "turned off: Doddy's server won't call the user in the morning any more."
            + (calling ? " That day's call was already being placed, so it may still ring this once." : "")
    }

    public static let noMorningCalls = "not changed: there was no morning call to stop. Nothing was set up."

    public static let morningStopUnknown =
        "unknown: Doddy couldn't confirm the stop reached its server. Don't say the calls are stopped. Stopping again is safe: "
        + "call stop_morning_calls once more, or the user can tap Stop in Settings, Phone calls."

    public static func morningStopFailed(_ error: ServerError?) -> String {
        switch error {
        case .offline?: "failed: Doddy couldn't reach its server, so the morning calls weren't stopped. Try again when online, or tap Stop in Settings, Phone calls."
        default: "failed: Doddy's server gave an answer Doddy didn't expect, so the morning calls may not be stopped. The user can tap Stop in Settings, Phone calls."
        }
    }

    public static let morningStopNoServer =
        "failed: Doddy's server isn't set up in this version of the app, so there are no morning calls from it to stop."
}
