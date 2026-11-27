import Foundation

// Pausing and resuming Doddy's own stopwatch or focus timer by voice (decision 2026-11-27-voice-first-doddy, the
// "Focus, stopwatch: pause and resume" row of docs/product/VOICE_COVERAGE.md). One tool, `pause_resume`, with the clock
// and the action; the clocks themselves are the same ones the screen's pause button drives.
//
// The protocol, as code:
// - Runs at once, like starting and stopping them: Doddy's own clock on this iPhone, no other app, account or person,
//   undone by saying the opposite. After an email, a page or the screen has been read it asks once, like every own thing.
// - The app reads the clock's real state first (`ClockPauseState`) and `decide` says what happens: nothing to pause, one
//   already in that state, one that is over, or the change. Every reply is read back from the clock after the change,
//   so "paused" is said only when the clock says paused, never because the call went through.
//
// Platforms: iPhone and iPad (the voice conversation).

/// The two clocks that can be paused.
public enum PausableClock: String, Sendable, Equatable, CaseIterable {
    case stopwatch
    case focus

    var spoken: String { self == .stopwatch ? "stopwatch" : "focus timer" }
}

/// What the clock is doing now, read from the controller (never assumed).
public enum ClockPauseState: Equatable, Sendable {
    case none, running, paused, over
}

public enum ClockPauseVoice {
    static func parse(_ args: Arguments, name: String) -> VoiceToolRequest {
        let what = args.text("what")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard let clock = PausableClock(rawValue: what) else {
            return .invalid(name: name, reason: "what must be \"stopwatch\" or \"focus\"")
        }
        switch args.text("action")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pause": return .pauseResume(clock: clock, resume: false)
        case "resume": return .pauseResume(clock: clock, resume: true)
        default: return .invalid(name: name, reason: "action must be \"pause\" or \"resume\"")
        }
    }

    public enum Decision: Equatable, Sendable {
        /// The clock is in the other state: toggle it, then read it back.
        case change
        /// Nothing to change; this is what Doddy is told.
        case reply(String)
    }

    public static func decide(clock: PausableClock, resume: Bool, state: ClockPauseState) -> Decision {
        switch (state, resume) {
        case (.none, _):
            return .reply("failed: there is no \(clock.spoken) running or paused. Nothing changed. Offer to start one if the user wants.")
        case (.over, _):
            return .reply("failed: the \(clock.spoken) is already over, so it can't be paused or resumed. Nothing changed.")
        case (.running, false), (.paused, true):
            return .change
        case (.paused, false):
            return .reply("not changed: the \(clock.spoken) is already paused. Nothing changed.")
        case (.running, true):
            return .reply("not changed: the \(clock.spoken) is already running. Nothing changed.")
        }
    }

    /// After the change, from the clock's state read again. `reading` is the time as `Stopwatch.spoken` says it: the time
    /// counted so far for the stopwatch, the time left for the focus timer.
    public static func result(clock: PausableClock, resume: Bool, after: ClockPauseState, reading: String) -> String {
        guard after == (resume ? .running : .paused) else {
            return VoiceToolReply.failed("The \(clock.spoken) didn't change. Tell the user it is still \(after == .running ? "running" : "paused").")
        }
        let time = clock == .stopwatch ? "\(reading) so far" : "\(reading) left"
        return resume
            ? "changed: the \(clock.spoken) runs again, \(time). Tell the user."
            : "changed: the \(clock.spoken) is paused, \(time). The user says \"resume\" to go on."
    }
}
