import DoddyCore
import XCTest

final class FindRequestTests: XCTestCase {
    func testQueryBecomesOneTidyLine() {
        XCTAssertEqual(FindRequest(query: "  gate\n code \t 4821 ").query, "gate code 4821")
        XCTAssertEqual(FindRequest(query: " \n ").query, "")
        XCTAssertEqual(FindRequest(query: "Gdzie są zapasowe klucze?").query, "Gdzie są zapasowe klucze?")
    }

    func testLongQueriesAreCutAtAWordBreak() {
        let words = Array(repeating: "keys", count: 60).joined(separator: " ") // 299 characters
        let query = FindRequest(query: words).query
        XCTAssertLessThanOrEqual(query.count, FindRequest.maxLength)
        XCTAssertTrue(query.hasSuffix("keys"))
        let unbroken = String(repeating: "a", count: 250)
        XCTAssertEqual(FindRequest(query: unbroken).query.count, FindRequest.maxLength)
    }
}
