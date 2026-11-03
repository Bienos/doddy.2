import Foundation
import XCTest
@testable import DoddyCore

// ADR-700: linking Apple or Google to this account from the iPhone, for Doddy on the web.

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
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://web-sign-in/return?result=linked&provider=google")!), .linked(.google))
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://web-sign-in/return?result=already&provider=apple")!), .already(.apple))
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://web-sign-in/return?result=taken&provider=google")!), .taken(.google))
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://web-sign-in/return?result=canceled&provider=google")!), .canceled)
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://web-sign-in/return?result=busy")!), .busy)
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://web-sign-in/return?result=failed")!), .failed)
        // "linked" without a provider, another scheme, another path: never read as linked.
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://web-sign-in/return?result=linked")!), .failed)
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy-dev://web-sign-in/return?result=linked&provider=google")!), .failed)
        XCTAssertEqual(ticket.outcome(of: URL(string: "doddy://connected-apps/return?result=linked&provider=google")!), .failed)
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
    private(set) var tickets: [WebSignInProvider] = []

    func newCode() async throws(WebLinkError) -> WebLinkCode { throw .notConfigured }
    func browsers() async throws(WebLinkError) -> [WebBrowserSession] { [] }
    func signOut(browser id: UUID) async throws(WebLinkError) {}
    func signInProviders() async throws(WebLinkError) -> [WebSignInProvider] { lock.withLock { providers } }
    func linkedSignIns() async throws(WebLinkError) -> [WebLinkedSignIn] { lock.withLock { linked } }
    func linkTicket(for provider: WebSignInProvider) async throws(WebLinkError) -> WebLinkTicket {
        lock.withLock { tickets.append(provider) }
        return try ticketResult.get()
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

    func testLinkingShowsWhatTheServerSaidAndThenWhatItKeeps() async {
        let fake = FakeMethods()
        let signIn = googleSignIn
        let sheet = FakeSheet(.success(URL(string: "doddy://web-sign-in/return?result=linked&provider=google")!), before: { fake.linked = [signIn] })
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil }, authenticator: sheet)
        await model.refreshMethods()
        XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: []))
        await model.link(.google)
        XCTAssertEqual(fake.tickets, [.google])
        XCTAssertEqual(model.linkOutcome, .linked(.google))
        XCTAssertEqual(model.methods, .loaded(offered: [.google, .apple], linked: [googleSignIn]), "the list is the server's, read again")
        XCTAssertNil(model.linking)
    }

    func testTakenCancelledOrABrokenSheetLinkNothing() async {
        let fake = FakeMethods()
        for (sheet, outcome) in [
            (FakeSheet(.success(URL(string: "doddy://web-sign-in/return?result=taken&provider=google")!)), WebLinkOutcome.taken(.google)),
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
