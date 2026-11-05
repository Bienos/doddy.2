import Foundation

/// How dictated words join the box in Messages. The microphone fills the draft; nothing is sent until the
/// person taps Send, so they can read and fix the words first.
public enum DictationRules {
    /// One dictation stops by itself after this long, so a mic left on is never listening for long.
    public static let maxSeconds = 120

    /// `base` is what was in the box when the mic was tapped; `spoken` is everything heard since (it grows
    /// and changes while the person talks). The result is always `base` followed by the latest `spoken`,
    /// never an earlier guess stacked on top of it.
    public static func merged(base: String, spoken: String) -> String {
        let words = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return base }
        guard !base.allSatisfy(\.isWhitespace) else { return words }
        let separator = base.last?.isWhitespace == true ? "" : " "
        return base + separator + words
    }
}
