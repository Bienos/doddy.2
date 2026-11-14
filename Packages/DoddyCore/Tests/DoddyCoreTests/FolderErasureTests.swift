import Foundation
import XCTest
@testable import DoddyCore

/// The file side of "Erase everything on this iPhone": a folder's contents are removed and read back, a folder or
/// file that isn't there counts as already empty, and what can't be removed is reported, not hidden.
final class FolderErasureTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("FolderErasureTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Permissions a test took away are given back so the folder can be removed.
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? fileManager.removeItem(at: root)
    }

    private func write(_ name: String, in folder: URL? = nil, text: String = "x") throws -> URL {
        let directory = folder ?? root!
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testRemovesFilesAndNestedFoldersButKeepsTheFolder() throws {
        _ = try write("a.json")
        _ = try write("b.caf", in: root.appendingPathComponent("recording-1", isDirectory: true))
        _ = try write(".hidden")
        try FolderErasure.eraseContents(of: root)
        XCTAssertTrue(fileManager.fileExists(atPath: root.path), "the folder itself stays")
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), [])
        XCTAssertEqual(try FolderErasure.isEmpty(root), true)
    }

    func testAFolderThatIsNotThereIsAlreadyEmpty() throws {
        let missing = root.appendingPathComponent("never-made", isDirectory: true)
        XCTAssertNoThrow(try FolderErasure.eraseContents(of: missing))
        XCTAssertEqual(try FolderErasure.isEmpty(missing), true)
    }

    func testReadBackSeesWhatIsLeft() throws {
        _ = try write("kept.json")
        XCTAssertEqual(try FolderErasure.isEmpty(root), false)
    }

    func testNamesToKeepSurviveAndAreIgnoredByTheReadBack() throws {
        _ = try write("Library-like")
        _ = try write("note.json")
        try FolderErasure.eraseContents(of: root, keeping: ["Library-like"])
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), ["Library-like"])
        XCTAssertEqual(try FolderErasure.isEmpty(root, ignoring: ["Library-like"]), true)
        XCTAssertEqual(try FolderErasure.isEmpty(root), false)
    }

    func testRunningItTwiceIsHarmless() throws {
        _ = try write("a.json")
        try FolderErasure.eraseContents(of: root)
        XCTAssertNoThrow(try FolderErasure.eraseContents(of: root))
        XCTAssertEqual(try FolderErasure.isEmpty(root), true)
    }

    func testAFileIsRemovedAndAMissingFileIsFine() throws {
        let file = try write("trips-v1.json")
        try FolderErasure.eraseFile(file)
        XCTAssertFalse(fileManager.fileExists(atPath: file.path))
        XCTAssertNoThrow(try FolderErasure.eraseFile(file))
        XCTAssertTrue(FolderErasure.fileIsGone(file))
    }

    func testAFileThatIsStillThereIsNotGone() throws {
        let file = try write("still-here.json")
        XCTAssertFalse(FolderErasure.fileIsGone(file))
    }

    func testASymbolicLinkIsRemovedWithoutTouchingWhatItPointsAt() throws {
        let outside = fileManager.temporaryDirectory.appendingPathComponent("FolderErasureTests-outside-\(UUID().uuidString)")
        try Data("outside".utf8).write(to: outside)
        defer { try? fileManager.removeItem(at: outside) }
        try fileManager.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        try FolderErasure.eraseContents(of: root)
        XCTAssertEqual(try FolderErasure.isEmpty(root), true)
        XCTAssertTrue(fileManager.fileExists(atPath: outside.path), "only the link goes, never what it points at")
    }

    /// A file manager that refuses to remove one name, as a locked or busy file would.
    private final class StuckFileManager: FileManager, @unchecked Sendable {
        let stuck: String
        init(stuck: String) {
            self.stuck = stuck
            super.init()
        }

        override func removeItem(at URL: URL) throws {
            if URL.lastPathComponent == stuck { throw CocoaError(.fileWriteNoPermission) }
            try super.removeItem(at: URL)
        }
    }

    func testWhatCannotBeRemovedIsReportedAndTheRestIsStillRemoved() throws {
        _ = try write("stuck.json")
        _ = try write("free-1.json")
        _ = try write("free-2.json")
        let manager = StuckFileManager(stuck: "stuck.json")
        XCTAssertThrowsError(try FolderErasure.eraseContents(of: root, fileManager: manager)) { error in
            XCTAssertEqual(error as? FolderErasure.Failure, .couldNotRemove(1))
        }
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), ["stuck.json"], "the rest still went")
        XCTAssertEqual(try FolderErasure.isEmpty(root), false, "what stayed is seen by the read-back")
    }

    func testAFileThatCannotBeRemovedIsReported() throws {
        let file = try write("stuck.json")
        let manager = StuckFileManager(stuck: "stuck.json")
        XCTAssertThrowsError(try FolderErasure.eraseFile(file, fileManager: manager))
        XCTAssertFalse(FolderErasure.fileIsGone(file))
    }
}
