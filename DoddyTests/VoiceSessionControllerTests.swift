#if DEBUG
import DoddyCore
import Foundation
import XCTest
@testable import Doddy

/// The voice controller's confirmation cards with a fake Calendar (AppTests review 2026-10-11,
/// finding 2). App-target tests: NOT RUN in the authoring environment (no Xcode).
///
/// Tool calls arriving from the provider, and End then Start while one is still running, are in
/// `StaleToolCallTests` below (through `beginForTesting` and `receiveToolCallForTesting`). Not
/// covered, for lack of a seam: the alarm list (static `AlarmScheduler`), and a real `start`
/// (needs the microphone and a provider).
final class VoiceSessionControllerTests: XCTestCase {
    /// A controller with a fake Calendar and a fake provider link. `restore()` puts the Calendar
    /// switch back as it was; each test calls it in a `defer`.
    @MainActor
    fileprivate struct Harness {
        /// The switches the tests use, turned on for one test and put back by `restore()`.
        private static let switches: [VoiceConnection] = [.calendar, .reminders, .timers]

        let devices = FakeDevices()
        let link = FakeLink()
        let controller: VoiceSessionController
        private let savedSwitches: [VoiceConnection: Any?]
        /// "Listening" marks the first conversation as had (ADR-326); `beginForTesting` reaches it,
        /// so the flag is put back too, or the app's later UI tests would skip Home's first visit.
        private let savedFirstConversation: Any?

        init() {
            // The card re-checks Settings → Connections at the tap; turned on for this test only.
            var saved: [VoiceConnection: Any?] = [:]
            for connection in Self.switches {
                saved[connection] = UserDefaults.standard.object(forKey: connection.preferenceKey)
                UserDefaults.standard.set(true, forKey: connection.preferenceKey)
            }
            savedSwitches = saved
            savedFirstConversation = UserDefaults.standard.object(forKey: PreferenceKey.hadFirstConversation)
            controller = VoiceSessionController(
                store: MemoryStore(environment: .live(arguments: ["-inMemoryStore"])),
                activity: ActivityLogStore(fileURL: nil),
                devices: devices)
        }

        func show(_ action: VoiceSessionController.PendingAction) {
            controller.showCardForTesting(action, link: link)
        }

        func restore() {
            for (connection, value) in savedSwitches {
                UserDefaults.standard.set(value, forKey: connection.preferenceKey)
            }
            UserDefaults.standard.set(savedFirstConversation, forKey: PreferenceKey.hadFirstConversation)
        }
    }

    // MARK: Approved card runs exactly the approved payload, once

    @MainActor
    func testApprovedChangeRunsExactlyThatPlanOnce() async {
        let t = Harness()
        defer { t.restore() }
        let plan = Self.movePlan()
        t.show(.changeEvent(toolCallID: "call-1", plan: plan))

        await t.controller.confirmPendingAction()
        await t.controller.confirmPendingAction()  // a second tap: the card is gone

        XCTAssertEqual(t.devices.changedPlans, [plan])
        XCTAssertEqual(t.devices.writeCount, 1)
        XCTAssertNil(t.controller.pendingAction)
        XCTAssertEqual(t.link.results.map(\.id), ["call-1"])
        XCTAssertEqual(t.link.results.first?.text, VoiceToolReply.eventChanged(plan, calendar: .current))
    }

    @MainActor
    func testApprovedDeleteRemovesExactlyThatEventOnce() async {
        let t = Harness()
        defer { t.restore() }
        let event = Self.event(id: "evt-9", title: "Gym")
        t.show(.deleteEvent(toolCallID: "call-2", event: event))

        await t.controller.confirmPendingAction()
        await t.controller.confirmPendingAction()

        XCTAssertEqual(t.devices.deletedEvents, [event])
        XCTAssertEqual(t.devices.writeCount, 1)
        XCTAssertEqual(t.link.results.map(\.id), ["call-2"])
        XCTAssertEqual(t.link.results.first?.text, VoiceToolReply.eventDeleted(event, calendar: .current))
    }

    @MainActor
    func testTranslatorAsksFirstThenStartsOnATap() async {
        // ASK-01 (ADR-483): start_translator is a yesFirst ask, so a card comes first and
        // nothing starts until the user says yes. This replaces f40861c's "starts immediately".
        let t = Harness()
        defer { t.restore() }
        t.controller.beginForTesting(link: t.link)

        await t.controller.receiveToolCallForTesting(
            name: VoiceToolName.startTranslator, id: "translator-1", parameters: #"{"their_language":"es"}"#).value

        guard case .some(.ask) = t.controller.pendingAction else { return XCTFail("start_translator must ask first (ASK-01)") }
        XCTAssertNil(t.controller.translator)
        XCTAssertTrue(t.link.results.isEmpty)

        await t.controller.confirmPendingAction()

        XCTAssertEqual(t.controller.translator?.setup.other?.code, "es")
        XCTAssertEqual(t.link.results.map(\.id), ["translator-1"])
        XCTAssertTrue(t.link.results.first?.text.hasPrefix("started:") == true)
    }

    // MARK: Declined card runs nothing

    @MainActor
    func testDeclinedChangeRunsNothing() async {
        let t = Harness()
        defer { t.restore() }
        t.show(.changeEvent(toolCallID: "call-3", plan: Self.movePlan()))

        await t.controller.declinePendingAction()
        await t.controller.confirmPendingAction()  // a late confirm after decline does nothing

        XCTAssertEqual(t.devices.writeCount, 0)
        XCTAssertNil(t.controller.pendingAction)
        XCTAssertEqual(t.link.results.map(\.id), ["call-3"])
        XCTAssertEqual(t.link.results.first?.text, VoiceToolReply.changeDeclined)
    }

    @MainActor
    func testDeclinedDeleteRunsNothing() async {
        let t = Harness()
        defer { t.restore() }
        t.show(.deleteEvent(toolCallID: "call-4", event: Self.event(id: "evt-1", title: "Dentist")))

        await t.controller.declinePendingAction()

        XCTAssertEqual(t.devices.writeCount, 0)
        XCTAssertEqual(t.link.results.map(\.text), [VoiceToolReply.deleteDeclined])
    }

    // MARK: Failed and unconfirmed writes

    @MainActor
    func testThrowingChangeRepliesFailedNothingChanged() async throws {
        let t = Harness()
        defer { t.restore() }
        t.devices.changeEventResult = .failure(FakeWriteError())
        t.show(.changeEvent(toolCallID: "call-5", plan: Self.movePlan()))

        await t.controller.confirmPendingAction()

        let reply = try XCTUnwrap(t.link.results.first?.text)
        XCTAssertTrue(reply.hasPrefix("failed: "), reply)
        XCTAssertTrue(reply.hasSuffix("Nothing was changed."), reply)
        XCTAssertEqual(reply, VoiceToolReply.failed(UserFacingError.message(for: FakeWriteError()), nothing: .changed))
        XCTAssertEqual(t.devices.writeCount, 1)
        XCTAssertNil(t.controller.changeReceipt)
    }

    /// DOD-08: a change Calendar didn't confirm is `unknown`, never done.
    @MainActor
    func testUnconfirmedChangeRepliesUnknown() async throws {
        let t = Harness()
        defer { t.restore() }
        t.devices.changeEventResult = .success(.unconfirmed)
        t.show(.changeEvent(toolCallID: "call-6", plan: Self.movePlan()))

        await t.controller.confirmPendingAction()

        let reply = try XCTUnwrap(t.link.results.first?.text)
        XCTAssertTrue(reply.hasPrefix("unknown:"), reply)
        XCTAssertEqual(reply, VoiceToolReply.eventChangeUnconfirmed)
        XCTAssertNil(t.controller.changeReceipt)
    }

    // MARK: Fixtures

    private static func event(id: String, title: String) -> CalendarEventSummary {
        // Two days ahead, so the card's "time passed" check never fires.
        let start = Date().addingTimeInterval(2 * 86_400)
        return CalendarEventSummary(id: id, title: title, start: start, end: start.addingTimeInterval(3_600), allDay: false)
    }

    /// The same event, one hour later.
    private static func movePlan() -> EventChangePlan {
        let before = event(id: "evt-1", title: "Dentist")
        let after = CalendarEventSummary(
            id: before.id, title: before.title,
            start: before.start.addingTimeInterval(3_600), end: before.end.addingTimeInterval(3_600), allDay: false)
        return EventChangePlan(before: before, after: after)
    }
}

/// A tool call reaches only the conversation it came from (audit 2026-10-12 §5 #1 and #10,
/// ADR-458). Each test starts a conversation, lets a tool call get as far as a Reminders or
/// notification lookup, holds it there, taps End and starts a new conversation, and only then
/// lets the lookup finish. The last tests run the same calls without End, so a guard that
/// dropped everything would fail them. NOT RUN in the authoring environment (no Xcode).
final class StaleToolCallTests: XCTestCase {
    private typealias Harness = VoiceSessionControllerTests.Harness

    @MainActor
    func testACardFromAnEndedConversationNeverShowsInTheNextOne() async {
        let t = Harness()
        defer { t.restore() }
        t.devices.holdsReads = true
        t.devices.openReminders = [Self.reminder("Buy milk")]
        let first = FakeLink()
        t.controller.beginForTesting(link: first)
        let call = t.controller.receiveToolCallForTesting(
            name: VoiceToolName.deleteReminder, id: "old-delete", parameters: #"{"title":"Buy milk"}"#)
        await Self.waitUntilHeld(t.devices)

        await t.controller.stop()
        let second = FakeLink()
        t.controller.beginForTesting(link: second)
        t.devices.release()
        await call.value

        XCTAssertNil(t.controller.pendingAction, "the old call's card is not shown in the new conversation")
        await t.controller.confirmPendingAction()  // a tap in the new conversation has nothing to run
        XCTAssertEqual(t.devices.writeCount, 0)
        XCTAssertEqual(first.results, [], "nothing is sent to the ended conversation")
        XCTAssertEqual(second.results, [], "nor to the new one")
    }

    @MainActor
    func testAnAnswerForAnEndedConversationIsNotSentToTheNextOne() async {
        let t = Harness()
        defer { t.restore() }
        t.devices.holdsReads = true
        t.devices.openReminders = []  // the lookup ends in a reply ("not found"), not a card
        let first = FakeLink()
        t.controller.beginForTesting(link: first)
        let call = t.controller.receiveToolCallForTesting(
            name: VoiceToolName.deleteReminder, id: "old-lookup", parameters: #"{"title":"Buy milk"}"#)
        await Self.waitUntilHeld(t.devices)

        await t.controller.stop()
        let second = FakeLink()
        t.controller.beginForTesting(link: second)
        t.devices.release()
        await call.value

        XCTAssertEqual(first.results, [])
        XCTAssertEqual(second.results, [], "the new conversation never hears an answer to a question it didn't ask")
        XCTAssertNil(t.controller.pendingAction)
    }

    @MainActor
    func testATimerCardFromAnEndedConversationIsDropped() async {
        let t = Harness()
        defer { t.restore() }
        t.devices.holdsReads = true  // the notification permission check
        let first = FakeLink()
        t.controller.beginForTesting(link: first)
        let call = t.controller.receiveToolCallForTesting(
            name: VoiceToolName.setTimer, id: "old-timer", parameters: #"{"minutes":5}"#)
        await Self.waitUntilHeld(t.devices)

        await t.controller.stop()
        let second = FakeLink()
        t.controller.beginForTesting(link: second)
        t.devices.release()
        await call.value

        XCTAssertNil(t.controller.pendingAction)
        await t.controller.confirmPendingAction()
        XCTAssertEqual(t.devices.writeCount, 0, "no timer is started")
        XCTAssertEqual(first.results, [])
        XCTAssertEqual(second.results, [])
    }

    @MainActor
    func testACallStillQueuedWhenEndIsTappedLooksNothingUp() async {
        let t = Harness()
        defer { t.restore() }
        t.devices.openReminders = [Self.reminder("Buy milk")]
        let first = FakeLink()
        t.controller.beginForTesting(link: first)
        // The call arrives in the first conversation but hasn't run yet when End is tapped.
        let call = t.controller.receiveToolCallForTesting(
            name: VoiceToolName.deleteReminder, id: "queued", parameters: #"{"title":"Buy milk"}"#)
        await t.controller.stop()
        let second = FakeLink()
        t.controller.beginForTesting(link: second)
        await call.value

        XCTAssertEqual(t.devices.readCount, 0, "Reminders is not even read")
        XCTAssertNil(t.controller.pendingAction)
        XCTAssertEqual(first.results, [])
        XCTAssertEqual(second.results, [])
    }

    @MainActor
    func testACardOnScreenWhenEndIsTappedRunsNothingAfterTheNextStart() async {
        let t = Harness()
        defer { t.restore() }
        t.devices.openReminders = [Self.reminder("Buy milk")]
        let first = FakeLink()
        t.controller.beginForTesting(link: first)
        await t.controller.receiveToolCallForTesting(
            name: VoiceToolName.deleteReminder, id: "shown", parameters: #"{"title":"Buy milk"}"#).value
        XCTAssertNotNil(t.controller.pendingAction, "the card is up in the first conversation")

        await t.controller.stop()
        XCTAssertNil(t.controller.pendingAction, "End takes the card away")
        let second = FakeLink()
        t.controller.beginForTesting(link: second)
        await t.controller.confirmPendingAction()

        XCTAssertEqual(t.devices.writeCount, 0)
        XCTAssertEqual(second.results, [])
    }

    // MARK: The same calls without End still work

    @MainActor
    func testWithoutEndTheHeldCallShowsItsCardAndTheApprovedDeleteRunsOnce() async {
        let t = Harness()
        defer { t.restore() }
        t.devices.holdsReads = true
        let reminder = Self.reminder("Buy milk")
        t.devices.openReminders = [reminder]
        let link = FakeLink()
        t.controller.beginForTesting(link: link)
        let call = t.controller.receiveToolCallForTesting(
            name: VoiceToolName.deleteReminder, id: "now-delete", parameters: #"{"title":"Buy milk"}"#)
        await Self.waitUntilHeld(t.devices)
        t.devices.release()
        await call.value

        guard case .deleteReminder(let id, let shown)? = t.controller.pendingAction else {
            return XCTFail("expected the delete card, got \(String(describing: t.controller.pendingAction))")
        }
        XCTAssertEqual(id, "now-delete")
        XCTAssertEqual(shown, reminder)
        await t.controller.confirmPendingAction()
        await t.controller.confirmPendingAction()  // a second tap: the card is gone
        XCTAssertEqual(t.devices.writeCount, 1)
        XCTAssertEqual(link.results.map(\.id), ["now-delete"])
        XCTAssertEqual(link.results.first?.text, VoiceToolReply.reminderDeleted("Buy milk"))
    }

    @MainActor
    func testWithoutEndTheHeldLookupAnswersTheConversationThatAsked() async {
        let t = Harness()
        defer { t.restore() }
        t.devices.holdsReads = true
        let link = FakeLink()
        t.controller.beginForTesting(link: link)
        let call = t.controller.receiveToolCallForTesting(
            name: VoiceToolName.deleteReminder, id: "now-lookup", parameters: #"{"title":"Buy milk"}"#)
        await Self.waitUntilHeld(t.devices)
        t.devices.release()
        await call.value

        XCTAssertEqual(link.results.map(\.id), ["now-lookup"])
        XCTAssertEqual(link.results.first?.text, VoiceToolReply.reminderNotFound("Buy milk"))
    }

    // MARK: Helpers

    /// Lets the tool call run until its lookup is held. Fails rather than hangs if it never gets there.
    @MainActor
    private static func waitUntilHeld(_ devices: FakeDevices, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if devices.heldReads > 0 { return }
            await Task.yield()
        }
        XCTFail("the tool call never reached its lookup", file: file, line: line)
    }

    private static func reminder(_ title: String) -> ReminderSnapshot {
        ReminderSnapshot(id: "rem-\(title)", title: title, listTitle: "Reminders", due: nil, markerURL: nil)
    }
}

private struct FakeWriteError: Error {}

/// Calendar and Reminders that record every write and return what the test set.
@MainActor
private final class FakeDevices: DeviceConnecting {
    var accessResult: DeviceConnections.Access = .granted
    var changeEventResult: Result<DeviceConnections.ChangeOutcome, any Error> = .success(.verified)
    var deleteEventResult: Result<DeviceConnections.ChangeOutcome, any Error> = .success(.verified)
    private(set) var changedPlans: [EventChangePlan] = []
    private(set) var deletedEvents: [CalendarEventSummary] = []
    /// Every call that writes to Calendar, Reminders or notifications.
    private(set) var writeCount = 0

    /// What `incompleteReminders` returns.
    var openReminders: [ReminderSnapshot] = []
    /// When set, `incompleteReminders` and `notificationAccess` wait until `release()`, so a test
    /// can tap End and Start while a tool call is still looking something up.
    var holdsReads = false
    private var held: [CheckedContinuation<Void, Never>] = []
    /// Reads waiting in `held` right now.
    var heldReads: Int { held.count }
    /// Every `incompleteReminders` and `notificationAccess` call, held or not.
    private(set) var readCount = 0

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    private func read() async {
        readCount += 1
        guard holdsReads else { return }
        await withCheckedContinuation { held.append($0) }
    }

    func access(for connection: VoiceConnection) -> DeviceConnections.Access { accessResult }
    func notificationAccess() async -> DeviceConnections.Access {
        await read()
        return accessResult
    }
    func events(in range: VoiceTimeRange) -> [CalendarEventSummary] { [] }

    // CalendarEventWriter: an event saved is read back as written.
    func saveEvent(_ draft: CalendarEventDraft) throws -> (event: CalendarEventSummary, eventID: String)? {
        writeCount += 1
        return (CalendarEventSummary(id: "fake-event", title: draft.title, start: draft.start, end: draft.end, allDay: draft.allDay), "fake-event")
    }

    func changeEvent(_ plan: EventChangePlan) throws -> DeviceConnections.ChangeOutcome {
        writeCount += 1
        changedPlans.append(plan)
        return try changeEventResult.get()
    }

    func undo(_ undo: ActivityUndo) async -> UndoResult {
        writeCount += 1
        return .leftAlone
    }

    func eventLocation(_ event: CalendarEventSummary) -> String? { nil }
    func eventNotes(_ event: CalendarEventSummary) -> String? { nil }
    func reminderLists() -> [ReminderListRef] { [] }

    func changeReminder(_ before: ReminderSnapshot, _ change: ReminderChange) throws -> DeviceConnections.ChangeOutcome {
        writeCount += 1
        return .verified
    }

    func deleteEvent(_ event: CalendarEventSummary) throws -> DeviceConnections.ChangeOutcome {
        writeCount += 1
        deletedEvents.append(event)
        return try deleteEventResult.get()
    }

    func deleteReminder(_ before: ReminderSnapshot) throws -> DeviceConnections.ChangeOutcome {
        writeCount += 1
        return .verified
    }

    func reminderSnapshot(id: String) -> ReminderSnapshot? { nil }

    // TimerWriter: a timer scheduled is listed as waiting.
    private var timers: [PendingTimer] = []
    func pendingTimers() async -> [PendingTimer] { timers }
    func scheduleTimer(_ draft: TimerDraft, identifier: String) async throws {
        writeCount += 1
        timers.append(PendingTimer(identifier: identifier, firesAt: Date().addingTimeInterval(TimeInterval(draft.seconds))))
    }

    func findContacts(named name: String) throws -> [DeviceConnections.ContactMatch] { [] }
    func contactBirthdays() throws -> [ContactBirthday] { [] }

    // ReminderStore
    func incompleteReminders() async throws -> [ReminderSnapshot] {
        await read()
        return openReminders
    }

    func save(_ write: ReminderWrite) throws -> String {
        writeCount += 1
        return "fake-reminder"
    }
}

/// Stands in for the ElevenLabs or OpenAI conversation: keeps every tool result sent.
private final class FakeLink: LiveVoiceLink, @unchecked Sendable {
    struct Sent: Equatable {
        let id: String
        let text: String
        let isError: Bool
    }

    private let lock = NSLock()
    private var sent: [Sent] = []

    var results: [Sent] { lock.withLock { sent } }

    func sendToolResult(for toolCallId: String, result: String, isError: Bool) async throws {
        lock.withLock { sent.append(Sent(id: toolCallId, text: result, isError: isError)) }
    }

    func setMuted(_ muted: Bool) async throws {}
    func sendMessage(_ text: String) async throws {}
    func updateContext(_ context: String) async throws {}
    func endConversation() async {}
    func setAgentVolume(_ volume: Double) -> Double? { nil }
}
#endif
