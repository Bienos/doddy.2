import Foundation

// What the Dynamic Island, the Lock Screen and the pill show about a recording (ADR-579). The
// snapshot is the whole content of the Live Activity: enums and numbers, never a word that was
// said, because the Lock Screen is visible to anyone. The widget extension has no database.

public struct CaptureActivitySnapshot: Codable, Equatable, Hashable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable {
        case recording, paused, interrupted
        /// Closing the files. Shown for a moment.
        case saving
        /// Kept. The last thing the activity shows.
        case saved
    }

    public var phase: Phase
    /// Audio captured when `anchor` was set (or in total, once paused or saved).
    public var capturedMilliseconds: Int
    /// When the current stretch of audio began. Only while recording; the timer runs from it.
    public var anchor: Date?
    public var interruption: InterruptionKind?
    /// "Stops in 10 minutes": the cap is close.
    public var nearLimit: Bool
    /// A try to resume failed; the Lock Screen says to open Doddy.
    public var resumeFailed: Bool

    public init(phase: Phase, capturedMilliseconds: Int, anchor: Date? = nil, interruption: InterruptionKind? = nil,
                nearLimit: Bool = false, resumeFailed: Bool = false) {
        self.phase = phase
        self.capturedMilliseconds = capturedMilliseconds
        self.anchor = anchor
        self.interruption = interruption
        self.nearLimit = nearLimit
        self.resumeFailed = resumeFailed
    }

    private enum CodingKeys: String, CodingKey {
        case phase, capturedMilliseconds, anchor, interruption, nearLimit, resumeFailed
    }

    /// Content written by another build still decodes: a newer interruption kind is read as the
    /// plain system interruption, and a missing key takes its quiet default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(Phase.self, forKey: .phase)
        capturedMilliseconds = try container.decodeIfPresent(Int.self, forKey: .capturedMilliseconds) ?? 0
        anchor = try container.decodeIfPresent(Date.self, forKey: .anchor)
        interruption = (try? container.decodeIfPresent(InterruptionKind.self, forKey: .interruption)) ?? nil
        nearLimit = try container.decodeIfPresent(Bool.self, forKey: .nearLimit) ?? false
        resumeFailed = try container.decodeIfPresent(Bool.self, forKey: .resumeFailed) ?? false
    }

    /// Nil when there is nothing to show: no session, a start still in progress, a failure.
    public static func make(from state: CaptureState, now: Date) -> CaptureActivitySnapshot? {
        switch state {
        case .recording(let s):
            return CaptureActivitySnapshot(
                phase: .recording, capturedMilliseconds: s.closedMilliseconds,
                anchor: s.openPart?.startedAt, nearLimit: s.warnedNearLimit)
        case .paused(let s):
            return CaptureActivitySnapshot(phase: .paused, capturedMilliseconds: s.capturedMilliseconds(at: now),
                                           resumeFailed: s.lastResumeFailure != nil)
        case .interrupted(let s, let kind):
            return CaptureActivitySnapshot(phase: .interrupted, capturedMilliseconds: s.capturedMilliseconds(at: now),
                                           interruption: kind, resumeFailed: s.lastResumeFailure != nil)
        case .finalizing(let s, _):
            return CaptureActivitySnapshot(phase: .saving, capturedMilliseconds: s.capturedMilliseconds(at: now))
        case .finished(.saved(let saved)):
            return CaptureActivitySnapshot(phase: .saved, capturedMilliseconds: saved.durationMilliseconds)
        case .idle, .preparing, .failed, .finished(.discardedTooShort):
            return nil
        }
    }
}

/// The words and the choices around a snapshot. Plain functions, so they are tested here.
public enum CapturePresentation {
    public static let name = "DODDY Capture"

    /// The date a running timer counts from: `Text(timerInterval:)` in the widget needs a start,
    /// and with this one it shows the audio captured, not the time since the button was pressed.
    public static func timerStart(_ snapshot: CaptureActivitySnapshot) -> Date? {
        guard snapshot.phase == .recording, let anchor = snapshot.anchor else { return nil }
        return anchor.addingTimeInterval(-TimeInterval(snapshot.capturedMilliseconds) / 1000)
    }

    /// Elapsed audio at `now`, for the places that cannot run a timer (the pill, accessibility).
    public static func elapsedMilliseconds(_ snapshot: CaptureActivitySnapshot, at now: Date) -> Int {
        guard snapshot.phase == .recording, let anchor = snapshot.anchor else { return snapshot.capturedMilliseconds }
        return snapshot.capturedMilliseconds + CaptureStateMachine.milliseconds(from: anchor, to: now)
    }

    public static func status(_ snapshot: CaptureActivitySnapshot, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch snapshot.phase {
        case .recording: return polish ? "Nagrywanie" : "Recording"
        case .paused: return polish ? "Wstrzymane" : "Paused"
        case .interrupted: return polish ? "Przerwane" : "Interrupted"
        case .saving: return polish ? "Zapisywanie…" : "Saving…"
        case .saved: return polish ? "Zapisano" : "Saved"
        }
    }

    /// One more line when there is something true to add.
    public static func detail(_ snapshot: CaptureActivitySnapshot, _ language: NotificationLanguage) -> String? {
        let polish = language == .polish
        switch snapshot.phase {
        case .recording:
            return snapshot.nearLimit ? (polish ? "Zatrzyma się za mniej niż 10 minut" : "Stops in under 10 minutes") : nil
        case .paused:
            if snapshot.resumeFailed { return polish ? "Nie udało się wznowić. Otwórz Doddy’ego." : "Couldn't resume. Open Doddy." }
            return polish ? "Mikrofon jest wyłączony" : "The microphone is off"
        case .interrupted:
            if snapshot.resumeFailed { return polish ? "Nie udało się wznowić. Otwórz Doddy’ego." : "Couldn't resume. Open Doddy." }
            return snapshot.interruption.map { InterruptionPolicy.message($0, language) }
        case .saving, .saved:
            return nil
        }
    }

    /// "Recording • 12:43": the Lock Screen's line, and the spoken label.
    public static func line(_ snapshot: CaptureActivitySnapshot, at now: Date, _ language: NotificationLanguage) -> String {
        "\(status(snapshot, language)) • \(RecordingClock.string(milliseconds: elapsedMilliseconds(snapshot, at: now)))"
    }

    public static func symbol(_ snapshot: CaptureActivitySnapshot) -> String {
        switch snapshot.phase {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .interrupted: "exclamationmark.circle.fill"
        case .saving: "ellipsis.circle"
        case .saved: "checkmark.circle.fill"
        }
    }

    /// The orange recording cue is for audio being captured, and nothing else.
    public static func isRecordingCue(_ snapshot: CaptureActivitySnapshot) -> Bool { snapshot.phase == .recording }

    public static func canPause(_ snapshot: CaptureActivitySnapshot) -> Bool { snapshot.phase == .recording }
    public static func canResume(_ snapshot: CaptureActivitySnapshot) -> Bool { snapshot.phase == .paused || snapshot.phase == .interrupted }
    /// A recording can always be stopped until it is being saved.
    public static func canStop(_ snapshot: CaptureActivitySnapshot) -> Bool {
        snapshot.phase == .recording || snapshot.phase == .paused || snapshot.phase == .interrupted
    }

    public enum Action: Sendable { case pause, resume, stop, open }

    /// The words on the island's and the Lock Screen's buttons.
    public static func label(_ action: Action, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch action {
        case .pause: return polish ? "Wstrzymaj" : "Pause"
        case .resume: return polish ? "Wznów" : "Resume"
        case .stop: return "Stop"
        case .open: return polish ? "Otwórz" : "Open"
        }
    }

    /// Said once, in the app, when the cap is near.
    public static func nearLimitNotice(minutesLeft: Int, _ language: NotificationLanguage) -> String {
        language == .polish
            ? "Nagranie zatrzyma się i zapisze za około \(minutesLeft) minut."
            : "The recording will stop and save in about \(minutesLeft) minutes."
    }

    /// What an intent says aloud or shows, and only after the recorder reported audio coming in.
    public static func startedLine(_ language: NotificationLanguage) -> String {
        language == .polish ? "Nagrywam." : "Recording."
    }

    /// What the pill above the app says while audio is being captured.
    public static func pillTitle(_ language: NotificationLanguage) -> String {
        language == .polish ? "Doddy nagrywa" : "Doddy is recording"
    }

    public static func pillDetail(_ language: NotificationLanguage) -> String {
        language == .polish ? "Dźwięk zostaje na tym iPhonie. Stop zapisuje nagranie." : "The audio stays on this iPhone. Stop saves the recording."
    }
}
