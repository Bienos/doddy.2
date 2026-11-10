import DoddyCore
import Foundation

/// Where the screen-sharing extension leaves the one picture of the screen and its state (decision
/// 2026-11-09-doddy-looks-at-the-screen), in the App Group folder the widgets and "Save to Doddy" use. Compiled
/// into the app and the `DoddyScreen` broadcast extension. A build signed without the App Group has no folder:
/// the extension then writes nothing and the app hears "not sharing".
enum ScreenShareFiles {
    static var folder: URL? {
        #if canImport(Darwin)
        guard let id = Bundle.main.object(forInfoDictionaryKey: "DoddyAppGroup") as? String,
              id.hasPrefix("group."), !id.contains("$(") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        #else
        return nil // App Groups exist only on Apple platforms; this branch is for the Linux type-check.
        #endif
    }

    static var frameURL: URL? { folder?.appendingPathComponent(ScreenShare.frameFileName, isDirectory: false) }
    static var stateURL: URL? { folder?.appendingPathComponent(ScreenShare.stateFileName, isDirectory: false) }

    // MARK: Written by the extension

    /// The picture first, then the state that names its size, so the app never takes a half-written picture
    /// as the screen (`ScreenLookReadiness.unreadable` when the two disagree).
    static func writeFrame(_ jpeg: Data, capturedAt: Date, startedAt: Date) throws {
        guard let frameURL, let stateURL else { throw CocoaError(.fileNoSuchFile) }
        try jpeg.write(to: frameURL, options: Self.writeOptions)
        let state = ScreenShareState(live: true, startedAt: startedAt, frameAt: capturedAt, frameBytes: jpeg.count)
        try state.encoded().write(to: stateURL, options: Self.writeOptions)
    }

    static func markStarted(at date: Date) throws {
        guard let stateURL else { throw CocoaError(.fileNoSuchFile) }
        if let frameURL { try? FileManager.default.removeItem(at: frameURL) }
        try ScreenShareState(live: true, startedAt: date).encoded().write(to: stateURL, options: Self.writeOptions)
    }

    /// Sharing ended (or was paused): the picture is deleted, so nothing of the screen stays on disk.
    static func markEnded() {
        if let frameURL { try? FileManager.default.removeItem(at: frameURL) }
        if let stateURL { try? FileManager.default.removeItem(at: stateURL) }
    }

    // MARK: Read by the app

    /// Whether there is a fresh picture, and its bytes when there is.
    static func current(now: Date = Date()) -> (readiness: ScreenLookReadiness, jpeg: Data?) {
        let state = stateURL.flatMap { try? Data(contentsOf: $0) }.flatMap(ScreenShareState.decoded)
        let jpeg = frameURL.flatMap { try? Data(contentsOf: $0) }
        let readiness = ScreenLookReadiness.check(state: state, frameBytes: jpeg?.count, now: now)
        if case .ready = readiness { return (readiness, jpeg) }
        return (readiness, nil)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        // Readable while the iPhone is unlocked only; the extension runs only while the person shares.
        [.atomic, .completeFileProtectionUnlessOpen]
        #else
        [.atomic]
        #endif
    }
}
