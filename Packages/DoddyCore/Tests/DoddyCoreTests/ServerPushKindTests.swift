@testable import DoddyCore
import XCTest

/// Written without a Swift toolchain at hand: run `make test-core` before relying on it.
final class ServerPushKindTests: XCTestCase {
    func testACallResultPushIsRecognised() {
        XCTAssertEqual(ServerPushKind.parse(["aps": ["alert": "x"], "doddy": ["kind": "call-result"]]), .callResult)
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
