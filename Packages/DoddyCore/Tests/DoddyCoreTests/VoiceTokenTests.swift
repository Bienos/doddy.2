import XCTest
@testable import DoddyCore

final class VoiceTokenTests: XCTestCase {
    func testServerAddressWinsAndMustBeHTTPSWithACode() {
        XCTAssertEqual(VoiceConnectionMode.resolve(serverAddress: " ", accessCode: nil, publicAgentID: "agent_1"), .publicAgent(agentID: "agent_1"))
        XCTAssertEqual(
            VoiceConnectionMode.resolve(serverAddress: "https://doddy.example/api/voice-token", accessCode: " code ", publicAgentID: "agent_1"),
            .tokenServer(endpoint: URL(string: "https://doddy.example/api/voice-token")!, accessCode: "code"))
        guard case .notSetUp = VoiceConnectionMode.resolve(serverAddress: "http://doddy.example", accessCode: "code", publicAgentID: "agent_1") else {
            return XCTFail("plain http must be refused, not fall back to the public agent")
        }
        guard case .notSetUp = VoiceConnectionMode.resolve(serverAddress: "https://doddy.example", accessCode: "", publicAgentID: "agent_1") else {
            return XCTFail("a server without an access code must not fall back to the public agent")
        }
    }

    func testTokenReplies() {
        XCTAssertEqual(VoiceTokenServer.token(status: 200, body: Data(#"{"token":"jwt"}"#.utf8)), .success("jwt"))
        XCTAssertEqual(VoiceTokenServer.token(status: 200, body: Data(#"{"token":""}"#.utf8)), .failure(.badResponse))
        XCTAssertEqual(VoiceTokenServer.token(status: 401, body: Data()), .failure(.accessCodeRejected))
        XCTAssertEqual(VoiceTokenServer.token(status: 503, body: Data()), .failure(.busy))
        XCTAssertEqual(VoiceTokenServer.token(status: 504, body: Data()), .failure(.serverProblem(status: 504)))
    }
}
