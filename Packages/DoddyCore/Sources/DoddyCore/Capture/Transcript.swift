import Foundation

// A recording's words (ADR-588). The recognizer hands back timed words for each audio part; this
// groups them into lines, lays the parts end to end on the recording's own time, and says
// whether there is enough speech to trust. Nothing here invents a speaker or a word: a line has
// no speaker unless a recognizer can say who spoke reliably, and none can on the device today.

public struct TranscriptWord: Equatable, Sendable {
    public let text: String
    /// From the start of the audio file it came from.
    public let startMilliseconds: Int
    public let durationMilliseconds: Int
    /// 0 to 1, if the recognizer gave one. Zero is read as "not given".
    public let confidence: Double?

    public init(text: String, startMilliseconds: Int, durationMilliseconds: Int, confidence: Double? = nil) {
        self.text = text
        self.startMilliseconds = startMilliseconds
        self.durationMilliseconds = durationMilliseconds
        self.confidence = confidence
    }

    var endMilliseconds: Int { startMilliseconds + durationMilliseconds }
}

/// A line on its own part's time, before the parts are laid end to end.
public struct DraftSegment: Equatable, Sendable {
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    public let text: String
    public let confidence: Double?

    public init(startMilliseconds: Int, endMilliseconds: Int, text: String, confidence: Double? = nil) {
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.text = text
        self.confidence = confidence
    }
}

public struct TranscriptSegment: Equatable, Sendable, Identifiable {
    /// From 0, in time order, across the whole recording.
    public let index: Int
    /// On the recording's own time: the parts' audio end to end, gaps left out.
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    /// What the user sees. The user may correct it.
    public var text: String
    /// What the recognizer wrote, kept so a correction can be told from a recognition.
    public let originalText: String
    public let confidence: Double?
    /// Always nil today: no on-device recognizer names who spoke, and Doddy does not guess.
    public let speaker: String?

    public var id: Int { index }
    public var isEdited: Bool { text != originalText }

    public init(index: Int, startMilliseconds: Int, endMilliseconds: Int, text: String, originalText: String? = nil,
                confidence: Double? = nil, speaker: String? = nil) {
        self.index = index
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.text = text
        self.originalText = originalText ?? text
        self.confidence = confidence
        self.speaker = speaker
    }
}

/// Groups timed words into lines: at a pause, at the end of a sentence once there is enough to
/// read, and never longer than a few lines of text.
public enum TranscriptSegmenter {
    public static let pauseMilliseconds = 1_200
    public static let maxSpanMilliseconds = 20_000
    public static let maxWords = 40
    public static let sentenceMinWords = 6

    public static func group(_ words: [TranscriptWord]) -> [DraftSegment] {
        let usable = words
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startMilliseconds < $1.startMilliseconds }
        var segments: [DraftSegment] = []
        var current: [TranscriptWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " ")
            let scores = current.compactMap(\.confidence).filter { $0 > 0 }
            let confidence = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
            let end = max(last.endMilliseconds, first.startMilliseconds)
            segments.append(DraftSegment(startMilliseconds: first.startMilliseconds, endMilliseconds: end, text: text, confidence: confidence))
            current = []
        }

        for word in usable {
            if let first = current.first, let last = current.last {
                let pause = word.startMilliseconds - last.endMilliseconds
                let span = word.endMilliseconds - first.startMilliseconds
                let sentenceDone = current.count >= sentenceMinWords && endsSentence(last.text)
                if pause >= pauseMilliseconds || span > maxSpanMilliseconds || current.count >= maxWords || sentenceDone {
                    flush()
                }
            }
            current.append(word)
        }
        flush()
        return segments
    }

    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return ".?!…".contains(last)
    }
}

public struct AssemblyPart: Equatable, Sendable {
    /// Where this part starts on the recording's own time.
    public let offsetMilliseconds: Int
    public let durationMilliseconds: Int
    public let segments: [DraftSegment]

    public init(offsetMilliseconds: Int, durationMilliseconds: Int, segments: [DraftSegment]) {
        self.offsetMilliseconds = offsetMilliseconds
        self.durationMilliseconds = durationMilliseconds
        self.segments = segments
    }
}

public enum TranscriptAssembler {
    /// A recognizer that reports a word this far past the end of its audio is not believed.
    public static let overrunMilliseconds = 2_000

    /// Lays the parts end to end. Lines are moved onto the recording's time, kept inside their own
    /// part's audio, dropped if empty or past the audio, and numbered from 0 in time order.
    public static func assemble(_ parts: [AssemblyPart]) -> [TranscriptSegment] {
        var placed: [(start: Int, end: Int, text: String, confidence: Double?)] = []
        for part in parts {
            for draft in part.segments {
                let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                var start = max(0, draft.startMilliseconds)
                var end = max(start, draft.endMilliseconds)
                if part.durationMilliseconds > 0 {
                    guard start <= part.durationMilliseconds + overrunMilliseconds else { continue }
                    start = min(start, part.durationMilliseconds)
                    end = min(max(end, start), part.durationMilliseconds)
                }
                placed.append((part.offsetMilliseconds + start, part.offsetMilliseconds + end, text, draft.confidence))
            }
        }
        placed.sort { ($0.start, $0.end) < ($1.start, $1.end) }
        return placed.enumerated().map { index, item in
            TranscriptSegment(index: index, startMilliseconds: item.start, endMilliseconds: item.end, text: item.text, confidence: item.confidence)
        }
    }
}

/// Whether there is enough speech to trust a summary of it.
public struct TranscriptQuality: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable { case good, poor, noSpeech }

    public let verdict: Verdict
    public let wordCount: Int
    public let wordsPerMinute: Double
    public let meanConfidence: Double?

    public static let lowConfidence = 0.4
    public static let lowWordsPerMinute = 15.0
    /// Shorter than this, a low word rate says nothing.
    public static let rateMinMilliseconds = 60_000

    public static func assess(_ segments: [TranscriptSegment], durationMilliseconds: Int) -> TranscriptQuality {
        let words = segments.reduce(0) { $0 + SearchFolding.tokens($1.text).count }
        let minutes = Double(max(durationMilliseconds, 1)) / 60_000
        let rate = Double(words) / minutes
        let scores = segments.compactMap(\.confidence).filter { $0 > 0 }
        let mean = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        let verdict: Verdict
        if words == 0 {
            verdict = .noSpeech
        } else if durationMilliseconds >= rateMinMilliseconds && rate < lowWordsPerMinute {
            verdict = .poor
        } else if let mean, mean < lowConfidence {
            verdict = .poor
        } else {
            verdict = .good
        }
        return TranscriptQuality(verdict: verdict, wordCount: words, wordsPerMinute: rate, meanConfidence: mean)
    }

    /// A summary is offered only when the words can be trusted.
    public var allowsSummary: Bool { verdict == .good }

    public func message(_ language: NotificationLanguage) -> String? {
        let polish = language == .polish
        switch verdict {
        case .good: return nil
        case .noSpeech:
            return polish ? "Nie rozpoznano mowy w tym nagraniu, więc nie ma czego streszczać." : "No speech was recognised in this recording, so there is nothing to summarise."
        case .poor:
            return polish ? "Jakość dźwięku była zbyt niska, żeby rzetelnie streścić to nagranie. Słowa poniżej mogą zawierać błędy." : "The audio quality was too low to summarise this recording reliably. The words below may contain mistakes."
        }
    }
}

public enum TranscriptEdit {
    public static let maxCharacters = 2_000

    /// A corrected line, cleaned, or nil if it would leave the line empty. A line is corrected,
    /// never deleted, so the timeline stays whole.
    public static func cleaned(_ text: String) -> String? {
        let flat = text.unicodeScalars.map { scalar -> String in
            if scalar == "\n" || scalar == "\t" { return " " }
            return CharacterSet.controlCharacters.contains(scalar) ? "" : String(scalar)
        }.joined()
        let collapsed = flat.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let limited = String(collapsed.prefix(maxCharacters)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? nil : limited
    }
}

public enum TranscriptFormat {
    /// "[14:32] text"
    public static func line(_ segment: TranscriptSegment) -> String {
        "[\(RecordingClock.string(milliseconds: segment.startMilliseconds))] \(segment.text)"
    }

    /// A stable fingerprint of the words and their times. It changes when the user corrects a line,
    /// so anything built from the old words can be told apart (a summary is then out of date).
    /// Not a security hash.
    public static func fingerprint(_ segments: [TranscriptSegment]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for segment in segments {
            for byte in "\(segment.startMilliseconds)|\(segment.endMilliseconds)|\(segment.text)\n".utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// The transcript as a Markdown file, with the quiet stretches marked where they happened.
    public static func markdown(title: String, startedAt: Date, durationMilliseconds: Int, languageCode: String,
                                segments: [TranscriptSegment], gaps: [CaptureGap], _ language: NotificationLanguage,
                                calendar: Calendar = .current) -> String {
        let polish = language == .polish
        var lines = ["# \(title)", ""]
        lines.append((polish ? "Nagrano: " : "Recorded: ") + RecordingTitle.standard(startedAt: startedAt, language: language, calendar: calendar)
                     + " · " + RecordingClock.string(milliseconds: durationMilliseconds) + " · " + languageCode)
        lines.append(polish
            ? "_Słowa zapisano na tym iPhonie. Mogą zawierać błędy._"
            : "_Written out on this iPhone. It may contain mistakes._")
        lines.append("")
        var pending = gaps.filter(\.isNoticeable).sorted { $0.atMilliseconds < $1.atMilliseconds }
        for segment in segments {
            while let gap = pending.first, gap.atMilliseconds <= segment.startMilliseconds {
                lines.append("_[\(gap.note(language))]_")
                pending.removeFirst()
            }
            lines.append("**\(RecordingClock.string(milliseconds: segment.startMilliseconds))** \(segment.text)")
        }
        for gap in pending { lines.append("_[\(gap.note(language))]_") }
        return lines.joined(separator: "\n") + "\n"
    }
}
