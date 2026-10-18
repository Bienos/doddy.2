import DoddyCore
import Foundation

/// Non-secret voice service configuration. The URL is a public endpoint, not a credential.
enum VoiceConfig {
    /// Existing owner-controlled deployment. Provider credentials remain on that server.
    static let tokenEndpointAddress = "https://doddy-voice-token.vercel.app/api/voice-token"

    static var tokenEndpoint: URL? { VoiceTokenServer.endpoint(from: tokenEndpointAddress) }

    static var authEndpoint: URL? {
        guard let tokenEndpoint else { return nil }
        var components = URLComponents(url: tokenEndpoint, resolvingAgainstBaseURL: false)
        components?.path = "/api/voice-auth"
        return components?.url
    }
}
