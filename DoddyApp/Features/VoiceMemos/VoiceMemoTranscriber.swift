import DoddyCore
import Foundation
import Speech

/// Writes out a recording on this iPhone (ADR-230). On-device recognition is required: if this
/// iPhone can't do it for the language, nothing is written out and nothing is sent to Apple or
/// anyone else. The text goes into the editor for the user to check; it is never saved by itself.
enum VoiceMemoTranscriber {
    enum Outcome: Equatable {
        case text(RecognizedText.Result)
        /// Nothing was heard as words.
        case noSpeech
        /// This iPhone can't write out this language without sending the audio, so it didn't.
        case notOnDevice
        /// Speech recognition is off for Doddy in the Settings app.
        case notAllowed
        case failed
    }

    /// Languages to offer: the iPhone's own languages that it can write out on the device.
    static func languages() -> [Locale] {
        var seen = Set<String>()
        return Locale.preferredLanguages.compactMap { identifier -> Locale? in
            let locale = Locale(identifier: identifier)
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition,
                  seen.insert(recognizer.locale.identifier).inserted else { return nil }
            return recognizer.locale
        }
        .prefix(4)
        .map { $0 }
    }

    static func transcribe(_ url: URL, locale: Locale) async -> Outcome {
        guard await authorize() else { return .notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            return .notOnDevice
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        // Never sent to Apple's servers. The capability guard checks this line stays.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        let once = Once<Outcome>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = VoiceMemoText.transcript(result.bestTranscription.formattedString)
                    once.resume(text.text.isEmpty ? .noSpeech : .text(text))
                } else if let error {
                    // "No speech detected" comes back as an error too (code 1110).
                    once.resume((error as NSError).code == 1110 ? .noSpeech : .failed)
                }
            }
        }
    }

    private static func authorize() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}

/// Resumes a continuation exactly once, whichever callback comes first.
private final class Once<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    func set(_ continuation: CheckedContinuation<Value, Never>) {
        lock.lock(); defer { lock.unlock() }
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
