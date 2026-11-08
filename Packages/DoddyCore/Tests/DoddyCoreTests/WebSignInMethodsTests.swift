import Foundation
import XCTest
@testable import DoddyCore

// ADR-818: linking Apple or Google to this account from the iPhone, for Doddy on the web.

/// Answers by method and path.
private final class RoutedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    let routes: [String: (Int, String)]

    init(_ routes: [String: (Int, String)]) {
        self.routes = routes
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        lock.withLock { recorded.append(request) }
        let (status, body) = routes["\(request.method) \(request.url.path)"] ?? (404, #"{"error":{"code":"not_found","message":"Not found."}}"#)
        return (status, Data(body.utf8))
    }
}

private let server = URL(string: "https://doddy.example.com")!
private let googleId = UUID(uuidString: "5B0C8F7E-2A41-4C3D-9E6F-0123456789AB")!
private let ticketURL = "https://app.doddy.test/v1/web/oauth/start?ticket=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_ABCDE"

private func client(_ transport: RoutedTransport) -> BackendWebLinkClient {
    BackendWebLinkClient(baseURL: server, sessionToken: { "ds1.a.b" }, transport: transport)!
}

final class WebSignInMethodsClientTests: XCTestCase {
    func testProvidersAreReadAndAnOlderServerOffersNone() async throws {
        let offered = RoutedTransport(["GET /v1/web/sign-in-options": (200, #"{"providers":["google","apple","facebook"]}"#)])
        let providers = try await client(offered).signInProviders()
        XCTAssertEqual(providers, [.google, .apple], "unknown providers are left out")
        let older = RoutedTransport([:])
        let none = try await client(older).signInProviders()
        XCTAssertEqual(none, [])
    }

    func testLinkedSignInsAreReadWithThePhonesSession() async throws {
        let transport = RoutedTransport(["GET /v1/web/identities": (200, #"{"identities":[{"id":"5b0c8f7e-2a41-4c3d-9e6f-0123456789ab","provider":"google","linkedAt":"2026-11-03T10:00:00.000Z"},{"id":"7d1e9a0b-3c52-4d6e-8f70-123456789abc","provider":"myspace","linkedAt":"2026-11-03T10:00:00.000Z"}]}"#)])
        let linked = try await client(transport).linkedSignIns()
        XCTAssertEqual(linked.map(\.id), [googleId])
        XCTAssertEqual(linked.first?.provider, .google)
        XCTAssertEqual(transport.requests.first?.headers["authorization"], "Bearer ds1.a.b")
    }

    func testATicketIsAskedForOneProviderAndOnlyDoddysStartAddressIsAccepted() async throws {
        let good = RoutedTransport(["POST /v1/web/oauth/tickets": (200, #"{"url":"\#(ticketURL)","expiresAt":"2026-11-03T10:05:00.000Z","callbackScheme":"doddy"}"#)])
        let ticket = try await client(good).linkTicket(for: .apple)
        XCTAssertEqual(ticket.url.absoluteString, ticketURL)
        XCTAssertEqual(ticket.callbackScheme, "doddy")
        let request = try XCTUnwrap(good.requests.first)
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"provider":"apple"}"#)

        for (url, scheme) in [
            ("https://evil.example/phish", "doddy"),
            ("http://app.doddy.test/v1/web/oauth/start?ticket=x", "doddy"),
            ("https://app.doddy.test/v1/web/oauth/start?ticket=x&redirect=evil", "doddy"),
            (ticketURL, "https"),
            (ticketURL, "evil"),
        ] {
            let bad = RoutedTransport(["POST /v1/web/oauth/tickets": (200, #"{"url":"\#(url)","expiresAt":"2026-11-03T10:05:00.000Z","callbackScheme":"\#(scheme)"}"#)])
            do {
                _ = try await client(bad).linkTicket(for: .google)
                XCTFail("accepted \(url) \(scheme)")
            } catch {
                XCTAssertEqual(error, .unreadable)
            }
        }
    }

    func testUnlinkDeletesByTheLowercaseId() async throws {
        let transport = RoutedTransport(["DELETE /v1/web/identities/5b0c8f7e-2a41-4c3d-9e6f-0123456789ab": (200, #"{"unlinked":true}"#)])
        try await client(transport).unlink(signIn: googleId)
        XCTAssertEqual(transport.requests.first?.method, "DELETE")
    }

    func testTheSheetsEndIsReadStrictly() {
        let ticket = WebLinkTicket(url: URL(string: ticketURL)!, callbackScheme: "doddy")
        let code = String(repeating: "Ab3_-", count: 8) + "xyz"
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=confirm&provider=google&code=\(code)")!), .confirm(code: code))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=canceled&provider=google")!), .done(.canceled))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=busy")!), .done(.busy))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=failed")!), .done(.failed))
        // The sheet can never say "linked" by itself: only the server's answer to this iPhone's confirmation can.
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=linked&provider=google")!), .done(.failed))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=confirm&provider=google&code=short")!), .done(.failed))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy-dev://web-sign-in/return?result=confirm&code=\(code)")!), .done(.failed))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://connected-apps/return?result=confirm&code=\(code)")!), .done(.failed))
    }

    func testConfirmingSendsTheCodeAndReadsTheServersAnswer() async throws {
        let code = String(repeating: "Ab3_-", count: 8) + "xyz"
        let transport = RoutedTransport(["POST /v1/web/oauth/complete": (200, #"{"result":"taken","provider":"google"}"#)])
        let outcome = try await client(transport).completeLink(code: code)
        XCTAssertEqual(outcome, .taken(.google))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), #"{"code":"\#(code)"}"#)
        XCTAssertEqual(request.headers["authorization"], "Bearer ds1.a.b")
        let odd = RoutedTransport(["POST /v1/web/oauth/complete": (200, #"{"result":"merged","provider":"google"}"#)])
        do {
            _ = try await client(odd).completeLink(code: code)
            XCTFail("an unknown answer was read")
        } catch {
            XCTAssertEqual(error, .unreadable)
        }
    }
}

/// A server stand-in for the model.
private final class FakeMethods: WebLinkClient, @unchecked Sendable {
    private let lock = NSLock()
    var providers: [WebSignInProvider] = [.google, .apple]
    var linked: [WebLinkedSignIn] = []
    var ticketResult: Result<WebLinkTicket, WebLinkError> = .success(WebLinkTicket(url: URL(string: ticketURL)!, callbackScheme: "doddy"))
    /// What linking does on the server when the sheet ends.
    var onSheetEnd: (() -> Void)?
    var unlinkResults: [Result<Void, WebLinkError>] = []
    /// What the server answers this iPhone's confirmation; linking `onConfirm` when it succeeds.
    var completeResult: Result<WebLinkOutcome, WebLinkError> = .success(.linked(.google))
    var onConfirm: [WebLinkedSignIn] = []
    private(set) var confirmed: [String] = []
    private(set) var tickets: [WebSignInProvider] = []
    var joinResult: Result<WebJoinOutcome, WebLinkError> = .success(.joined(.google))
    var joinedAccount: WebJoinedAccount?
    private(set) var joins: [(String, String)] = []
    private(set) var leaves: [String] = []

    func newCode() async throws(WebLinkError) -> WebLinkCode { throw .notConfigured }
    func browsers() async throws(WebLinkError) -> [WebBrowserSession] { [] }
    func signOut(browser id: UUID) async throws(WebLinkError) {}
    func signInProviders() async throws(WebLinkError) -> [WebSignInProvider] { lock.withLock { providers } }
    func linkedSignIns() async throws(WebLinkError) -> [WebLinkedSignIn] { lock.withLock { linked } }
    func linkTicket(for provider: WebSignInProvider) async throws(WebLinkError) -> WebLinkTicket {
        lock.withLock { tickets.append(provider) }
        return try ticketResult.get()
    }
    func completeLink(code: String) async throws(WebLinkError) -> WebLinkOutcome {
        lock.withLock { confirmed.append(code) }
        let outcome = try completeResult.get()
        lock.withLock { linked = onConfirm }
        return outcome
    }
    func joinTicket(for provider: WebSignInProvider) async throws(WebLinkError) -> WebLinkTicket {
        lock.withLock { tickets.append(provider) }
        return try ticketResult.get()
    }
    func join(code: String, deviceID: String) async throws(WebLinkError) -> WebJoinOutcome {
        lock.withLock { joins.append((code, deviceID)) }
        let outcome = try joinResult.get()
        if case .joined(let p) = outcome { lock.withLock { joinedAccount = WebJoinedAccount(provider: p, since: Date(timeIntervalSince1970: 5)) } }
        return outcome
    }
    func deviceAccount(deviceID: String) async throws(WebLinkError) -> WebJoinedAccount? { lock.withLock { joinedAccount } }
    func leaveJoinedAccount(deviceID: String) async throws(WebLinkError) {
        lock.withLock {
            leaves.append(deviceID)
            joinedAccount = nil
        }
    }
    func unlink(signIn id: UUID) async throws(WebLinkError) {
        let result = lock.withLock { unlinkResults.removeFirst() }
        try result.get()
        lock.withLock { linked.removeAll { $0.id == id } }
    }
}

private struct FakeSheet: WebAuthenticator {
    let result: Result<URL, WebAuthenticationError>
    let before: (@Sendable () -> Void)?

    init(_ result: Result<URL, WebAuthenticationError>, before: (@Sendable () -> Void)? = nil) {
        self.result = result
        self.before = before
    }

    func authenticate(url: URL, callbackScheme: String) async throws(WebAuthenticationError) -> URL {
        before?()
        return try result.get()
    }
}

@MainActor
final class WebSignInMethodsModelTests: XCTestCase {
    private let googleSignIn = WebLinkedSignIn(id: googleId, provider: .google, linkedAt: Date(timeIntervalSince1970: 1_000))

    func testHiddenWhenTheServerOffersNeitherOrTheAppCantOpenASheet() async {
        let fake = FakeMethods()
        fake.providers = []
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: FakeSheet(.failure(.failed)))
        await model.refreshMethods()
        XCTAssertEqual(model.methods, .unavailable)
        let withProviders = FakeMethods()
        let noSheet = WebSignInModel(makeClient: { withProviders }, renewClient: { nil })
        await noSheet.refreshMethods()
        XCTAssertEqual(noSheet.methods, .unavailable)
    }

    private let confirmCode = String(repeating: "Ab3_-", count: 8) + "xyz"
    private var confirmURL: URL { URL(string: "doddy://web-sign-in/return?result=confirm&provider=google&code=\(confirmCode)")! }

    func testLinkingConfirmsWithThisIPhoneThenShowsWhatTheServerKeeps() async {
        let fake = FakeMethods()
        fake.onConfirm = [googleSignIn]
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: FakeSheet(.success(confirmURL)))
        await model.refreshMethods()
        XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: []))
        await model.link(.google)
        XCTAssertEqual(fake.tickets, [.google])
        XCTAssertEqual(fake.confirmed, [confirmCode])
        XCTAssertEqual(model.linkOutcome, .linked(.google))
        XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: [googleSignIn]), "the list is the server's, read again")
        XCTAssertNil(model.linking)
    }

    func testTakenCancelledOrABrokenSheetLinkNothing() async {
        let fake = FakeMethods()
        fake.completeResult = .success(.taken(.google))
        for (sheet, outcome) in [
            (FakeSheet(.success(confirmURL)), WebLinkOutcome.taken(.google)),
            (FakeSheet(.success(URL(string: "doddy://web-sign-in/return?result=linked&provider=google")!)), .failed),
            (FakeSheet(.failure(.canceled)), .canceled),
            (FakeSheet(.failure(.failed)), .failed),
            (FakeSheet(.success(URL(string: "doddy://elsewhere?result=linked&provider=google")!)), .failed),
        ] {
            let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: sheet)
            await model.link(.google)
            XCTAssertEqual(model.linkOutcome, outcome)
            XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: []))
        }
    }

    func testAnExpiredConfirmationLinksNothingAndSaysSo() async {
        let fake = FakeMethods()
        fake.completeResult = .failure(.notFound)
        fake.onConfirm = [googleSignIn]
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: FakeSheet(.success(confirmURL)))
        await model.link(.google)
        XCTAssertEqual(model.linkOutcome, .failed)
        XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: []))
        let offline = FakeMethods()
        offline.completeResult = .failure(.transport)
        let second = WebSignInModel(makeClient: { offline }, renewClient: { nil }, authenticator: FakeSheet(.success(confirmURL)))
        await second.link(.google)
        XCTAssertEqual(second.linkProblem, .offline)
        XCTAssertNil(second.linkOutcome)
    }

    func testNoTicketMeansNoSheet() async {
        let fake = FakeMethods()
        fake.ticketResult = .failure(.rateLimited(retryAfterSeconds: 120))
        final class Opened: @unchecked Sendable { var count = 0 }
        let opened = Opened()
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: FakeSheet(.failure(.failed), before: { opened.count += 1 }))
        await model.link(.apple)
        XCTAssertEqual(model.linkProblem, .tooMany(minutes: 2))
        XCTAssertNil(model.linkOutcome)
        XCTAssertEqual(opened.count, 0)
    }

    func testASignInLeavesTheListOnlyAfterTheServerUnlinkedIt() async {
        let fake = FakeMethods()
        fake.linked = [googleSignIn]
        fake.unlinkResults = [.failure(.transport), .success(())]
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: FakeSheet(.failure(.canceled)))
        await model.refreshMethods()
        await model.unlink(googleId)
        XCTAssertEqual(model.linkProblem, .offline)
        XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: [googleSignIn]))
        await model.unlink(googleId)
        XCTAssertNil(model.linkProblem)
        XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: []))
        XCTAssertTrue(model.unlinking.isEmpty)
    }
}

// ADR-819: this iPhone using an account made on the web.

final class WebJoinClientTests: XCTestCase {
    private let code = String(repeating: "Ab3_-", count: 8) + "xyz"
    private let device = "22222222-2222-4222-8222-222222222222"

    func testJoinSendsTheCodeAndThisDeviceAndReadsTheAnswer() async throws {
        let transport = RoutedTransport(["POST /v1/web/oauth/join": (200, #"{"result":"joined","provider":"apple"}"#)])
        let outcome = try await client(transport).join(code: code, deviceID: device.uppercased())
        XCTAssertEqual(outcome, .joined(.apple))
        let body = try XCTUnwrap(transport.requests.first?.body)
        XCTAssertEqual(String(data: body, encoding: .utf8), #"{"code":"\#(code)","deviceId":"\#(device)"}"#)
    }

    func testTheDeviceAccountIsReadAndAnOlderServerMeansItsOwn() async throws {
        let joined = RoutedTransport(["POST /v1/web/device-account": (200, #"{"joined":{"provider":"google","since":"2026-11-03T10:00:00.000Z"}}"#)])
        let account = try await client(joined).deviceAccount(deviceID: device)
        XCTAssertEqual(account?.provider, .google)
        let own = RoutedTransport(["POST /v1/web/device-account": (200, #"{"joined":null}"#)])
        let none = try await client(own).deviceAccount(deviceID: device)
        XCTAssertNil(none)
        let older = RoutedTransport([:])
        let unknown = try await client(older).deviceAccount(deviceID: device)
        XCTAssertNil(unknown)
    }

    func testTheSheetsJoinEndIsReadStrictly() {
        let ticket = WebLinkTicket(url: URL(string: ticketURL)!, callbackScheme: "doddy")
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=join&provider=google&code=\(code)")!), .joinConfirm(code: code))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=not_linked&provider=google")!), .done(.notLinked))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=join&code=bad")!), .done(.failed))
        XCTAssertEqual(ticket.end(of: URL(string: "doddy://web-sign-in/return?result=joined&provider=google")!), .done(.failed), "never 'joined' from the sheet alone")
    }
}

@MainActor
final class WebJoinModelTests: XCTestCase {
    private let code = String(repeating: "Ab3_-", count: 8) + "xyz"
    private let device = "22222222-2222-4222-8222-222222222222"
    private var joinURL: URL { URL(string: "doddy://web-sign-in/return?result=join&provider=google&code=\(code)")! }

    func testJoiningConfirmsWithThisIPhoneThenRenewsItsSession() async {
        let fake = FakeMethods()
        final class Renewals: @unchecked Sendable { var count = 0 }
        let renewals = Renewals()
        let id = device
        let model = WebSignInModel(makeClient: { fake }, renewClient: { renewals.count += 1; return fake }, authenticator: FakeSheet(.success(joinURL)), deviceID: { id })
        await model.refreshDeviceAccount()
        XCTAssertEqual(model.deviceAccount, .own)
        await model.joinAccount(with: .google)
        XCTAssertEqual(fake.joins.map(\.0), [code])
        XCTAssertEqual(fake.joins.map(\.1), [device])
        XCTAssertEqual(renewals.count, 1, "the session is renewed into the joined account")
        XCTAssertEqual(model.joinOutcome, .joined(.google))
        XCTAssertEqual(model.deviceAccount, .joined(WebJoinedAccount(provider: .google, since: Date(timeIntervalSince1970: 5))))
        XCTAssertNil(model.joining)
    }

    func testNoAccountCancelledOrOwnChangeNothing() async {
        for (sheet, result, outcome) in [
            (FakeSheet(.success(URL(string: "doddy://web-sign-in/return?result=not_linked&provider=google")!)), Result<WebJoinOutcome, WebLinkError>.success(.joined(.google)), WebSignInModel.JoinOutcome.notLinked),
            (FakeSheet(.failure(.canceled)), .success(.joined(.google)), .canceled),
            (FakeSheet(.success(joinURL)), .success(.own(.google)), .own(.google)),
            (FakeSheet(.success(joinURL)), .failure(.notFound), .failed),
        ] {
            let fake = FakeMethods()
            fake.joinResult = result
            let id = device
            let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: sheet, deviceID: { id })
            await model.joinAccount(with: .google)
            XCTAssertEqual(model.joinOutcome, outcome)
            XCTAssertNil(fake.joinedAccount)
        }
    }

    func testJoinedButNoNewSessionYetSaysSo() async {
        let fake = FakeMethods()
        let id = device
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: FakeSheet(.success(joinURL)), deviceID: { id })
        await model.joinAccount(with: .google)
        XCTAssertEqual(model.joinOutcome, .joinedRenewPending(.google))
    }

    func testLeavingGoesBackToThisIPhonesOwnAccount() async {
        let fake = FakeMethods()
        fake.joinedAccount = WebJoinedAccount(provider: .apple, since: Date(timeIntervalSince1970: 1))
        let id = device
        let model = WebSignInModel(makeClient: { fake }, renewClient: { fake }, authenticator: FakeSheet(.failure(.canceled)), deviceID: { id })
        await model.refreshDeviceAccount()
        XCTAssertEqual(model.deviceAccount, .joined(WebJoinedAccount(provider: .apple, since: Date(timeIntervalSince1970: 1))))
        await model.leaveJoinedAccount()
        XCTAssertEqual(fake.leaves, [device])
        XCTAssertEqual(model.joinOutcome, .left)
        XCTAssertEqual(model.deviceAccount, .own)
    }

    func testWithoutADeviceIdNothingIsTried() async {
        let fake = FakeMethods()
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: FakeSheet(.success(joinURL)))
        await model.joinAccount(with: .google)
        XCTAssertNil(model.joinOutcome)
        XCTAssertTrue(fake.tickets.isEmpty)
    }
}

