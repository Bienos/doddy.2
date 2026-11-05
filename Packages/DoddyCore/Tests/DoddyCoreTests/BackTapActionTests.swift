@testable import DoddyCore
import XCTest

/// Settings → Back Tap and Siri: what "Talk to Doddy" does. The default keeps the old behaviour.
final class BackTapActionTests: XCTestCase {
    func testDefaultStartsAConversationWithTheBigIsland() {
        XCTAssertEqual(BackTapAction.stored(nil), .conversation)
        XCTAssertTrue(BackTapAction.stored(nil).startsConversation)
        XCTAssertTrue(BackTapAction.stored(nil).opensIsland)
    }

    func testUnknownStoredValueFallsBackToTheDefault() {
        XCTAssertEqual(BackTapAction.stored("island"), .conversation)
        XCTAssertEqual(BackTapAction.stored(""), .conversation)
    }

    func testSmallIslandStartsAConversationWithoutOpeningIt() {
        XCTAssertEqual(BackTapAction.stored(BackTapAction.smallIsland.rawValue), .smallIsland)
        XCTAssertTrue(BackTapAction.smallIsland.startsConversation)
        XCTAssertFalse(BackTapAction.smallIsland.opensIsland)
    }

    func testOpenAppStartsNothing() {
        XCTAssertEqual(BackTapAction.stored(BackTapAction.openApp.rawValue), .openApp)
        XCTAssertFalse(BackTapAction.openApp.startsConversation)
        XCTAssertFalse(BackTapAction.openApp.opensIsland)
    }
}
