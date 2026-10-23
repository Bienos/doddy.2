import Foundation

// DODDY Capture (ADR-579): the words and numbers every part of recording agrees on. Plain Swift
// for the Linux tests; the recorder, the Live Activity and the screens in the app use them.
//
// A recording is source material, not memory. It becomes a note only when the user taps
// "Remember this" on one thing in it (`CaptureMemory`).

/// Every number the recorder, the storage, the state machine and the Live Activity agree on.
public enum CaptureLimits {
    /// One audio part is one file, closed on its own. A kill loses at most the part in progress.
    public static let segmentSeconds = 600
    /// Longest recording. A Live Activity lasts at most 8 hours, and iOS stops an intent-started
    /// recording whose activity has ended, so the cap stays well under it.
    public static let maxSeconds = 4 * 3600
    /// "Stops in 10 minutes" is said once, this long before the cap.
    public static let warnBeforeMaxSeconds = 600
    /// Wall-clock cap from the first sample, pauses and interruptions included (the activity's life).
    public static let maxWallSeconds = 7 * 3600
    /// A recording that is paused or interrupted this long is saved as it is.
    public static let notCapturingGiveUpSeconds = 3600
    /// Shorter than this is a mis-tap and is not kept.
    public static let minMilliseconds = 1000
    /// A part shorter than this found after a kill is not worth recovering.
    public static let minRecoverablePartMilliseconds = 500
    /// A start is refused with less free space than this.
    public static let minFreeBytesToStart: Int64 = 200 * 1024 * 1024
    /// Below this the recording stops and is saved.
    public static let stopFreeBytes: Int64 = 50 * 1024 * 1024
    /// Speech, mono: AAC at this rate is clear for transcription and about 14 MB an hour.
    public static let sampleRate = 16_000
    public static let bitRate = 32_000
    public static let maxResumeAttempts = 3
    public static let maxTitleCharacters = 120
    /// A quoted line has to be found this close (in the recording's own time) to the time it cites.
    public static let citationToleranceMilliseconds = 15_000

    /// What an hour costs on disk, for the free-space check.
    public static func estimatedBytes(seconds: Int) -> Int64 {
        Int64(bitRate / 8) * Int64(max(0, seconds))
    }
}

/// What the recording is. Chosen by the user; Doddy never presents a guess as a fact.
public enum RecordingKind: String, CaseIterable, Codable, Sendable {
    case meeting, lecture, interview, conversation, personal, other

    public func name(_ language: NotificationLanguage) -> String {
        switch (self, language) {
        case (.meeting, .english): "Meeting"
        case (.meeting, .polish): "Spotkanie"
        case (.lecture, .english): "Lecture"
        case (.lecture, .polish): "Wykład"
        case (.interview, .english): "Interview"
        case (.interview, .polish): "Rozmowa kwalifikacyjna"
        case (.conversation, .english): "Conversation"
        case (.conversation, .polish): "Rozmowa"
        case (.personal, .english): "Personal notes"
        case (.personal, .polish): "Notatki osobiste"
        case (.other, .english): "Recording"
        case (.other, .polish): "Nagranie"
        }
    }
}

/// The library's tabs. "Imported" is not offered: this slice cannot import audio.
public enum RecordingCategory: String, CaseIterable, Sendable {
    case all, meetings, conversations, ideas

    public var kinds: [RecordingKind]? {
        switch self {
        case .all: nil
        case .meetings: [.meeting, .lecture, .interview]
        case .conversations: [.conversation, .other]
        case .ideas: [.personal]
        }
    }

    public func name(_ language: NotificationLanguage) -> String {
        switch (self, language) {
        case (.all, .english): "All"
        case (.all, .polish): "Wszystkie"
        case (.meetings, .english): "Meetings"
        case (.meetings, .polish): "Spotkania"
        case (.conversations, .english): "Conversations"
        case (.conversations, .polish): "Rozmowy"
        case (.ideas, .english): "Ideas"
        case (.ideas, .polish): "Pomysły"
        }
    }
}

/// How the recording was started. Only for the start rules and the log, never for content.
public enum CaptureOrigin: String, Codable, Sendable {
    /// A button inside Doddy.
    case app
    /// Shortcuts, Siri or the Action Button running an App Intent.
    case intent
    /// A Control Center, Lock Screen or Action Button control.
    case control

    /// iOS stops a recording an `AudioRecordingIntent` started when no Live Activity is up, so
    /// these starts do not go on without one. A start from inside Doddy does (the screen and
    /// iOS's own microphone dot already show it).
    public var requiresLiveActivity: Bool { self != .app }
}

/// Where a recording is in its life. The phase on disk, not the live state (`CaptureState`).
public enum RecordingPhase: String, Codable, Sendable {
    /// Audio is being written, or Doddy was closed before it could finish the recording.
    case recording
    case saved
    /// Finished after a kill: whatever audio could be read was kept.
    case recovered
    /// Nothing usable remains. The row stays so the user is told, not left wondering.
    case lost
}

public enum TranscriptionStatus: String, Codable, Sendable {
    case notStarted, running, done
    /// Ran and found no words.
    case noSpeech
    /// This iPhone cannot write this language out on the device, so nothing was written out and
    /// nothing was sent anywhere.
    case unsupportedLanguage
    /// Speech recognition is off for Doddy in Settings.
    case notAllowed
    case failed
}

public struct Recording: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// What the user typed. Empty means "use the default title" (`RecordingTitle`).
    public var title: String
    public var kind: RecordingKind
    public let origin: CaptureOrigin
    public var phase: RecordingPhase
    /// BCP-47, such as "pl-PL". One language per recording.
    public var languageCode: String
    public let startedAt: Date
    public var endedAt: Date?
    /// Audio actually captured: the parts added up. Gaps are not in it.
    public var durationMilliseconds: Int
    public var endReason: CaptureEndReason?
    public var transcription: TranscriptionStatus
    /// Quiet stretches (pauses, interruptions, rotations) with their positions.
    public var gaps: [CaptureGap]

    public init(
        id: UUID, title: String = "", kind: RecordingKind = .other, origin: CaptureOrigin,
        phase: RecordingPhase = .recording, languageCode: String, startedAt: Date, endedAt: Date? = nil,
        durationMilliseconds: Int = 0, endReason: CaptureEndReason? = nil,
        transcription: TranscriptionStatus = .notStarted, gaps: [CaptureGap] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.origin = origin
        self.phase = phase
        self.languageCode = languageCode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMilliseconds = durationMilliseconds
        self.endReason = endReason
        self.transcription = transcription
        self.gaps = gaps
    }

    public func displayTitle(_ language: NotificationLanguage, calendar: Calendar = .current) -> String {
        RecordingTitle.display(title, startedAt: startedAt, language: language, calendar: calendar)
    }
}

/// One audio file of a recording. Parts play back to back, so the recording's own time (the one
/// transcript timestamps use) is the parts' durations added up, with the gaps left out.
public struct RecordingPart: Equatable, Sendable {
    public let recordingID: UUID
    /// From 1.
    public let index: Int
    public let fileName: String
    /// Where this part starts on the recording's own time.
    public let startOffsetMilliseconds: Int
    /// Nil while the part is still being written.
    public var durationMilliseconds: Int?

    public init(recordingID: UUID, index: Int, fileName: String, startOffsetMilliseconds: Int, durationMilliseconds: Int? = nil) {
        self.recordingID = recordingID
        self.index = index
        self.fileName = fileName
        self.startOffsetMilliseconds = startOffsetMilliseconds
        self.durationMilliseconds = durationMilliseconds
    }

    /// Made by Doddy, never from outside: "part-0001.caf".
    public static func fileName(index: Int) -> String {
        "part-" + String(format: "%04d", min(max(index, 1), 9999)) + ".caf"
    }

    public static func isValidFileName(_ name: String) -> Bool {
        guard name.count == 13, name.hasPrefix("part-"), name.hasSuffix(".caf") else { return false }
        let digits = name.dropFirst(5).dropLast(4)
        return digits.count == 4 && digits.allSatisfy { $0 >= "0" && $0 <= "9" } && digits != "0000"
    }
}

public enum CaptureEndReason: String, Codable, Sendable {
    case userStopped
    case durationLimit
    case storageLow
    /// Nothing captured for an hour (paused or interrupted), so it was saved as it was.
    case idleTimeout
    case activityLifetime
    /// Finished after Doddy was closed unexpectedly.
    case recovered

    public func note(_ language: NotificationLanguage) -> String? {
        let polish = language == .polish
        switch self {
        case .userStopped: return nil
        case .durationLimit:
            return polish ? "Nagranie osiągnęło limit \(CaptureLimits.maxSeconds / 3600) godzin i zostało zapisane." : "The recording reached its \(CaptureLimits.maxSeconds / 3600)-hour limit and was saved."
        case .storageLow:
            return polish ? "W iPhonie kończy się miejsce, więc nagranie zatrzymano i zapisano." : "This iPhone is nearly out of space, so the recording was stopped and saved."
        case .idleTimeout:
            return polish ? "Nic nie nagrywało się przez godzinę, więc Doddy zapisał to, co było." : "Nothing was recording for an hour, so Doddy saved what there was."
        case .activityLifetime:
            return polish ? "iOS pokazuje nagranie na ekranie blokady najwyżej kilka godzin, więc Doddy je zapisał." : "iOS shows a recording on the Lock Screen for only so many hours, so Doddy saved it."
        case .recovered:
            return polish ? "Doddy został zamknięty w trakcie nagrywania. Zapisano to, co dało się odczytać; koniec mógł zostać utracony." : "Doddy was closed while recording. What could be read was saved; the end may be missing."
        }
    }
}

/// A stretch where nothing was recorded, on the recording's own time.
public struct CaptureGap: Equatable, Codable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case userPaused
        /// A call, an alarm, Siri or another app took the microphone, or the route was lost.
        case interruption
        /// The ten-minute rotation: milliseconds, not a loss anyone hears.
        case segmentRotation
    }

    /// Where on the recording's own time the quiet stretch sits.
    public let atMilliseconds: Int
    /// How long nothing was recorded, by the clock.
    public let wallMilliseconds: Int
    public let reason: Reason

    public init(atMilliseconds: Int, wallMilliseconds: Int, reason: Reason) {
        self.atMilliseconds = atMilliseconds
        self.wallMilliseconds = wallMilliseconds
        self.reason = reason
    }

    /// Only these are shown to the user; a rotation's few milliseconds are not.
    public var isNoticeable: Bool { wallMilliseconds >= 1000 }

    public func note(_ language: NotificationLanguage) -> String {
        let polish = language == .polish
        let length = RecordingClock.string(milliseconds: wallMilliseconds)
        switch reason {
        case .userPaused: return polish ? "Wstrzymano nagrywanie (\(length))" : "Recording was paused (\(length))"
        case .interruption: return polish ? "Nagrywanie przerwano (\(length))" : "Recording was interrupted (\(length))"
        case .segmentRotation: return polish ? "Krótka przerwa techniczna (\(length))" : "Brief technical gap (\(length))"
        }
    }
}

/// "2:34" and "1:02:03".
public enum RecordingClock {
    public static func string(milliseconds: Int) -> String {
        let total = max(0, milliseconds) / 1000
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return "\(hours):" + pad(minutes) + ":" + pad(seconds) }
        return "\(minutes):" + pad(seconds)
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}

/// The default name of a recording, and the cleaning of one the user typed.
public enum RecordingTitle {
    private static let monthsEnglish = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let monthsPolish = ["sty", "lut", "mar", "kwi", "maj", "cze", "lip", "sie", "wrz", "paź", "lis", "gru"]

    /// "Recording 22 Oct, 14:03" / "Nagranie 22 paź, 14:03".
    public static func standard(startedAt: Date, language: NotificationLanguage, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: startedAt)
        let month = max(1, min(12, parts.month ?? 1)) - 1
        let minute = parts.minute ?? 0
        let clock = "\(parts.hour ?? 0):" + (minute < 10 ? "0\(minute)" : "\(minute)")
        let noun = language == .polish ? "Nagranie" : "Recording"
        let name = (language == .polish ? monthsPolish : monthsEnglish)[month]
        return "\(noun) \(parts.day ?? 1) \(name), \(clock)"
    }

    public static func display(_ stored: String, startedAt: Date, language: NotificationLanguage, calendar: Calendar = .current) -> String {
        let cleaned = clean(stored)
        return cleaned.isEmpty ? standard(startedAt: startedAt, language: language, calendar: calendar) : cleaned
    }

    /// Trimmed, one line, no control characters, at most `maxTitleCharacters`.
    public static func clean(_ text: String) -> String {
        let flat = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || $0 == "\n" ? " " : String($0) }.joined()
        let collapsed = flat.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return String(collapsed.prefix(CaptureLimits.maxTitleCharacters)).trimmingCharacters(in: .whitespaces)
    }
}

/// What the library and the detail page say about where a recording is.
public enum RecordingStatusText {
    public static func line(_ recording: Recording, isCapturingNow: Bool, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch recording.phase {
        case .recording:
            return isCapturingNow
                ? (polish ? "Nagrywanie" : "Recording")
                : (polish ? "Nie zakończono" : "Not finished")
        case .lost:
            return polish ? "Nic nie udało się zapisać" : "Nothing could be saved"
        case .saved, .recovered:
            switch recording.transcription {
            case .notStarted: return polish ? "Zapisano · czeka na zapis słów" : "Saved · waiting to be written out"
            case .running: return polish ? "Zapisywanie słów…" : "Writing out the words…"
            case .done: return polish ? "Transkrypcja gotowa" : "Transcript ready"
            case .noSpeech: return polish ? "Nie znaleziono mowy" : "No speech found"
            case .unsupportedLanguage:
                return polish ? "Ten język nie jest dostępny na tym iPhonie" : "This iPhone can't write this language out"
            case .notAllowed: return polish ? "Rozpoznawanie mowy jest wyłączone" : "Speech recognition is off for Doddy"
            case .failed: return polish ? "Nie udało się zapisać słów · spróbuj ponownie" : "Couldn't write out the words · try again"
            }
        }
    }
}
