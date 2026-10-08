import Foundation

/// Failure taxonomy from docs/architecture/AI_RUNTIME.md. Every case leaves local memory
/// and unsent drafts untouched; callers decide what to tell the user.
public enum AssistantError: Error, Equatable, Sendable {
    case notAuthorized
    case offline
    case timeout
    case rateLimited
    case providerUnavailable
    /// The reply cited a memory that was not part of the request. The text must not be shown as grounded.
    case invalidCitations
    case cancelled
    /// The request was rejected before or by the gateway (empty, too long, too many memories).
    case invalidRequest
    /// The gateway answered 200 but the body was not the documented shape.
    case malformedResponse

    /// Gateway error codes (gateway/README.md).
    init?(gatewayCode: String) {
        switch gatewayCode {
        case "notAuthorized": self = .notAuthorized
        case "rateLimited": self = .rateLimited
        case "invalidRequest": self = .invalidRequest
        case "timeout": self = .timeout
        case "providerUnavailable": self = .providerUnavailable
        case "invalidCitations": self = .invalidCitations
        default: return nil
        }
    }
}
