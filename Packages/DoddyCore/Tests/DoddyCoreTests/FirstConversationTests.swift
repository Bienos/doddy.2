import DoddyCore
import XCTest

/// The guided first conversation (ADR-401): once, and never instead of a translator or a check-in.
final class FirstConversationTests: XCTestCase {
    func testOnlyTheVeryFirstPlainConversationGetsTheTour() {
        XCTAssertTrue(FirstConversationPrompt.isFirst(hadConversationBefore: false, translator: false, morningCheckIn: false))
        XCTAssertFalse(FirstConversationPrompt.isFirst(hadConversationBefore: true, translator: false, morningCheckIn: false))
        XCTAssertFalse(FirstConversationPrompt.isFirst(hadConversationBefore: false, translator: true, morningCheckIn: false))
        XCTAssertFalse(FirstConversationPrompt.isFirst(hadConversationBefore: false, translator: false, morningCheckIn: true))
    }

    func testTheVariableIsYesOrNo() {
        XCTAssertEqual(FirstConversationPrompt.variableName, "first_conversation")
        XCTAssertEqual(FirstConversationPrompt.render(isFirst: true), "yes")
        XCTAssertEqual(FirstConversationPrompt.render(isFirst: false), "no")
    }
}
