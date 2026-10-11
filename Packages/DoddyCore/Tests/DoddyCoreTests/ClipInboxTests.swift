import XCTest
@testable import DoddyCore

/// The Mac clip inbox and Safari clips (ADR-352, ADR-353).
final class ClipInboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("clip-inbox-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func item(_ text: String, at offset: TimeInterval = 0) -> ShareInboxItem {
        ShareInboxItem(text: text, sharedAt: now.addingTimeInterval(offset))
    }

    func testSeveralClipsWaitOldestFirstAndNoneReplacesAnother() throws {
        let inbox = ClipInbox(directory: folder)
        let a = item("First", at: -20), b = item("Second", at: -10), c = item("Third", at: 0)
        for clip in [c, a, b] { XCTAssertEqual(try inbox.add(clip, now: now), .added) }
        XCTAssertEqual(inbox.waiting(now: now).map(\.text), ["First", "Second", "Third"])
        XCTAssertTrue(inbox.remove(id: b.id))
        XCTAssertEqual(inbox.waiting(now: now).map(\.text), ["First", "Third"])
    }

    func testTheInboxFillsUpAndSaysSo() throws {
        let inbox = ClipInbox(directory: folder)
        for index in 0..<ClipInbox.maxWaiting { XCTAssertEqual(try inbox.add(item("clip \(index)", at: Double(index)), now: now), .added) }
        XCTAssertEqual(try inbox.add(item("one too many"), now: now), .full)
        XCTAssertEqual(inbox.waiting(now: now).count, ClipInbox.maxWaiting)
    }

    func testStaleAndUnreadableFilesAreDroppedOthersLeftAlone() throws {
        let inbox = ClipInbox(directory: folder)
        _ = try inbox.add(item("fresh"), now: now)
        let old = item("old", at: -(ShareInboxItem.keptFor + 60))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try old.encoded().write(to: inbox.fileURL(for: old.id))
        try Data("not json".utf8).write(to: folder.appendingPathComponent("broken.clip"))
        let other = folder.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: other)
        XCTAssertEqual(inbox.waiting(now: now).map(\.text), ["fresh"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("broken.clip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "files that aren't clips are never touched")
    }

    func testSafariClipWithASelectionKeepsTheSelectionTitleAndLink() throws {
        let clip = try XCTUnwrap(WebClip(title: " Kebab\nrecipe ", address: "https://example.com/r?a=1", selection: "  2 cups of flour "))
        let saved = try XCTUnwrap(clip.item(sharedAt: now))
        XCTAssertEqual(saved.text, "2 cups of flour\n\n\u{2014} Kebab recipe\nhttps://example.com/r?a=1")
    }

    func testSafariClipWithoutASelectionIsTheTitleAndLink() throws {
        let clip = try XCTUnwrap(WebClip(title: "Train times", address: "https://example.com/trains", selection: ""))
        XCTAssertEqual(clip.item(sharedAt: now)?.text, "Train times\nhttps://example.com/trains")
    }

    func testOnlyWebAddressesAreKeptAsLinks() throws {
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "safari-web-extension://x/y", "about:blank", "ftp://example.com/a", "https://"] {
            let clip = try XCTUnwrap(WebClip(title: "T", address: bad, selection: nil), bad)
            XCTAssertEqual(clip.address, "", bad)
            XCTAssertEqual(clip.item(sharedAt: now)?.text, "T", bad)
        }
        XCTAssertNil(WebClip(title: "  ", address: "about:blank", selection: nil), "nothing to keep")
    }

    func testMessageFromSafariIgnoresWrongTypesAndLimitsLengths() throws {
        let clip = try XCTUnwrap(WebClip(message: ["title": 7, "url": "https://example.com", "selection": String(repeating: "a", count: 20_000), "extra": "x"]))
        XCTAssertEqual(clip.title, "")
        XCTAssertEqual(clip.selection.count, WebClip.maxSelection)
        XCTAssertNil(WebClip(message: [:]))
        XCTAssertNil(WebClip(message: ["title": ["a"], "url": 5]))
    }
}
