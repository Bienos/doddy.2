import XCTest
@testable import DoddyCore

/// Recaps of calls with Doddy (ADR-693): decoding the server's reply, and saving before acknowledging.
final class CallRecapTests: XCTestCase {
    private let callId = UUID(uuidString: "6F9619FF-8B86-4D11-B42D-00C04FC964FF")!
    private let digest = String(repeating: "a", count: 64)

    /// A reply as server/messaging/src/callRecaps/service.ts writes it.
    private var readyJSON: String {
        """
        {"callId":"6f9619ff-8b86-4d11-b42d-00c04fc964ff","state":"ready","digest":"\(digest)","recap":{
          "format":1,"callId":"6f9619ff-8b86-4d11-b42d-00c04fc964ff","direction":"inbound","startedAt":"2026-11-02T12:00:00.000Z",
          "durationSecs":42,"summary":"Poprosiłeś o notatkę o dentyście.","summaryBy":"doddy_model","summaryNote":null,"language":"pl",
          "agreed":[{"text":"Dentysta jutro","line":1,"quote":"jutro o 10 mam dentystę"}],"couldNotDo":[],
          "notes":[{"id":"n1","text":"Jutro o 10 dentysta","createdAt":"2026-11-02T12:00:20.000Z"}],"nextStep":null,
          "transcript":[{"speaker":"doddy","text":"Hi, this is Doddy.","atSecs":0},{"speaker":"caller","text":"Zapisz, że jutro o 10 mam dentystę.","atSecs":3.5}],
          "droppedPointers":0,"builtAt":"2026-11-02T12:01:00.000Z"}}
        """
    }

    func testReplyDecodesAndPointsAtItsLine() throws {
        let reply = try JSONDecoder().decode(CallRecapReply.self, from: Data(readyJSON.utf8))
        let recap = try XCTUnwrap(reply.recap)
        XCTAssertTrue(recap.hasSummary)
        XCTAssertNil(recap.missingSummaryReason)
        XCTAssertEqual(recap.line(for: recap.agreed[0])?.text, "Zapisz, że jutro o 10 mam dentystę.")
        XCTAssertEqual(recap.notes.map(\.text), ["Jutro o 10 dentysta"])
        XCTAssertNotNil(recap.startedDate)
        XCTAssertEqual(CallRecapState(server: reply.state), .ready)
    }

    func testARulesOnlyRecapSaysWhyItHasNoSummary() {
        let recap = CallRecap(callId: "c", direction: "outbound", summary: nil, summaryBy: "rules", summaryNote: "daily_limit", builtAt: "x")
        XCTAssertFalse(recap.hasSummary)
        XCTAssertEqual(recap.missingSummaryReason, .dailyLimit)
        XCTAssertEqual(CallRecap(callId: "c", direction: "inbound", summary: nil, summaryBy: "rules", summaryNote: "new_reason", builtAt: "x")
            .missingSummaryReason, .unknown)
    }

    func testOlderServersSendNoRecapStateInTheCallList() throws {
        let old = try JSONDecoder().decode(CallRecord.self, from: Data(#"{"id":"\#(callId.uuidString)","direction":"inbound","status":"started","createdAt":"2026-11-02T12:00:00Z"}"#.utf8))
        XCTAssertEqual(old.recapState, .none)
        let new = try JSONDecoder().decode(CallRecord.self, from: Data(#"{"id":"\#(callId.uuidString)","direction":"inbound","status":"started","createdAt":"2026-11-02T12:00:00Z","recap":"waiting"}"#.utf8))
        XCTAssertEqual(new.recapState, .waiting)
    }

    func testTheClientUsesLowercaseIdsAndSendsTheDigestBack() async throws {
        let transport = StepTransport([
            .success(ServerResponse(status: 200, body: Data(readyJSON.utf8))),
            .success(ServerResponse(status: 200, body: Data(#"{"deletions":[{"what":"recap","reason":"acked","deletedAt":"2026-11-02T12:02:00Z"}]}"#.utf8))),
            .success(ServerResponse(status: 404, body: Data(#"{"error":"not_found"}"#.utf8))),
        ])
        let client = DoddyServerClient(transport: transport, credentials: FixedCredentials(token: "t"))
        _ = try await client.callRecap(callId)
        let deletions = try await client.acknowledgeCallRecap(callId, digest: digest)
        XCTAssertEqual(deletions.map(\.what), ["recap"])
        let none = try await client.deleteCallRecap(callId)
        XCTAssertEqual(none, [], "404: the server has none, which is what was asked")
        let sent = await transport.sent
        let path = "/v1/calls/6f9619ff-8b86-4d11-b42d-00c04fc964ff/recap"
        XCTAssertEqual(sent.map(\.path), [path, path + "/ack", path])
        XCTAssertEqual(String(decoding: try XCTUnwrap(sent[1].body), as: UTF8.self), #"{"digest":"\#(digest)"}"#)
    }

    // MARK: Save, then acknowledge

    func testTheServerCopyIsAcknowledgedOnlyAfterTheRecapIsSavedHere() async throws {
        let reply = try JSONDecoder().decode(CallRecapReply.self, from: Data(readyJSON.utf8))
        let backend = FakeRecapBackend(reply: reply)
        let repo = MemoryRecapRepository()
        let loaded = try await CallRecapLoader(backend: backend, repository: repo).load(callId)
        guard case .saved(let stored) = loaded else { return XCTFail("expected saved, got \(loaded)") }
        XCTAssertFalse(stored.serverCopyPending)
        XCTAssertEqual(stored.deletions.map(\.what), ["recap"])
        let events = await backend.events
        XCTAssertEqual(events, ["get", "ack"])
        let savedBeforeAck = await repo.savesBeforeFirstAck(events: events)
        XCTAssertTrue(savedBeforeAck)
    }

    func testAFailedSaveNeverAcknowledges() async throws {
        let reply = try JSONDecoder().decode(CallRecapReply.self, from: Data(readyJSON.utf8))
        let backend = FakeRecapBackend(reply: reply)
        do {
            _ = try await CallRecapLoader(backend: backend, repository: UnavailableCallRecapRepository()).load(callId)
            XCTFail("a failed save must throw")
        } catch {}
        let events = await backend.events
        XCTAssertEqual(events, ["get"], "the server keeps its copy")
    }

    func testAFailedAcknowledgementKeepsTheRecapAndIsRetriedNextTime() async throws {
        let reply = try JSONDecoder().decode(CallRecapReply.self, from: Data(readyJSON.utf8))
        let backend = FakeRecapBackend(reply: reply, ackFails: 1)
        let repo = MemoryRecapRepository()
        let loader = CallRecapLoader(backend: backend, repository: repo)
        guard case .saved(let first) = try await loader.load(callId) else { return XCTFail("expected saved") }
        XCTAssertTrue(first.serverCopyPending)
        guard case .saved(let second) = try await loader.load(callId) else { return XCTFail("expected saved") }
        XCTAssertFalse(second.serverCopyPending)
        let events = await backend.events
        XCTAssertEqual(events, ["get", "ack", "ack"], "read from this iPhone the second time, only the ack is repeated")
    }

    func testWaitingNoneAndGoneAreNotSaved() async throws {
        for (state, expected) in [("waiting", CallRecapLoad.waiting), ("none", .none), ("acked", .gone(.acked)), ("expired", .gone(.expired))] {
            let backend = FakeRecapBackend(reply: CallRecapReply(callId: "x", state: state, recap: nil, digest: nil))
            let repo = MemoryRecapRepository()
            let result = try await CallRecapLoader(backend: backend, repository: repo).load(callId)
            XCTAssertEqual(result, expected, state)
            let saved = try await repo.list()
            XCTAssertTrue(saved.isEmpty, state)
        }
    }

    func testDeleteRemovesTheServerCopyBeforeThisIPhonesOne() async throws {
        let reply = try JSONDecoder().decode(CallRecapReply.self, from: Data(readyJSON.utf8))
        let failing = FakeRecapBackend(reply: reply, deleteFails: true)
        let repo = MemoryRecapRepository()
        let loader = CallRecapLoader(backend: failing, repository: repo)
        _ = try await loader.load(callId)
        do {
            try await loader.delete(callId)
            XCTFail("a failed server delete must throw")
        } catch {}
        let kept = try await repo.get(callId)
        XCTAssertNotNil(kept, "kept here while the server's delete failed")
        try await CallRecapLoader(backend: FakeRecapBackend(reply: reply), repository: repo).delete(callId)
        let gone = try await repo.get(callId)
        XCTAssertNil(gone)
    }
}

private actor FakeRecapBackend: CallRecapBackend {
    let reply: CallRecapReply
    var ackFails: Int
    let deleteFails: Bool
    private(set) var events: [String] = []

    init(reply: CallRecapReply, ackFails: Int = 0, deleteFails: Bool = false) {
        self.reply = reply
        self.ackFails = ackFails
        self.deleteFails = deleteFails
    }

    func callRecap(_ callId: UUID) async throws -> CallRecapReply {
        events.append("get")
        return reply
    }

    func acknowledgeCallRecap(_ callId: UUID, digest: String) async throws -> [CallRecapDeletion] {
        events.append("ack")
        if ackFails > 0 {
            ackFails -= 1
            throw ServerError.offline
        }
        return [CallRecapDeletion(what: "recap", reason: "acked", deletedAt: "2026-11-02T12:02:00Z")]
    }

    func deleteCallRecap(_ callId: UUID) async throws -> [CallRecapDeletion] {
        events.append("delete")
        if deleteFails { throw ServerError.offline }
        return []
    }
}

/// Records the order of saves, so a test can check the recap was stored before the acknowledgement.
private actor MemoryRecapRepository: CallRecapRepository {
    private var rows: [UUID: StoredCallRecap] = [:]
    private(set) var saves: [Bool] = [] // serverCopyPending of each save

    func save(_ record: StoredCallRecap) async throws -> StoredCallRecap {
        rows[record.callId] = record
        saves.append(record.serverCopyPending)
        return record
    }
    func get(_ callId: UUID) async throws -> StoredCallRecap? { rows[callId] }
    func list() async throws -> [StoredCallRecap] { Array(rows.values) }
    func delete(_ callId: UUID) async throws { rows[callId] = nil }
    func deleteAll() async throws { rows = [:] }

    /// The first save stored the recap with the server copy still pending, i.e. before the ack returned.
    func savesBeforeFirstAck(events: [String]) -> Bool { saves.first == true && events.firstIndex(of: "ack") != nil }
}
