import XCTest
@testable import DoddyCore

final class ThreadLocalFilesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ name: String, ageDays: Double) -> LocalMadeFile {
        LocalMadeFile(name: "\(name).pptx", title: name, kind: "deck", createdAt: now.addingTimeInterval(-ageDays * 24 * 3600))
    }

    func testShownDropsExpiredAndReadsOldestFirst() {
        let fresh = file("Fresh", ageDays: 1)
        let older = file("Older", ageDays: 5)
        let old = file("Old", ageDays: 8)
        XCTAssertEqual(LocalMadeFiles.shown([fresh, old, older], now: now).map(\.title), ["Older", "Fresh"])
        XCTAssertEqual(LocalMadeFiles.expired([fresh, old, older], now: now).map(\.title), ["Old"])
    }

    func testShownKeepsTheNewestSix() {
        let many = (0..<9).map { file("File \($0)", ageDays: Double($0) * 0.5) }
        let shown = LocalMadeFiles.shown(many, now: now)
        XCTAssertEqual(shown.count, LocalMadeFiles.limit)
        XCTAssertEqual(shown.first?.title, "File 5")
        XCTAssertEqual(shown.last?.title, "File 0")
    }

    func testAWeekExactlyIsStillKept() {
        XCTAssertFalse(LocalMadeFiles.isExpired(file("Edge", ageDays: 7), now: now))
        XCTAssertTrue(LocalMadeFiles.isExpired(file("Past", ageDays: 7.01), now: now))
    }

    func testRoundTripsThroughJSON() throws {
        let kept = file("Date ideas", ageDays: 0)
        let data = try JSONEncoder().encode([kept])
        XCTAssertEqual(try JSONDecoder().decode([LocalMadeFile].self, from: data), [kept])
        XCTAssertEqual(kept.label, "Deck")
    }

    func testPresentationReplyMentionsMessagesOnlyWhenKept() {
        let draft = PresentationDraft(title: "Date ideas", subtitle: nil, slides: [])
        XCTAssertFalse(VoiceToolReply.presentationMade(draft).contains("Messages"))
        XCTAssertTrue(VoiceToolReply.presentationMade(draft, inMessages: true).contains(LocalMadeFiles.inMessagesNote))
    }
}
