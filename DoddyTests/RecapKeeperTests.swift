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

    // MARK: - Conversations with Doddy (step 3a)

    private func lines(_ words: Int) -> [RecapModelIO.Line] {
        [.init(speaker: .person, text: Array(repeating: "słowo", count: words).joined(separator: " ")),
         .init(speaker: .doddy, text: "Jasne.")]
    }

    @MainActor
    func testAConversationIsNotRecappedWhileOffPrivateOrShort() async throws {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let start = Date()
        let off = await RecapKeeper.recapConversation(lines: lines(100), startedAt: start, endedAt: start, isPrivate: false,
                                                      store: store, defaults: defaults)
        XCTAssertEqual(off, .skipped(.switchedOff))

        RecapKeeper.setRemember(true, defaults: defaults, now: start.addingTimeInterval(-60))
        let hidden = await RecapKeeper.recapConversation(lines: lines(100), startedAt: start, endedAt: start, isPrivate: true,
                                                         store: store, defaults: defaults)
        XCTAssertEqual(hidden, .skipped(.privateConversation))
        let short = await RecapKeeper.recapConversation(lines: lines(RecapRules.minimumWordsFromPerson - 1), startedAt: start,
                                                        endedAt: start, isPrivate: false, store: store, defaults: defaults)
        XCTAssertEqual(short, .skipped(.tooShort))
        XCTAssertTrue(store.memories.isEmpty)
    }

    @MainActor
    func testWithoutAppleIntelligenceAndWithoutTheServerThereIsNoRecap() async throws {
        try XCTSkipIf(OnDeviceRecapWriter.isAvailable(languageCode: RecapKeeper.languageCode),
                      "this device can write recaps itself")
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let start = Date()
        RecapKeeper.setRemember(true, defaults: defaults, now: start.addingTimeInterval(-60))
        let outcome = await RecapKeeper.recapConversation(lines: lines(100), startedAt: start, endedAt: start,
                                                          isPrivate: false, store: store, defaults: defaults)
        XCTAssertEqual(outcome, .skipped(.noWriter))
        XCTAssertTrue(store.memories.isEmpty)
    }

    @MainActor
    func testTheModelsAnswerIsTakenFromAroundItsJSON() {
        XCTAssertEqual(OnDeviceRecapWriter.json(in: "```json\n{\"discussed\": []}\n```"), "{\"discussed\": []}")
        XCTAssertEqual(OnDeviceRecapWriter.json(in: "no json"), "no json")
    }

    // MARK: - Recordings (step 4)

    private func recording(language: String = "pl-PL") -> Recording {
        Recording(id: UUID(), origin: .app, phase: .saved, languageCode: language, startedAt: Date().addingTimeInterval(-600),
                  endedAt: Date().addingTimeInterval(-60), durationMilliseconds: 540_000, transcription: .done)
    }

    private func segments(words: Int) -> [TranscriptSegment] {
        [TranscriptSegment(index: 0, startMilliseconds: 0, endMilliseconds: 5_000,
                           text: Array(repeating: "słowo", count: words).joined(separator: " "))]
    }

    @MainActor
    func testARecordingsWordsBecomeLinesWithNoSpeakerGuessed() {
        let lines = RecapKeeper.lines(from: segments(words: 3))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.speaker, .other, "no on-device recognizer says who spoke, and Doddy doesn't guess")
        XCTAssertEqual(RecapKeeper.language(of: recording(language: "pl-PL")), "pl")
        XCTAssertEqual(RecapKeeper.language(of: recording(language: "en_GB")), "en")
    }

    @MainActor
    func testATooShortRecordingIsNotRecappedEvenWhenAskedFor() async {
        let result = await RecapKeeper.writeRecap(for: recording(), segments: segments(words: RecapRules.minimumWordsFromPerson - 1),
                                                  explicit: true, defaults: defaults)
        guard case .skipped(.tooShort) = result else { return XCTFail("\(result)") }
    }

    @MainActor
    func testTheTapStandsInForTheSwitchButNeverForTheServerYes() async throws {
        try XCTSkipIf(OnDeviceRecapWriter.isAvailable(languageCode: "pl"), "this device can write recaps itself")
        // The switch is off and so is the server yes: a tap is not a yes to sending the words anywhere.
        XCTAssertFalse(RecapKeeper.isOn(defaults))
        let result = await RecapKeeper.writeRecap(for: recording(), segments: segments(words: 100), explicit: true, defaults: defaults)
        guard case .skipped(.noWriter) = result else { return XCTFail("\(result)") }
    }

    @MainActor
    func testASavedRecordingRecapIsOneNoteMarkedOnlyAfterTheReadBack() async throws {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let rec = recording()
        let written = try ConversationRecap(kind: .recording, with: nil, endedAt: Date(), discussed: ["Termin wizyty"],
                                            agreed: [], toDo: ["Zadzwonić w piątek"], writtenBy: .onDevice)
        XCTAssertFalse(RecapKeeper.hasRecap(recording: rec.id, defaults: defaults))
        let ok = await RecapKeeper.saveRecap(written, noteText: "Nagranie\n• Termin wizyty", recordingID: rec.id,
                                             recordingTitle: "Wizyta", store: store, defaults: defaults)
        XCTAssertTrue(ok)
        XCTAssertTrue(RecapKeeper.hasRecap(recording: rec.id, defaults: defaults))
        XCTAssertEqual(store.memories.first?.source, .conversationRecap)

        // A save that fails is not marked.
        let broken = MemoryStore(environment: .unavailable)
        let other = recording()
        let failed = await RecapKeeper.saveRecap(written, noteText: "x", recordingID: other.id, recordingTitle: "", store: broken,
                                                 defaults: defaults)
        XCTAssertFalse(failed)
        XCTAssertFalse(RecapKeeper.hasRecap(recording: other.id, defaults: defaults))
    }

    @MainActor
    func testNothingIsRecappedAutomaticallyWhileTheSwitchIsOff() async {
        let store = MemoryStore(environment: .live(arguments: ["-inMemoryStore"]))
        let saved = await RecapKeeper.rememberRecordings([RecordingListItem(recording: recording(), preview: nil)], store: store,
                                                         defaults: defaults)
        XCTAssertEqual(saved, 0)
        XCTAssertTrue(store.memories.isEmpty)
    }
}
