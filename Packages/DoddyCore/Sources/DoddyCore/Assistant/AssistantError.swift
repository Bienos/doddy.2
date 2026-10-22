import Foundation

/// Everything that can go wrong asking the assistant (docs/architecture/AI_RUNTIME.md).
/// None of these touch local memory: notes stay usable whatever happens here.
public enum AssistantError: Error, Equatable, Sendable {
    case notConfigured
    case consentRequired
    case notAuthorized
    case offline
    case timeout
    case rateLimited(retryAfterSeconds: Int?)
    /// Doddy's daily Ask Doddy cap (this iPhone, or everyone) is used up until the next UTC day.
    case dailyLimitReached
    case providerUnavailable
    case refused
    case invalidRequest
    /// The answer cited a note that was not sent, or cited the same note twice. The answer is discarded.
    case invalidCitations
    /// The reply could not be parsed or was empty. The answer is discarded.
    case malformedResponse
    case unsafeToolRequest
    case cancelled

    /// Worth an automatic retry. Offline, rate limits and refusals are not: they need the user or time.
    /// Nor is a timeout: the gateway may have passed the question and notes to the model and spent
    /// the budget, so sending it again is the user's choice (Try again), not automatic (DOD-11).
    public var isTransient: Bool {
        switch self {
        case .providerUnavailable: true
        default: false
        }
    }

    /// Whether a "Try again" button makes sense right now. The daily spend cap only resets on the
    /// next UTC day, so retrying sooner can only fail again (ADR-125).
    public var canRetryNow: Bool {
        self != .dailyLimitReached
    }

    /// Plain wording for the screen. Never includes request text.
    public var userMessage: String {
        switch self {
        case .notConfigured:
            "Ask Doddy isn't set up on Doddy's server yet."
        case .consentRequired:
            "Turn on Ask Doddy in Settings first. It sends your question to a server."
        case .notAuthorized:
            "Doddy couldn't sign this iPhone in to his server. Check your connection and try again."
        case .offline:
            "You're offline. Your notes still work. Try again when you're connected."
        case .timeout:
            "That took too long. Nothing was lost. Try again."
        case .rateLimited(let seconds):
            if let seconds { "Doddy is getting a lot of questions. Try again in about \(seconds) seconds." }
            else { "Doddy is getting a lot of questions. Try again in a little while." }
        case .dailyLimitReached:
            "Doddy's daily limit is reached. Try again tomorrow. Your notes still work."
        case .providerUnavailable:
            "The assistant is unavailable right now. Try again in a moment."
        case .refused:
            "Doddy can't help with that one."
        case .invalidRequest:
            "That question can't be sent as written. Shorten it and try again."
        case .invalidCitations:
            "The answer couldn't be checked against your notes, so Doddy discarded it. Try again."
        case .malformedResponse:
            "Doddy got an answer it couldn't read, so it was discarded. Try again."
        case .unsafeToolRequest:
            "Doddy won't do that here."
        case .cancelled:
            "Cancelled."
        }
    }

    /// Maps Doddy's server error code (`backend/src/errors.ts`, ADR-587). Unknown codes become `providerUnavailable`.
    init(backendCode: String, retryAfterSeconds: Int?) {
        switch backendCode {
        case "unauthenticated": self = .notAuthorized
        case "rate_limited": self = .rateLimited(retryAfterSeconds: retryAfterSeconds)
        case "quota_exceeded": self = .dailyLimitReached
        case "provider_timeout": self = .timeout
        case "invalid_request", "payload_too_large": self = .invalidRequest
        case "refused": self = .refused
        case "malformed_provider_result": self = .malformedResponse
        case "live_not_configured": self = .notConfigured
        default: self = .providerUnavailable
        }
    }

    /// Maps the old gateway's wire code (`gateway/src/errors.js`). Unknown codes become `providerUnavailable`.
    init(wireCode: String, retryAfterSeconds: Int?) {
        switch wireCode {
        case "notAuthorized": self = .notAuthorized
        case "rateLimited": self = .rateLimited(retryAfterSeconds: retryAfterSeconds)
        case "dailyLimitReached": self = .dailyLimitReached
        case "timeout": self = .timeout
        case "invalidRequest", "payloadTooLarge": self = .invalidRequest
        case "invalidCitations": self = .invalidCitations
        case "refused": self = .refused
        case "notConfigured": self = .notConfigured
        default: self = .providerUnavailable
        }
    }
}
