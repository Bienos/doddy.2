import Foundation

// MARK: call_me_later (ADR-490 unit U4, ADR-495)
//
// "Call me at six about the cake." The agent proposes a time and a reason; the card shows the time,
// the last digits of the number, the exact sentence Doddy will say when the call is answered, and
// a "Call even in quiet hours" switch. The tap approves exactly that (ApprovalHash.call). Doddy's
// messaging server books it and its worker places the call at that time, after checking the number,
// consent, quiet hours where the user is then, and the caps again. Nothing here places a call.

extension VoiceToolName {
    /// A call from Doddy's number to the user's verified number at a later time, after a card.
    public static let callMeLater = "call_me_later"
}

/// Mirrored in `docs/trust/config/doddy_rules.yaml` (contact_policy) and the server's
/// `scheduledCalls.ts`; `ScheduledCallTests` keeps them equal.
public enum ScheduledCallLimits {
    /// UTF-16 code units, as the server counts them. Longer is refused, never cut.
    public static let reasonMaxLength = 200
    public static let maxDaysAhead = 7
    /// The card needs a little time to be read and tapped; the server itself refuses less than a minute.
    public static let minimumLead: TimeInterval = 120
    /// A call the server couldn't place within this long after its time is not placed at all.
    public static let lateMinutes = 15
    public static let pendingMax = 10

    /// Why a reason can't go on a card, or nil when it can. The phone agent receives it as a
    /// variable, so `{{` and `}}` are refused too.
    public static func problem(with reason: String) -> String? {
        if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "reason is empty" }
        if reason.utf16.count > reasonMaxLength { return "reason is longer than \(reasonMaxLength) characters" }
        if let hidden = ApprovedTextLimits.hiddenCharacter(in: reason) {
            return "reason has a hidden character (U+\(String(hidden.value, radix: 16, uppercase: true))); write it without"
        }
        if reason.contains("{{") || reason.contains("}}") { return "reason can't contain {{ or }}" }
        if reason.contains("\n") || reason.contains("\r") { return "reason must be one line" }
        return nil
    }
}

/// Quiet hours as the server sends them, on the user's own clock: no scheduled call rings inside
/// them unless its card allowed it. A window whose start is after its end crosses midnight.
public struct QuietHours: Equatable, Sendable, Codable {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    /// Also in doddy_rules.yaml (contact_policy.quiet_hours_default).
    public static let standard = QuietHours(start: "21:00", end: "08:00")

    /// "HH:MM" to minutes after midnight.
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// Whether `date` falls inside quiet hours on the wall clock of `timeZone`, the way the server
    /// decides it. Unreadable hours count as the standard ones.
    public func contains(_ date: Date, timeZone: TimeZone) -> Bool {
        let start = Self.minutes(start) ?? 21 * 60
        let end = Self.minutes(end) ?? 8 * 60
        guard start != end else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let clock = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }
}

extension ApprovalHash {
    /// A call Doddy places later (ADR-495): to `to` (E.164), at `at` (UTC, YYYY-MM-DDTHH:MM:SSZ),
    /// saying `reason`, and whether the user allowed it inside quiet hours.
    public static func call(to: String, at: String, reason: String, allowQuietHours: Bool) -> String {
        hex([version, "call", to, at, reason, allowQuietHours ? "1" : "0"])
    }
}

/// A call the agent proposed. Nothing is booked until the user taps Book call on the card.
public struct CallLaterDraft: Equatable, Sendable {
    /// Whole minutes in the user's zone, so the card and the server agree on the second.
    public let at: Date
    /// Exactly as the agent wrote it: the card shows it and Doddy says it when the call is answered.
    public let reason: String
    /// The iPhone's zone when it was proposed; quiet hours are checked here and again by the server
    /// where the user is when the call is due.
    public let timeZoneID: String

    public init(at: Date, reason: String, timeZoneID: String) {
        self.at = Date(timeIntervalSince1970: (at.timeIntervalSince1970).rounded(.down))
        self.reason = reason
        self.timeZoneID = timeZoneID
    }

    /// The time as the approval and the server have it.
    public var atText: String { Self.utc(at) }

    static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }

    /// The same call whatever the quiet-hours switch says, for "an earlier try was unclear".
    public func identity(to: String) -> String { approvalHash(to: to, allowQuietHours: false) }

    /// What the card approves: this number, this time, this reason, and the quiet-hours choice.
    public func approvalHash(to: String, allowQuietHours: Bool) -> String {
        ApprovalHash.call(to: to, at: atText, reason: reason, allowQuietHours: allowQuietHours)
    }

    public func inQuietHours(_ quiet: QuietHours) -> Bool { quiet.contains(at, timeZone: timeZone) }

    /// What Doddy says first when the call is answered, as the server writes it (callOpening).
    public func opening(_ language: NotificationLanguage) -> String {
        language == .polish
            ? "Cześć, tu Doddy, asystent AI. Dzwonię zgodnie z Twoją prośbą w sprawie: \(reason)"
            : "Hi, this is Doddy, an AI assistant. You asked me to call you about this: \(reason)"
    }
}

/// Whether a call can be proposed at all: the user verified their number, agreed to calls from
/// Doddy, and the server can place calls.
public enum CallReadiness: Equatable, Sendable {
    case ready(to: String, quietHours: QuietHours)
    case noPhone
    case callsOff
    case notSetUp

    public init(settings: CallSettings, phone: PhoneStatus) {
        if !settings.available.outbound {
            self = .notSetUp
        } else if let number = phone.phone, settings.phoneVerified {
            self = settings.outboundConsent ? .ready(to: number, quietHours: settings.quietHours ?? .standard) : .callsOff
        } else {
            self = .noPhone
        }
    }
}

extension VoiceToolRequest {
    /// `time` (YYYY-MM-DDTHH:MM, local), `reason`, optional `said_time` (the user's own words).
    static func parseCallMeLater(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let timeText = args.text("time") else { return .invalid(name: name, reason: "missing time") }
        // Exactly as the agent wrote it: the card shows it and Doddy says it, so nothing is trimmed.
        guard let reason = args.text("reason") else { return .invalid(name: name, reason: "missing reason") }
        if let problem = ScheduledCallLimits.problem(with: reason) { return .invalid(name: name, reason: problem) }
        let due: ReminderDue
        switch ReminderDueRules.check(timeText, now: now, calendar: calendar) {
        case .due(let checked): due = checked
        case .clarify(let clarification): return .needsClarification(name: name, clarification)
        }
        guard due.hasTime, let date = due.date else {
            return .needsClarification(name: name, ReminderClarification(
                kind: .unreadable, problem: "a call needs a time of day, not only a day", question: "what time"))
        }
        // The user's own words for when, if the agent passed them (ADR-253).
        if let said = args.text("said_time"), let question = SaidTime.check(said, due: due, now: now, timeRequired: true) {
            return .needsClarification(name: name, question)
        }
        if date.timeIntervalSince(now) < ScheduledCallLimits.minimumLead {
            return .needsClarification(name: name, ReminderClarification(
                kind: .unreadable, problem: "a call can be booked from two minutes ahead; for a call now, the user taps Call me now in Settings, Phone calls",
                question: "for a time at least a few minutes from now"))
        }
        if date.timeIntervalSince(now) > TimeInterval(ScheduledCallLimits.maxDaysAhead) * 86_400 {
            return .needsClarification(name: name, ReminderClarification(
                kind: .unreadable, problem: "a call can be booked at most \(ScheduledCallLimits.maxDaysAhead) days ahead",
                question: "for a time within the next week, or suggest a reminder instead"))
        }
        return .callMeLater(CallLaterDraft(at: date, reason: reason, timeZoneID: due.timeZoneID ?? calendar.timeZone.identifier))
    }
}

/// When the app tells the server its time zone again (ADR-495): quiet hours for a booked call are
/// checked in the zone the server last heard, so the app sends a new one when it comes to the
/// front while a call it booked may still be waiting. Nothing is sent when no call is waiting.
public enum CallZoneSync {
    public static let waitingUntilKey = "calls.bookedWaitingUntil"
    public static let lastSentKey = "calls.lastSentTimeZone"

    public static func shouldSend(now: Date, waitingUntil: Date?, lastSent: String?, current: String) -> Bool {
        guard let waitingUntil, waitingUntil > now else { return false }
        return lastSent != current
    }

    /// After a booking or a list from the server: the latest time a call may still be waiting.
    public static func waitingUntil(_ calls: [ScheduledCall]) -> Date? {
        calls.filter(\.canCancel).compactMap(\.atDate).max()
    }
}

// MARK: Server

/// A call booked for later, as the server lists it. `reason` is nil once the call is over or
/// won't happen (it is erased then), or when it can't be read.
public struct ScheduledCall: Equatable, Sendable, Decodable, Identifiable {
    public let id: UUID
    /// UTC, YYYY-MM-DDTHH:MM:SSZ.
    public let at: String
    /// scheduled, placing, placed, cancelled, skipped_quiet_hours, missed, limit, failed or unknown.
    public let state: String
    public let errorCode: String?
    public let allowQuietHours: Bool
    public let reason: String?

    public var atDate: Date? { ServerDates.parse(at) }
    public var canCancel: Bool { state == "scheduled" }
}

/// What happened to a call the user approved on a card.
public enum ScheduleCallOutcome: Equatable, Sendable {
    /// The server booked it, or had booked it on an earlier try of the same approval.
    case booked(id: UUID)
    /// Refused before anything was booked; the server's error code (see `VoiceToolReply.callRefused`).
    case refused(String)
    /// The request may have reached the server but no answer came back (DOD-08).
    case unknown
}

extension DoddyServerClient {
    func pendingCallKey(_ hash: String) -> String {
        if let key = pendingCallKeys[hash] { return key }
        let key = UUID().uuidString
        pendingCallKeys[hash] = key
        return key
    }

    func forgetCallKey(_ hash: String) { pendingCallKeys[hash] = nil }

    /// A call the user approved on a card (ADR-495). `allowQuietHours` is the card's switch; the
    /// approval covers it with the number, time and reason. One idempotency key per approval, kept
    /// until the server booked it, so a try-again after an unknown outcome books it at most once.
    /// Throws `ServerError` when it certainly wasn't booked.
    public func scheduleCall(
        _ draft: CallLaterDraft, to: String, allowQuietHours: Bool, language: NotificationLanguage
    ) async throws -> ScheduleCallOutcome {
        let hash = draft.approvalHash(to: to, allowQuietHours: allowQuietHours)
        let key = pendingCallKey(hash)
        let request = try Self.json(ScheduleBody(
            at: draft.atText, reason: draft.reason, timeZone: draft.timeZoneID, allowQuietHours: allowQuietHours,
            language: language.serverCode, approvalHash: hash, idempotencyKey: key))
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/calls/scheduled", body: request, startsSomething: true)
        } catch is OutcomeUnknown {
            return .unknown
        }
        if response.status == 202, let booked = try? JSONDecoder().decode(Booked.self, from: response.body) {
            forgetCallKey(hash)
            // A repeat of a call that is no longer waiting is not "booked" (the server answers
            // 409 for that; this guards against an older server that repeats 202).
            if let state = booked.state, state != "scheduled", state != "placing" { return .refused("already_done") }
            return .booked(id: booked.id)
        }
        let code = (try? JSONDecoder().decode(CallError.self, from: response.body))?.error
        switch (response.status, code) {
        // Each of these is answered before anything is booked.
        case (400, _): return .refused("invalid")
        case (409, _): return .refused(code ?? "status_409")
        case (429, _): return .refused(code ?? "rate_limited")
        case (503, _): return .refused("not_configured")
        // Any other server error may come after the server booked it: unknown, never "not booked".
        case (500..., _): return .unknown
        default: throw Self.error(from: response)
        }
    }

    public func scheduledCalls() async throws -> [ScheduledCall] {
        let list: ScheduledList = try await getJSON("/v1/calls/scheduled")
        return list.calls
    }

    /// Only a call still waiting can be cancelled; the server answers 409 for one already placed.
    public func cancelScheduledCall(_ id: UUID) async throws {
        try await expect(204, .delete, "/v1/calls/scheduled/\(id.uuidString.lowercased())")
    }

    /// The iPhone's current zone, so quiet hours are checked where the user is when a call is due.
    public func setCallTimeZone(_ identifier: String) async throws {
        try await expect(204, .put, "/v1/calls/settings", ZoneBody(timeZone: identifier))
    }
}

private struct ScheduleBody: Encodable {
    let at: String
    let reason: String
    let timeZone: String
    let allowQuietHours: Bool
    let language: String
    let approvalHash: String
    let idempotencyKey: String
}
private struct Booked: Decodable { let id: UUID; let state: String? }
private struct CallError: Decodable { let error: String? }
private struct ScheduledList: Decodable { let calls: [ScheduledCall] }
private struct ZoneBody: Encodable { let timeZone: String }

// MARK: What the agent hears

extension VoiceToolReply {
    public static let callDeclined = "declined: the user chose not to book this call. Nothing was booked."

    public static let callNoServer =
        "failed: Doddy's server isn't set up in this version of the app, so Doddy can't call the user later. Nothing was booked."

    public static let callOffline =
        "failed: Doddy couldn't reach its server, so nothing was booked. The user can try again when they're online."

    /// Before the card: the server couldn't say which number is the user's or whether calls are on.
    public static func callCheckFailed(_ error: ServerError?) -> String {
        switch error {
        case .offline?: callOffline
        case .accountMissing?: callNotReady(.noPhone)
        default: "failed: Doddy couldn't check the user's number with its server, so nothing was booked. The user can try again in a moment."
        }
    }

    public static func callNotReady(_ readiness: CallReadiness) -> String {
        switch readiness {
        case .ready:
            "failed: something went wrong before the card was shown. Nothing was booked."
        case .noPhone:
            "failed: the user hasn't verified their phone number in Settings, Notifications and texts, so Doddy has no number to call. Nothing was booked."
        case .callsOff:
            "failed: calls from Doddy are switched off. The user can turn on Doddy may call me in Settings, Phone calls. Nothing was booked."
        case .notSetUp:
            "failed: Doddy's phone line isn't set up on its server yet, so it can't call. Nothing was booked."
        }
    }

    /// After the tap, an answer that means the call certainly wasn't booked.
    public static func callNotBooked(_ error: ServerError?) -> String {
        switch error {
        case .offline?: callOffline
        case .accountMissing?:
            "failed: Doddy's server no longer knows this iPhone, so the user needs to verify their number again in Settings, Notifications and texts. Nothing was booked."
        default: "failed: Doddy's server gave an answer Doddy didn't expect. Nothing was booked."
        }
    }

    /// `mayBeBooked`: an earlier try of this call had an unclear outcome, so a refusal now doesn't
    /// mean nothing is booked (the earlier one may be).
    public static func callRefused(_ code: String, quietHours: QuietHours = .standard, mayBeBooked: Bool = false) -> String {
        let reason = switch code {
        case "quiet_hours":
            "that time is inside quiet hours (\(quietHours.start) to \(quietHours.end)) where the user is. Ask for another time, or whether to call even in quiet hours, which the user can switch on on the card."
        case "approval_mismatch":
            "the user's number changed after the card was shown, so the approval didn't match."
        case "too_soon":
            "that time is less than a minute away."
        case "too_far":
            "that time is more than \(ScheduledCallLimits.maxDaysAhead) days away."
        case "too_many_scheduled":
            "\(ScheduledCallLimits.pendingMax) calls are already booked. The user can cancel one in Settings, Phone calls."
        case "daily_limit":
            "Doddy may call the user at most \(ContactCaps.callsPerDay) times a day, and that day is full."
        case "hourly_limit":
            "Doddy may call the user at most \(ContactCaps.callsPerHour) times an hour, and that hour is full. Suggest another time."
        case "outbound_not_enabled":
            "calls from Doddy are switched off in Settings, Phone calls."
        case "no_verified_phone":
            "the user has no verified number in Settings, Notifications and texts."
        case "not_configured":
            "Doddy's phone line isn't set up on its server yet."
        case "rate_limited":
            "there were too many tries in the last hour. Try again later."
        case "idempotency_mismatch":
            "the server saw a different call under the same approval. Ask the user to ask again."
        case "already_booked":
            "this exact call (the same time and reason) is already booked. The user can see it in Settings, Phone calls."
        case "already_done":
            "this exact call was booked earlier and isn't waiting any more (it was placed, cancelled or skipped). The user can see what happened in Settings, Phone calls."
        case "invalid":
            "the server didn't accept the time or the reason as written."
        default:
            "the server refused it (\(code))."
        }
        if code == "already_booked" || code == "already_done" { return "failed: \(reason) Nothing new was booked." }
        if mayBeBooked {
            return "failed: \(reason) Nothing new was booked, but Doddy couldn't confirm an earlier try of this call, so it may already be booked. "
                + "Tell the user to check Settings, Phone calls."
        }
        return "failed: \(reason) Nothing was booked."
    }

    /// The server booked it. Not a call yet: the server still checks quiet hours and the caps when
    /// it is due, and tells the user if it doesn't call.
    public static func callBooked(_ draft: CallLaterDraft, calendar: Calendar) -> String {
        var local = calendar
        local.timeZone = draft.timeZone
        return "booked: Doddy's server will call the user's number at \(localText(draft.at, hasTime: true, calendar: local)). "
            + "When they answer, Doddy says the reason first. If it can't call then (quiet hours in their iPhone's time zone, "
            + "the limit on calls, their number or consent changed), it doesn't call and sends a notification if notifications are on. "
            + "They can cancel it in Settings, Phone calls."
    }

    /// The request may have reached the server but no answer came back (DOD-08, DOD-09).
    public static let callUnknown = """
        unknown: Doddy couldn't confirm whether its server booked the call. Don't say it is booked, and don't call \
        call_me_later again on your own. The user can check in Settings, Phone calls. If they ask to try again, call \
        call_me_later with exactly the same time and reason: the server books the same time and reason at most once.
        """
}

extension ContactCaps {
    /// The server's caps on Doddy's calls (contact_policy.caps_default).
    public static let callsPerHour = 3
    public static let callsPerDay = 10
}
