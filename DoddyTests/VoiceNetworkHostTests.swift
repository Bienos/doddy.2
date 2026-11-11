import ElevenLabs
import XCTest
@testable import Doddy

final class VoiceNetworkHostTests: XCTestCase {
    /// A provided token is parsed locally by this SDK API: no HTTP request, room, microphone or
    /// provider session. The assertion catches an SDK update changing the host we prepare.
    @MainActor
    func testPreparationHostMatchesThePinnedSDKsVoiceHost() async throws {
        let details = try await TokenService().fetchConnectionDetails(configuration: .conversationToken("unit-test-token"))
        XCTAssertEqual(VoiceConfig.mediaEndpointAddress, details.serverUrl)
    }
}
