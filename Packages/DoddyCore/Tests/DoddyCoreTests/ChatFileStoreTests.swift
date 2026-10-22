import XCTest
@testable import DoddyCore

/// ADR-594: a file reaches the thread only as a verified copy inside the thread's own folder.
final class ChatFileStoreTests: XCTestCase {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chatfiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testACopyIsKeptWithItsRealSizeKindAndFolder() throws {
        let root = try scratch()
        let source = root.appendingPathComponent("Wyniki Q4.pptx")
        try Data(repeating: 7, count: 2048).write(to: source)
        let store = ChatFileStore(directory: root.appendingPathComponent("Messages"))
        let file = try store.keep(copyOf: source)
        XCTAssertEqual(file.name, "Wyniki Q4.pptx")
        XCTAssertEqual(file.kind, .presentation)
        XCTAssertEqual(file.bytes, 2048)
        XCTAssertTrue(file.relativePath.hasPrefix("Files/"))
        XCTAssertEqual(try Data(contentsOf: store.url(for: file)).count, 2048)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the original stays where it was")
    }

    func testAMissingSourceIsRefusedAndNothingIsMade() throws {
        let root = try scratch()
        let store = ChatFileStore(directory: root.appendingPathComponent("Messages"))
        XCTAssertThrowsError(try store.keep(copyOf: root.appendingPathComponent("nie ma.pdf"))) {
            XCTAssertEqual($0 as? ChatFileStore.Failure, .sourceMissing)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.filesDirectory.path))
    }

    func testACopyThatCannotBeWrittenIsNotKeptAndLeavesNothingBehind() throws {
        let root = try scratch()
        let source = root.appendingPathComponent("a.pdf")
        try Data("x".utf8).write(to: source)
        // A file where the thread's folder should be: the copy can't happen.
        let blocker = root.appendingPathComponent("Messages")
        try Data("x".utf8).write(to: blocker)
        let store = ChatFileStore(directory: blocker)
        XCTAssertThrowsError(try store.keep(copyOf: source)) { XCTAssertEqual($0 as? ChatFileStore.Failure, .notKept) }
    }

    func testAFileOverTheLimitIsRefusedAndNothingIsMade() throws {
        let root = try scratch()
        let store = ChatFileStore(directory: root.appendingPathComponent("Messages"))
        let big = Data(count: ChatFileStore.maxBytes + 1)
        XCTAssertThrowsError(try store.keep(data: big, named: "film.mov")) { XCTAssertEqual($0 as? ChatFileStore.Failure, .tooBig) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.filesDirectory.path))
    }

    func testBytesAreKeptTheSameWay() throws {
        let root = try scratch()
        let store = ChatFileStore(directory: root.appendingPathComponent("Messages"))
        let file = try store.keep(data: Data(repeating: 1, count: 300), named: "zdjęcie.jpg")
        XCTAssertEqual(file.kind, .image)
        XCTAssertEqual(file.bytes, 300)
        XCTAssertEqual(try Data(contentsOf: store.url(for: file)).count, 300)
    }

    func testANameCannotLeaveItsFolder() throws {
        XCTAssertEqual(ChatFileStore.safeName("../../etc/passwd"), "passwd")
        XCTAssertEqual(ChatFileStore.safeName("a\\b\\c.txt"), "c.txt")
        XCTAssertEqual(ChatFileStore.safeName("   "), "file")
        XCTAssertEqual(ChatFileStore.safeName("..."), "file")
    }

    func testDeleteAllRemovesEveryKeptFile() throws {
        let root = try scratch()
        let store = ChatFileStore(directory: root.appendingPathComponent("Messages"))
        _ = try store.keep(data: Data("a".utf8), named: "a.txt")
        _ = try store.keep(data: Data("b".utf8), named: "b.txt")
        try store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.filesDirectory.path))
        XCTAssertNoThrow(try store.deleteAll(), "nothing to delete is fine")
    }

    func testStepsCardShowsOnlyWhatTheIPhoneReported() {
        let full = ChatInfographic.steps(StepTotals(steps: 6240, distanceMeters: 4_712, floorsUp: 9), dayName: "Dziś", stepsWord: "kroków", distanceLabel: "Dystans", floorsLabel: "Piętra", source: "Z Ruchu i kondycji")
        XCTAssertEqual(full.headline, "6\u{00A0}240 kroków")
        XCTAssertEqual(full.rows.map(\.display), ["4.7 km", "9"])
        XCTAssertEqual(full.rows.map(\.label), ["Dystans", "Piętra"])
        XCTAssertEqual(full.barFractions, [0, 0], "different units are never drawn against each other")
        let bare = ChatInfographic.steps(StepTotals(steps: 12, distanceMeters: nil, floorsUp: nil), dayName: "Wczoraj", stepsWord: "kroków", distanceLabel: "D", floorsLabel: "P", source: "x")
        XCTAssertEqual(bare.headline, "12 kroków")
        XCTAssertTrue(bare.rows.isEmpty)
        XCTAssertEqual(ChatInfographic.spaced(1_234_567), "1\u{00A0}234\u{00A0}567")
        let short = ChatInfographic.steps(StepTotals(steps: 0, distanceMeters: 310, floorsUp: nil), dayName: "d", stepsWord: "s", distanceLabel: "D", floorsLabel: "P", source: "x")
        XCTAssertEqual(short.rows.map(\.display), ["310 m"])
    }

    func testALinkMessageSurvivesTheLogFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString)/messages.json")
        let log = ChatLogFile(url: url)
        let link = ChatMessage(sender: .doddy, content: .link(ChatLink(title: "Raport.docx", kind: "doc", url: URL(string: "https://example.com/r/1")!)))
        _ = try log.append(link)
        XCTAssertEqual(try log.load(), [link])
    }
}
