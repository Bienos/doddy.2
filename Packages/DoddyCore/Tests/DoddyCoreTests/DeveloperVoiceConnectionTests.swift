import XCTest
@testable import DoddyCore

final class DeveloperVoiceConnectionTests: XCTestCase {
    /// The words a Debug build showed on 8 Nov 2026, once the agent's authentication was on: the SDK's
    /// `ConversationError.authenticationFailed` wrapping its `TokenError.authenticationFailed` (3.3.1).
    let refusal = "Authentication failed: Authentication failed - agent may be private. For private agents, use a conversation token from your backend instead of connecting directly."

    func testTheAgentsRefusalIsRecognised() {
        XCTAssertTrue(DeveloperVoiceConnection.isRefusal(refusal))
        XCTAssertTrue(DeveloperVoiceConnection.isRefusal("Authentication failed - agent may be private."))
    }

    func testOtherFailedStartsAreNotARefusal() {
        // A server error, a bad reply or a lost connection keeps its own message and the switch stays on.
        for other in [
            "Authentication failed: HTTP error: 500",
            "Authentication failed: Invalid response from server",
            "Connection failed: The Internet connection appears to be offline.",
            "Agent did not join in time.",
            "",
        ] {
            XCTAssertFalse(DeveloperVoiceConnection.isRefusal(other), other)
        }
    }

    func testSignedInCarriesOnThroughTheTokenServer() {
        let server = VoiceConnectionMode.tokenServer(endpoint: URL(string: "https://doddy.example/api/voice-token")!)
        XCTAssertEqual(DeveloperVoiceConnection.afterRefusal(tokenServer: server, signedIn: true), .retry(server))
    }

    func testNoVoiceSessionAsksToSignInInsteadOfTheSDKsText() {
        let server = VoiceConnectionMode.tokenServer(endpoint: URL(string: "https://doddy.example/api/voice-token")!)
        XCTAssertEqual(DeveloperVoiceConnection.afterRefusal(tokenServer: server, signedIn: false), .signInNeeded)
    }

    func testTheRefusedConnectionIsNeverTriedAgain() {
        let direct = VoiceConnectionMode.directAgent(agentID: "agent_x")
        XCTAssertEqual(DeveloperVoiceConnection.afterRefusal(tokenServer: direct, signedIn: true), .signInNeeded)
    }

    func testATokenServerThatIsNotSetUpSaysSo() {
        let notSetUp = VoiceConnectionMode.resolve(serverAddress: "")
        guard case .notSetUp(let reason) = notSetUp else { return XCTFail("expected notSetUp") }
        XCTAssertEqual(DeveloperVoiceConnection.afterRefusal(tokenServer: notSetUp, signedIn: true), .notSetUp(reason: reason))
    }
}
