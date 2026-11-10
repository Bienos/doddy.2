import Foundation

// The focus timer (ADR-241) and the wind-down before bed (ADR-780) by voice (decision 2026-11-10-timers-by-voice;
// owner, 10 Nov 2026: "Skupienie, minutniki i stoper … lepiej to schować i po prostu wywoływać to na komendę do
// Doddy'ego"). Home's ••• menu no longer starts them; a conversation does, and Home shows a running one with Pause
// and Stop. They are Doddy's own timers on this iPhone, no other app or account, so like the stopwatch (ADR-652)
// they sit outside Pause all and the Connections switches. ASK-01: starting and stopping show a card and run on a
// tap; reading the focus timer asks "yes" first. Every reply is worked out from the session the app reads back
// after the change, never from the request, so Doddy never says a timer runs that doesn't.
//
// A plain timer by voice stays `set_timer` (AlarmKit, ADR-650): one voice path for "set a timer", so the agent never
// has to choose between two.

extension VoiceToolName {
    public static let startFocus = "start_focus"
    public static let stopFocus = "stop_focus"
    public static let checkFocus = "check_focus"
    public static let startWindDown = "start_wind_down"
    public static let stopWindDown = "stop_wind_down"
}

/// The lengths the voice may ask for, and what it gets when it gives none.
public enum TimerVoice {
    /// The focus screen's middle preset (`FocusSession.presetMinutes`), when the user gave no length.
    public static let focusDefaultMinutes = 25
    /// `FocusSession` keeps a focus between 1 and 180 minutes.
    public static let focusMinutes = 1...180
    /// The wind-down screen's first choice, when the user gave no length.
    public static let windDownDefaultMinutes = 10
    /// A wind-down is a short, quiet time before bed: an hour at most by voice.
    public static let windDownMinutes = 1...60

    /// Which countdown a reply is about, in the words the agent hears.
    public enum Kind: Sendable {
        case focus
        case windDown

        var name: String {
            switch self {
            case .focus: "focus timer"
            case .windDown: "wind-down"
            }
        }
    }

    /// Whole minutes from the `minutes` argument: `fallback` when it is left out (or null), nil when it is not a
    /// number or, rounded, falls outside `allowed`. Checked as a Double first: `Int(_:)` traps on a value it
    /// can't hold (review C6).
    static func minutes(_ args: Arguments, fallback: Int, allowed: ClosedRange<Int>) -> Int? {
        guard let raw = args.raw("minutes"), !(raw is NSNull) else { return fallback }
        guard let value = args.number("minutes"), value.isFinite else { return nil }
        let rounded = value.rounded()
        guard rounded >= Double(allowed.lowerBound), rounded <= Double(allowed.upperBound) else { return nil }
        return Int(rounded)
    }

    /// The card's and the activity row's length: "25 min" (the focus screen's own words in both languages).
    static func length(_ minutes: Int) -> String { "\(minutes) min" }
}

/// What the replies need from a focus timer or a wind-down: both count down the same way.
public protocol VoiceCountdown {
    var duration: TimeInterval { get }
    var label: String? { get }
    var isRunning: Bool { get }
    var isPaused: Bool { get }
    var isOver: Bool { get }
    var endsAt: Date? { get }
    /// The time ran out, as opposed to being stopped early.
    var ranOut: Bool { get }
    func remaining(at now: Date) -> TimeInterval
}

extension FocusSession: VoiceCountdown {
    public var ranOut: Bool { if case .finished = state { true } else { false } }
}

extension CountdownSession: VoiceCountdown {
    public var ranOut: Bool { if case .finished = state { true } else { false } }
}

extension VoiceToolRequest {
    static func parseStartFocus(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let minutes = TimerVoice.minutes(args, fallback: TimerVoice.focusDefaultMinutes, allowed: TimerVoice.focusMinutes) else {
            return .invalid(name: name, reason: "minutes must be a number from \(TimerVoice.focusMinutes.lowerBound) to \(TimerVoice.focusMinutes.upperBound)")
        }
        // Cleaned as the focus timer keeps it, so the card shows exactly what the Lock Screen will.
        return .startFocus(minutes: minutes, label: FocusSession.cleanLabel(args.text("label")))
    }

    static func parseStartWindDown(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let minutes = TimerVoice.minutes(args, fallback: TimerVoice.windDownDefaultMinutes, allowed: TimerVoice.windDownMinutes) else {
            return .invalid(name: name, reason: "minutes must be a number from \(TimerVoice.windDownMinutes.lowerBound) to \(TimerVoice.windDownMinutes.upperBound)")
        }
        return .startWindDown(minutes: minutes)
    }
}

extension VoiceToolReply {
    /// Said after the tap, from the session the app read back once it started: running, with its end.
    /// `alertConfirmed` is whether iOS listed the "time's up" notification as pending.
    public static func countdownStarted(_ kind: TimerVoice.Kind, _ session: (any VoiceCountdown)?, alertConfirmed: Bool?,
                                        calendar: Calendar) -> String {
        guard let session, session.isRunning, let end = session.endsAt else {
            return "failed: the \(kind.name) didn't start. Nothing is running. Tell the user; never say it started."
        }
        var text = "added: \(kind.name) started, \(durationText(Int(session.duration.rounded()))), ends at \(localText(end, hasTime: true, calendar: calendar))."
        text += alertConfirmed == true
            ? " A notification comes when it ends."
            : " iOS didn't confirm a notification for the end (notifications may be off for Doddy): tell the user there may be no alert. Doddy's Home still shows the time left."
        if let label = session.label { text += " Its label:\n" + ToolData.block([quoted("Label", label)]) }
        return text
    }

    /// One at a time: a running or paused one is never replaced by a new one.
    public static func countdownAlreadyThere(_ kind: TimerVoice.Kind, _ session: any VoiceCountdown, now: Date) -> String {
        "failed: a \(kind.name) is already \(session.isPaused ? "paused" : "running") with \(Stopwatch.spoken(session.remaining(at: now), polish: false)) left. Nothing was started. Tell the user; for a new one, they stop this one first."
    }

    /// `before` is the session as it was when the tap arrived; `after` as the app read it back once it was stopped.
    public static func countdownStopped(_ kind: TimerVoice.Kind, before: (any VoiceCountdown)?, after: (any VoiceCountdown)?,
                                        now: Date) -> String {
        guard let before else {
            return "failed: there is no \(kind.name) running. Nothing changed. Offer to start one if the user wants."
        }
        guard !before.isOver else {
            return before.ranOut
                ? "failed: the \(kind.name) had already ended. Nothing changed."
                : "failed: the \(kind.name) was already stopped. Nothing changed."
        }
        guard let after, after.isOver else {
            return "failed: the \(kind.name) still shows as running, so it may not have stopped. Ask the user to stop it on Doddy's Home or the Lock Screen."
        }
        if after.ranOut {
            return "failed: the \(kind.name)'s time had already run out, so there was nothing left to stop. Nothing changed."
        }
        return "changed: \(kind.name) stopped with \(Stopwatch.spoken(before.remaining(at: now), polish: false)) left. Tell the user."
    }

    /// The focus timer as the app reads it now (a look-up: nothing changes).
    public static func focusReading(_ session: (any VoiceCountdown)?, now: Date, calendar: Calendar) -> String {
        guard let session else {
            return "There is no focus timer. Offer to start one if the user wants. Never guess a time."
        }
        let left = session.remaining(at: now)
        let state: String
        if session.isRunning, left > 0, let end = session.endsAt {
            state = "running: \(Stopwatch.spoken(left, polish: false)) left, it ends at \(localText(end, hasTime: true, calendar: calendar))"
        } else if session.isPaused {
            state = "paused with \(Stopwatch.spoken(left, polish: false)) left"
        } else if session.ranOut || session.isRunning {
            state = "over: its time is up"
        } else {
            state = "stopped: it was stopped before its time was up"
        }
        var text = "The focus timer is \(state)."
        if let label = session.label { text += " Its label:\n" + ToolData.block([quoted("Label", label)]) }
        return text
    }
}
