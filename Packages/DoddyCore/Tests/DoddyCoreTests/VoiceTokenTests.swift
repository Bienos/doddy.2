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

    // MARK: Loading errors (ADR-681)

    func testOnlyAMissingOrLostConnectionIsOffline() {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                     .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff] {
            XCTAssertEqual(VoiceTokenServer.loadingFailure(URLError(code)), .offline, "\(code)")
        }
    }

    func testACancelledStartIsNotOffline() {
        // Closing the voice sheet while it connected cancelled the start, which said "You're offline".
        XCTAssertEqual(VoiceTokenServer.loadingFailure(URLError(.cancelled)), .cancelled)
        XCTAssertEqual(VoiceTokenServer.loadingFailure(CancellationError()), .cancelled)
        XCTAssertFalse(Offline.isNoConnection(VoiceTokenError.cancelled))
    }

    func testATimeoutAndARefusedSecureConnectionAreNotOffline() {
        XCTAssertEqual(VoiceTokenServer.loadingFailure(URLError(.timedOut)), .timedOut)
        for code in [URLError.Code.secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
                     .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
                     .clientCertificateRejected, .clientCertificateRequired] {
            XCTAssertEqual(VoiceTokenServer.loadingFailure(URLError(code)), .secureConnectionFailed, "\(code)")
        }
        XCTAssertFalse(Offline.isNoConnection(VoiceTokenError.timedOut))
        XCTAssertFalse(Offline.isNoConnection(VoiceTokenError.secureConnectionFailed))
    }

    func testAnUnnamedLoadingErrorStaysOfflineAsBefore() {
        XCTAssertEqual(VoiceTokenServer.loadingFailure(URLError(.unknown)), .offline)
        XCTAssertEqual(VoiceTokenServer.loadingFailure(NSError(domain: "x", code: 1)), .offline)
    }

    func testTheNewFailuresNeverSayOffline() {
        for error in [VoiceTokenError.cancelled, .timedOut, .secureConnectionFailed] {
            let text = VoiceTokenServer.message(for: error)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("offline"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("internet connection"), text)
            XCTAssertNotEqual(text, VoiceTokenServer.message(for: .offline))
        }
    }
}
