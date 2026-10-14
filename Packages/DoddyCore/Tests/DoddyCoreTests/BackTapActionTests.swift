@testable import DoddyCore
import XCTest

/// Settings → Back Tap and Siri: what "Talk to Doddy" does. The default keeps the old behaviour.
final class BackTapActionTests: XCTestCase {
    func testDefaultStartsAConversation() {
        XCTAssertEqual(BackTapAction.stored(nil), .conversation)
        XCTAssertTrue(BackTapAction.stored(nil).startsConversation)
    }

    func testUnknownStoredValueFallsBackToTheDefault() {
        XCTAssertEqual(BackTapAction.stored("island"), .conversation)
        XCTAssertEqual(BackTapAction.stored(""), .conversation)
    }

    func testOpenAppStoresAndReadsBack() {
        XCTAssertEqual(BackTapAction.stored(BackTapAction.openApp.rawValue), .openApp)
        XCTAssertFalse(BackTapAction.openApp.startsConversation)
    }
}
