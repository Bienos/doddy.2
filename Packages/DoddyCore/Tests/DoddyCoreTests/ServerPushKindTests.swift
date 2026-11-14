@testable import DoddyCore
import XCTest

/// Written without a Swift toolchain at hand: run `make test-core` before relying on it.
final class ServerPushKindTests: XCTestCase {
    func testACallResultPushIsRecognised() {
        XCTAssertEqual(ServerPushKind.parse(["aps": ["alert": "x"], "doddy": ["kind": "call-result"]]), .callResult)
    }

    func testAFinishedTaskOrFileOpensMessages() {
        XCTAssertEqual(ServerPushKind.parse(["doddy": ["kind": "errand-result"]]), .errandResult)
        XCTAssertEqual(ServerPushKind.parse(["doddy": ["kind": "file-ready"]]), .fileReady)
        XCTAssertTrue(ServerPushKind.errandResult.opensMessages)
        XCTAssertTrue(ServerPushKind.fileReady.opensMessages)
        XCTAssertFalse(ServerPushKind.callResult.opensMessages)
    }

    /// Owner's review, 12 Nov 2026: a tap on a radar notification didn't open the radar. The server's hint is the kind only.
    func testARadarPushOpensTheRadar() {
        XCTAssertEqual(ServerPushKind.parse(["aps": ["alert": "x"], "doddy": ["kind": "radar"]]), .radar)
        XCTAssertTrue(ServerPushKind.radar.opensRadar)
        XCTAssertFalse(ServerPushKind.radar.opensMessages)
        for other in [ServerPushKind.callResult, .errandResult, .fileReady] {
            XCTAssertFalse(other.opensRadar, other.rawValue)
        }
        XCTAssertNil(ServerPushKind.parse(["doddy": ["kind": "radar:1234"]]), "never an id in the hint")
    }

    func testNothingElseOpensAnything() {
        XCTAssertNil(ServerPushKind.parse([:]))
        XCTAssertNil(ServerPushKind.parse(["aps": ["alert": "x"]]))
        XCTAssertNil(ServerPushKind.parse(["doddy": ["kind": "something-new"]]))
        XCTAssertNil(ServerPushKind.parse(["doddy": "call-result"]))
        XCTAssertNil(ServerPushKind.parse(["doddy": ["kind": 3]]))
        XCTAssertNil(ServerPushKind.parse(["firesAt": 1_793_000_000.0]), "a local timer's userInfo is not a server push")
    }
}
