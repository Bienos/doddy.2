import DoddyCore
import Foundation

/// Non-secret voice service configuration. The URL is a public endpoint, not a credential.
enum VoiceConfig {
    /// The production domain of the owner's Vercel project `doddy-voice-token` (team `doddyyyy`).
    /// Provider credentials remain on that server. The older `doddy-voice-token.vercel.app`
    /// belonged to a previous team's project and now answers 402 DEPLOYMENT_DISABLED.
    static let tokenEndpointAddress = "https://doddy-voice-token-beta.vercel.app/api/voice-token"

    static var tokenEndpoint: URL? { VoiceTokenServer.endpoint(from: tokenEndpointAddress) }

    // MARK: Developer connection (ADR-551)

    /// Settings key of the Debug-only switch "Talk without Apple sign-in".
    static let directVoiceKey = "developer.directVoice"

    #if DEBUG
    /// The live ElevenLabs agent's id (public: it is in the repo's docs, and the agent has no
    /// authentication). A Debug build may connect to it directly, so voice can be tried with a free
    /// Apple ID, which can't have Sign in with Apple. On by default in Debug; Release and TestFlight
    /// builds compile this to `false` and always need a DODDY voice account.
    static let directAgentID = "agent_0501m4et27vyeawrwqfdxxfszfa6"
    static var directVoiceEnabled: Bool { UserDefaults.standard.object(forKey: directVoiceKey) as? Bool ?? true }
    #else
    static let directAgentID = ""
    static var directVoiceEnabled: Bool { false }
    #endif

    /// The voice the next conversation uses (ElevenLabs unless the user picked OpenAI, ADR-546).
    static var chosenProvider: VoiceProvider {
        VoiceProvider.effective(stored: UserDefaults.standard.string(forKey: VoiceProvider.preferenceKey), tokenServerSet: true)
    }

    /// The Debug developer connection (ADR-551) reaches only the ElevenLabs agent. OpenAI's key stays on
    /// the token server, so OpenAI always goes through it, with a Doddy voice account (ADR-633).
    static func usesDirectAgent(for provider: VoiceProvider) -> Bool {
        directVoiceEnabled && provider == .elevenLabs
    }

    /// How a conversation with `provider` reaches the voice service: the Debug developer connection for
    /// ElevenLabs when it is on (ADR-551), otherwise the token server.
    static func connectionMode(for provider: VoiceProvider) -> VoiceConnectionMode {
        if usesDirectAgent(for: provider) { return .directAgent(agentID: directAgentID) }
        return VoiceConnectionMode.resolve(serverAddress: tokenEndpointAddress)
    }

    /// The connection for the chosen voice. The voice screen, Home and Talk in the Island (ADR-577)
    /// all start with it. It used to ignore the voice, so in a Debug build OpenAI got the developer
    /// connection and failed with "Voice isn't set up yet" before any network call (ADR-633).
    static var connectionMode: VoiceConnectionMode { connectionMode(for: chosenProvider) }

    static var authEndpoint: URL? {
        guard let tokenEndpoint else { return nil }
        var components = URLComponents(url: tokenEndpoint, resolvingAgainstBaseURL: false)
        components?.path = "/api/voice-auth"
        return components?.url
    }
}
