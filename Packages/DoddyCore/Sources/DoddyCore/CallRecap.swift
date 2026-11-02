import Foundation

// Recaps of S2 calls (ADR-693; server/messaging/src/callRecaps/). After a call with Doddy's number
// (or a Call me now), the server builds a recap from the call's transcript. The app saves it on this
// iPhone first and only then acknowledges it, so the server deletes its copy only once the recap is
// here (the same order as errands and call cases).

/// One line of the call's transcript, as the server cut it (the caller's PIN already masked).
public struct CallRecapLine: Codable, Equatable, Sendable {
    /// `doddy` or `caller`.
    public let speaker: String
    public let text: String
    public let atSecs: Double?

    public init(speaker: String, text: String, atSecs: Double? = nil) {
        self.speaker = speaker
        self.text = text
        self.atSecs = atSecs
    }

    public var isDoddy: Bool { speaker == "doddy" }
}

/// Something the recap points at in the transcript: a short description and the words it came from.
/// The server keeps a pointer only when `quote` is words from that very line.
public struct CallRecapPointer: Codable, Equatable, Sendable {
    public let text: String
    public let line: Int
    public let quote: String

    public init(text: String, line: Int, quote: String) {
        self.text = text
        self.line = line
        self.quote = quote
    }
}

/// A note Doddy took on the call. It waited in the call-notes inbox for the user's confirmation when
/// the recap was built; it becomes a memory only when the user saves it there.
public struct CallRecapNote: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let createdAt: String

    public init(id: String, text: String, createdAt: String) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    public var createdDate: Date? { ServerDates.parse(createdAt) }
}

/// Why a recap has no summary (`CallRecap.summaryNote`).
public enum CallRecapSummaryNote: String, Sendable {
    case noWriter = "no_writer"
    case writerFailed = "writer_failed"
    case dailyLimit = "daily_limit"
    case saveClaim = "save_claim"
    case emptyCall = "empty_call"
    case transcriptUnreadable = "transcript_unreadable"
    case unusableSummary = "unusable_summary"
    case unknown
}

public struct CallRecap: Codable, Equatable, Sendable {
    public let format: Int
    public let callId: String
    /// `inbound` (the user called Doddy) or `outbound` (Call me now).
    public let direction: String
    public let startedAt: String?
    public let durationSecs: Double?
    /// Nil when no model wrote one; `summaryNote` says why.
    public let summary: String?
    /// `doddy_model` or `rules`.
    public let summaryBy: String
    public let summaryNote: String?
    public let language: String?
    public let agreed: [CallRecapPointer]
    public let couldNotDo: [CallRecapPointer]
    public let notes: [CallRecapNote]
    public let nextStep: String?
    public let transcript: [CallRecapLine]
    public let droppedPointers: Int
    public let builtAt: String

    public init(
        format: Int = 1, callId: String, direction: String, startedAt: String? = nil, durationSecs: Double? = nil,
        summary: String?, summaryBy: String, summaryNote: String? = nil, language: String? = nil,
        agreed: [CallRecapPointer] = [], couldNotDo: [CallRecapPointer] = [], notes: [CallRecapNote] = [],
        nextStep: String? = nil, transcript: [CallRecapLine] = [], droppedPointers: Int = 0, builtAt: String
    ) {
        self.format = format
        self.callId = callId
        self.direction = direction
        self.startedAt = startedAt
        self.durationSecs = durationSecs
        self.summary = summary
        self.summaryBy = summaryBy
        self.summaryNote = summaryNote
        self.language = language
        self.agreed = agreed
        self.couldNotDo = couldNotDo
        self.notes = notes
        self.nextStep = nextStep
        self.transcript = transcript
        self.droppedPointers = droppedPointers
        self.builtAt = builtAt
    }

    public var startedDate: Date? { startedAt.flatMap(ServerDates.parse) }
    public var isInbound: Bool { direction == "inbound" }
    /// The summary was written by Doddy's model (and checked by the server), not left out.
    public var hasSummary: Bool { summaryBy == "doddy_model" && summary != nil }
    public var missingSummaryReason: CallRecapSummaryNote? {
        guard !hasSummary else { return nil }
        return summaryNote.map { CallRecapSummaryNote(rawValue: $0) ?? .unknown } ?? .unknown
    }

    /// The transcript line a pointer came from, when it is still there.
    public func line(for pointer: CallRecapPointer) -> CallRecapLine? {
        transcript.indices.contains(pointer.line) ? transcript[pointer.line] : nil
    }
}

/// The server's state for a call's recap (`GET /v1/calls`, `GET /v1/calls/:id/recap`).
public enum CallRecapState: String, Sendable {
    case none, waiting, ready, acked, deleted, expired
    case unknown

    public init(server: String?) {
        self = server.map { CallRecapState(rawValue: $0) ?? .unknown } ?? .none
    }
}

public struct CallRecapReply: Decodable, Equatable, Sendable {
    public let callId: String
    public let state: String
    public let recap: CallRecap?
    public let digest: String?
}

/// What the server deleted, and why (`acked`, `deleted`, `expired`, `recap_built`).
public typealias CallRecapDeletion = ErrandDeletion

/// A recap kept on this iPhone. `acknowledgedAt` is set once the server confirmed it deleted its copy.
public struct StoredCallRecap: Codable, Equatable, Sendable, Identifiable {
    public let callId: UUID
    public var recap: CallRecap
    public var digest: String
    public var savedAt: Date
    public var acknowledgedAt: Date?
    public var deletions: [CallRecapDeletion]

    public init(callId: UUID, recap: CallRecap, digest: String, savedAt: Date, acknowledgedAt: Date? = nil, deletions: [CallRecapDeletion] = []) {
        self.callId = callId
        self.recap = recap
        self.digest = digest
        self.savedAt = savedAt
        self.acknowledgedAt = acknowledgedAt
        self.deletions = deletions
    }

    public var id: UUID { callId }
    /// The server still holds a copy (the acknowledgement hasn't been confirmed yet).
    public var serverCopyPending: Bool { acknowledgedAt == nil }
}

public protocol CallRecapRepository: Sendable {
    /// Inserts or replaces; returns what was read back (a mismatch throws).
    func save(_ record: StoredCallRecap) async throws -> StoredCallRecap
    func get(_ callId: UUID) async throws -> StoredCallRecap?
    /// Newest first.
    func list() async throws -> [StoredCallRecap]
    func delete(_ callId: UUID) async throws
    func deleteAll() async throws
}

public struct UnavailableCallRecapRepository: CallRecapRepository {
    public init() {}
    public func save(_ record: StoredCallRecap) async throws -> StoredCallRecap { throw LearningStoreError.verificationFailed }
    public func get(_ callId: UUID) async throws -> StoredCallRecap? { nil }
    public func list() async throws -> [StoredCallRecap] { [] }
    public func delete(_ callId: UUID) async throws {}
    public func deleteAll() async throws {}
}

/// The three server calls the recap flow needs (`DoddyServerClient` in the app; a fake in tests).
public protocol CallRecapBackend: Sendable {
    func callRecap(_ callId: UUID) async throws -> CallRecapReply
    func acknowledgeCallRecap(_ callId: UUID, digest: String) async throws -> [CallRecapDeletion]
    func deleteCallRecap(_ callId: UUID) async throws -> [CallRecapDeletion]
}

/// What the app can show for one call.
public enum CallRecapLoad: Equatable, Sendable {
    /// On this iPhone. `serverCopyPending` says whether the server still has its copy.
    case saved(StoredCallRecap)
    /// The server is still building it (the transcript arrives a little after the call ends).
    case waiting
    /// No recap for this call (an older call, or the post-call webhook isn't set up).
    case none
    /// The server's copy is gone (saved on another iPhone, deleted, or past 30 days) and it isn't here.
    case gone(CallRecapState)
}

/// Fetch, save here, then acknowledge (DOD-06: the server deletes only what is safely stored here).
public struct CallRecapLoader: Sendable {
    let backend: any CallRecapBackend
    let repository: any CallRecapRepository
    let now: @Sendable () -> Date

    public init(backend: any CallRecapBackend, repository: any CallRecapRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.repository = repository
        self.now = now
    }

    public func load(_ callId: UUID) async throws -> CallRecapLoad {
        if let local = try await repository.get(callId) {
            // Saved before; if the acknowledgement didn't get through then, try again now.
            return .saved(local.serverCopyPending ? ((try? await acknowledge(local)) ?? local) : local)
        }
        let reply = try await backend.callRecap(callId)
        switch CallRecapState(server: reply.state) {
        case .ready:
            guard let recap = reply.recap, let digest = reply.digest, digest.count == 64 else {
                throw ServerError.unexpected(status: 200)
            }
            let saved = try await repository.save(StoredCallRecap(callId: callId, recap: recap, digest: digest, savedAt: now()))
            // A failed acknowledgement leaves the server's copy; it is tried again next time.
            return .saved((try? await acknowledge(saved)) ?? saved)
        case .waiting: return .waiting
        case .none: return .none
        case let state: return .gone(state)
        }
    }

    /// Deletes the server's copy (if it still has one), then this iPhone's.
    public func delete(_ callId: UUID) async throws {
        _ = try await backend.deleteCallRecap(callId)
        try await repository.delete(callId)
    }

    private func acknowledge(_ local: StoredCallRecap) async throws -> StoredCallRecap {
        let deletions = try await backend.acknowledgeCallRecap(local.callId, digest: local.digest)
        var updated = local
        updated.acknowledgedAt = now()
        updated.deletions = deletions
        return try await repository.save(updated)
    }
}

extension DoddyServerClient: CallRecapBackend {
    public func callRecap(_ callId: UUID) async throws -> CallRecapReply {
        try await getJSON("/v1/calls/\(callId.uuidString.lowercased())/recap")
    }

    public func acknowledgeCallRecap(_ callId: UUID, digest: String) async throws -> [CallRecapDeletion] {
        let response = try await authorized(.post, "/v1/calls/\(callId.uuidString.lowercased())/recap/ack",
                                            body: try Self.json(RecapAckBody(digest: digest)))
        guard response.status == 200, let body = try? JSONDecoder().decode(RecapDeletionsReply.self, from: response.body)
        else { throw Self.error(from: response) }
        return body.deletions
    }

    /// A 404 means the server holds no recap for this call, which is what was asked for.
    public func deleteCallRecap(_ callId: UUID) async throws -> [CallRecapDeletion] {
        let response = try await authorized(.delete, "/v1/calls/\(callId.uuidString.lowercased())/recap", body: nil)
        if response.status == 404 { return [] }
        guard response.status == 200, let body = try? JSONDecoder().decode(RecapDeletionsReply.self, from: response.body)
        else { throw Self.error(from: response) }
        return body.deletions
    }
}

private struct RecapAckBody: Encodable { let digest: String }
private struct RecapDeletionsReply: Decodable { let deletions: [CallRecapDeletion] }
