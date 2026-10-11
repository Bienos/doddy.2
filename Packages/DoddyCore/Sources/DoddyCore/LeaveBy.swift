import Foundation

// "Remind me when to leave" (ADR-335). For a place and an arrival time, the app reads where the
// iPhone is once (While Using location), asks Apple Maps for the travel time to arrive by then,
// and shows a card: the place Maps found, the travel time, and when to leave. Only after Set
// reminder is a local notification scheduled, and it is read back from iOS. The travel time is
// worked out when the card is made; traffic can change, and the card and reply say so.

public enum TravelMode: String, Codable, Equatable, Sendable, CaseIterable {
    case driving, walking, transit

    public var phrase: String {
        switch self {
        case .driving: "by car"
        case .walking: "on foot"
        case .transit: "by public transport"
        }
    }
}

public struct LeaveByRequest: Equatable, Sendable {
    public static let maxBufferMinutes = 60
    public let place: String
    public let arriveBy: Date
    public let mode: TravelMode
    public let bufferMinutes: Int

    public init(place: String, arriveBy: Date, mode: TravelMode = .driving, bufferMinutes: Int = 10) {
        self.place = place
        self.arriveBy = arriveBy
        self.mode = mode
        self.bufferMinutes = bufferMinutes
    }
}

public struct LeaveByPlan: Equatable, Sendable {
    public let request: LeaveByRequest
    /// The place Apple Maps found, as shown on the card.
    public let placeName: String
    public let placeAddress: String
    public let travelSeconds: TimeInterval
    public let leaveAt: Date
    /// When the travel time was worked out.
    public let computedAt: Date

    public var travelMinutes: Int { Int((travelSeconds / 60).rounded(.up)) }
}

public enum LeaveByProblem: Error, Equatable, Sendable {
    /// Leaving would already be in the past, or within the next minute.
    case tooLate(leaveAt: Date)
    /// More than 12 hours of travel: not a "when to leave" reminder.
    case tooFar
}

public enum LeaveBy {
    public static let maxTravel: TimeInterval = 12 * 3600

    public static func plan(_ request: LeaveByRequest, placeName: String, placeAddress: String, travelSeconds: TimeInterval,
                            now: Date) -> Result<LeaveByPlan, LeaveByProblem> {
        guard travelSeconds > 0, travelSeconds <= maxTravel else { return .failure(.tooFar) }
        let leaveAt = request.arriveBy.addingTimeInterval(-travelSeconds - TimeInterval(request.bufferMinutes * 60))
        // Rounded down to the minute, so the reminder is never later than needed.
        let rounded = Date(timeIntervalSince1970: (leaveAt.timeIntervalSince1970 / 60).rounded(.down) * 60)
        guard rounded > now.addingTimeInterval(60) else { return .failure(.tooLate(leaveAt: rounded)) }
        return .success(LeaveByPlan(request: request, placeName: placeName, placeAddress: placeAddress,
                                    travelSeconds: travelSeconds, leaveAt: rounded, computedAt: now))
    }

    /// The notification: where to, by when, and how the time was worked out. Nothing more.
    public static func notification(_ plan: LeaveByPlan, calendar: Calendar, language: NotificationLanguage = .english) -> (title: String, body: String) {
        let arrive = clock(plan.request.arriveBy, calendar: calendar)
        switch language {
        case .english:
            return ("Time to leave",
                    "For \(plan.placeName), to be there by \(arrive). About \(plan.travelMinutes) min \(plan.request.mode.phrase) when you set this; traffic may have changed.")
        case .polish:
            let how = switch plan.request.mode {
            case .driving: "samochodem"
            case .walking: "pieszo"
            case .transit: "komunikacją miejską"
            }
            return ("Czas wychodzić",
                    "Do: \(plan.placeName), żeby być na \(arrive). Około \(plan.travelMinutes) min \(how) w chwili ustawiania; ruch mógł się zmienić.")
        }
    }

    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

extension VoiceToolName {
    public static let remindWhenToLeave = "remind_when_to_leave"
}

extension VoiceToolRequest {
    static func parseLeaveBy(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let place = args.text("place")?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty, place.count <= 200 else {
            return .invalid(name: name, reason: "missing place")
        }
        guard let text = args.text("arrive_by") else { return .invalid(name: name, reason: "missing arrive_by") }
        switch ReminderDueRules.check(text, now: now, calendar: calendar) {
        case .clarify(let question): return .needsClarification(name: name, question)
        case .due(let due):
            guard due.hasTime, let arriveBy = due.date(in: calendar) else {
                return .invalid(name: name, reason: "arrive_by needs a time, as YYYY-MM-DDTHH:MM")
            }
            var mode = TravelMode.driving
            if let raw = args.text("mode") {
                guard let parsed = TravelMode(rawValue: raw.lowercased()) else { return .invalid(name: name, reason: "mode must be driving, walking or transit") }
                mode = parsed
            }
            let buffer = args.number("buffer_minutes").map { Int($0) } ?? 10
            guard (0...LeaveByRequest.maxBufferMinutes).contains(buffer) else { return .invalid(name: name, reason: "buffer_minutes must be 0 to 60") }
            return .leaveBy(LeaveByRequest(place: place, arriveBy: arriveBy, mode: mode, bufferMinutes: buffer))
        }
    }
}

extension VoiceToolReply {
    public static func leaveBySet(_ plan: LeaveByPlan, calendar: Calendar) -> String {
        "added: a reminder to leave at \(LeaveBy.clock(plan.leaveAt, calendar: calendar)) on \(LeaveBy.day(plan.leaveAt, calendar: calendar)) "
            + "for \(plan.placeName), to arrive by \(LeaveBy.clock(plan.request.arriveBy, calendar: calendar)): "
            + "about \(plan.travelMinutes) min \(plan.request.mode.phrase) plus \(plan.request.bufferMinutes) min spare. "
            + "Apple Maps worked out the travel time just now; traffic can change, so say so."
    }

    public static let leaveByDeclined = "declined: the user chose not to set the reminder. Nothing was set."

    public static func leaveByTooLate(_ leaveAt: Date, calendar: Calendar) -> String {
        "not added: to arrive on time the user would have had to leave at \(LeaveBy.clock(leaveAt, calendar: calendar)), which has passed or is now. Tell them; nothing was set."
    }

    public static let leaveByTooFar = "not added: the trip is longer than 12 hours or has no travel time. Nothing was set; say a leave reminder isn't useful for it."

    public static func leaveByNoPlace(_ place: String) -> String {
        "not found: Apple Maps found no place for \"\(place)\". Nothing was set. Ask the user for the address or a clearer name."
    }

    public static func leaveByNoRoute(_ mode: TravelMode) -> String {
        "failed: Apple Maps found no route \(mode.phrase) to that place. Nothing was set. Offer another way of travelling if it makes sense."
    }
}

extension VoiceToolReply {
    /// Location isn't usable, or no position came within 15 seconds. Approximate location is
    /// enough for travel time.
    public static func leaveByNoLocation(_ readiness: LocationReadiness?) -> String {
        switch readiness {
        case .denied: return "failed: Doddy isn't allowed to use location, which it needs once to work out the travel time. Tell the user they can allow it (While Using) in iOS Settings, Doddy, Location. Nothing was set."
        case .unavailable: return "failed: Location Services are off on this iPhone, so the travel time can't be worked out. Nothing was set."
        default: return "failed: the iPhone couldn't get its position just now, so the travel time can't be worked out. Nothing was set; offer a reminder at a time the user picks instead."
        }
    }

    public static let leaveByNotAllowed = "failed: notifications are off for Doddy, so it can't remind the user. Tell them they can allow notifications in iOS Settings, Doddy. Nothing was set."
    public static let leaveByFailed = "failed: the reminder couldn't be set on this iPhone. Nothing was set."
}
