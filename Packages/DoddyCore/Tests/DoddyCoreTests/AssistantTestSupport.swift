import Foundation
@testable import DoddyCore

enum Fixtures {
    /// Repository root, found from this file's path (Packages/DoddyCore/Tests/DoddyCoreTests/...).
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("schemas/fixtures/\(name)"))
    }

    static func json(_ name: String) throws -> [String: Any] {
        try XCTUnwrapJSON(data(name))
    }

    static func XCTUnwrapJSON(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.notAnObject
        }
        return object
    }

    enum FixtureError: Error { case notAnObject }
}

func makeRecord(
    _ text: String = "Parked on level 3",
    id: UUID = UUID(),
    source: MemorySource = .explicitText,
    capturedAt: Date? = Date(timeIntervalSince1970: 1_790_000_000)
) throws -> MemoryRecord {
    try MemoryRecord(id: id, rawText: text, source: source, capturedAt: source == .importedLegacyUnknown ? nil : capturedAt)
}

func candidate(_ record: MemoryRecord, terms: [String] = ["parked"]) -> MemoryCandidate {
    MemoryCandidate(record: record, matchedTerms: terms)
}

/// Scripted assistant client that records what it was asked.
actor FakeAssistantClient: AssistantClient {
    private var script: [Result<AssistantReply, any Error>]
    private(set) var requests: [AssistantRequest] = []

    init(_ script: [Result<AssistantReply, any Error>]) { self.script = script }

    func respond(_ request: AssistantRequest) async throws -> AssistantReply {
        requests.append(request)
        let next = script.count > 1 ? script.removeFirst() : script[0]
        return try next.get()
    }
}

struct FakeRecall: RecallService {
    let outcome: Result<RecallOutcome, any Error>
    let onCall: @Sendable () -> Void

    init(_ outcome: Result<RecallOutcome, any Error>, onCall: @escaping @Sendable () -> Void = {}) {
        self.outcome = outcome
        self.onCall = onCall
    }

    func recall(_ question: String, limit: Int) async throws -> RecallOutcome {
        onCall()
        return try outcome.get()
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

actor SleepRecorder {
    private(set) var waits: [Duration] = []
    func record(_ duration: Duration) { waits.append(duration) }
}
