import Foundation

// MARK: call_me_now (decision 2026-11-10-call-me-now-by-voice)
//
// "Doddy, call me." The same call as Settings › Phone calls › Call me now (ADR-750): from Doddy's
// number to the user's own verified number, at once. The card shows the last digits of that number;
// nothing is placed until the tap. Doddy's messaging server checks the number, consent and the caps
// again before Twilio rings the phone. Nothing here places a call.

extension VoiceToolName {
    /// A call from Doddy's number to the user's verified number now, after a card.
    public static let callMeNow = "call_me_now"
}

/// What happened to a "Call me now" the user approved on a card.
public enum CallNowOutcome: Equatable, Sendable {
    /// Twilio accepted the call; the phone should ring. Not yet answered.
    case requested
    /// The request may have reached the server but no answer came back (DOD-08): it may be ringing.
    case unknown
    /// Certainly not placed; the server's reason.
    case refused(ServerError)

    public init(_ request: CallRequest) {
        self = request.status == "requested" ? .requested : .unknown
    }
}

extension VoiceToolReply {
    public static let callNowDeclined = "declined: the user chose not to be called now. No call was placed."

    public static let callNowNoServer =
        "failed: Doddy's server isn't set up in this version of the app, so Doddy can't call the user. No call was placed."

    /// Before the card: why Doddy can't call now. Same reasons as a call booked for later.
    public static func callNowNotReady(_ readiness: CallReadiness) -> String {
        callNotReady(readiness).replacingOccurrences(of: "Nothing was booked.", with: "No call was placed.")
    }

    /// Before the card: the server couldn't say which number is the user's or whether calls are on.
    public static func callNowCheckFailed(_ error: ServerError?) -> String {
        switch error {
        case .offline?:
            "failed: Doddy couldn't reach its server, so no call was placed. The user can try again when they're online."
        case .accountMissing?:
            callNowNotReady(.noPhone)
        default:
            "failed: Doddy couldn't check the user's number with its server, so no call was placed. The user can try again in a moment."
        }
    }

    public static func callNow(_ outcome: CallNowOutcome) -> String {
        switch outcome {
        case .requested:
            return "requested: Doddy's phone line is calling the user's number now. Say in one short sentence that their phone "
                + "will ring. Don't say the call connected: Doddy only knows it was started."
        case .unknown:
            return "unknown: Doddy couldn't confirm whether its server started the call, so the phone may or may not ring. "
                + "Don't say it is calling, and don't call call_me_now again on your own. If nothing rings within a minute, "
                + "the user can ask again or tap Call me now in Settings, Phone calls."
        case .refused(let error):
            return "failed: \(refusal(error)) No call was placed."
        }
    }

    static func refusal(_ error: ServerError) -> String {
        switch error {
        case .providerUnavailable:
            "the phone service turned the call down. The user can try again in a few minutes."
        case .offline:
            "Doddy couldn't reach its server. The user can try again when they're online."
        case .rateLimited:
            "Doddy may call the user at most \(ContactCaps.callsPerHour) times an hour and \(ContactCaps.callsPerDay) times a day, and that limit is reached."
        case .notConfigured:
            "Doddy's phone line isn't set up on its server yet."
        case .notEnabled("no_verified_phone"):
            "the user hasn't verified their phone number in Settings, Notifications and texts."
        case .notEnabled("outbound_not_enabled"):
            "calls from Doddy are switched off. The user can turn on Doddy may call me in Settings, Phone calls."
        case .notEnabled("phone_not_allowed"):
            "the user's number is in a country Doddy doesn't call."
        case .accountMissing:
            "Doddy's server no longer knows this iPhone, so the user needs to verify their number again in Settings, Notifications and texts."
        default:
            "Doddy's server gave an answer Doddy didn't expect."
        }
    }
}
