import XCTest

@testable import DoddyCore

final class ThreadTaskResultsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func errand(_ title: String, _ state: ErrandState, hoursAgo: Double) -> StoredErrand {
        var errand = StoredErrand(
            id: UUID(), createdAt: now.addingTimeInterval(-hoursAgo * 3_600 - 60), state: state,
            draft: ErrandDraft(words: "find \(title)", brief: "Find \(title)", title: title))
        errand.updatedAt = now.addingTimeInterval(-hoursAgo * 3_600)
        return errand
    }

    func testDoneAndFailedTasksAreShownButNotOpenOrCancelledOnes() {
        let list = [
            errand("done", .done, hoursAgo: 1), errand("failed", .failed, hoursAgo: 2),
            errand("cancelled", .cancelled, hoursAgo: 1), errand("running", .running, hoursAgo: 1),
            errand("queued", .queued, hoursAgo: 1), errand("unknown", .unknown, hoursAgo: 1),
        ]
        XCTAssertEqual(ThreadTaskResults.shown(list, now: now).map(\.title), ["failed", "done"])
    }

    func testOnlyThisWeeksResults() {
        let list = [errand("old", .done, hoursAgo: 24 * 8), errand("new", .done, hoursAgo: 24 * 6)]
        XCTAssertEqual(ThreadTaskResults.shown(list, now: now).map(\.title), ["new"])
    }

    func testTheNewestFewOldestFirst() {
        let list = (1...5).map { errand("t\($0)", .done, hoursAgo: Double($0)) }
        XCTAssertEqual(ThreadTaskResults.shown(list, now: now).map(\.title), ["t3", "t2", "t1"])
    }
}
