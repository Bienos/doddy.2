import XCTest
@testable import DoddyCore

/// A file made only to be handed to the share sheet (a transcript, a history) lives in one folder of its own in
/// the temporary directory, one sub-folder per file, and is deleted when the share ends; whatever a closed app
/// left behind is swept the next time.
final class TemporaryShareFilesTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("share-files-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func make(_ text: String = "words", title: String = "Standup") throws -> URL {
        try TemporaryShareFiles.write(Data(text.utf8), title: title, fileExtension: "md", fallback: "Recording", in: base)
    }

    // MARK: Writing

    func testTheFileIsWrittenUnderTheShareFolderInItsOwnSubfolder() throws {
        let url = try make("hello")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
        XCTAssertEqual(url.lastPathComponent, "Standup.md")
        let folder = TemporaryShareFiles.folder(in: base)
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path, folder.standardizedFileURL.path)
    }

    func testTwoFilesWithTheSameTitleDoNotReplaceEachOther() throws {
        let first = try make("one")
        let second = try make("two")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "two")
    }

    func testTheFileNameIsMadeSafe() {
        func name(_ title: String) -> String { TemporaryShareFiles.fileName(for: title, fileExtension: "md", fallback: "Recording") }
        XCTAssertEqual(name("Standup 12/11"), "Standup 1211.md", "no path separators")
        XCTAssertEqual(name("a\\b:c*d?e\"f<g>h|i"), "abcdefghi.md")
        XCTAssertEqual(name("  Notes  "), "Notes.md")
        XCTAssertEqual(name("../../etc"), "etc.md", "no way out of the folder")
        XCTAssertEqual(name(".hidden"), "hidden.md")
        XCTAssertEqual(name("line\none\ttab"), "lineonetab.md", "no control characters")
        XCTAssertEqual(name(""), "Recording.md")
        XCTAssertEqual(name("///"), "Recording.md")
        XCTAssertEqual(name("Spotkanie z Anią — plan"), "Spotkanie z Anią — plan.md", "other scripts and punctuation stay")
        XCTAssertLessThanOrEqual(name(String(repeating: "x", count: 500)).count, TemporaryShareFiles.maxNameLength + 3)
    }

    // MARK: Deleting

    func testRemoveDeletesTheFileAndItsSubfolderAndNothingElse() throws {
        let kept = try make("keep", title: "Other")
        let gone = try make("drop")
        XCTAssertTrue(TemporaryShareFiles.remove(gone, in: base))
        XCTAssertFalse(exists(gone))
        XCTAssertFalse(exists(gone.deletingLastPathComponent()), "its own folder goes too")
        XCTAssertTrue(exists(kept), "another export is left alone")
    }

    func testRemoveOfAFileAlreadyGoneIsStillDone() throws {
        let url = try make()
        XCTAssertTrue(TemporaryShareFiles.remove(url, in: base))
        XCTAssertTrue(TemporaryShareFiles.remove(url, in: base))
    }

    func testRemoveNeverTouchesAFileOutsideTheShareFolder() throws {
        let outside = base.appendingPathComponent("not-ours.txt")
        try Data("x".utf8).write(to: outside)
        XCTAssertFalse(TemporaryShareFiles.remove(outside, in: base), "refused, and says so")
        XCTAssertTrue(exists(outside))
        let sibling = TemporaryShareFiles.folder(in: base).appendingPathComponent("../not-ours.txt")
        XCTAssertFalse(TemporaryShareFiles.remove(sibling, in: base))
        XCTAssertTrue(exists(outside))
    }

    func testRemoveAllSweepsEveryLeftoverAndIsSafeWhenThereIsNone() throws {
        XCTAssertTrue(TemporaryShareFiles.removeAll(in: base), "no folder yet is fine")
        let a = try make("a", title: "A")
        let b = try make("b", title: "B")
        XCTAssertTrue(TemporaryShareFiles.removeAll(in: base))
        XCTAssertFalse(exists(a))
        XCTAssertFalse(exists(b))
        XCTAssertFalse(exists(TemporaryShareFiles.folder(in: base)))
        XCTAssertTrue(exists(base), "only the share folder goes, never the temporary directory itself")
    }
}
