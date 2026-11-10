import DoddyCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Writes a recap with Apple's Foundation Models on this iPhone (decision 2026-11-09-conversation-recaps:
/// "Oba", the iPhone first). Nothing leaves the phone. Available only on an iPhone with Apple
/// Intelligence on iOS 26 or later, and only when the model supports the language the recap is written
/// in. Its answer is a proposal: `RecapModelIO.read` accepts it only if every recap rule holds.
@MainActor
enum OnDeviceRecapWriter {
    enum Failure: Error, Equatable {
        case unavailable
    }

    /// Whether this iPhone can write a recap in `languageCode` ("pl", "en") now.
    static func isAvailable(languageCode: String) -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return false }
            return model.supportedLanguages.contains { $0.languageCode?.identifier == languageCode }
        }
        #endif
        return false
    }

    /// The model's raw answer (JSON text), for `RecapModelIO.read`.
    static func write(kind: ConversationRecapKind, lines: [RecapModelIO.Line], languageCode: String) async throws -> Data {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable(languageCode: languageCode) {
            let session = LanguageModelSession(instructions: RecapModelIO.instructions(kind: kind, languageCode: languageCode))
            let response = try await session.respond(to: RecapModelIO.conversation(lines))
            return Data(Self.json(in: response.content).utf8)
        }
        #endif
        throw Failure.unavailable
    }

    /// The JSON object in an answer that may wrap it in a code fence or a sentence; `RecapModelIO.read`
    /// still refuses anything that isn't exactly the three lists.
    static func json(in text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }
}
