import DoddyCore
import Foundation

/// Non-secret voice service configuration. The URL is a public endpoint, not a credential.
enum VoiceConfig {
    /// The production domain of the owner's Vercel project `doddy-voice-token` (team `doddyyyy`).
    /// Provider credentials remain on that server. The older `doddy-voice-token.vercel.app`
    /// belonged to a previous team's project and now answers 402 DEPLOYMENT_DISABLED.
    static let tokenEndpointAddress = "https://doddy-voice-token-beta.vercel.app/api/voice-token"

    static var tokenEndpoint: URL? { VoiceTokenServer.endpoint(from: tokenEndpointAddress) }

    static var authEndpoint: URL? {
        guard let tokenEndpoint else { return nil }
        var components = URLComponents(url: tokenEndpoint, resolvingAgainstBaseURL: false)
        components?.path = "/api/voice-auth"
        return components?.url
    }
}
