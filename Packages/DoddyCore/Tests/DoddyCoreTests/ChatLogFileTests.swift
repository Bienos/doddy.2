import XCTest
@testable import DoddyCore

/// ADR-582: the Messages thread is kept on disk, verified, bounded and deletable.
final class ChatLogFileTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("chatlog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("messages.json")
    }

    private func text(_ s: String, from sender: ChatMessage.Sender = .user, at date: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> ChatMessage {
        ChatMessage(sentAt: date, sender: sender, content: .text(s))
    }

    func testMissingFileIsAnEmptyThread() throws {
        XCTAssertEqual(try ChatLogFile(url: tempURL()).load(), [])
    }

    func testAppendThenLoadKeepsEveryKindOfMessage() throws {
        let log = ChatLogFile(url: tempURL())
        let file = ChatMessage(sender: .doddy, content: .file(ChatFile(name: "Wyniki Q4.pptx", kind: .presentation, bytes: 2_400_000, relativePath: "Files/q4.pptx")))
        let chart = ChatMessage(sender: .doddy, content: .infographic(ChatInfographic(
            title: "Październik", headline: "1 960 zł",
            rows: [.init(label: "Jedzenie", value: 820, display: "820 zł"), .init(label: "Rachunki", value: 640, display: "640 zł")])))
        let hello = text("Cześć")
        _ = try log.append(hello)
        _ = try log.append(file)
        _ = try log.append(chart)
        XCTAssertEqual(try log.load(), [hello, file, chart])
    }

    func testTheSameMessageIsNotKeptTwice() throws {
        let log = ChatLogFile(url: tempURL())
        let m = text("raz")
        _ = try log.append(m)
        _ = try log.append(m)
        XCTAssertEqual(try log.load().count, 1)
    }

    func testOnlyTheNewestMessagesAreKeptPastTheLimit() throws {
        let log = ChatLogFile(url: tempURL(), limit: 3)
        for i in 1...5 { _ = try log.append(text("m\(i)")) }
        XCTAssertEqual(try log.load().compactMap(\.text), ["m3", "m4", "m5"])
    }

    func testAWriteThatCannotBeKeptThrowsAndNothingIsClaimed() throws {
        // A file where the directory should be: the write can't happen.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        let log = ChatLogFile(url: blocker.appendingPathComponent("messages.json"))
        XCTAssertThrowsError(try log.append(text("nie zapisze się"))) {
            XCTAssertEqual($0 as? ChatLogFile.Failure, .notKept)
        }
    }

    func testAnUnreadableFileIsAnErrorNotAnEmptyThread() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let log = ChatLogFile(url: url)
        XCTAssertThrowsError(try log.load()) { XCTAssertEqual($0 as? ChatLogFile.Failure, .unreadable) }
        XCTAssertThrowsError(try log.append(text("x")), "a bad file is never overwritten by the next message")
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), "not json")
    }

    func testDeleteAllRemovesTheFile() throws {
        let log = ChatLogFile(url: tempURL())
        _ = try log.append(text("x"))
        try log.deleteAll()
        XCTAssertEqual(try log.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.url.path))
        XCTAssertNoThrow(try log.deleteAll(), "deleting an empty thread is fine")
    }

    func testUnreadCountsOnlyDoddysMessagesAfterTheLastLook() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let thread = [
            text("a", from: .doddy, at: t0), text("b", from: .user, at: t0.addingTimeInterval(10)),
            text("c", from: .doddy, at: t0.addingTimeInterval(20)), text("d", from: .doddy, at: t0.addingTimeInterval(30))]
        XCTAssertEqual(thread.unreadCount(since: nil), 3)
        XCTAssertEqual(thread.unreadCount(since: t0.addingTimeInterval(15)), 2)
        XCTAssertEqual(thread.unreadCount(since: t0.addingTimeInterval(30)), 0)
    }

    func testInfographicBarsAreRelativeToTheLongest() {
        let chart = ChatInfographic(title: "t", headline: "h", rows: [
            .init(label: "a", value: 820, display: ""), .init(label: "b", value: 410, display: ""), .init(label: "c", value: -5, display: "")])
        XCTAssertEqual(chart.barFractions, [1, 0.5, 0])
        XCTAssertEqual(ChatInfographic(title: "t", headline: "h", rows: []).barFractions, [])
    }

    func testFileKindFromTheName() {
        XCTAssertEqual(ChatFile.kind(forFileName: "Q4.PPTX"), .presentation)
        XCTAssertEqual(ChatFile.kind(forFileName: "raport.pdf"), .pdf)
        XCTAssertEqual(ChatFile.kind(forFileName: "dane.xlsx"), .spreadsheet)
        XCTAssertEqual(ChatFile.kind(forFileName: "zdjęcie.heic"), .image)
        XCTAssertEqual(ChatFile.kind(forFileName: "plik"), .other)
    }
}
