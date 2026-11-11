import Foundation

/// The same permission boundary for preparing a token and the provider's public network route.
/// Preparation opens no conversation, records nothing and carries no personal context.
public struct VoicePreparationConditions: Equatable, Sendable {
    public var foreground: Bool
    public var hasVoiceAccess: Bool
    public var hasSignedInOwner: Bool
    public var consentGranted: Bool
    public var microphoneAllowed: Bool
    public var paused: Bool
    public var conversationRunning: Bool
    public var configured: Bool

    public init(foreground: Bool, hasVoiceAccess: Bool, hasSignedInOwner: Bool, consentGranted: Bool,
                microphoneAllowed: Bool, paused: Bool, conversationRunning: Bool, configured: Bool) {
        self.foreground = foreground
        self.hasVoiceAccess = hasVoiceAccess
        self.hasSignedInOwner = hasSignedInOwner
        self.consentGranted = consentGranted
        self.microphoneAllowed = microphoneAllowed
        self.paused = paused
        self.conversationRunning = conversationRunning
        self.configured = configured
    }

    public var mayPrepare: Bool {
        foreground && hasVoiceAccess && hasSignedInOwner && consentGranted && microphoneAllowed
            && !paused && !conversationRunning && configured
    }
}

/// Bounds network preparation independently of the token shelf. A token can still be on the
/// shelf when the app returns to the foreground and DNS/TLS preparation is useful again.
public struct VoiceNetworkPreparationPolicy: Sendable {
    public static let minimumInterval: TimeInterval = 2 * 60
    private var lastRequestedAt: TimeInterval?

    public init() {}

    /// A monotonic clock, not wall time. A failed/unused preparation still counts, so changing
    /// settings or switching between apps cannot flood the provider with background HEADs.
    public mutating func request(if conditions: VoicePreparationConditions, at uptime: TimeInterval) -> Bool {
        guard conditions.mayPrepare, uptime.isFinite, uptime >= 0 else { return false }
        if let lastRequestedAt, uptime - lastRequestedAt < Self.minimumInterval { return false }
        lastRequestedAt = uptime
        return true
    }
}

/// Content-free timings reported by the real provider SDK. Room includes microphone setup;
/// agent is the wait for its participant, and init is the start-data send. Neither is playback.
public struct VoiceTransportTiming: Sendable {
    public let room: TimeInterval?
    public let agent: TimeInterval?
    public let initialization: TimeInterval?
    public let total: TimeInterval?

    public init(room: TimeInterval?, agent: TimeInterval?, initialization: TimeInterval?, total: TimeInterval?) {
        self.room = room
        self.agent = agent
        self.initialization = initialization
        self.total = total
    }

    public var line: String {
        "room/microphone \(Self.text(room)) · agent \(Self.text(agent)) · init \(Self.text(initialization)) · total \(Self.text(total))"
    }

    private static func text(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite, duration >= 0 else { return "unavailable" }
        return VoiceStartTimeline.text(duration)
    }
}
