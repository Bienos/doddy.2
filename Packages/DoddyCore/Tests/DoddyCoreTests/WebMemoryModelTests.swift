import Foundation
import XCTest
@testable import DoddyCore

/// A server stand-in: every call is recorded, and each kind of call takes the next scripted answer
/// (the last one repeats).
private final class FakeMemory: WebMemoryClient, @unchecked Sendable {
    private let lock = NSLock()
    var states: [Result<WebMemoryState, WebMemoryError>] = []
    var notes: [Result<Int, WebMemoryError>] = []
    var conversations: [Result<Void, WebMemoryError>] = [.success(())]
    var deletes: [Result<WebMemoryState, WebMemoryError>] = []
    private(set) var stateCalls: [(notes: Bool, conversations: Bool)] = []
    private(set) var sentNotes: [[KeptNote]] = []
    private(set) var sentConversations: [KeptConversation] = []
    private(set) var deleteCalls = 0

    private func next<T>(_ list: inout [Result<T, WebMemoryError>]) -> Result<T, WebMemoryError> {
        list.count > 1 ? list.removeFirst() : list[0]
    }

    func setState(notes: Bool, conversations: Bool) async throws(WebMemoryError) -> WebMemoryState {
        try lock.withLock {
            stateCalls.append((notes, conversations))
            return next(&states)
        }.get()
    }

    func replaceNotes(_ items: [KeptNote]) async throws(WebMemoryError) -> Int {
        try lock.withLock {
            sentNotes.append(items)
            return notes.isEmpty ? .success(items.count) : next(&notes)
        }.get()
    }

    func putConversation(_ conversation: KeptConversation) async throws(WebMemoryError) {
        try lock.withLock {
            sentConversations.append(conversation)
            return next(&conversations)
        }.get()
    }

    func deleteAll() async throws(WebMemoryError) -> WebMemoryState {
        try lock.withLock {
            deleteCalls += 1
            return next(&deletes)
        }.get()
    }
}

private func note(_ n: Int, _ text: String) -> MemoryRecord {
    try! MemoryRecord(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!, rawText: text, source: .explicitVoice, category: .fact, capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(n)))
}

private func log(_ n: Int = 1, lines: Int = 2) -> ConversationLog {
    ConversationLog(
        id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", 100 + n))!, startedAt: Date(timeIntervalSince1970: 1_000), endedAt: Date(timeIntervalSince1970: 1_100),
        lines: (0..<lines).map { .init(fromUser: $0 % 2 == 0, text: "Line \($0)") }, ended: "user")
}

private func freshDefaults() -> UserDefaults {
    let suite = "doddy.tests.webmemory.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let on = WebMemoryState(notes: true, conversations: true)
private let notesOnly = WebMemoryState(notes: true, conversations: false)
private let allOff = WebMemoryState(notes: false, conversations: false)

@MainActor
final class WebMemoryModelTests: XCTestCase {
    private func model(_ fake: FakeMemory?, renewed: FakeMemory? = nil, defaults: UserDefaults? = nil) -> WebMemoryModel {
        WebMemoryModel(makeClient: { fake }, renewClient: { renewed }, defaults: defaults ?? freshDefaults(), now: { Date(timeIntervalSince1970: 5_000) })
    }

    func testEverythingStartsOff() {
        let model = model(FakeMemory())
        XCTAssertFalse(model.notesOn)
        XCTAssertFalse(model.conversationsOn)
        XCTAssertEqual(model.notesStatus, .idle)
    }

    func testASwitchTurnsOnOnlyAfterTheServerSaidYesAndNotesAreSentAtOnce() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly)]
        let model = model(fake)
        let ok = await model.setKept(.notes, on: true, records: [note(1, "Anna's birthday"), note(2, "Dentist")], privateNotes: PrivateNotes())
        XCTAssertTrue(ok)
        XCTAssertTrue(model.notesOn)
        XCTAssertFalse(model.conversationsOn)
        XCTAssertEqual(fake.stateCalls.map { [$0.notes, $0.conversations] }, [[true, false]])
        XCTAssertEqual(fake.sentNotes.count, 1)
        XCTAssertEqual(fake.sentNotes[0].map(\.text), ["Anna's birthday", "Dentist"])
        XCTAssertEqual(model.notesStatus, .sent(count: 2, at: Date(timeIntervalSince1970: 5_000)))
    }

    func testTheSwitchIsStoredSoItSurvivesARelaunch() async {
        let defaults = freshDefaults()
        let fake = FakeMemory()
        fake.states = [.success(on)]
        let first = model(fake, defaults: defaults)
        await first.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())
        let relaunched = model(fake, defaults: defaults)
        XCTAssertTrue(relaunched.conversationsOn)
        XCTAssertTrue(relaunched.notesOn)
    }

    func testAServerThatDoesntAnswerLeavesTheSwitchOffAndSaysWhy() async {
        let fake = FakeMemory()
        fake.states = [.failure(.transport)]
        let model = model(fake)
        let ok = await model.setKept(.notes, on: true, records: [note(1, "x")], privateNotes: PrivateNotes())
        XCTAssertFalse(ok)
        XCTAssertFalse(model.notesOn, "nothing is shown as kept until the server said so")
        XCTAssertEqual(model.problem, .offline)
        XCTAssertTrue(fake.sentNotes.isEmpty)
    }

    func testAServerWithNoKeyIsSaidPlainly() async {
        let fake = FakeMemory()
        fake.states = [.failure(.notSetUp)]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        XCTAssertEqual(model.problem, .notSetUp)
        XCTAssertFalse(model.notesOn)
    }

    func testTurningNotesOffAsksTheServerToDeleteThemAndKeepsTheOtherKind() async {
        let fake = FakeMemory()
        fake.states = [.success(on), .success(WebMemoryState(notes: false, conversations: true, deletedNotes: 4))]
        let model = model(fake)
        await model.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())
        await model.setKept(.notes, on: false, records: [], privateNotes: PrivateNotes())
        XCTAssertEqual(fake.stateCalls.last.map { [$0.notes, $0.conversations] }, [false, true])
        XCTAssertFalse(model.notesOn)
        XCTAssertTrue(model.conversationsOn)
        XCTAssertEqual(model.notesStatus, .idle)
    }

    func testAFailedSwitchOffStaysOnBecauseNothingWasDeleted() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly), .failure(.server(message: "x"))]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        let ok = await model.setKept(.notes, on: false, records: [], privateNotes: PrivateNotes())
        XCTAssertFalse(ok)
        XCTAssertTrue(model.notesOn, "the server still holds the notes, so the switch still says so")
        XCTAssertEqual(model.problem, .server)
    }

    func testPrivateNotesNeverGoInTheList() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly)]
        let model = model(fake)
        let secret = note(2, "PRIVATE diagnosis")
        await model.setKept(.notes, on: true, records: [note(1, "Anna's birthday"), secret], privateNotes: PrivateNotes(ids: [secret.id]))
        XCTAssertEqual(fake.sentNotes[0].map(\.text), ["Anna's birthday"])
    }

    func testAFailedNoteSendKeepsTheSwitchOnAndIsRetried() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly)]
        fake.notes = [.failure(.transport), .success(1)]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [note(1, "Anna")], privateNotes: PrivateNotes())
        XCTAssertTrue(model.notesOn, "the server confirmed the switch")
        XCTAssertEqual(model.notesStatus, .failed(.offline), "and the page doesn't claim the notes were sent")
        XCTAssertTrue(model.needsNotesRetry)
        model.retryIfNeeded([note(1, "Anna")], privateNotes: PrivateNotes(), notesLoaded: true)
        await model.settle()
        XCTAssertEqual(fake.sentNotes.count, 2)
        XCTAssertEqual(model.notesStatus, .sent(count: 1, at: Date(timeIntervalSince1970: 5_000)))
        XCTAssertFalse(model.needsNotesRetry)
    }

    func testTheListIsNotSentAfterAFailedReadOfTheNotes() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly)]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [note(1, "Anna")], privateNotes: PrivateNotes())
        model.retryIfNeeded([], privateNotes: PrivateNotes(), notesLoaded: false)
        await model.settle()
        XCTAssertEqual(fake.sentNotes.count, 1, "an empty or stale list would wipe or roll back the server's notes")
    }

    func testAnUpToDateListIsNotSentAgainWithoutReason() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly)]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [note(1, "Anna")], privateNotes: PrivateNotes())
        model.retryIfNeeded([note(1, "Anna")], privateNotes: PrivateNotes(), notesLoaded: true)
        await model.settle()
        XCTAssertEqual(fake.sentNotes.count, 1)
    }

    func testABurstOfEditsIsOneSendWithTheLatestList() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly)]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        model.scheduleNotes([note(1, "first")], privateNotes: PrivateNotes(), delay: .milliseconds(80))
        model.scheduleNotes([note(1, "first"), note(2, "second")], privateNotes: PrivateNotes(), delay: .milliseconds(80))
        await model.settle()
        XCTAssertEqual(fake.sentNotes.count, 2, "the empty list at switching on, then one for the burst")
        XCTAssertEqual(fake.sentNotes.last?.map(\.text), ["first", "second"])
    }

    func testNothingIsScheduledWhileNotesAreOff() async {
        let fake = FakeMemory()
        let model = model(fake)
        model.scheduleNotes([note(1, "x")], privateNotes: PrivateNotes(), delay: .zero)
        await model.settle()
        XCTAssertTrue(fake.sentNotes.isEmpty)
    }

    func testTheServerSayingItIsOffSwitchesTheLocalSwitchOffAndStops() async {
        let fake = FakeMemory()
        fake.states = [.success(on)]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        fake.notes = [.failure(.off)]
        await model.sendNotes([note(1, "x")], privateNotes: PrivateNotes())
        XCTAssertFalse(model.notesOn, "deleted from the web: the iPhone stops sending")
        XCTAssertTrue(model.conversationsOn, "the other kind is untouched")
        XCTAssertFalse(model.needsNotesRetry)
        let sentBefore = fake.sentNotes.count
        await model.sendNotes([note(1, "x")], privateNotes: PrivateNotes())
        XCTAssertEqual(fake.sentNotes.count, sentBefore, "and doesn't try again")
    }

    func testARefusedSessionIsRenewedOnceThenTheActionIsRetried() async {
        let stale = FakeMemory()
        stale.states = [.failure(.unauthenticated)]
        let fresh = FakeMemory()
        fresh.states = [.success(notesOnly)]
        let model = model(stale, renewed: fresh)
        let ok = await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        XCTAssertTrue(ok)
        XCTAssertTrue(model.notesOn)
    }

    func testStillRefusedAfterRenewingIsSignedOutNotALoop() async {
        let stale = FakeMemory()
        stale.states = [.failure(.unauthenticated)]
        let alsoStale = FakeMemory()
        alsoStale.states = [.failure(.unauthenticated)]
        let model = model(stale, renewed: alsoStale)
        let ok = await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        XCTAssertFalse(ok)
        XCTAssertEqual(model.problem, .signedOut)
    }

    func testNoServerSaysSo() async {
        let model = model(nil)
        let ok = await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        XCTAssertFalse(ok)
        XCTAssertEqual(model.problem, .notConfigured)
    }

    func testTooManyTriesSaysHowLongToWait() async {
        let fake = FakeMemory()
        fake.states = [.failure(.rateLimited(retryAfterSeconds: 61))]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        XCTAssertEqual(model.problem, .tooMany(minutes: 2))
    }

    // MARK: delete everything

    func testDeletingEverythingSwitchesBothOffOnlyAfterTheServerConfirmed() async {
        let fake = FakeMemory()
        fake.states = [.success(on)]
        fake.deletes = [.failure(.transport), .success(WebMemoryState(notes: false, conversations: false, deletedNotes: 5, deletedConversations: 2))]
        let model = model(fake)
        await model.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())

        let failed = await model.deleteEverythingOnServer()
        XCTAssertNil(failed)
        XCTAssertTrue(model.notesOn && model.conversationsOn, "not confirmed: nothing changed, nothing claimed")
        XCTAssertEqual(model.problem, .offline)

        let done = await model.deleteEverythingOnServer()
        XCTAssertEqual(done?.deletedNotes, 5)
        XCTAssertEqual(done?.deletedConversations, 2)
        XCTAssertFalse(model.notesOn)
        XCTAssertFalse(model.conversationsOn)
        XCTAssertNil(model.problem)
    }

    // MARK: conversations

    func testAConversationIsSentWhenTheyAreKeptAndItIsNotPrivate() async {
        let fake = FakeMemory()
        fake.states = [.success(on)]
        let model = model(fake)
        await model.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())
        await model.sendConversation(log(), language: "pl", isPrivate: false)
        XCTAssertEqual(fake.sentConversations.count, 1)
        XCTAssertEqual(fake.sentConversations[0].turns.map(\.role), ["user", "doddy"])
        XCTAssertEqual(fake.sentConversations[0].language, "pl")
    }

    func testAPrivateConversationOrASwitchedOffKindSendsNothing() async {
        let fake = FakeMemory()
        fake.states = [.success(notesOnly), .success(on)]
        let model = model(fake)
        await model.setKept(.notes, on: true, records: [], privateNotes: PrivateNotes())
        await model.sendConversation(log(), language: "pl", isPrivate: false)
        XCTAssertTrue(fake.sentConversations.isEmpty, "conversations are off")
        await model.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())
        await model.sendConversation(log(2), language: "pl", isPrivate: true)
        XCTAssertTrue(fake.sentConversations.isEmpty, "a private conversation never leaves the iPhone")
        await model.sendConversation(log(3, lines: 0), language: "pl", isPrivate: false)
        XCTAssertTrue(fake.sentConversations.isEmpty, "nothing was said")
    }

    func testAConversationThatCouldntBeSentIsRetriedFromTheLogsTheiPhoneStillHas() async {
        let fake = FakeMemory()
        fake.states = [.success(on)]
        fake.conversations = [.failure(.transport), .success(())]
        let defaults = freshDefaults()
        let model = model(fake, defaults: defaults)
        await model.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())
        let first = log(1)
        let second = log(2)
        await model.sendConversation(first, language: "en", isPrivate: false)
        XCTAssertEqual(fake.sentConversations.count, 1)

        // At the next launch only the conversation that failed is sent again; the other was never pending.
        await model.retryConversations(from: [first, second], language: "en")
        XCTAssertEqual(fake.sentConversations.map(\.id), [first.id, first.id])
        await model.retryConversations(from: [first, second], language: "en")
        XCTAssertEqual(fake.sentConversations.count, 2, "once it went through it is not sent again")
    }

    func testTheServerSayingConversationsAreOffStopsThemAndForgetsTheQueue() async {
        let fake = FakeMemory()
        fake.states = [.success(on)]
        fake.conversations = [.failure(.off)]
        let model = model(fake)
        await model.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())
        await model.sendConversation(log(), language: "en", isPrivate: false)
        XCTAssertFalse(model.conversationsOn)
        XCTAssertTrue(model.notesOn, "notes are untouched")
        await model.sendConversation(log(2), language: "en", isPrivate: false)
        XCTAssertEqual(fake.sentConversations.count, 1, "and it doesn't try again")
    }

    func testAConversationTheServerSaysIsTooBigIsNotRetriedForever() async {
        let fake = FakeMemory()
        fake.states = [.success(on)]
        fake.conversations = [.failure(.tooLarge)]
        let model = model(fake)
        await model.setKept(.conversations, on: true, records: [], privateNotes: PrivateNotes())
        let big = log()
        await model.sendConversation(big, language: "en", isPrivate: false)
        await model.retryConversations(from: [big], language: "en")
        XCTAssertEqual(fake.sentConversations.count, 1)
    }
}
