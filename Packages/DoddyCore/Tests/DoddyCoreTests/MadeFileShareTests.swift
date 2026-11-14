import XCTest
@testable import DoddyCore

final class MadeFileShareTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_300_000)
    private let id = "abcdefghijklmnopqrstuvwx"

    private func document(_ status: MadeDocument.Status, deleteAfter: TimeInterval = 86_400) -> MadeDocument {
        MadeDocument(id: id, name: "Warszawa.pptx", kind: .deck, status: status,
                     createdAt: now.addingTimeInterval(-60), deleteAfter: now.addingTimeInterval(deleteAfter), sizeBytes: 10)
    }

    private var link: URL { URL(string: "https://doddy.example/v1/documents/\(id)?exp=1&sig=x")! }

    func testAReadyFileIsShared() {
        XCTAssertEqual(MadeFileShare.lookup(link: link, in: [document(.ready)], now: now), .ready(document(.ready)))
    }

    func testAFileStillBeingMadeSaysSo() {
        XCTAssertEqual(MadeFileShare.lookup(link: link, in: [document(.working)], now: now), .making)
        XCTAssertEqual(MadeFileShare.lookup(link: link, in: [document(.interrupted)], now: now), .failed)
        XCTAssertEqual(MadeFileShare.lookup(link: link, in: [document(.failed)], now: now), .failed)
    }

    func testAFileTheServerNoLongerKeepsIsGone() {
        XCTAssertEqual(MadeFileShare.lookup(link: link, in: [], now: now), .gone)
        XCTAssertEqual(MadeFileShare.lookup(link: link, in: [document(.ready, deleteAfter: -1)], now: now), .gone)
        XCTAssertEqual(MadeFileShare.lookup(link: URL(string: "https://example.com/file.pdf")!, in: [document(.ready)], now: now), .gone)
    }
}
