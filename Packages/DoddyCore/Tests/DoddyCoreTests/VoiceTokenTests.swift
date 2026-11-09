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

    // MARK: Waits in words and the sign-in throttle (ADR-712)

    private var warsaw: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    /// 4 Nov 2026 (plus `day`) at `hour:minute` in Warsaw.
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 4) -> Date {
        warsaw.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testAWaitReadsInMinutesThenHours() {
        let noon = at(12)
        func phrase(_ seconds: Int?) -> String { VoiceTokenServer.waitPhrase(seconds: seconds, now: noon, calendar: warsaw) }
        XCTAssertEqual(phrase(nil), "later")
        XCTAssertEqual(phrase(0), "later")
        XCTAssertEqual(phrase(-5), "later")
        XCTAssertEqual(phrase(1), "in a minute or two")
        XCTAssertEqual(phrase(90), "in a minute or two")
        XCTAssertEqual(phrase(91), "in about 2 minutes")
        XCTAssertEqual(phrase(1_800), "in about 30 minutes")
        XCTAssertEqual(phrase(3_600), "in about 60 minutes")
        XCTAssertEqual(phrase(5_400), "in about 90 minutes")
        XCTAssertEqual(phrase(5_401), "in about 2 hours")
        XCTAssertEqual(phrase(7_200), "in about 2 hours")
        XCTAssertEqual(phrase(7_201), "in about 3 hours")
        XCTAssertEqual(phrase(39_600), "in about 11 hours", "from noon, 11 hours is 23:00 the same day")
    }

    func testSeveralHoursPastMidnightReadTomorrow() {
        func phrase(_ seconds: Int, from now: Date) -> String { VoiceTokenServer.waitPhrase(seconds: seconds, now: now, calendar: warsaw) }
        // The server's daily window ends at midnight UTC, which is 01:00 in Warsaw in November.
        XCTAssertEqual(phrase(39_600, from: at(15)), "tomorrow", "660 minutes from 15:00 is 02:00 the next day")
        XCTAssertEqual(phrase(36_000, from: at(15)), "tomorrow")
        XCTAssertEqual(phrase(39_600, from: at(1)), "in about 11 hours", "the same wait from 01:00 ends at noon, the same day")
        // Under six hours it still says how many hours, even across midnight.
        XCTAssertEqual(phrase(3 * 3_600, from: at(23, 30)), "in about 3 hours")
        XCTAssertEqual(phrase(5 * 3_600, from: at(20)), "in about 5 hours")
        XCTAssertEqual(phrase(6 * 3_600, from: at(20)), "tomorrow")
        // A wait that is a day or more says so.
        XCTAssertEqual(phrase(35 * 3_600, from: at(12)), "tomorrow", "noon plus 35 hours is 23:00 tomorrow")
        XCTAssertEqual(phrase(36 * 3_600, from: at(12)), "in about 2 days")
        XCTAssertEqual(phrase(49 * 3_600, from: at(12)), "in about 3 days")
    }

    func testADailyCapNeverSaysSixHundredMinutes() {
        let text = VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: 39_600), now: at(15), calendar: warsaw)
        XCTAssertEqual(text, "You've started a lot of conversations. Try again tomorrow; your notes still work.")
        XCTAssertFalse(text.contains("660"))
        XCTAssertFalse(text.contains("minutes"))
        let hours = VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: 10_000), now: at(8), calendar: warsaw)
        XCTAssertEqual(hours, "You've started a lot of conversations. Try again in about 3 hours; your notes still work.")
    }

    func testTheShortWaitsKeepTheirOldWords() {
        XCTAssertEqual(VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: nil)),
                       "You've started a lot of conversations. Try again later; your notes still work.")
        XCTAssertEqual(VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: 60)),
                       "You've started a lot of conversations. Try again in a minute or two; your notes still work.")
        XCTAssertEqual(VoiceTokenServer.message(for: .rateLimited(retryAfterSeconds: 1_800)),
                       "You've started a lot of conversations. Try again in about 30 minutes; your notes still work.")
    }

    func testTheRetryAfterHeaderIsReadAsPositiveSeconds() {
        XCTAssertEqual(VoiceTokenServer.retryAfterSeconds("1800"), 1_800)
        XCTAssertEqual(VoiceTokenServer.retryAfterSeconds(" 120 "), 120)
        for bad in [nil, "", "0", "-3", "soon", "1.5", "Wed, 21 Oct 2026 07:28:00 GMT"] {
            XCTAssertNil(VoiceTokenServer.retryAfterSeconds(bad), bad ?? "nil")
        }
        // The token reply reads it for a 429.
        let body = Data(#"{"error":"rate_limited"}"#.utf8)
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: body, retryAfter: "39600"), .failure(.rateLimited(retryAfterSeconds: 39_600)))
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: body, retryAfter: "1800"), .failure(.rateLimited(retryAfterSeconds: 1_800)))
        XCTAssertEqual(VoiceTokenServer.token(status: 429, body: body), .failure(.rateLimited(retryAfterSeconds: nil)))
    }

    func testAThrottledSignInIsNotAVerificationFailure() {
        XCTAssertEqual(VoiceAuthStatus.failure(status: 429, action: "sign-in", retryAfter: "2400"), .tooManySignIns(retryAfterSeconds: 2_400))
        XCTAssertEqual(VoiceAuthStatus.failure(status: 429, action: "sign-in", retryAfter: nil), .tooManySignIns(retryAfterSeconds: nil))
        XCTAssertEqual(VoiceAuthStatus.failure(status: 429, action: "sign-in", retryAfter: "soon"), .tooManySignIns(retryAfterSeconds: nil))
        // The throttle is for sign-ins only; any other 429 is an ordinary refusal.
        for action in ["refresh", "sign-out", "delete-account"] {
            XCTAssertEqual(VoiceAuthStatus.failure(status: 429, action: action, retryAfter: "60"), .rejected, action)
        }
        // The rest is as the app has always read it.
        XCTAssertEqual(VoiceAuthStatus.failure(status: 401, action: "sign-in", retryAfter: nil), .sessionExpired)
        for status in [404, 500, 503] {
            XCTAssertEqual(VoiceAuthStatus.failure(status: status, action: "refresh", retryAfter: nil), .serverNotConfigured, "\(status)")
        }
        for status in [400, 403, 409, 502] {
            XCTAssertEqual(VoiceAuthStatus.failure(status: status, action: "sign-in", retryAfter: nil), .rejected, "\(status)")
        }
    }

    func testTheThrottledSignInSaysSoPlainly() {
        XCTAssertEqual(VoiceTokenServer.signInThrottledMessage(retryAfterSeconds: nil), "Too many sign-ins from this network. Try again later.")
        XCTAssertEqual(VoiceTokenServer.signInThrottledMessage(retryAfterSeconds: 2_400, now: at(12), calendar: warsaw),
                       "Too many sign-ins from this network. Try again in about 40 minutes.")
        XCTAssertEqual(VoiceTokenServer.signInThrottledMessage(retryAfterSeconds: 39_600, now: at(15), calendar: warsaw),
                       "Too many sign-ins from this network. Try again tomorrow.")
        for seconds in [nil, 60, 2_400, 39_600] {
            let text = VoiceTokenServer.signInThrottledMessage(retryAfterSeconds: seconds, now: at(15), calendar: warsaw)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("verif"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("Apple"), "it isn't Apple's doing: \(text)")
        }
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
