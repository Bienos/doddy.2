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
}
