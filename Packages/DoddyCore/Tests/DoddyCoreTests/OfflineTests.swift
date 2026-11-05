import DoddyCore
import Foundation
import XCTest

/// Offline (ADR-289): which errors mean "no connection".
final class OfflineTests: XCTestCase {
    func testNoConnectionIsRecognisedAlsoWhenWrapped() {
        XCTAssertTrue(Offline.isNoConnection(URLError(.notConnectedToInternet)))
        XCTAssertTrue(Offline.isNoConnection(VoiceTokenError.offline))
        let wrapped = NSError(domain: "LiveKit", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue)])
        XCTAssertTrue(Offline.isNoConnection(wrapped))
    }

    func testServerAnswersAreNotOffline() {
        XCTAssertFalse(Offline.isNoConnection(VoiceTokenError.sessionExpired))
        XCTAssertFalse(Offline.isNoConnection(URLError(.badServerResponse)))
        XCTAssertFalse(Offline.isNoConnection(NSError(domain: "x", code: 1)))
    }

    /// ADR-686: a timeout means the server was slow (a free server waking up), not that the
    /// iPhone is offline, so it isn't shown as "You're offline".
    func testATimeoutIsASlowServerNotOffline() {
        XCTAssertFalse(Offline.isNoConnection(URLError(.timedOut)))
        XCTAssertTrue(Offline.isServerSlow(URLError(.timedOut)))
        XCTAssertTrue(Offline.isServerSlow(VoiceTokenError.timedOut))
        XCTAssertFalse(Offline.isNoConnection(VoiceTokenError.timedOut))
        let wrapped = NSError(domain: "LiveKit", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)])
        XCTAssertTrue(Offline.isServerSlow(wrapped))
        XCTAssertFalse(Offline.isServerSlow(URLError(.notConnectedToInternet)))
        XCTAssertFalse(Offline.isServerSlow(VoiceTokenError.offline))
        XCTAssertFalse(VoiceTokenServer.message(for: .timedOut).lowercased().contains("internet connection"))
        XCTAssertFalse(Offline.slowServerMessage.lowercased().contains("offline"))
    }
}
