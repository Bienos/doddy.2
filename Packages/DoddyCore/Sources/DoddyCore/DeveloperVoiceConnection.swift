import Foundation

/// The Debug builds' developer connection (ADR-551) reaches the ElevenLabs agent by its public id,
/// with no token. Once the agent's authentication is on, ElevenLabs refuses that, and the SDK says
/// "Authentication failed - agent may be private. For private agents, use a conversation token from
/// your backend…". On 8 Nov 2026 the main agent's authentication was turned on and a Debug build
/// showed exactly that English text on a Polish screen. These rules say what the app does instead.
public enum DeveloperVoiceConnection {
    /// What a start does after the agent refused the developer connection.
    public enum AfterRefusal: Equatable, Sendable {
        /// Carry on with the same start through the token server, as Release builds do.
        case retry(VoiceConnectionMode)
        /// No voice session on this iPhone: stop and ask the person to sign in. The voice sheet shows
        /// its sign-in step the next time, because the developer switch is off by then.
        case signInNeeded
        /// The token server isn't set up either: stop with its own reason.
        case notSetUp(reason: String)
    }

    /// True when a failed start's description is ElevenLabs refusing the public agent id (a 401 from
    /// its public token endpoint). The SDK is pinned (`project.yml`, elevenlabs-swift-sdk 3.3.1) and
    /// its words for that 401 are matched here (`TokenError.authenticationFailed`). Any other failure,
    /// a server error or a lost connection, is not a refusal and keeps its own message.
    public static func isRefusal(_ description: String) -> Bool {
        let text = description.lowercased()
        return text.contains("agent may be private") || text.contains("for private agents")
    }

    /// `tokenServer` is the connection the app would use without the developer switch;
    /// `signedIn` is whether this iPhone has a voice session for it.
    public static func afterRefusal(tokenServer: VoiceConnectionMode, signedIn: Bool) -> AfterRefusal {
        switch tokenServer {
        case .tokenServer:
            return signedIn ? .retry(tokenServer) : .signInNeeded
        case .notSetUp(let reason):
            return .notSetUp(reason: reason)
        case .directAgent:
            // Never retry the connection that was just refused.
            return .signInNeeded
        }
    }
}
