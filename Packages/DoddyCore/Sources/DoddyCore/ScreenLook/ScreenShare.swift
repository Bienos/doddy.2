import Foundation

/// "Doddy, what's this on my screen?" (decision 2026-11-09-doddy-looks-at-the-screen).
///
/// The person starts iOS screen broadcasting to Doddy themselves (the system "Start Broadcast" sheet; no app
/// can start it for them, and iOS shows that the screen is being shared). While it runs, Doddy's broadcast
/// extension keeps **one** small picture of the screen in the App Group folder, replaced about once a second,
/// and a state file that says sharing is on. Nothing leaves the iPhone until the person asks about the screen
/// in a voice conversation and says yes (ASK-01): then the app sends that one picture to Doddy's server, which
/// asks Claude and keeps nothing. When sharing stops, the extension deletes the picture.
///
/// This file is the contract between the extension and the app, as rules tested on Linux: the file names, the
/// sizes, and when a picture is fresh enough to count as "the screen now".
public enum ScreenShare {
    /// The voice tool (`voice-agent/tools.json`).
    public static let toolName = "look_at_screen"
    /// The one picture, a JPEG, in the App Group folder.
    public static let frameFileName = "screen-frame.jpg"
    /// `ScreenShareState`, JSON, in the App Group folder.
    public static let stateFileName = "screen-share.json"
    /// The largest picture the extension writes and the app sends (the server takes up to 1,000,000 base64 bytes).
    public static let maxFrameBytes = 750_000
    /// The picture's long edge in pixels: text on an iPhone screen stays readable, the file stays small.
    public static let frameLongEdge = 1_280
    /// How often the extension replaces the picture, at most.
    public static let frameInterval: TimeInterval = 1
    /// A picture older than this is not "the screen now" (sharing froze, or the extension was stopped by iOS).
    public static let freshFor: TimeInterval = 10
    /// The server refuses a frame older than this.
    public static let serverMaxAge: TimeInterval = 30
    /// The broadcast extension's bundle id suffix, after the app's own id.
    public static let extensionBundleSuffix = ".screen"
}

extension VoiceToolName {
    /// "What's on my screen?" (decision 2026-11-09-doddy-looks-at-the-screen).
    public static let lookAtScreen = ScreenShare.toolName
}

/// What the extension writes next to the picture. `live` false (or no file) means sharing is off.
public struct ScreenShareState: Codable, Equatable, Sendable {
    public var live: Bool
    public var startedAt: Date
    /// When the picture on disk was captured; nil before the first one.
    public var frameAt: Date?
    /// The picture's size in bytes, as written.
    public var frameBytes: Int?

    public init(live: Bool, startedAt: Date, frameAt: Date? = nil, frameBytes: Int? = nil) {
        self.live = live
        self.startedAt = startedAt
        self.frameAt = frameAt
        self.frameBytes = frameBytes
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data) -> ScreenShareState? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(ScreenShareState.self, from: data)
    }
}

/// Whether there is a picture of the screen to look at right now.
public enum ScreenLookReadiness: Equatable, Sendable {
    /// A fresh picture: send it.
    case ready(frameAge: TimeInterval)
    /// Sharing is off (or was never started).
    case notSharing
    /// Sharing started but no picture arrived yet.
    case noFrameYet
    /// Sharing says it is on, but the newest picture is too old to be the screen now.
    case stale(frameAge: TimeInterval)
    /// The file on disk is empty, too large or not what the state says.
    case unreadable

    /// - Parameters:
    ///   - state: the state file, nil when there is none or it can't be read.
    ///   - frameBytes: the picture file's actual size, nil when there is no file.
    public static func check(state: ScreenShareState?, frameBytes: Int?, now: Date) -> ScreenLookReadiness {
        guard let state, state.live else { return .notSharing }
        guard let frameAt = state.frameAt, let frameBytes else { return .noFrameYet }
        guard frameBytes > 0, frameBytes <= ScreenShare.maxFrameBytes, frameBytes == state.frameBytes else { return .unreadable }
        let age = max(0, now.timeIntervalSince(frameAt))
        // A clock that went backwards a lot is not trusted as fresh either.
        guard age <= ScreenShare.freshFor, now.timeIntervalSince(frameAt) > -ScreenShare.freshFor else { return .stale(frameAge: age) }
        return .ready(frameAge: age)
    }
}

/// Whether Home says the screen is shared with Doddy: the "Show screen" capsule turns into "Screen shared", and
/// after the conversation a small mark stays in Home's header so the person can stop it (owner review, 13 Nov 2026).
/// iOS shows its own indicator too; this one only says what the extension's state file says, and stops saying it
/// when that file goes quiet, so an extension iOS ended without a word is never shown as sharing for long.
public enum ScreenShareIndicator {
    /// iOS sends the extension no new picture while the screen doesn't change, so this is longer than
    /// `ScreenShare.freshFor`: a still screen keeps counting as shared for two minutes after its last picture.
    public static let shownFor: TimeInterval = 120

    public static func isSharing(_ state: ScreenShareState?, now: Date) -> Bool {
        guard let state, state.live else { return false }
        let age = now.timeIntervalSince(state.frameAt ?? state.startedAt)
        // A clock that went backwards a lot is not trusted either (as in `ScreenLookReadiness`).
        return age <= shownFor && age > -ScreenShare.freshFor
    }
}

/// The size the extension scales a screen to: the long edge at most `ScreenShare.frameLongEdge`, never larger
/// than the screen, whole pixels, aspect kept.
public enum ScreenFrameSize {
    public static func scaled(width: Int, height: Int, longEdge: Int = ScreenShare.frameLongEdge) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        let long = max(width, height)
        guard long > longEdge else { return (width, height) }
        let factor = Double(longEdge) / Double(long)
        return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
    }
}
