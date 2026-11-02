import XCTest
@testable import DoddyCore

final class VoiceTokenTests: XCTestCase {
    func testResolveNeverReturnsTheDevelopmentDirectConnection() {
        // ADR-551: the direct agent connection is built only by Debug app code, never by `resolve`.
        for address in ["", "https://doddy.example/api/voice-token", "http://x", "agent_0501m4et27vyeawrwqfdxxfszfa6"] {
            if case .directAgent = VoiceConnectionMode.resolve(serverAddress: address) { XCTFail(address) }
        }
    }

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

    /// ADR-687: the daily limits say which one was reached, so the screen can point to the smaller
    /// OpenAI voice instead of "try again in about 700 minutes".
    func testADailyLimitIsToldApartFromTheHourlyOne() {
        let full = Data(#"{"error":"daily_limit","limit":"full_model"}"#.utf8)
        let any = Data(#"{"error":"daily_limit","limit":"voice"}"#.utf8)
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: full, retryAfter: "40000"), .failure(.dailyLimit(fullModelOnly: true)))
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: any, retryAfter: "40000"), .failure(.dailyLimit(fullModelOnly: false)))
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 429, body: full), .failure(.dailyLimit(fullModelOnly: true)))
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: Data(#"{"error":"rate_limited"}"#.utf8), retryAfter: "60"), .failure(.rateLimited(retryAfterSeconds: 60)))
        XCTAssertTrue(VoiceTokenServer.message(for: .dailyLimit(fullModelOnly: true)).contains("smaller one"))
        XCTAssertTrue(VoiceTokenServer.message(for: .dailyLimit(fullModelOnly: false)).contains("tomorrow"))
        XCTAssertFalse(Offline.isNoConnection(VoiceTokenError.dailyLimit(fullModelOnly: true)))
    }
}
