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

    /// ADR-328: the owner's Picovoice key from the token server.
    func testWakeWordKeyFromTheTokenServer() {
        let key = "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789+/=="
        XCTAssertEqual(String(data: VoiceTokenServer.wakeWordKeyRequestBody, encoding: .utf8), #"{"provider":"picovoice"}"#)
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 200, body: Data(#"{"accessKey":"  \#(key) "}"#.utf8)), .success(key))
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 200, body: Data(#"{"accessKey":"short"}"#.utf8)), .failure(.badResponse))
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 200, body: Data(#"{"token":"jwt"}"#.utf8)), .failure(.badResponse),
                       "an ElevenLabs token is never taken for a key")
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 401, body: Data()), .failure(.accessCodeRejected))
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 500, body: Data()), .failure(.serverNotConfigured))
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 400, body: Data()), .failure(.serverProblem(status: 400)), "a server from before ADR-328")
    }
}
