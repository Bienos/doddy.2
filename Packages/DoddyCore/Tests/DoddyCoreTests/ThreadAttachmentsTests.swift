import XCTest

@testable import DoddyCore

final class ThreadAttachmentsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func id(_ n: Int) -> String { String(repeating: "a", count: 23) + String(n % 10) }

    private func document(
        _ n: Int, status: MadeDocument.Status = .ready, age: TimeInterval = 100, keptFor: TimeInterval = 3_600
    ) -> MadeDocument {
        MadeDocument(
            id: id(n), name: "File \(n)", kind: .deck, status: status, createdAt: now.addingTimeInterval(-age),
            deleteAfter: now.addingTimeInterval(keptFor), sizeBytes: 10)
    }

    func testTheIdIsReadFromAnyServerLinkOfTheRightShapeOnly() {
        let good = URL(string: "https://doddy.example/v1/documents/\(id(1))?exp=1&sig=x")!
        XCTAssertEqual(ThreadAttachments.documentID(of: good), id(1))
        XCTAssertNil(ThreadAttachments.documentID(of: URL(string: "https://doddy.example/v1/documents/short")!))
        XCTAssertNil(ThreadAttachments.documentID(of: URL(string: "https://doddy.example/other/documents/\(id(1))")!))
        XCTAssertNil(ThreadAttachments.documentID(of: URL(string: "https://doddy.example/v1/documents/\(id(1))/x")!))
    }

    func testOnlyReadyFilesThatAreStillKeptAreShown() {
        let list = [
            document(1), document(2, status: .working), document(3, status: .failed),
            document(4, status: .interrupted), document(5, keptFor: -1),
        ]
        XCTAssertEqual(ThreadAttachments.shown(documents: list, thread: [], now: now).map(\.id), [id(1)])
    }

    func testAFileAlreadyInTheThreadIsNotShownTwice() {
        let link = URL(string: "https://doddy.example/v1/documents/\(id(1))?exp=1&sig=x")!
        let bubble = ThreadMessage.file(ThreadDocument(url: link, name: "File 1", kind: "deck"), now: now)
        let shown = ThreadAttachments.shown(documents: [document(1), document(2)], thread: [bubble], now: now)
        XCTAssertEqual(shown.map(\.id), [id(2)])
    }

    func testTheNewestFewAreShownOldestFirst() {
        let list = (0..<9).map { document($0, age: TimeInterval(1_000 - $0 * 100)) }
        let shown = ThreadAttachments.shown(documents: list, thread: [], now: now)
        XCTAssertEqual(shown.count, ThreadAttachments.limit)
        XCTAssertEqual(shown, shown.sorted { $0.createdAt < $1.createdAt })
        XCTAssertFalse(shown.contains { $0.id == id(0) })
    }
}
