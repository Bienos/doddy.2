#if DEBUG
import DoddyCore
import Foundation
import XCTest
@testable import Doddy

/// The voice controller's confirmation cards with a fake Calendar (AppTests review 2026-10-11,
/// finding 2). App-target tests: NOT RUN in the authoring environment (no Xcode).
///
/// Tool calls reach the controller through the DEBUG seam `handleToolCallForTesting`, the same
/// path as an OpenAI Realtime call; `start` gets a fake microphone answer and a fake ElevenLabs
/// link through the initializer.
final class VoiceSessionControllerTests: XCTestCase {
    /// A controller with a fake Calendar, fake alarms and a fake provider link. `restore()` puts
    /// the settings it changed back as they were; each test calls it in a `defer`.
    @MainActor
    private struct Harness {
        let devices = FakeDevices()
        let link = FakeLink()
        let controller: VoiceSessionController
        /// Settings the controller reads, as they were before this test.
        private let saved: [(key: String, value: Any?)]

        /// `alarms` is what the alarm list reads; nil means iOS couldn't read it.
        init(alarms: [DoddyAlarm]? = []) {
            // Settings → Connections is re-checked at each call and tap: Calendar and Timers on,
            // Pause all off, for this test only.
            let on = [VoiceConnection.calendar.preferenceKey, VoiceConnection.timers.preferenceKey]
            saved = (on + [ConnectionPause.preferenceKey]).map { ($0, UserDefaults.standard.object(forKey: $0)) }
            for key in on { UserDefaults.standard.set(true, forKey: key) }
            UserDefaults.standard.set(false, forKey: ConnectionPause.preferenceKey)
            controller = VoiceSessionController(
                store: MemoryStore(environment: .live(arguments: ["-inMemoryStore"])),
                activity: ActivityLogStore(fileURL: nil),
                devices: devices,
                alarms: { alarms })
        }

        func show(_ action: VoiceSessionController.PendingAction) {
            controller.showCardForTesting(action, link: link)
        }

        /// One tool call from the provider, mid-conversation.
        func call(_ name: String, id: String, arguments: String = "{}") async {
            await controller.handleToolCallForTesting(RealtimeFunctionCall(callID: id, name: name, arguments: arguments), link: link)
        }

        func restore() {
            for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
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

    // MARK: Unreadable alarm list (DOD-08)

    /// An alarm list iOS couldn't read is `unknown:`, never "none set".
    @MainActor
    func testUnreadableAlarmListRepliesUnknown() async throws {
        let t = Harness(alarms: nil)
        defer { t.restore() }

        await t.call(VoiceToolName.listAlarms, id: "call-7")

        XCTAssertEqual(t.link.results.map(\.id), ["call-7"])
        let reply = try XCTUnwrap(t.link.results.first?.text)
        XCTAssertTrue(reply.hasPrefix("unknown:"), reply)
        XCTAssertEqual(reply, VoiceToolReply.alarmsUnreadable)
    }

    /// Unreadable is not "not found": the alarm may still ring, so no card and nothing cancelled.
    @MainActor
    func testCancelAlarmWithUnreadableListRepliesUnknown() async throws {
        let t = Harness(alarms: nil)
        defer { t.restore() }

        await t.call(VoiceToolName.cancelAlarm, id: "call-8", arguments: "{\"time\":\"07:00\"}")

        XCTAssertEqual(t.link.results.map(\.id), ["call-8"])
        let reply = try XCTUnwrap(t.link.results.first?.text)
        XCTAssertTrue(reply.hasPrefix("unknown:"), reply)
        XCTAssertEqual(reply, VoiceToolReply.alarmsUnreadable)
        XCTAssertNil(t.controller.pendingAction)
        XCTAssertEqual(t.devices.writeCount, 0)
    }

    /// The control case: a list that was read and is empty says "none".
    @MainActor
    func testReadableEmptyAlarmListSaysNone() async {
        let t = Harness(alarms: [])
        defer { t.restore() }

        await t.call(VoiceToolName.listAlarms, id: "call-9")

        XCTAssertEqual(t.link.results.map(\.text), [VoiceToolReply.alarms([])])
    }

    // MARK: A start replaced while connecting is ended (review H1, DOD-11)

    /// Start, stop while the provider is still connecting, start again: when the first
    /// connection arrives late it is ended at once, and only the second is the conversation.
    @MainActor
    func testStartReplacedWhileConnectingEndsTheFirstLink() async throws {
        let key = VoiceProvider.preferenceKey
        let savedProvider = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)  // ElevenLabs, the path with the seam
        defer { UserDefaults.standard.set(savedProvider, forKey: key) }
        let links = HeldLinks()
        let controller = VoiceSessionController(
            store: MemoryStore(environment: .live(arguments: ["-inMemoryStore"])),
            logs: ConversationLogStore(fileURL: nil),
            activity: ActivityLogStore(fileURL: nil),
            devices: FakeDevices(),
            microphone: { true },
            openLink: { _, _ in await links.open() })
        let mode = VoiceConnectionMode.publicAgent(agentID: "test-agent")

        let first = Task { await controller.start(mode, profile: .empty) }
        try await links.waitUntilFirstIsHeld()
        // A second start while the first is connecting does nothing.
        await controller.start(mode, profile: .empty)
        XCTAssertEqual(links.opened.count, 1)

        await controller.stop()
        await controller.start(mode, profile: .empty)
        links.releaseFirst()
        await first.value

        XCTAssertEqual(links.opened.count, 2)
        let (old, current) = (links.opened[0], links.opened[1])
        XCTAssertEqual(old.endCount, 1, "the replaced connection must be ended")
        XCTAssertEqual(current.endCount, 0)
        XCTAssertTrue(controller.isLive)
        // Only the second link is the conversation: Mute reaches it and not the first.
        await controller.toggleMute()
        XCTAssertEqual(current.muteCount, 1)
        XCTAssertEqual(old.muteCount, 0)

        await controller.stop()
        XCTAssertEqual(current.endCount, 1)
        XCTAssertEqual(old.endCount, 1)
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
    private var ended = 0
    private var muted = 0

    var results: [Sent] { lock.withLock { sent } }
    /// How many times the conversation was ended, and Mute was set.
    var endCount: Int { lock.withLock { ended } }
    var muteCount: Int { lock.withLock { muted } }

    func sendToolResult(for toolCallId: String, result: String, isError: Bool) async throws {
        lock.withLock { sent.append(Sent(id: toolCallId, text: result, isError: isError)) }
    }

    func setMuted(_ muted: Bool) async throws { lock.withLock { self.muted += 1 } }
    func sendMessage(_ text: String) async throws {}
    func updateContext(_ context: String) async throws {}
    func endConversation() async { lock.withLock { ended += 1 } }
    func setAgentVolume(_ volume: Double) -> Double? { nil }
}

/// The provider connecting: the first link opened waits until the test releases it, as a slow
/// connection would; later ones open at once.
@MainActor
private final class HeldLinks {
    private(set) var opened: [FakeLink] = []
    private var held: CheckedContinuation<Void, Never>?

    func open() async -> any LiveVoiceLink {
        let link = FakeLink()
        opened.append(link)
        if opened.count == 1 { await withCheckedContinuation { held = $0 } }
        return link
    }

    func waitUntilFirstIsHeld() async throws {
        for _ in 0..<500 where held == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard held != nil else { throw NeverReachedProvider() }
    }

    struct NeverReachedProvider: Error {}

    func releaseFirst() {
        held?.resume()
        held = nil
    }
}
#endif
