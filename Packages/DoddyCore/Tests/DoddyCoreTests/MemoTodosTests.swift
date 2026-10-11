import XCTest
@testable import DoddyCore

final class MemoTodosTests: XCTestCase {
    func testEnglishLeadInsAreDroppedAndTheRestIsKept() {
        let memo = "OK so the meeting went well. I need to call the plumber about the leak. Don't forget to buy milk! "
            + "And remember to email Anna the slides. Buy batteries."
        XCTAssertEqual(MemoTodos.suggest(memo), ["Call the plumber about the leak", "Buy milk", "Email Anna the slides", "Buy batteries"])
    }

    func testPolishLeadInsAndVerbs() {
        let memo = "Muszę zadzwonić do mamy. Nie zapomnij kupić chleba. Pamiętaj, żeby zapłacić za prąd. Kup mleko. Było fajnie."
        XCTAssertEqual(MemoTodos.suggest(memo), ["Zadzwonić do mamy", "Kupić chleba", "Zapłacić za prąd", "Kup mleko"])
    }

    func testQuestionsChatterAndRepeatsAreLeftOut() {
        let memo = "Do I need to call Adam? I need tomatoes for the sauce. I need to. Call Adam. call adam. The weather was nice."
        XCTAssertEqual(MemoTodos.suggest(memo), ["Call Adam"])
    }

    func testAtMostFiveAndNothingTooLong() {
        let memo = (1...8).map { "Buy item number \($0)." }.joined(separator: " ")
        XCTAssertEqual(MemoTodos.suggest(memo).count, MemoTodos.maxItems)
        XCTAssertEqual(MemoTodos.suggest("I need to " + String(repeating: "word ", count: 40)), [])
        XCTAssertEqual(MemoTodos.suggest(""), [])
    }
}
