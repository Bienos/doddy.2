import XCTest
@testable import DoddyCore

/// "Remind me when to leave" and the Outlook and Gmail reply drafts in the action status model
/// (round 6's writes, after ADR-319 to ADR-322).
final class LeaveByActionsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    /// Mon 12 Oct 2026, 08:00 in Warsaw.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8))! }

    private func plan(_ place: String = "Dentist on Mokotowska", mode: TravelMode = .driving, buffer: Int = 10) -> LeaveByPlan {
        let request = LeaveByRequest(place: place, arriveBy: now + 2 * 3600, mode: mode, bufferMinutes: buffer)
        return try! LeaveBy.plan(request, placeName: "Dentysta", placeAddress: "Mokotowska 1", travelSeconds: 1500, now: now).get()
    }

    // MARK: Keys

    func testTheSameTripHasTheSameKey() {
        let a = plan()
        XCTAssertEqual(LeaveByIdempotency.key(a.request), LeaveByIdempotency.key(plan("  dentist on  MOKOTOWSKA ").request))
        XCTAssertEqual(LeaveByIdempotency.key(a.request), LeaveByIdempotency.key(plan(buffer: 20).request), "spare minutes don't make another trip")
        XCTAssertNotEqual(LeaveByIdempotency.key(a.request), LeaveByIdempotency.key(plan(mode: .walking).request))
        XCTAssertNotEqual(LeaveByIdempotency.key(a.request), LeaveByIdempotency.key(plan("Gym").request))

        let id = LeaveByIdempotency.identifier(key: LeaveByIdempotency.key(a.request), id: UUID())
        XCTAssertEqual(LeaveByIdempotency.key(fromIdentifier: id), LeaveByIdempotency.key(a.request))
        XCTAssertNil(LeaveByIdempotency.key(fromIdentifier: "doddy.leaveBy.\(UUID().uuidString)"), "set before keys: no key")

        let request = ActivityRequest.describe(.leaveBy(a.request), calendar: calendar)
        XCTAssertEqual(request?.operationKey, LeaveByIdempotency.key(a.request))
        XCTAssertEqual(request?.app, .maps)
    }

    // MARK: Setting

    @MainActor
    func testItLooksFirstAndNeverSetsASecondOne() async {
        let writer = FakeLeaveWriter()
        let first = await LeaveBySetAction.set(plan(), with: writer)
        guard case .set(let pending) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(writer.scheduled, 1)

        let again = await LeaveBySetAction.set(plan(buffer: 15), with: writer)
        XCTAssertEqual(again, .alreadySet(pending))
        XCTAssertEqual(writer.scheduled, 1, "nothing new was scheduled")
        XCTAssertFalse(again.attemptedWrite)
        let reply = VoiceToolReply.leaveBy(again, plan: plan(), calendar: calendar)
        XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: false).0, .alreadyThere)
    }

    @MainActor
    func testOnlyWhatIOSListsCountsAsSet() async {
        let lost = FakeLeaveWriter()
        lost.dropsWrites = true
        let unknown = await LeaveBySetAction.set(plan(), with: lost)
        XCTAssertEqual(unknown, .unknown)
        XCTAssertTrue(VoiceToolReply.leaveBy(unknown, plan: plan(), calendar: calendar).hasPrefix("unknown:"))

        let throwsButKept = FakeLeaveWriter()
        throwsButKept.throwsAfterWriting = true
        guard case .set = await LeaveBySetAction.set(plan(), with: throwsButKept) else { return XCTFail("listed after an error counts as set") }

        let failed = FakeLeaveWriter()
        failed.throwsAfterWriting = true
        failed.dropsWrites = true
        let notSet = await LeaveBySetAction.set(plan(), with: failed)
        XCTAssertEqual(notSet, .notSet)
        XCTAssertTrue(notSet.attemptedWrite)

        let off = FakeLeaveWriter()
        off.allowed = false
        let notAllowed = await LeaveBySetAction.set(plan(), with: off)
        XCTAssertEqual(notAllowed, .notAllowed)
        XCTAssertFalse(notAllowed.attemptedWrite, "nothing was tried: it doesn't count towards the 3-try stop")
        XCTAssertEqual(off.scheduled, 0)
    }

    func testTheReceiptIsWhatIOSListsAndHasPolish() throws {
        let fires = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9, minute: 25))!
        let receipt = ActivityReceipt(leaveBy: PendingLeaveBy(identifier: "doddy.leaveBy.l1-x.y", firesAt: fires), plan: plan(), calendar: calendar, readAt: now)
        XCTAssertEqual(receipt.app, .maps)
        XCTAssertEqual(receipt.lines, ["Leave at 09:25, 2026-10-12", "Place: Dentysta", "Arrive by 10:00"])
        XCTAssertEqual(receipt.lines(.polish), ["Wyjście o 09:25, 2026-10-12", "Miejsce: Dentysta", "Na miejscu do 10:00"])
    }

    // MARK: Drafts in Outlook and Gmail replies

    func testOutlookAndReplyDraftsAreKeyedWritesWithTheirOwnApp() {
        let outlook = CloudToolCall(name: CloudToolName.draftOutlookEmail, arguments: ["to": .string("a@b.co"), "subject": .string("Hi"), "body": .string("x")])
        XCTAssertNotNil(CloudIdempotency.key(outlook))
        let request = ActivityRequest.describe(.cloudTool(outlook), calendar: calendar)
        XCTAssertEqual(request?.app, .outlook)
        XCTAssertEqual(request?.operationKey, CloudIdempotency.key(outlook))
        let reply = CloudToolCall(name: CloudToolName.draftEmailReply, arguments: ["query": .string("from:anna"), "body": .string("Yes")])
        XCTAssertNotNil(CloudIdempotency.key(reply))
        XCTAssertNil(CloudIdempotency.key(CloudToolCall(name: CloudToolName.readOutlookCalendar, arguments: [:])), "reads have no key")
        XCTAssertEqual(ActivityEntry.outcome(of: VoiceToolReply.cloudAlreadyThere(CloudToolName.draftOutlookEmail), isLookup: false).0, .alreadyThere)
    }
}

@MainActor
private final class FakeLeaveWriter: LeaveByWriter {
    var allowed = true
    var dropsWrites = false
    var throwsAfterWriting = false
    private(set) var scheduled = 0
    private var pending: [PendingLeaveBy] = []

    func notificationsAllowed() async -> Bool { allowed }
    func pendingLeaveBys() async -> [PendingLeaveBy] { pending }
    func scheduleLeaveBy(_ plan: LeaveByPlan, identifier: String) async throws {
        scheduled += 1
        if !dropsWrites { pending.append(PendingLeaveBy(identifier: identifier, firesAt: plan.leaveAt)) }
        if throwsAfterWriting { throw CocoaError(.fileWriteUnknown) }
    }
}
