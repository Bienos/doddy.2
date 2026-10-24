import Foundation

/// A file the person asked for in Messages, offered by Doddy as a card (ADR-606). The model only proposes: it
/// does not make the file. The card shows exactly these words, and nothing runs until the person taps. Then the
/// app asks Doddy's server for the same single-use approval the voice uses for `make_document` and runs it with
/// exactly these arguments. Limits are that tool's (title 120, request 1,500 characters), checked here again
/// because the device does not take the server's word for it.
public struct AssistantProposal: Equatable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case deck, doc, spreadsheet, pdf, text
    }

    public static let maxTitleLength = 120
    public static let maxRequestLength = 1_500

    public let kind: Kind
    public let title: String
    public let request: String

    /// nil unless it can be shown and run as it is: a known kind, a title and a request, inside the limits.
    public static func make(kind: String, title: String, request: String) -> AssistantProposal? {
        guard let kind = Kind(rawValue: kind) else { return nil }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !request.isEmpty,
              title.unicodeScalars.count <= maxTitleLength, request.unicodeScalars.count <= maxRequestLength
        else { return nil }
        return AssistantProposal(kind: kind, title: title, request: request)
    }

    /// The server tool this runs: `make_document`, with exactly the words on the card.
    public var toolCall: CloudToolCall {
        CloudToolCall(name: CloudToolName.makeDocument, arguments: [
            "kind": .string(kind.rawValue), "title": .string(title), "request": .string(request),
        ])
    }

    /// For the card: "Deck", "Document", "Spreadsheet", "PDF", "Text".
    public var label: String {
        switch kind {
        case .deck: "Deck"
        case .doc: "Document"
        case .spreadsheet: "Spreadsheet"
        case .pdf: "PDF"
        case .text: "Text"
        }
    }
}

/// Makes the file a proposal asks for. The app's implementation asks Doddy's server (prepare, then run with the
/// approval it returns); tests use a fake.
public protocol ThreadDocumentMaker: Sendable {
    func make(_ proposal: AssistantProposal) async throws -> ThreadDocument
}

public enum ThreadDocumentError: Error, Equatable, Sendable {
    /// This build has no server address or no session.
    case notConfigured
    /// The iPhone is offline.
    case offline
    /// The server answered, but the file was not made (a refusal, a limit, or it reported a failure).
    case failed
}
