import DoddyCore
import Foundation
import XCTest
@testable import Doddy

/// Decision 2026-11-09-conversation-recaps, step 2: a call Doddy made for the person becomes a recap note
/// only while "Remember what we talked about" is on, once, and only for calls answered after it was
/// turned on. App-target test: hosted Mac job only.
final class RecapKeeperTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "RecapKeeperTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func answeredCall(at date: Date) throws -> StoredCallCase {
        let card = """
        {"outcome": "answered", "source": "transcript", "confidence": "high", "confidenceReasons": [],
         "summary": "Laptop będzie gotowy w piątek po 15.", "summaryBy": "rules",
         "quote": {"text": "W piątek po piętnastej", "line": 0},
         "transcript": [{"speaker": "callee", "text": "W piątek po piętnastej", "atSecs": 12}],
         "nextStep": {"kind": "pickup", "text": "Odebrać laptopa w piątek"}, "warnings": [], "callbackPromised": false,
         "takenOverAtSecs": null, "durationSecs": 64}
        """
        let result = try JSONDecoder().decode(CallResultCard.self, from: Data(card.utf8))
        var record = StoredCallCase(id: UUID(), createdAt: date, state: "completed",
                                    brief: CallBriefDraft(calleeName: "Serwis Laptop", phone: "221234567", principalName: "Anna",
                                                          goal: "Sprawdzić laptop.", question: "Czy laptop jest gotowy?"),
                                    resultAttemptId: UUID(), result: result)
        record.updatedAt = date
        return record
    }

    @MainActor
    func testNothingIsSavedWhileTheSwitchIsOff() async throws {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let saved = await RecapKeeper.rememberCalls([try answeredCall(at: Date())], store: store, defaults: defaults)
        XCTAssertEqual(saved, 0)
        XCTAssertTrue(store.memories.isEmpty)
    }

    @MainActor
    func testAnAnsweredCallIsSavedOnceAsARecapWithoutTheTranscript() async throws {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let on = Date().addingTimeInterval(-60)
        RecapKeeper.setRemember(true, defaults: defaults, now: on)
        let call = try answeredCall(at: Date())

        let saved1 = await RecapKeeper.rememberCalls([call], store: store, defaults: defaults)
        XCTAssertEqual(saved1, 1)
        let saved2 = await RecapKeeper.rememberCalls([call], store: store, defaults: defaults)
        XCTAssertEqual(saved2, 0, "once")
        let note = try XCTUnwrap(store.memories.first)
        XCTAssertEqual(store.memories.count, 1)
        XCTAssertEqual(note.source, .conversationRecap)
        XCTAssertTrue(note.currentText.contains("Czy laptop jest gotowy?"))
        XCTAssertTrue(note.currentText.contains("Odebrać laptopa w piątek"))
        XCTAssertFalse(note.currentText.contains("W piątek po piętnastej"), "never the transcript, not even the quote")
        XCTAssertTrue(RecapKeeper.hasRecap(call, defaults: defaults))

        // A deleted recap does not come back.
        try await store.delete(id: note.id)
        let saved3 = await RecapKeeper.rememberCalls([call], store: store, defaults: defaults)
        XCTAssertEqual(saved3, 0)
        XCTAssertTrue(store.memories.isEmpty)
    }

    @MainActor
    func testTurningTheSwitchOnIsNotAYesForEarlierCalls() async throws {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let earlier = try answeredCall(at: Date().addingTimeInterval(-3_600))
        RecapKeeper.setRemember(true, defaults: defaults, now: Date())
        let saved4 = await RecapKeeper.rememberCalls([earlier], store: store, defaults: defaults)
        XCTAssertEqual(saved4, 0)
        XCTAssertTrue(store.memories.isEmpty)

        RecapKeeper.setRemember(false, defaults: defaults)
        XCTAssertFalse(RecapKeeper.isOn(defaults))
        XCTAssertNil(RecapKeeper.since(defaults))
    }

    @MainActor
    func testAFailedSaveIsNotMarkedAndIsTriedAgain() async throws {
        let broken = MemoryStore(environment: .unavailable)
        RecapKeeper.setRemember(true, defaults: defaults, now: Date().addingTimeInterval(-60))
        let call = try answeredCall(at: Date())
        let saved5 = await RecapKeeper.rememberCalls([call], store: broken, defaults: defaults)
        XCTAssertEqual(saved5, 0)
        XCTAssertFalse(RecapKeeper.hasRecap(call, defaults: defaults), "nothing claimed without a read-back")

        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let saved6 = await RecapKeeper.rememberCalls([call], store: store, defaults: defaults)
        XCTAssertEqual(saved6, 1)
    }
}
