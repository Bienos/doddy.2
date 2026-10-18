import XCTest
@testable import DoddyCore

final class VoiceTokenTests: XCTestCase {
    func testVoiceServerMustBeConfiguredOverHTTPSAndNeverFallsBackToPublicAgent() {
        XCTAssertEqual(
            VoiceConnectionMode.resolve(serverAddress: "https://doddy.example/api/voice-token"),
            .tokenServer(endpoint: URL(string: "https://doddy.example/api/voice-token")!))
        for address in ["", " ", "http://doddy.example", "https://user:pass@doddy.example/api/voice-token"] {
            guard case .notSetUp = VoiceConnectionMode.resolve(serverAddress: address) else {
                return XCTFail("invalid endpoint must fail closed: \(address)")
            }
        }
    }

    func testTokenReplies() {
        XCTAssertEqual(VoiceTokenServer.token(status: 200, body: Data(#"{"token":"jwt"}"#.utf8)), .success("jwt"))
        XCTAssertEqual(VoiceTokenServer.token(status: 200, body: Data(#"{"token":""}"#.utf8)), .failure(.badResponse))
        XCTAssertEqual(VoiceTokenServer.token(status: 401, body: Data()), .failure(.sessionExpired))
        XCTAssertEqual(VoiceTokenServer.token(status: 503, body: Data()), .failure(.busy))
        XCTAssertEqual(VoiceTokenServer.token(status: 503, body: Data(#"{"error":"server_not_configured"}"#.utf8)), .failure(.serverNotConfigured))
        XCTAssertEqual(VoiceTokenServer.token(status: 503, body: Data(#"{"error":"voice_busy"}"#.utf8)), .failure(.busy))
        XCTAssertEqual(VoiceTokenServer.token(status: 404, body: Data()), .failure(.serverNotConfigured))
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
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 401, body: Data()), .failure(.sessionExpired))
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 500, body: Data()), .failure(.busy))
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 500, body: Data(#"{"error":"server_not_configured"}"#.utf8)), .failure(.serverNotConfigured))
        XCTAssertEqual(VoiceTokenServer.wakeWordKey(status: 400, body: Data()), .failure(.serverProblem(status: 400)), "a server from before ADR-328")
    }

    func testRateLimitSaysHowLongToWaitInsteadOfTryAgainInAMoment() {
        let body = Data(#"{"error":"rate_limited"}"#.utf8)
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: body, retryAfter: "1800"), .failure(.rateLimited(retryAfterSeconds: 1800)))
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: body), .failure(.rateLimited(retryAfterSeconds: nil)))
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: body, retryAfter: "soon"), .failure(.rateLimited(retryAfterSeconds: nil)))
        let wait = VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: 1800))
        XCTAssertTrue(wait.contains("about 30 minutes"), wait)
        XCTAssertFalse(wait.contains("in a moment"))
        XCTAssertFalse(VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: nil)).contains("in a moment"))
    }
}
