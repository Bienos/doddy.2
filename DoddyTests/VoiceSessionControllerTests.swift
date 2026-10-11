#if DEBUG
import DoddyCore
import Foundation
import XCTest
@testable import Doddy

/// The voice controller's confirmation cards with a fake Calendar (AppTests review 2026-10-11,
/// finding 2). App-target tests: NOT RUN in the authoring environment (no Xcode).
///
/// Not covered here, for lack of a seam: tool calls arriving from the provider (`handle` and
/// `handleOpenAICall` are private and need `isLive`), the alarm list (static `AlarmScheduler`),
/// and a second `start` ending the first (needs the microphone and a provider).
final class VoiceSessionControllerTests: XCTestCase {
    /// A controller with a fake Calendar and a fake provider link. `restore()` puts the Calendar
    /// switch back as it was; each test calls it in a `defer`.
    @MainActor
    private struct Harness {
        let devices = FakeDevices()
        let link = FakeLink()
        let controller: VoiceSessionController
        private let savedCalendarSwitch: Any?

        init() {
            // The card re-checks Settings → Connections at the tap; turned on for this test only.
            let key = VoiceConnection.calendar.preferenceKey
            savedCalendarSwitch = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.set(true, forKey: key)
            controller = VoiceSessionController(
                store: MemoryStore(environment: .live(arguments: ["-inMemoryStore"])),
                activity: ActivityLogStore(fileURL: nil),
                devices: devices)
        }

        func show(_ action: VoiceSessionController.PendingAction) {
            controller.showCardForTesting(action, link: link)
        }

        func restore() {
            UserDefaults.standard.set(savedCalendarSwitch, forKey: VoiceConnection.calendar.preferenceKey)
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

    func access(for connection: VoiceConnection) -> DeviceConnections.Access { accessResult }
    func notificationAccess() async -> DeviceConnections.Access { accessResult }
    func events(in range: VoiceTimeRange) -> [CalendarEventSummary] { [] }

    func addEvent(_ draft: CalendarEventDraft) throws -> (outcome: DeviceConnections.AddOutcome, eventID: String?) {
        writeCount += 1
        return (.verified, nil)
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

    func startTimer(_ draft: TimerDraft) async throws -> DeviceConnections.AddOutcome {
        writeCount += 1
        return .verified
    }

    func findContacts(named name: String) throws -> [DeviceConnections.ContactMatch] { [] }
    func contactBirthdays() throws -> [ContactBirthday] { [] }

    // ReminderStore
    func incompleteReminders() async throws -> [ReminderSnapshot] { [] }

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
