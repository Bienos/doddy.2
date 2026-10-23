import Foundation

// Finding the part of a recording a question is about (ADR-579). On the device, with the same
// SQLite full-text search the notes use: no embeddings, no model. Only when a measurement shows
// this is not enough is anything heavier worth adding.

public struct TranscriptChunk: Equatable, Sendable {
    public let index: Int
    public let firstSegment: Int
    public let lastSegment: Int
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    /// "[14:32] line" per line.
    public let text: String

    public init(index: Int, firstSegment: Int, lastSegment: Int, startMilliseconds: Int, endMilliseconds: Int, text: String) {
        self.index = index
        self.firstSegment = firstSegment
        self.lastSegment = lastSegment
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.text = text
    }
}

/// Cuts a long transcript into pieces a model can read one at a time, each a whole number of
/// lines, with the last line of one repeated at the start of the next so nothing falls in a seam.
public enum TranscriptChunker {
    public static let defaultMaxCharacters = 1_800

    public static func chunks(_ segments: [TranscriptSegment], maxCharacters: Int = defaultMaxCharacters,
                              overlapSegments: Int = 1) -> [TranscriptChunk] {
        guard !segments.isEmpty else { return [] }
        let limit = max(200, maxCharacters)
        var chunks: [TranscriptChunk] = []
        var start = 0
        while start < segments.count {
            var end = start
            var size = 0
            while end < segments.count {
                let length = TranscriptFormat.line(segments[end]).count + 1
                if end > start, size + length > limit { break }
                size += length
                end += 1
            }
            let last = end - 1
            chunks.append(TranscriptChunk(
                index: chunks.count, firstSegment: start, lastSegment: last,
                startMilliseconds: segments[start].startMilliseconds, endMilliseconds: segments[last].endMilliseconds,
                text: segments[start...last].map(TranscriptFormat.line).joined(separator: "\n")))
            if end >= segments.count { break }
            start = max(end - max(0, overlapSegments), start + 1)
        }
        return chunks
    }
}

/// Lines around a hit, as one stretch of the recording with its times.
public struct Excerpt: Equatable, Sendable {
    public let firstSegment: Int
    public let lastSegment: Int
    public let startMilliseconds: Int
    public let endMilliseconds: Int
    /// "[14:32] line" per line, for the reader.
    public let text: String
    /// The same lines without times, for checking a quote against.
    public let plainText: String

    public init(firstSegment: Int, lastSegment: Int, startMilliseconds: Int, endMilliseconds: Int, text: String, plainText: String) {
        self.firstSegment = firstSegment
        self.lastSegment = lastSegment
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.text = text
        self.plainText = plainText
    }
}

public enum ExcerptBuilder {
    public static let defaultRadius = 2
    public static let defaultMaxCharacters = 3_000
    public static let defaultMaxExcerpts = 5

    /// Widens each hit (most relevant first) by `radius` lines each way, joins stretches that touch,
    /// and stops adding when the characters would pass `maxCharacters`. Returned in time order.
    public static func excerpts(hits: [Int], segments: [TranscriptSegment], radius: Int = defaultRadius,
                                maxCharacters: Int = defaultMaxCharacters, maxExcerpts: Int = defaultMaxExcerpts) -> [Excerpt] {
        guard !segments.isEmpty else { return [] }
        var ranges: [ClosedRange<Int>] = []
        func characters(_ rs: [ClosedRange<Int>]) -> Int {
            rs.reduce(0) { total, r in total + segments[r].reduce(0) { $0 + TranscriptFormat.line($1).count + 1 } }
        }
        for hit in hits where segments.indices.contains(hit) {
            let wanted = max(0, hit - radius)...min(segments.count - 1, hit + radius)
            var merged = wanted
            var rest: [ClosedRange<Int>] = []
            for range in ranges {
                if range.upperBound >= merged.lowerBound - 1, range.lowerBound <= merged.upperBound + 1 {
                    merged = min(range.lowerBound, merged.lowerBound)...max(range.upperBound, merged.upperBound)
                } else {
                    rest.append(range)
                }
            }
            let candidate = rest + [merged]
            if candidate.count > maxExcerpts || characters(candidate) > maxCharacters { continue }
            ranges = candidate
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }.map { range in
            let lines = segments[range]
            return Excerpt(
                firstSegment: range.lowerBound, lastSegment: range.upperBound,
                startMilliseconds: lines.first!.startMilliseconds, endMilliseconds: lines.last!.endMilliseconds,
                text: lines.map(TranscriptFormat.line).joined(separator: "\n"),
                plainText: lines.map(\.text).joined(separator: " "))
        }
    }
}

public enum RecordingSearch {
    /// The FTS5 pattern for a question or a few words, with the notes' own matching rules (folding,
    /// Polish and English stopwords and endings, spoken numbers). Nil when nothing is left to look for.
    public static func pattern(for query: String) -> String? {
        RecallMatching.ftsPattern(RecallMatching.terms(query))
    }
}
