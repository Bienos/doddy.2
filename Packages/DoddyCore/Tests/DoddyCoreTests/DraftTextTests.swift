import DoddyCore
import XCTest

final class DraftTextTests: XCTestCase {
    func testPastingIntoAnEmptyOrBlankEditorReplacesIt() {
        XCTAssertEqual(DraftText.pasting("Gate code 4821", into: ""), "Gate code 4821")
        XCTAssertEqual(DraftText.pasting("Gate code 4821", into: " \n "), "Gate code 4821")
    }

    func testPastingAfterTextGoesOnANewLineAndKeepsEveryCharacter() {
        XCTAssertEqual(DraftText.pasting("  4821 \n", into: "Gate code"), "Gate code\n  4821 \n")
        XCTAssertEqual(DraftText.pasting("4821", into: "Gate code\n"), "Gate code\n4821", "no blank line added")
    }

    func testNothingToPasteChangesNothing() {
        XCTAssertEqual(DraftText.pasting("", into: "Gate code"), "Gate code")
        XCTAssertEqual(DraftText.pasting([String](), into: "Gate code"), "Gate code")
        XCTAssertEqual(DraftText.pasting(["", ""], into: ""), "")
    }

    func testSeveralClipboardItemsBecomeOnePasteOnePerLine() {
        XCTAssertEqual(DraftText.pasting(["milk", "", "eggs"], into: "Shopping:"), "Shopping:\nmilk\neggs")
    }
}
