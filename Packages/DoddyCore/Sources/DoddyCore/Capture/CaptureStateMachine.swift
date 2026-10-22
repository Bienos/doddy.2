import Foundation

// The one source of truth for a recording session (ADR-588). The app's coordinator owns an
// instance, feeds it what really happened (the recorder started, iOS interrupted, the user
// tapped Stop) and does what it answers with. It decides nothing about audio itself, so every
// rule here runs on Linux.
//
// Three rules matter more than the rest, and each has a test:
//  - "recording" is entered only after the recorder says it is capturing (and, for a start from
//    a shortcut or control, the Live Activity is up). Nothing says "recording" on a hope.
//  - There is one session. A second start while one is going is rejected, never queued.
//  - A pause the user asked for is never resumed by the system's say-so.
//
// "saved → processing → ready" is not here: a second recording may start while the first is
// being written out, so those steps live on each recording (`TranscriptionStatus`), not in one
// global state.

public enum InterruptionKind: String, Codable, Equatable, Sendable {
    /// A call, an alarm, Siri or another app took the audio. iOS does not say which.
    case systemAudio
    /// The microphone was muted at the hardware (a cover on some iPads).
    case builtInMicMuted
    /// The input in use went away (headphones taken off, Bluetooth lost).
    case routeDisconnected
    /// iOS reset its audio services; the session has to be set up again.
    case mediaServicesReset
    /// The recorder stopped and iOS did not say why.
    case recorderStopped
    /// The next ten-minute part could not be started.
    case rotationFailed
}

public enum CaptureFailure: Equatable, Sendable {
    case microphoneDenied
    /// iOS has not been asked yet, and it can only ask with Doddy on screen.
    case microphoneNotAsked
    /// iOS refused the audio session: a call or another app has the microphone.
    case microphoneBusy
    /// A voice conversation with Doddy is running, and both need the one audio session.
    case conversationRunning
    case storageLow
    case liveActivityUnavailable
    case recorderCouldNotStart
    /// The recording could not be closed cleanly. The audio files are kept for recovery.
    case saveFailed
    case databaseUnavailable
    /// Doddy is locked with Face ID.
    case appLocked
    /// The notice before the first recording (`CaptureNotice`) has not been accepted in the app.
    case noticeNotAccepted

    public func message(_ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch self {
        case .microphoneDenied:
            return polish ? "Doddy nie ma dostępu do mikrofonu. Włącz go w Ustawieniach iPhone’a." : "Doddy can't use the microphone. Turn it on in the iPhone Settings."
        case .microphoneNotAsked:
            return polish ? "Otwórz Doddy’ego i zacznij nagrywanie raz, aby iOS mógł zapytać o mikrofon." : "Open Doddy and start a recording once, so iOS can ask about the microphone."
        case .microphoneBusy:
            return polish ? "Mikrofon jest teraz zajęty (rozmowa albo inna aplikacja). Spróbuj, gdy się zwolni." : "The microphone is busy (a call or another app). Try again when it's free."
        case .conversationRunning:
            return polish ? "Trwa rozmowa z Doddym. Zakończ ją, a potem nagrywaj." : "A conversation with Doddy is running. End it, then record."
        case .storageLow:
            return polish ? "W iPhonie jest za mało miejsca na nagranie. Zwolnij trochę miejsca." : "This iPhone doesn't have enough free space to record. Free some up."
        case .liveActivityUnavailable:
            return polish ? "Nagrywanie bez otwierania Doddy’ego wymaga Aktywności na żywo. Włącz je dla Doddy’ego w Ustawieniach iPhone’a." : "Recording without opening Doddy needs Live Activities. Turn them on for Doddy in the iPhone Settings."
        case .recorderCouldNotStart:
            return polish ? "Nagrywanie się nie rozpoczęło, więc nic nie zapisano." : "Recording didn't start, so nothing was saved."
        case .saveFailed:
            return polish ? "Nie udało się czysto zamknąć nagrania. Pliki audio zostały; Doddy spróbuje je odzyskać po ponownym otwarciu." : "The recording couldn't be closed cleanly. The audio files are kept, and Doddy will try to recover them next time he opens."
        case .databaseUnavailable:
            return polish ? "Doddy nie może teraz zapisać nagrania, więc nie zaczął." : "Doddy can't save a recording right now, so he didn't start."
        case .appLocked:
            return polish ? "Doddy jest zablokowany. Odblokuj go, aby nagrywać." : "Doddy is locked. Unlock him to record."
        case .noticeNotAccepted:
            return polish ? "Otwórz Nagrania w Doddym i raz przeczytaj, jak działa nagrywanie. Potem zacznij ponownie." : "Open Recordings in Doddy once to read how recording works. Then start again."
        }
    }
}

public enum StartRejection: Equatable, Sendable {
    case alreadyActive

    public func message(_ language: NotificationLanguage) -> String {
        language == .polish ? "Doddy już nagrywa." : "Doddy is already recording."
    }
}

public struct ClosedPart: Equatable, Sendable {
    public let index: Int
    public let durationMilliseconds: Int

    public init(index: Int, durationMilliseconds: Int) {
        self.index = index
        self.durationMilliseconds = durationMilliseconds
    }
}

public enum ActivityStatus: Equatable, Sendable {
    case pending, up, unavailable
}

public struct PendingStart: Equatable, Sendable {
    public let id: UUID
    public let origin: CaptureOrigin
    public let requestedAt: Date
    public var preflightPassedAt: Date?
    public var recorderStartedAt: Date?
    public var activity: ActivityStatus

    public init(id: UUID, origin: CaptureOrigin, requestedAt: Date, preflightPassedAt: Date? = nil,
                recorderStartedAt: Date? = nil, activity: ActivityStatus = .pending) {
        self.id = id
        self.origin = origin
        self.requestedAt = requestedAt
        self.preflightPassedAt = preflightPassedAt
        self.recorderStartedAt = recorderStartedAt
        self.activity = activity
    }
}

public struct OpenPart: Equatable, Sendable {
    public let index: Int
    public let startedAt: Date
    /// Set when the audio stops (pause, interruption, stop). Until the recorder reports the real
    /// length (`partClosed`) this is the clock's estimate.
    public var endedAt: Date?

    public init(index: Int, startedAt: Date, endedAt: Date? = nil) {
        self.index = index
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct CaptureSession: Equatable, Sendable {
    public let id: UUID
    public let origin: CaptureOrigin
    /// When the first audio was verified.
    public let startedAt: Date
    public var closedParts: [ClosedPart] = []
    public var openPart: OpenPart?
    public var gaps: [CaptureGap] = []
    /// While nothing is being recorded: since when, and why.
    public var quietSince: Date?
    public var quietReason: CaptureGap.Reason?
    public var activity: ActivityStatus
    public var warnedNearLimit = false
    public var rotationInFlight = false
    public var rotationBackoffUntil: Date?
    public var resumeAttempts = 0
    public var lastResumeFailure: CaptureFailure?
    public var finalizingSince: Date?

    public init(id: UUID, origin: CaptureOrigin, startedAt: Date, closedParts: [ClosedPart] = [],
                openPart: OpenPart? = nil, gaps: [CaptureGap] = [], activity: ActivityStatus) {
        self.id = id
        self.origin = origin
        self.startedAt = startedAt
        self.closedParts = closedParts
        self.openPart = openPart
        self.gaps = gaps
        self.activity = activity
    }

    public var closedMilliseconds: Int { closedParts.reduce(0) { $0 + $1.durationMilliseconds } }

    public var nextPartIndex: Int { max(closedParts.last?.index ?? 0, openPart?.index ?? 0) + 1 }

    /// Audio captured so far: the closed parts, and the part being written by the clock.
    public func capturedMilliseconds(at now: Date) -> Int {
        guard let open = openPart else { return closedMilliseconds }
        return closedMilliseconds + CaptureStateMachine.milliseconds(from: open.startedAt, to: open.endedAt ?? now)
    }

    /// Microphone audio is being written right now.
    public var isCapturing: Bool { openPart != nil && openPart?.endedAt == nil }
}

public struct SavedCapture: Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let durationMilliseconds: Int
    public let reason: CaptureEndReason
    public let gaps: [CaptureGap]
    public let parts: [ClosedPart]
}

public enum CaptureOutcome: Equatable, Sendable {
    case saved(SavedCapture)
    /// A mis-tap: shorter than `CaptureLimits.minMilliseconds`. Nothing is kept.
    case discardedTooShort
}

public enum CaptureState: Equatable, Sendable {
    case idle
    /// Checks and start-up. No audio is claimed yet.
    case preparing(PendingStart)
    case recording(CaptureSession)
    /// The user paused. The microphone is off: the part was closed.
    case paused(CaptureSession)
    /// The system took the audio, or the recorder stopped.
    case interrupted(CaptureSession, InterruptionKind)
    case finalizing(CaptureSession, CaptureEndReason)
    case finished(CaptureOutcome)
    case failed(CaptureFailure)
}

public enum CaptureEvent: Equatable, Sendable {
    case startRequested(id: UUID, origin: CaptureOrigin, at: Date)
    case preflightPassed(at: Date)
    case preflightFailed(CaptureFailure)
    /// The recorder started and reports that audio is coming in (not merely that it was asked to).
    case recorderStarted(partIndex: Int, at: Date)
    case recorderFailedToStart(CaptureFailure)
    case activityUp
    case activityUnavailable
    /// The system or the user ended the Live Activity while the session goes on.
    case activityEnded
    case pauseRequested(at: Date)
    case resumeRequested(at: Date)
    case stopRequested(at: Date)
    case tick(at: Date)
    /// The next part is writing and the old one is closed. `gapMilliseconds` is the clock between.
    case segmentRotated(closedPart: Int, closedMilliseconds: Int, newPart: Int, gapMilliseconds: Int, at: Date)
    /// The old part is closed but the new one would not start.
    case rotationFailed(closedPart: Int, closedMilliseconds: Int, at: Date)
    /// Nothing changed: the new part could not be prepared, the old one is still writing.
    case rotationAborted(at: Date)
    /// The open part is closed, and the recorder says how long it was.
    case partClosed(index: Int, milliseconds: Int, at: Date)
    case interruptionBegan(InterruptionKind, at: Date)
    case interruptionEnded(shouldResume: Bool, at: Date)
    case recorderStoppedUnexpectedly(at: Date)
    case storageLow(freeBytes: Int64, at: Date)
    /// Everything is closed and saved; the parts are the recorder's own durations.
    case finalized(parts: [ClosedPart], at: Date)
    case finalizeFailed
    case acknowledged
}

public enum CaptureEffect: Equatable, Sendable {
    /// Permission, free space, no conversation, no Face ID lock, a database. Answer with
    /// `preflightPassed` or `preflightFailed`.
    case runPreflight(CaptureOrigin)
    /// Open the part's row and file, start the recorder; answer `recorderStarted` or
    /// `recorderFailedToStart`.
    case startRecorder(partIndex: Int)
    /// Request the Live Activity; answer `activityUp` or `activityUnavailable`.
    case startActivity
    case updateActivity
    /// Prepare the next part, stop the old one, start the new one.
    case rotate(closing: Int, opening: Int)
    /// Stop the recorder for this part and answer `partClosed`.
    case closePart(index: Int)
    /// Close any open part, save, end the Live Activity; answer `finalized` or `finalizeFailed`.
    case finalize
    /// Stop everything, end the Live Activity, delete what exists. Nothing worth keeping.
    case discard
    case checkpoint
    case warnNearLimit(minutesLeft: Int)
    case rejectStart(StartRejection)
}

public struct CaptureStateMachine: Equatable, Sendable {
    public private(set) var state: CaptureState

    public init(state: CaptureState = .idle) {
        self.state = state
    }

    /// How long a start may take once the checks have passed.
    public static let startTimeoutSeconds: TimeInterval = 15
    /// How long closing and saving may take.
    public static let finalizeTimeoutSeconds: TimeInterval = 90
    /// After a failed rotation attempt that changed nothing, the next one waits this long.
    public static let rotationBackoffSeconds: TimeInterval = 30

    public static func milliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }

    // MARK: - What the rest of the app reads

    /// A session exists: the audio session is Doddy's, and a conversation must not start.
    public var isActive: Bool {
        switch state {
        case .idle, .finished, .failed: false
        default: true
        }
    }

    /// Microphone audio is being written. This is what the indicator says.
    public var isCapturingAudio: Bool {
        if case .recording(let session) = state { return session.isCapturing }
        return false
    }

    public var session: CaptureSession? {
        switch state {
        case .recording(let s), .paused(let s), .interrupted(let s, _), .finalizing(let s, _): s
        default: nil
        }
    }

    // MARK: - Transitions

    /// Applies one event and returns what the coordinator has to do, in order.
    @discardableResult
    public mutating func handle(_ event: CaptureEvent) -> [CaptureEffect] {
        switch state {
        case .idle, .finished, .failed:
            return handleResting(event)
        case .preparing(let pending):
            return handlePreparing(pending, event)
        case .recording(let session):
            return handleRecording(session, event)
        case .paused(let session):
            return handleQuiet(session, event, interruption: nil)
        case .interrupted(let session, let kind):
            return handleQuiet(session, event, interruption: kind)
        case .finalizing(let session, let reason):
            return handleFinalizing(session, reason, event)
        }
    }

    private mutating func handleResting(_ event: CaptureEvent) -> [CaptureEffect] {
        switch event {
        case .startRequested(let id, let origin, let at):
            state = .preparing(PendingStart(id: id, origin: origin, requestedAt: at, activity: .pending))
            return [.runPreflight(origin)]
        case .acknowledged:
            state = .idle
            return []
        case .recorderStarted:
            // A start that was cancelled while it was starting: the recorder must not run on unseen.
            return [.discard]
        default:
            return []
        }
    }

    private mutating func handlePreparing(_ pending: PendingStart, _ event: CaptureEvent) -> [CaptureEffect] {
        var pending = pending
        switch event {
        case .startRequested:
            return [.rejectStart(.alreadyActive)]
        case .preflightPassed(let at):
            guard pending.preflightPassedAt == nil else { return [] }
            pending.preflightPassedAt = at
            state = .preparing(pending)
            return [.startRecorder(partIndex: 1), .startActivity]
        case .preflightFailed(let failure), .recorderFailedToStart(let failure):
            state = .failed(failure)
            return [.discard]
        case .recorderStarted(let partIndex, let at):
            guard pending.preflightPassedAt != nil, partIndex == 1, pending.recorderStartedAt == nil else { return [] }
            pending.recorderStartedAt = at
            return promoteIfReady(pending)
        case .activityUp:
            pending.activity = .up
            return promoteIfReady(pending)
        case .activityUnavailable:
            if pending.origin.requiresLiveActivity {
                state = .failed(.liveActivityUnavailable)
                return [.discard]
            }
            pending.activity = .unavailable
            return promoteIfReady(pending)
        case .stopRequested(let at):
            guard let started = pending.recorderStartedAt else {
                state = .idle
                return [.discard]
            }
            var session = CaptureSession(id: pending.id, origin: pending.origin, startedAt: started,
                                         openPart: OpenPart(index: 1, startedAt: started, endedAt: at), activity: pending.activity)
            session.finalizingSince = at
            state = .finalizing(session, .userStopped)
            return [.finalize]
        case .tick(let at):
            if let passed = pending.preflightPassedAt, at.timeIntervalSince(passed) > Self.startTimeoutSeconds {
                state = .failed(.recorderCouldNotStart)
                return [.discard]
            }
            return []
        default:
            return []
        }
    }

    /// Recording starts here and nowhere else.
    private mutating func promoteIfReady(_ pending: PendingStart) -> [CaptureEffect] {
        guard let started = pending.recorderStartedAt, pending.activity != .pending else {
            state = .preparing(pending)
            return []
        }
        let session = CaptureSession(id: pending.id, origin: pending.origin, startedAt: started,
                                     openPart: OpenPart(index: 1, startedAt: started), activity: pending.activity)
        state = .recording(session)
        return [.checkpoint, .updateActivity]
    }

    private mutating func handleRecording(_ session: CaptureSession, _ event: CaptureEvent) -> [CaptureEffect] {
        var s = session
        switch event {
        case .startRequested:
            return [.rejectStart(.alreadyActive)]
        case .tick(let at):
            return recordingTick(&s, at)
        case .segmentRotated(let closedPart, let closedMs, let newPart, let gapMs, let at):
            guard s.openPart?.index == closedPart else { return [] }
            s.closedParts.append(ClosedPart(index: closedPart, durationMilliseconds: closedMs))
            s.gaps.append(CaptureGap(atMilliseconds: s.closedMilliseconds, wallMilliseconds: gapMs, reason: .segmentRotation))
            s.openPart = OpenPart(index: newPart, startedAt: at)
            s.rotationInFlight = false
            state = .recording(s)
            return [.checkpoint]
        case .rotationAborted(let at):
            s.rotationInFlight = false
            s.rotationBackoffUntil = at.addingTimeInterval(Self.rotationBackoffSeconds)
            state = .recording(s)
            return []
        case .rotationFailed(let closedPart, let closedMs, let at):
            guard s.openPart?.index == closedPart else { return [] }
            s.closedParts.append(ClosedPart(index: closedPart, durationMilliseconds: closedMs))
            s.openPart = nil
            s.rotationInFlight = false
            return beginQuiet(&s, kind: .rotationFailed, reason: .interruption, at: at, closeOpenPart: false)
        case .pauseRequested(let at):
            return beginPause(&s, at: at)
        case .interruptionBegan(let kind, let at):
            return beginQuiet(&s, kind: kind, reason: .interruption, at: at, closeOpenPart: true)
        case .recorderStoppedUnexpectedly(let at):
            return beginQuiet(&s, kind: .recorderStopped, reason: .interruption, at: at, closeOpenPart: true)
        case .stopRequested(let at):
            return beginFinalizing(&s, .userStopped, at: at)
        case .storageLow(let free, let at):
            guard free < CaptureLimits.stopFreeBytes else { return [] }
            return beginFinalizing(&s, .storageLow, at: at)
        case .activityEnded:
            s.activity = .unavailable
            state = .recording(s)
            return [.startActivity]
        case .activityUp:
            s.activity = .up
            state = .recording(s)
            return [.updateActivity]
        case .activityUnavailable:
            s.activity = .unavailable
            state = .recording(s)
            return []
        default:
            return []
        }
    }

    private mutating func recordingTick(_ s: inout CaptureSession, _ at: Date) -> [CaptureEffect] {
        if at.timeIntervalSince(s.startedAt) >= TimeInterval(CaptureLimits.maxWallSeconds) {
            return beginFinalizing(&s, .activityLifetime, at: at)
        }
        let captured = s.capturedMilliseconds(at: at)
        if captured >= CaptureLimits.maxSeconds * 1000 {
            return beginFinalizing(&s, .durationLimit, at: at)
        }
        var effects: [CaptureEffect] = []
        if !s.warnedNearLimit, captured >= (CaptureLimits.maxSeconds - CaptureLimits.warnBeforeMaxSeconds) * 1000 {
            s.warnedNearLimit = true
            effects.append(.warnNearLimit(minutesLeft: CaptureLimits.warnBeforeMaxSeconds / 60))
        }
        if !s.rotationInFlight, let open = s.openPart, open.endedAt == nil,
           at.timeIntervalSince(open.startedAt) >= TimeInterval(CaptureLimits.segmentSeconds),
           s.rotationBackoffUntil.map({ at >= $0 }) ?? true {
            s.rotationInFlight = true
            effects.append(.rotate(closing: open.index, opening: s.nextPartIndex))
        }
        state = .recording(s)
        return effects
    }

    private mutating func beginPause(_ s: inout CaptureSession, at: Date) -> [CaptureEffect] {
        guard let open = s.openPart else { return [] }
        s.openPart?.endedAt = at
        s.quietSince = at
        s.quietReason = .userPaused
        s.rotationInFlight = false
        state = .paused(s)
        return [.closePart(index: open.index), .updateActivity]
    }

    /// Audio stopped without the user asking. Ends the open part, and tries again at once only
    /// for the kinds where waiting would change nothing (`InterruptionPolicy`).
    private mutating func beginQuiet(_ s: inout CaptureSession, kind: InterruptionKind, reason: CaptureGap.Reason,
                                     at: Date, closeOpenPart: Bool) -> [CaptureEffect] {
        var effects: [CaptureEffect] = []
        if closeOpenPart, let open = s.openPart {
            if s.openPart?.endedAt == nil { s.openPart?.endedAt = at }
            effects.append(.closePart(index: open.index))
        }
        s.quietSince = at
        s.quietReason = reason
        s.rotationInFlight = false
        if InterruptionPolicy.resumesImmediately(kind), s.resumeAttempts < CaptureLimits.maxResumeAttempts {
            effects.append(.startRecorder(partIndex: s.nextPartIndex))
        }
        state = .interrupted(s, kind)
        effects.append(.updateActivity)
        return effects
    }

    private mutating func beginFinalizing(_ s: inout CaptureSession, _ reason: CaptureEndReason, at: Date) -> [CaptureEffect] {
        if s.openPart != nil, s.openPart?.endedAt == nil { s.openPart?.endedAt = at }
        s.finalizingSince = at
        s.rotationInFlight = false
        state = .finalizing(s, reason)
        return [.finalize]
    }

    /// Paused (`interruption == nil`) and interrupted share their rules, except who may resume.
    private mutating func handleQuiet(_ session: CaptureSession, _ event: CaptureEvent, interruption: InterruptionKind?) -> [CaptureEffect] {
        var s = session
        func stay(_ s: CaptureSession) {
            state = interruption.map { .interrupted(s, $0) } ?? .paused(s)
        }
        switch event {
        case .startRequested:
            return [.rejectStart(.alreadyActive)]
        case .partClosed(let index, let ms, _):
            guard s.openPart?.index == index else { return [] }
            s.closedParts.append(ClosedPart(index: index, durationMilliseconds: ms))
            s.openPart = nil
            stay(s)
            return [.checkpoint]
        case .resumeRequested:
            return [.startRecorder(partIndex: s.nextPartIndex)]
        case .interruptionEnded(let shouldResume, _):
            // A pause the user asked for is theirs to end.
            guard let kind = interruption else { return [] }
            guard InterruptionPolicy.shouldResume(after: kind, systemAllows: shouldResume, attempts: s.resumeAttempts) else { return [] }
            return [.startRecorder(partIndex: s.nextPartIndex)]
        case .interruptionBegan(let kind, _):
            guard interruption != nil else { return [] }
            state = .interrupted(s, kind)
            return [.updateActivity]
        case .recorderStarted(let partIndex, let at):
            guard partIndex == s.nextPartIndex else { return [.discard] }
            // The old part's real length never arrived: keep it by the clock rather than lose it.
            if let open = s.openPart {
                let estimate = Self.milliseconds(from: open.startedAt, to: open.endedAt ?? at)
                s.closedParts.append(ClosedPart(index: open.index, durationMilliseconds: estimate))
                s.openPart = nil
            }
            let quietFor = s.quietSince.map { Self.milliseconds(from: $0, to: at) } ?? 0
            s.gaps.append(CaptureGap(atMilliseconds: s.closedMilliseconds, wallMilliseconds: quietFor, reason: s.quietReason ?? .interruption))
            s.openPart = OpenPart(index: partIndex, startedAt: at)
            s.quietSince = nil
            s.quietReason = nil
            s.resumeAttempts = 0
            s.lastResumeFailure = nil
            state = .recording(s)
            return [.checkpoint, .updateActivity]
        case .recorderFailedToStart(let failure):
            s.resumeAttempts += 1
            s.lastResumeFailure = failure
            stay(s)
            return [.updateActivity]
        case .stopRequested(let at):
            return beginFinalizing(&s, .userStopped, at: at)
        case .storageLow(let free, let at):
            guard free < CaptureLimits.stopFreeBytes else { return [] }
            return beginFinalizing(&s, .storageLow, at: at)
        case .tick(let at):
            if at.timeIntervalSince(s.startedAt) >= TimeInterval(CaptureLimits.maxWallSeconds) {
                return beginFinalizing(&s, .activityLifetime, at: at)
            }
            if let since = s.quietSince, at.timeIntervalSince(since) >= TimeInterval(CaptureLimits.notCapturingGiveUpSeconds) {
                return beginFinalizing(&s, .idleTimeout, at: at)
            }
            return []
        case .activityEnded:
            s.activity = .unavailable
            stay(s)
            return [.startActivity]
        case .activityUp:
            s.activity = .up
            stay(s)
            return [.updateActivity]
        default:
            return []
        }
    }

    private mutating func handleFinalizing(_ session: CaptureSession, _ reason: CaptureEndReason, _ event: CaptureEvent) -> [CaptureEffect] {
        var s = session
        switch event {
        case .startRequested:
            return [.rejectStart(.alreadyActive)]
        case .partClosed(let index, let ms, _):
            guard s.openPart?.index == index else { return [] }
            s.closedParts.append(ClosedPart(index: index, durationMilliseconds: ms))
            s.openPart = nil
            state = .finalizing(s, reason)
            return []
        case .finalized(let parts, _):
            s.closedParts = parts.sorted { $0.index < $1.index }
            s.openPart = nil
            let total = s.closedMilliseconds
            if total >= CaptureLimits.minMilliseconds {
                state = .finished(.saved(SavedCapture(
                    id: s.id, startedAt: s.startedAt, durationMilliseconds: total, reason: reason,
                    gaps: s.gaps, parts: s.closedParts)))
                return []
            }
            state = .finished(.discardedTooShort)
            return [.discard]
        case .finalizeFailed:
            // The row and the files stay, so recovery can finish the job at the next launch.
            state = .failed(.saveFailed)
            return []
        case .tick(let at):
            if let since = s.finalizingSince, at.timeIntervalSince(since) > Self.finalizeTimeoutSeconds {
                state = .failed(.saveFailed)
            }
            return []
        default:
            return []
        }
    }
}

/// What to do about audio that stopped by itself. iOS says little: a call, an alarm, Siri and
/// another app's microphone all arrive as one kind of interruption.
public enum InterruptionPolicy {
    /// Waiting would change nothing, so try the next part straight away.
    public static func resumesImmediately(_ kind: InterruptionKind) -> Bool {
        switch kind {
        case .routeDisconnected, .mediaServicesReset, .recorderStopped, .rotationFailed: true
        case .systemAudio, .builtInMicMuted: false
        }
    }

    /// After iOS says the interruption is over.
    public static func shouldResume(after kind: InterruptionKind, systemAllows: Bool, attempts: Int) -> Bool {
        guard attempts < CaptureLimits.maxResumeAttempts else { return false }
        switch kind {
        case .systemAudio: return systemAllows
        case .builtInMicMuted: return false
        case .routeDisconnected, .mediaServicesReset, .recorderStopped, .rotationFailed: return true
        }
    }

    public static func message(_ kind: InterruptionKind, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch kind {
        case .systemAudio:
            return polish ? "Rozmowa, budzik, Siri lub inna aplikacja używa mikrofonu. Nagrywanie czeka." : "A call, an alarm, Siri or another app is using the microphone. Recording is waiting."
        case .builtInMicMuted:
            return polish ? "Mikrofon jest wyciszony na urządzeniu." : "The microphone is muted on the device."
        case .routeDisconnected:
            return polish ? "Zmieniło się wejście dźwięku (słuchawki lub Bluetooth)." : "The audio input changed (headphones or Bluetooth)."
        case .mediaServicesReset:
            return polish ? "iOS zresetował usługi audio." : "iOS reset its audio services."
        case .recorderStopped:
            return polish ? "Nagrywanie zatrzymało się samo." : "Recording stopped by itself."
        case .rotationFailed:
            return polish ? "Nie udało się rozpocząć kolejnej części nagrania." : "The next part of the recording couldn't start."
        }
    }
}
