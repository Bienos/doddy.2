import Foundation
import XCTest

/// Reads the iPhone app's Swift sources from the repository, for tests that guard a rule across files (the same way
/// `FileProtectionInventoryTests` does). The paused Watch and Mac apps are left out. Skips when the package is
/// built without the app next to it.
enum AppSourceScan {
    /// Folders of Swift sources of the iPhone app and what it ships with.
    static let roots = [
        "DoddyApp", "Shared", "DoddyWidgets", "DoddyShare", "DoddyScreen", "DoddyNotificationContent",
        "Packages/DoddyCore/Sources",
    ]

    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    struct SourceFile {
        let path: String
        let text: String
    }

    static func swiftFiles() throws -> [SourceFile] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: repoRoot.appendingPathComponent("DoddyApp").path) else {
            throw XCTSkip("The app's sources are not next to this package.")
        }
        var found: [SourceFile] = []
        for root in roots {
            let base = repoRoot.appendingPathComponent(root)
            guard let walker = fileManager.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let relative = String(url.standardizedFileURL.path.dropFirst(repoRoot.standardizedFileURL.path.count + 1))
                found.append(SourceFile(path: relative, text: (try? String(contentsOf: url, encoding: .utf8)) ?? ""))
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// One file of the repository (any type), or nil.
    static func text(of relativePath: String) -> String? {
        try? String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
