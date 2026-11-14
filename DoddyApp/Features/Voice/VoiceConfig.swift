import DoddyCore
import Foundation

/// Non-secret voice service configuration. The URL is a public endpoint, not a credential.
enum VoiceConfig {
    /// The production domain of the owner's Vercel project `doddy-voice-token` (team `doddyyyy`).
    /// Provider credentials remain on that server. The older `doddy-voice-token.vercel.app`
    /// belonged to a previous team's project and now answers 402 DEPLOYMENT_DISABLED.
    static let tokenEndpointAddress = "https://doddy-voice-token-beta.vercel.app/api/voice-token"

    /// The media host used by the pinned ElevenLabs SDK 3.3.1's ConnectionConstants.
    /// Only its public network route is warmed: no token, room join, microphone or conversation.
    static let mediaEndpointAddress = "wss://livekit.rtc.elevenlabs.io"

    static var tokenEndpoint: URL? { VoiceTokenServer.endpoint(from: tokenEndpointAddress) }

    // MARK: Developer connection (ADR-551)

    /// Settings key of the Debug-only switch "Talk without Apple sign-in".
    static let directVoiceKey = "developer.directVoice"

    #if DEBUG
    /// The live ElevenLabs agent's id (public: it is in the repo's docs). A Debug build may connect to
    /// it directly, so voice can be tried with a free Apple ID, which can't have Sign in with Apple.
    /// That works only while the agent's authentication is off; it was turned on on 8 Nov 2026, and
    /// since then ElevenLabs refuses this connection (`directAgentRefused`). On by default in Debug;
    /// Release and TestFlight builds compile this to `false` and always need a DODDY voice account.
    static let directAgentID = "agent_0501m4et27vyeawrwqfdxxfszfa6"
    /// The translator-only agent's id (decision 2026-11-12-translator-agent), for the same Debug connection.
    static let translatorDirectAgentID = "agent_8901m787fgppedy9kkvg7memny34"
    static var directVoiceEnabled: Bool { UserDefaults.standard.object(forKey: directVoiceKey) as? Bool ?? true }

    /// The agent refused the developer connection (its authentication is on): the Debug switch
    /// "Developer: talk without Apple sign-in" goes off, so every later conversation goes through the
    /// token server like a Release build, and the voice sheet asks for sign-in when there is no voice
    /// session. Turning the switch on again in Settings tries the developer connection once more.
    static func directAgentRefused() { UserDefaults.standard.set(false, forKey: directVoiceKey) }
    #else
    static let directAgentID = ""
    static let translatorDirectAgentID = ""
    static var directVoiceEnabled: Bool { false }
    static func directAgentRefused() {}
    #endif

    /// True when a conversation can start with no Doddy voice account: the ElevenLabs developer
    /// connection (ADR-551), Debug builds only.
    static var talksWithoutAccount: Bool { usesDirectAgent }

    /// The Debug developer connection (ADR-551) reaches the ElevenLabs agent directly. Every other
    /// conversation goes through the token server, with a Doddy voice account.
    static var usesDirectAgent: Bool { directVoiceEnabled }

    /// How a conversation reaches ElevenLabs: the Debug developer connection when it is on (ADR-551),
    /// otherwise the token server. The voice screen, Home and Talk in the Island (ADR-577) all start with it.
    static var connectionMode: VoiceConnectionMode {
        if usesDirectAgent { return .directAgent(agentID: directAgentID) }
        return VoiceConnectionMode.resolve(serverAddress: tokenEndpointAddress)
    }

    static var authEndpoint: URL? {
        guard let tokenEndpoint else { return nil }
        var components = URLComponents(url: tokenEndpoint, resolvingAgainstBaseURL: false)
        components?.path = "/api/voice-auth"
        return components?.url
    }
}
