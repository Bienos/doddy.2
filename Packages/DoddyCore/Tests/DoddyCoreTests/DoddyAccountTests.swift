import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account (Apple, Google
/// or a code by email), and an iPhone's earlier data is brought into it once, never merged.

private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    var status: Int
    var body: Data
    var fails: Bool

    init(status: Int = 200, body: Data = Data("{}".utf8), fails: Bool = false) {
        self.status = status
        self.body = body
        self.fails = fails
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        if fails { throw URLError(.notConnectedToInternet) }
        return (status, body)
    }
}

private func json(_ data: Data?) -> [String: AnyHashable] {
    guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: AnyHashable] else { return [:] }
    return object
}

final class DoddyAccountTests: XCTestCase {
    private let config = DoddyAccountConfig(
        projectURL: URL(string: "https://abcdefghijklmnopqrst.supabase.co/some/path"),
        publishableKey: " sb_publishable_test ",
        redirectURL: URL(string: "doddy://auth-callback"))!
    private let now = Date(timeIntervalSince1970: 1_794_000_000)
    private let user = "5B0C8F7E-2A41-4C3D-9E6F-0123456789AB"

    private func sessionJSON(provider: String? = "email", expiresAt: Double? = 1_794_003_600, expiresIn: Double? = 3_600,
                             refresh: String = "refresh-1", id: String? = nil) -> Data {
        var user: [String: Any] = ["id": id ?? self.user, "email": "ana@example.com"]
        if let provider { user["app_metadata"] = ["provider": provider, "providers": [provider]] }
        var reply: [String: Any] = ["access_token": "access-1", "token_type": "bearer", "refresh_token": refresh, "user": user]
        if let expiresAt { reply["expires_at"] = expiresAt }
        if let expiresIn { reply["expires_in"] = expiresIn }
        return try! JSONSerialization.data(withJSONObject: reply)
    }

    // MARK: Rules

    func testTheConfigNeedsHTTPSAKeyAndAnAppRedirect() {
        XCTAssertEqual(config.projectURL.absoluteString, "https://abcdefghijklmnopqrst.supabase.co", "the origin only")
        XCTAssertEqual(config.publishableKey, "sb_publishable_test")
        let https = URL(string: "https://x.supabase.co"), back = URL(string: "doddy://auth-callback")
        XCTAssertNil(DoddyAccountConfig(projectURL: URL(string: "http://x.supabase.co"), publishableKey: "k", redirectURL: back))
        XCTAssertNil(DoddyAccountConfig(projectURL: https, publishableKey: "  ", redirectURL: back))
        XCTAssertNil(DoddyAccountConfig(projectURL: https, publishableKey: nil, redirectURL: back))
        XCTAssertNil(DoddyAccountConfig(projectURL: https, publishableKey: "k", redirectURL: URL(string: "https://doddy.lol/back")), "a web page is not the app")
        XCTAssertNil(DoddyAccountConfig(projectURL: nil, publishableKey: "k", redirectURL: back))
    }

    func testEmailAddressesAreTrimmedAndLowercasedAndJunkIsRefused() {
        XCTAssertEqual(EmailAddress.normalized("  Ana.Kowalska@Example.COM \n"), "ana.kowalska@example.com")
        XCTAssertEqual(EmailAddress.normalized("a+doddy@mail.example.pl"), "a+doddy@mail.example.pl")
        for junk in ["", "ana", "ana@", "@example.com", "ana@example", "ana@@example.com", "ana @example.com", "ana@.example.com", "ana@example.com.", "ana@exa..mple.com"] {
            XCTAssertNil(EmailAddress.normalized(junk), junk)
        }
        XCTAssertNil(EmailAddress.normalized(String(repeating: "a", count: 65) + "@example.com"), "local part too long")
    }

    func testCodesAreDigitsOnly() {
        XCTAssertEqual(EmailCode.normalized("123 456"), "123456")
        XCTAssertEqual(EmailCode.normalized(" 123-456 "), "123456")
        XCTAssertEqual(EmailCode.normalized("1234567890"), "1234567890")
        for junk in ["", "12345", "12345678901", "12a456", "١٢٣٤٥٦", "123 45x"] {
            XCTAssertNil(EmailCode.normalized(junk), junk)
        }
    }

    func testPKCEMatchesRFC7636() {
        // RFC 7636, appendix B.
        let bytes: [UInt8] = [116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173, 187, 186,
                              22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83, 132, 141, 121]
        let pair = PKCEPair.make(randomBytes: bytes)
        XCTAssertEqual(pair.verifier, "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pair.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let random = PKCEPair.random()
        XCTAssertEqual(random.verifier.count, 43)
        XCTAssertNotEqual(random, PKCEPair.random())
    }

    func testASessionIsFreshUntilAMinuteBeforeItRunsOut() {
        let session = DoddyAccountSession(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(120), userID: user, email: nil, method: .apple)
        XCTAssertTrue(session.isFresh(at: now))
        XCTAssertFalse(session.isFresh(at: now.addingTimeInterval(61)))
        XCTAssertEqual(session.authorization, "Bearer a")
    }

    // MARK: Email

    func testSendingACodeAsksSupabaseToMakeTheAccountIfNeeded() async throws {
        let transport = ScriptedTransport()
        try await DoddyAccountClient(config: config, transport: transport).sendEmailCode(to: " Ana@Example.com ")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.absoluteString, "https://abcdefghijklmnopqrst.supabase.co/auth/v1/otp")
        XCTAssertEqual(request.headers["apikey"], "sb_publishable_test")
        XCTAssertNil(request.headers["authorization"])
        // The exact bytes: Supabase reads `create_user` as a JSON boolean (Linux reads `true` back as 1, so no round trip).
        XCTAssertEqual(request.body.map { String(decoding: $0, as: UTF8.self) }, #"{"create_user":true,"email":"ana@example.com"}"#)
    }

    func testSendingACodeSaysWhatWentWrong() async {
        func failure(_ transport: ScriptedTransport, _ email: String = "ana@example.com") async -> DoddyAccountError? {
            do { try await DoddyAccountClient(config: config, transport: transport).sendEmailCode(to: email); return nil } catch { return error }
        }
        let refused = ScriptedTransport()
        let invalid = await failure(refused, "not an email")
        XCTAssertEqual(invalid, .invalidEmail)
        XCTAssertTrue(refused.requests.isEmpty, "nothing is sent for a bad address")
        let rateLimited = await failure(ScriptedTransport(status: 429))
        XCTAssertEqual(rateLimited, .rateLimited)
        let unavailable = await failure(ScriptedTransport(status: 500))
        XCTAssertEqual(unavailable, .unavailable)
        let offline = await failure(ScriptedTransport(fails: true))
        XCTAssertEqual(offline, .offline)
    }

    func testTheRightCodeGivesACheckedSession() async throws {
        let transport = ScriptedTransport(body: sessionJSON())
        let session = try await DoddyAccountClient(config: config, transport: transport)
            .verifyEmailCode(email: "Ana@example.com", code: "123 456", now: now)
        XCTAssertEqual(session, DoddyAccountSession(
            accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Date(timeIntervalSince1970: 1_794_003_600),
            userID: user.lowercased(), email: "ana@example.com", method: .email))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://abcdefghijklmnopqrst.supabase.co/auth/v1/verify")
        XCTAssertEqual(json(request.body), ["type": "email", "email": "ana@example.com", "token": "123456"])
    }

    func testAWrongOrExpiredCodeIsSaidPlainly() async {
        for status in [400, 401, 403, 422] {
            do {
                _ = try await DoddyAccountClient(config: config, transport: ScriptedTransport(status: status)).verifyEmailCode(email: "ana@example.com", code: "123456", now: now)
                XCTFail("\(status) passed")
            } catch {
                XCTAssertEqual(error, .invalidCode, "\(status)")
            }
        }
        let transport = ScriptedTransport()
        do {
            _ = try await DoddyAccountClient(config: config, transport: transport).verifyEmailCode(email: "ana@example.com", code: "12", now: now)
            XCTFail("a short code passed")
        } catch {
            XCTAssertEqual(error, .invalidCode)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    // MARK: Apple and Google

    func testAppleSendsTheIdentityTokenAndTheRawNonce() async throws {
        let transport = ScriptedTransport(body: sessionJSON(provider: "apple"))
        let session = try await DoddyAccountClient(config: config, transport: transport)
            .signInWithApple(identityToken: "apple.identity.token", rawNonce: "raw-nonce-1", now: now)
        XCTAssertEqual(session.method, .apple)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://abcdefghijklmnopqrst.supabase.co/auth/v1/token?grant_type=id_token")
        XCTAssertEqual(json(request.body), ["provider": "apple", "id_token": "apple.identity.token", "nonce": "raw-nonce-1"])
        do {
            _ = try await DoddyAccountClient(config: config, transport: ScriptedTransport(status: 400)).signInWithApple(identityToken: "t", rawNonce: "n", now: now)
            XCTFail("a refused Apple sign-in passed")
        } catch {
            XCTAssertEqual(error, .refused)
        }
    }

    func testGoogleOpensTheProjectWithPKCEAndExchangesOnlyItsOwnReturn() async throws {
        let client = DoddyAccountClient(config: config, transport: ScriptedTransport(body: sessionJSON(provider: "google")))
        let pkce = PKCEPair(verifier: "verifier-1", challenge: "challenge-1")
        let url = client.googleAuthorizeURL(pkce: pkce)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "abcdefghijklmnopqrst.supabase.co")
        XCTAssertEqual(url.path, "/auth/v1/authorize")
        XCTAssertEqual(items, ["provider": "google", "redirect_to": "doddy://auth-callback", "code_challenge": "challenge-1", "code_challenge_method": "s256"])

        XCTAssertEqual(client.googleCode(from: URL(string: "doddy://auth-callback?code=abc-123")!), "abc-123")
        for other in ["doddy-beta://auth-callback?code=abc", "doddy://other?code=abc", "doddy://auth-callback?error=access_denied&code=abc", "doddy://auth-callback", "doddy://auth-callback?code="] {
            XCTAssertNil(client.googleCode(from: URL(string: other)!), other)
        }

        let transport = ScriptedTransport(body: sessionJSON(provider: "google"))
        let session = try await DoddyAccountClient(config: config, transport: transport).exchangeGoogleCode("abc-123", pkce: pkce, now: now)
        XCTAssertEqual(session.method, .google)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://abcdefghijklmnopqrst.supabase.co/auth/v1/token?grant_type=pkce")
        XCTAssertEqual(json(request.body), ["auth_code": "abc-123", "code_verifier": "verifier-1"])
    }

    // MARK: Staying signed in

    func testRefreshKeepsTheMethodAndUsesExpiresInWhenThereIsNoExpiresAt() async throws {
        let old = DoddyAccountSession(accessToken: "a0", refreshToken: "r0", expiresAt: now, userID: user.lowercased(), email: nil, method: .apple)
        let transport = ScriptedTransport(body: sessionJSON(provider: nil, expiresAt: nil, expiresIn: 3_600, refresh: "r1"))
        let session = try await DoddyAccountClient(config: config, transport: transport).refresh(old, now: now)
        XCTAssertEqual(session.refreshToken, "r1")
        XCTAssertEqual(session.method, .apple)
        XCTAssertEqual(session.expiresAt, now.addingTimeInterval(3_600))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://abcdefghijklmnopqrst.supabase.co/auth/v1/token?grant_type=refresh_token")
        XCTAssertEqual(json(request.body), ["refresh_token": "r0"])
        do {
            _ = try await DoddyAccountClient(config: config, transport: ScriptedTransport(status: 400)).refresh(old, now: now)
            XCTFail("a dead refresh token passed")
        } catch {
            XCTAssertEqual(error, .signedOut)
        }
    }

    func testAReplyThatIsNotAGoodSessionIsNeverTakenForOne() async {
        let unreadable: [(String, Data, DoddyAccountError)] = [
            ("no refresh token", sessionJSON(refresh: ""), .unavailable),
            ("not a user id", sessionJSON(id: "apple-sub-1"), .unavailable),
            ("no expiry", sessionJSON(expiresAt: nil, expiresIn: nil), .unavailable),
            ("not JSON", Data("<html>".utf8), .unavailable),
            ("a phone account", sessionJSON(provider: "phone"), .refused),
        ]
        for (name, body, expected) in unreadable {
            do {
                _ = try await DoddyAccountClient(config: config, transport: ScriptedTransport(body: body)).verifyEmailCode(email: "ana@example.com", code: "123456", now: now)
                XCTFail("\(name) passed")
            } catch {
                XCTAssertEqual(error, expected, name)
            }
        }
    }

    func testSigningOutEndsThisSessionOnly() async throws {
        let transport = ScriptedTransport(status: 204)
        let session = DoddyAccountSession(accessToken: "a1", refreshToken: "r1", expiresAt: now, userID: user, email: nil, method: .email)
        await DoddyAccountClient(config: config, transport: transport).signOut(session)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://abcdefghijklmnopqrst.supabase.co/auth/v1/logout?scope=local")
        XCTAssertEqual(request.headers["authorization"], "Bearer a1")
        XCTAssertEqual(request.headers["apikey"], "sb_publishable_test")
        await DoddyAccountClient(config: config, transport: ScriptedTransport(fails: true)).signOut(session) // offline: no throw
    }

    // MARK: Bringing earlier data in

    private var account: DoddyAccountSession {
        DoddyAccountSession(accessToken: "acc", refreshToken: "r", expiresAt: now, userID: user.lowercased(), email: nil, method: .google)
    }
    private let backend = URL(string: "https://doddy.example.com")!
    private let messaging = URL(string: "https://messaging.example.com")!
    private let deviceToken43 = String(repeating: "A", count: 43)

    func testTheBackendLinkSendsBothSignInsAndReadsEachAnswer() async throws {
        let transport = ScriptedTransport(body: Data(#"{"linked":true}"#.utf8))
        let linked = await DoddyAccountLink.linkBackend(server: backend, account: account, deviceToken: "ds1.a.b", transport: transport)
        XCTAssertEqual(linked, .linked)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/account/link-device")
        XCTAssertEqual(request.headers["authorization"], "Bearer acc")
        XCTAssertEqual(json(request.body), ["deviceToken": "ds1.a.b"])

        let conflict = Data(#"{"error":{"code":"account_conflict","message":"Accounts are never merged."}}"#.utf8)
        let answers: [(Int, Data, DoddyAccountLink.Outcome)] = [
            (409, conflict, .conflict(message: "Accounts are never merged.")),
            (401, Data(#"{"error":{"code":"unauthenticated","message":"x"}}"#.utf8), .nothingToLink),
            (503, Data(#"{"error":{"code":"live_not_configured","message":"x"}}"#.utf8), .notSetUp),
            (500, Data(), .retryLater),
            (429, Data(#"{"error":{"code":"rate_limited","message":"x"}}"#.utf8), .retryLater),
        ]
        for (status, body, expected) in answers {
            let outcome = await DoddyAccountLink.linkBackend(server: backend, account: account, deviceToken: "ds1.a.b", transport: ScriptedTransport(status: status, body: body))
            XCTAssertEqual(outcome, expected, "\(status)")
        }
        let offline = await DoddyAccountLink.linkBackend(server: backend, account: account, deviceToken: "ds1.a.b", transport: ScriptedTransport(fails: true))
        XCTAssertEqual(offline, .retryLater)
        let none = ScriptedTransport()
        let notADeviceToken = await DoddyAccountLink.linkBackend(server: backend, account: account, deviceToken: "eyJ.not.ds1", transport: none)
        XCTAssertEqual(notADeviceToken, .nothingToLink)
        XCTAssertTrue(none.requests.isEmpty)
    }

    func testTheBackendProbeAsksWithTheAccountAndReadsYesNotYetOrLater() async throws {
        let yes = ScriptedTransport(status: 200, body: Data("{}".utf8))
        let use = await DoddyAccountLink.probeBackend(server: backend, account: account, transport: yes)
        XCTAssertEqual(use, .account)
        let request = try XCTUnwrap(yes.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://doddy.example.com/v1/connected-apps")
        XCTAssertEqual(request.headers["authorization"], "Bearer acc")
        let notYet = await DoddyAccountLink.probeBackend(server: backend, account: account, transport: ScriptedTransport(status: 401))
        XCTAssertEqual(notYet, .notYet)
        for status in [404, 500, 503] {
            let later = await DoddyAccountLink.probeBackend(server: backend, account: account, transport: ScriptedTransport(status: status))
            XCTAssertNil(later, "\(status)")
        }
        let offline = await DoddyAccountLink.probeBackend(server: backend, account: account, transport: ScriptedTransport(fails: true))
        XCTAssertNil(offline)
    }

    func testTheMessagingSignInSendsTheEarlierTokenOnlyWhenItIsOne() async throws {
        let reply = Data(#"{"accountId":"6C1D9A8F-3B52-4D4E-8F70-123456789ABC","deviceToken":"\#(deviceToken43)"}"#.utf8)
        let transport = ScriptedTransport(body: reply)
        let signedIn = await DoddyAccountLink.signInMessaging(server: messaging, account: account, earlierDeviceToken: deviceToken43, transport: transport)
        XCTAssertEqual(signedIn, .signedIn(accountID: "6c1d9a8f-3b52-4d4e-8f70-123456789abc", deviceToken: deviceToken43))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://messaging.example.com/v1/accounts/sign-in")
        XCTAssertEqual(request.headers["authorization"], "Bearer acc")
        XCTAssertEqual(json(request.body), ["deviceToken": deviceToken43])

        let noEarlier = ScriptedTransport(body: reply)
        _ = await DoddyAccountLink.signInMessaging(server: messaging, account: account, earlierDeviceToken: "short", transport: noEarlier)
        XCTAssertEqual(json(noEarlier.requests.first?.body), [:], "a token that isn't one is not sent")

        let answers: [(Int, Data, DoddyAccountLink.MessagingSignIn)] = [
            (409, Data(#"{"error":"account_conflict","reason":"device_account_has_data"}"#.utf8), .conflict(reason: "device_account_has_data")),
            (401, Data(#"{"error":"unauthorized"}"#.utf8), .accountRefused),
            (503, Data(#"{"error":"not_configured"}"#.utf8), .notSetUp),
            (503, Data(#"{"error":"account_check_unavailable"}"#.utf8), .retryLater),
            (200, Data(#"{"accountId":"nope","deviceToken":"x"}"#.utf8), .retryLater),
        ]
        for (status, body, expected) in answers {
            let outcome = await DoddyAccountLink.signInMessaging(server: messaging, account: account, earlierDeviceToken: nil, transport: ScriptedTransport(status: status, body: body))
            XCTAssertEqual(outcome, expected, "\(status) \(String(decoding: body, as: UTF8.self))")
        }
    }
}
