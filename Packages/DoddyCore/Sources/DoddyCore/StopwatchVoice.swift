import Foundation

// Voice tools for the stopwatch (ADR-642; owner, 24 Oct 2026: "stoper"). Doddy's own tool on this
// iPhone, no other app or account, so it sits outside Pause all and the Connections switches, like
// the parking spot. ASK-01: starting and stopping show a card and run on a tap; reading the time
// asks "yes" first. The reading is whatever the clock says; Doddy claims nothing else.

extension VoiceToolName {
    public static let startStopwatch = "start_stopwatch"
    public static let stopStopwatch = "stop_stopwatch"
    public static let checkStopwatch = "check_stopwatch"
}

extension VoiceToolReply {
    /// Said after the tap: it is running now (read back from the controller, not assumed).
    public static func stopwatchStarted(label: String?) -> String {
        var text = "added: stopwatch started. It counts up on the Lock Screen and in the island until the user stops it."
        if let label { text += " Its label:\n" + ToolData.block([quoted("Label", label)]) }
        return text
    }

    /// One at a time: the user's reading is never replaced.
    public static func stopwatchAlreadyThere(elapsed: TimeInterval, paused: Bool) -> String {
        "failed: a stopwatch is already \(paused ? "paused" : "running") at \(Stopwatch.spoken(elapsed, polish: false)). Nothing was started. Tell the user the reading; for a new one, they stop this one first."
    }

    public static func stopwatchStopped(elapsed: TimeInterval) -> String {
        "changed: stopwatch stopped at \(Stopwatch.spoken(elapsed, polish: false)). Tell the user that time."
    }

    /// Nothing to stop: either none was started, or it was stopped already.
    public static func noStopwatchToStop(stoppedAt: TimeInterval?) -> String {
        guard let stoppedAt else {
            return "failed: there is no stopwatch running. Nothing changed. Offer to start one if the user wants."
        }
        return "failed: the stopwatch was already stopped, at \(Stopwatch.spoken(stoppedAt, polish: false)). Nothing changed."
    }

    /// The reading, from a look at the stopwatch (a look-up: nothing changes).
    public static func stopwatchReading(_ watch: Stopwatch?, now: Date) -> String {
        guard let watch else {
            return "There is no stopwatch. Offer to start one if the user wants. Never guess a time."
        }
        let time = Stopwatch.spoken(watch.elapsed(at: watch.stoppedAt ?? now), polish: false)
        let state: String
        switch watch.state {
        case .running: state = "running: \(time) so far"
        case .paused: state = "paused at \(time)"
        case .stopped: state = "stopped at \(time)"
        }
        var text = "The stopwatch is \(state)."
        if let label = watch.label { text += " Its label:\n" + ToolData.block([quoted("Label", label)]) }
        return text
    }
}
