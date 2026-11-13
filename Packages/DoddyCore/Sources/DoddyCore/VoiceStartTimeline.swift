import Foundation

/// The stages between pressing Talk (or the Action Button) and the conversation connecting, with how
/// long each took. It exists to answer one question from a phone log (owner, 10 Nov 2026: Doddy is
/// slow to start): where do the seconds go? Decision `2026-11-10-voice-start-timing`.
///
/// Privacy: stage names are a fixed set of words and the rest is seconds. Nothing said, saved or
/// typed, no account, token or address can appear in a line.
public enum VoiceStartStage: String, CaseIterable, Sendable {
    /// From the press to the island being asked for (decision `2026-11-13-island-first`): the checks that
    /// need nothing but the iPhone. Before the stages below, which used to come before the island.
    case islandShown = "island shown"
    /// Restoring the Doddy voice session (may refresh the login over the network).
    case account
    /// Loading the saved profile when iOS started Doddy just for this press.
    case profile
    /// The conversation's own Live Activity and the audio session are up (since 13 Nov the island itself is
    /// already showing, `islandShown`). This is what the Action Button's intent waits for; the connect stage then runs on after the intent has returned (decision
    /// `2026-11-10-action-button-start`).
    case island
    /// Getting the voice token, joining the ElevenLabs room and the start of the conversation. The token
    /// request is also logged on its own, inside this stage, by `VoiceTokenClient`.
    case connect
}

/// Where a start's voice token came from. The only thing about the token that is ever logged.
public enum VoiceTokenSource: String, Sendable {
    /// Fetched ahead of time (`VoiceTokenShelf`).
    case shelf = "token shelf"
    /// A press joined the fetch ahead that was still running, without a second request.
    case warming = "token warming"
    /// Fetched at the press.
    case fetched = "token fetched"
}

public struct VoiceStartTimeline: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let stage: VoiceStartStage
        public let seconds: Double
    }

    public private(set) var entries: [Entry] = []
    private let startedAt: Double
    private var lastMark: Double

    /// `startedAt` and every `now` are readings of one monotonic clock in seconds
    /// (`ProcessInfo.systemUptime` in the app), so a changed wall clock can't skew them.
    public init(startedAt: Double) {
        self.startedAt = startedAt
        self.lastMark = startedAt
    }

    /// Ends `stage`, which began at the last mark (or the start).
    public mutating func mark(_ stage: VoiceStartStage, at now: Double) {
        entries.append(Entry(stage: stage, seconds: Self.clamped(now - lastMark)))
        lastMark = now
    }

    public func total(at now: Double) -> Double { Self.clamped(now - startedAt) }

    /// "account 0.31 s · profile 0.02 s · connect 2.40 s · total 2.73 s"
    /// With `token`, the fixed word for where the token came from is added at the end.
    public func line(at now: Double, token: VoiceTokenSource? = nil) -> String {
        (entries.map { "\($0.stage.rawValue) \(Self.text($0.seconds))" } + ["total \(Self.text(total(at: now)))"]
            + (token.map { [$0.rawValue] } ?? []))
            .joined(separator: " · ")
    }

    /// One duration, "0.31 s", for a log line.
    public static func text(_ seconds: Double) -> String {
        String(format: "%.2f s", clamped(seconds))
    }

    private static func clamped(_ seconds: Double) -> Double {
        seconds.isFinite ? max(0, seconds) : 0
    }
}
