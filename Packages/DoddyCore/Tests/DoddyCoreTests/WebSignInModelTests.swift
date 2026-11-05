import Foundation
import XCTest
@testable import DoddyCore

/// A server stand-in: each call takes the next scripted answer.
private final class FakeWebLink: WebLinkClient, @unchecked Sendable {
    private let lock = NSLock()
    var codes: [Result<WebLinkCode, WebLinkError>] = []
    var lists: [Result<[WebBrowserSession], WebLinkError>] = []
    var signOuts: [Result<Void, WebLinkError>] = []
    private(set) var signedOut: [UUID] = []

    func newCode() async throws(WebLinkError) -> WebLinkCode {
        try lock.withLock { codes.removeFirst() }.get()
    }

    func browsers() async throws(WebLinkError) -> [WebBrowserSession] {
        try lock.withLock { lists.removeFirst() }.get()
    }

    func signOut(browser id: UUID) async throws(WebLinkError) {
        lock.withLock { signedOut.append(id) }
        try lock.withLock { signOuts.removeFirst() }.get()
    }
}

private let origin = URL(string: "https://app.doddy.lol")!
private let sampleCode = WebLinkCode(code: "K7QM-4XPA", expiresAt: Date(timeIntervalSince1970: 1_000), webOrigin: origin)

private func browser(_ seen: TimeInterval, id: UUID = UUID()) -> WebBrowserSession {
    WebBrowserSession(
        id: id, browser: .safari, system: .macos, createdAt: Date(timeIntervalSince1970: 0),
        lastSeenAt: Date(timeIntervalSince1970: seen), expiresAt: Date(timeIntervalSince1970: seen + 100))
}

@MainActor
final class WebSignInModelTests: XCTestCase {
    func testACodeIsShownAndGoesAwayWhenItExpires() async {
        let fake = FakeWebLink()
        fake.codes = [.success(sampleCode)]
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil })
        await model.getCode()
        XCTAssertEqual(model.code, .shown(sampleCode))
        model.expireCode(now: Date(timeIntervalSince1970: 999))
        XCTAssertEqual(model.code, .shown(sampleCode), "a second left: still shown")
        model.expireCode(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(model.code, .none, "an expired code is never left on screen")
    }

    func testNoServerSaysSo() async {
        let model = WebSignInModel(makeClient: { nil }, renewClient: { nil })
        await model.getCode()
        XCTAssertEqual(model.code, .failed(.notConfigured))
        await model.refreshBrowsers()
        XCTAssertEqual(model.browsers, .failed(.notConfigured))
    }

    func testARefusedSessionIsRenewedOnceThenTheActionIsRetried() async {
        let stale = FakeWebLink()
        stale.codes = [.failure(.unauthenticated)]
        let fresh = FakeWebLink()
        fresh.codes = [.success(sampleCode)]
        let model = WebSignInModel(makeClient: { stale }, renewClient: { fresh })
        await model.getCode()
        XCTAssertEqual(model.code, .shown(sampleCode))
    }

    func testStillRefusedAfterRenewingIsSignedOutNotALoop() async {
        let stale = FakeWebLink()
        stale.codes = [.failure(.unauthenticated)]
        let alsoStale = FakeWebLink()
        alsoStale.codes = [.failure(.unauthenticated)]
        let model = WebSignInModel(makeClient: { stale }, renewClient: { alsoStale })
        await model.getCode()
        XCTAssertEqual(model.code, .failed(.signedOut))
    }

    func testTooManyCodesSaysHowLongToWait() async {
        let fake = FakeWebLink()
        fake.codes = [.failure(.rateLimited(retryAfterSeconds: 61)), .failure(.transport), .failure(.server(message: "x"))]
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil })
        await model.getCode()
        XCTAssertEqual(model.code, .failed(.tooMany(minutes: 2)))
        await model.getCode()
        XCTAssertEqual(model.code, .failed(.offline))
        await model.getCode()
        XCTAssertEqual(model.code, .failed(.server))
    }

    func testBrowsersAreListedMostRecentlyUsedFirst() async {
        let fake = FakeWebLink()
        let old = browser(10), recent = browser(50)
        fake.lists = [.success([old, recent])]
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil })
        await model.refreshBrowsers()
        XCTAssertEqual(model.browsers, .loaded([recent, old]))
    }

    func testABrowserLeavesTheListOnlyAfterTheServerSignedItOut() async {
        let fake = FakeWebLink()
        let a = browser(10), b = browser(20)
        fake.lists = [.success([a, b])]
        fake.signOuts = [.failure(.transport), .success(()), .failure(.notFound)]
        let model = WebSignInModel(makeClient: { fake }, renewClient: { nil })
        await model.refreshBrowsers()

        await model.signOut(a.id)
        XCTAssertEqual(model.signOutProblem, .offline)
        XCTAssertEqual(model.browsers, .loaded([b, a]), "a failed sign-out keeps the browser listed")

        await model.signOut(a.id)
        XCTAssertNil(model.signOutProblem)
        XCTAssertEqual(model.browsers, .loaded([b]))

        await model.signOut(b.id)
        XCTAssertNil(model.signOutProblem, "already signed out is the outcome asked for")
        XCTAssertEqual(model.browsers, .loaded([]))
        XCTAssertTrue(model.signingOut.isEmpty)
        XCTAssertEqual(fake.signedOut, [a.id, a.id, b.id])
    }
}
