import Foundation
import XCTest
@testable import DoddyCore

/// Which files the iPhone app, its widgets and extensions keep readable while the iPhone is locked.
///
/// iOS protects a file in one of a few classes. "Complete" means it can't be read or written while the iPhone is
/// locked. "Until first user authentication" means it can be, from the first unlock after a restart onwards. A
/// file holding conversations, transcripts or notes should be "complete" unless something that runs while the
/// iPhone is locked has to read or write it. This test reads the sources and fails when a file starts using the
/// weaker class without an entry below that says why, or when an entry stops being true. The weaker class is
/// the one that Apple names in code as `...UntilFirstUserAuthentication`.
///
/// Platforms: iPhone (the app, the widgets, the share and screen extensions). The Watch and Mac apps are paused.
final class FileProtectionInventoryTests: XCTestCase {
    /// path (from the repository root) → why it stays readable while the iPhone is locked.
    static let readableWhileLocked: [String: String] = [
        "DoddyApp/Infrastructure/AppEnvironment.swift":
            "The database folder (notes, lists, the Messages thread, recordings' words, call cases, errands, what Doddy learned). "
            + "Siri and Shortcuts, reminders, and a push that saves a finished task into Messages in the background read and write it "
            + "while the iPhone is locked, and a voice conversation goes on after the screen locks. SQLite's write-ahead log needs the same class.",
        "DoddyApp/Infrastructure/ConversationLogStore.swift":
            "Written when a voice conversation ends, which can be after the screen locked; read when the next one starts, which can be a background launch.",
        "DoddyApp/Infrastructure/ActivityLogStore.swift":
            "Tools write what they did while a conversation goes on, including after the screen locked.",
        "DoddyApp/Features/Photos/PhotoFiles.swift":
            "A note's photo, beside the database: it must be readable whenever its note is.",
        "DoddyApp/Features/VoiceMemos/AudioFiles.swift":
            "A note's voice memo, beside the database: it must be readable whenever its note is.",
        "DoddyApp/Features/Recordings/RecordingFiles.swift":
            "Recordings, beside the database: a recording goes on while the screen is locked (the audio background mode).",
        "DoddyApp/Features/Recordings/RecordingCoordinator.swift":
            "The part of a recording that is being written: it started before the iPhone locked and keeps being written.",
        "DoddyApp/Features/Messages/LocalMadeFilesStore.swift":
            "Files Doddy made, saved when the finished task's push arrives in the background.",
        "DoddyApp/Features/Sport/TrainingLogDatabase.swift":
            "A SQLite database like the main one: with the complete class a connection opened before the iPhone locked can fail its next read, "
            + "so databases use the first-unlock class. Only the training log's own screens read it.",
        "DoddyApp/Features/Spotlight/SpotlightSync.swift":
            "The Spotlight index of notes, updated when notes change, which can be during a conversation after the screen locked. "
            + "Open question for the owner: a stricter class would hide the index while locked, and notes saved while locked would appear after the next unlock.",
        "Packages/DoddyCore/Sources/DoddyCore/Travel/TripStore.swift":
            "Trips found in booking emails; only the Trips screens read it. Kept at the first-unlock class so a search that ends after the "
            + "screen locked can still save (a failed save would be shown, never hidden). A candidate for the complete class if the owner accepts that.",
        "Shared/Widgets/WidgetSnapshotFile.swift":
            "Widgets read it on a locked iPhone's Lock Screen. With the Face ID lock on it holds nothing of the person's (`WidgetSnapshot.make(appLockOn:)`).",
    ]

    /// Folders of Swift sources of the iPhone app and what it ships with. The paused Watch and Mac apps are left out.
    private static let roots = [
        "DoddyApp", "Shared", "DoddyWidgets", "DoddyShare", "DoddyScreen", "DoddyNotificationContent",
        "Packages/DoddyCore/Sources",
    ]

    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func swiftFiles() throws -> [(path: String, text: String)] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: repoRoot.appendingPathComponent("DoddyApp").path) else {
            throw XCTSkip("The app's sources are not next to this package.")
        }
        var found: [(String, String)] = []
        for root in Self.roots {
            let base = repoRoot.appendingPathComponent(root)
            guard let walker = fileManager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative = String(url.standardizedFileURL.path.dropFirst(repoRoot.standardizedFileURL.path.count + 1))
                found.append((relative, (try? String(contentsOf: url, encoding: .utf8)) ?? ""))
            }
        }
        return found
    }

    private static let weakerClass = "UntilFirstUserAuthentication"

    func testOnlyTheListedFilesUseTheWeakerClassAndEachHasAReason() throws {
        let using = try swiftFiles().filter { $0.text.contains(Self.weakerClass) }.map(\.path)
        let unlisted = using.filter { Self.readableWhileLocked[$0] == nil }
        XCTAssertEqual(unlisted, [],
                       "These files use the weaker protection class with no entry in `readableWhileLocked`. Use the complete class "
                       + "(`.completeFileProtection`) unless something that runs while the iPhone is locked has to read or write the file, "
                       + "and if so add the file here with the reason.")
    }

    func testEveryListedFileStillUsesTheWeakerClass() throws {
        let files = try swiftFiles()
        for (path, reason) in Self.readableWhileLocked {
            guard let file = files.first(where: { $0.path == path }) else {
                XCTFail("\(path) is listed but no longer exists: remove its entry")
                continue
            }
            XCTAssertTrue(file.text.contains(Self.weakerClass), "\(path) no longer uses the weaker class: remove its entry")
            XCTAssertGreaterThan(reason.count, 30, "\(path) needs a real reason")
        }
    }

    /// Files made only to be shared, and drafts, hold text that may carry codes and addresses: complete class.
    func testFilesMadeForSharingAndDraftsUseTheCompleteClass() throws {
        let files = try swiftFiles()
        for path in [
            "Packages/DoddyCore/Sources/DoddyCore/TemporaryShareFiles.swift",
            "Packages/DoddyCore/Sources/DoddyCore/Invoices/InvoiceDraftFile.swift",
            "DoddyApp/Infrastructure/UnfinishedNoteStore.swift",
            "DoddyApp/Features/Files/CallRecapSection.swift",
            "DoddyApp/Features/Files/FilesView.swift",
            "Shared/Share/ShareInboxFile.swift",
        ] {
            let file = try XCTUnwrap(files.first(where: { $0.path == path }), "\(path) moved: update this list")
            XCTAssertTrue(file.text.contains("completeFileProtection"), "\(path) should write with the complete class")
            XCTAssertFalse(file.text.contains(Self.weakerClass), "\(path) should not use the weaker class")
        }
    }

    /// The recording's transcript export used the weaker class in the temporary folder; it goes through the share folder now.
    func testTheTranscriptExportGoesThroughTheShareFolder() throws {
        let files = try swiftFiles()
        let detail = try XCTUnwrap(files.first(where: { $0.path == "DoddyApp/Features/Recordings/RecordingDetailView.swift" }))
        XCTAssertTrue(detail.text.contains("TemporaryShareFiles.write"))
        XCTAssertFalse(detail.text.contains("temporaryDirectory"), "a transcript is not written to the temporary folder by hand")
    }
}
