import DoddyCore
import XCTest

/// A list from a photo (ADR-270).
final class PhotoListTests: XCTestCase {
    func testBulletsAndNumbersGoAndAHeadingBecomesTheName() {
        let read = """
        Shopping:
        - milk
        • eggs 12
        2) bread
        [ ] Milk
        ☐ oat flakes
        """
        let proposal = PhotoList.proposal(from: read)
        XCTAssertEqual(proposal.name, "Shopping")
        XCTAssertEqual(proposal.items, ["milk", "eggs 12", "bread", "oat flakes"], "a repeat of milk is left out; words stay as read")
        XCTAssertEqual(proposal.leftOut, 0)
    }

    func testNoHeadingMeansNoNameAndLongLinesAreLeftOut() {
        let proposal = PhotoList.proposal(from: "tape\n" + String(repeating: "x", count: 201))
        XCTAssertNil(proposal.name)
        XCTAssertEqual(proposal.items, ["tape"])
        XCTAssertEqual(proposal.leftOut, 1)
    }
}
