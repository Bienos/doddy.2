import XCTest
import DoddyCore
@testable import Doddy

/// The Add-to-Reminders screen model, against an in-memory stand-in for EventKit.
@MainActor
final class ReminderFlowModelTests: XCTestCase {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
    /// 2026-10-10 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_791_633_600)

    private func makeModel(_ client: StubRemindersClient, title: String = "Call the dentist") -> ReminderFlowModel {
        let ledger = ActionLedger(adapters: [RemindersActionAdapter(client: client)])
        return ReminderFlowModel(ledger: ledger, client: client, suggestedTitle: title, timeZone: warsaw, now: { self.now })
    }

    func testAsksOnlyAfterExplanationThenShowsForm() async {
        let client = StubRemindersClient(.notDetermined)
        let model = makeModel(client)
        await model.start()
        XCTAssertEqual(model.access, .notAsked)
        let prompts = await client.requestCount
        XCTAssertEqual(prompts, 0, "no system prompt before the user taps Continue")
        await model.requestAccess()
        XCTAssertEqual(model.access, .ready(StubRemindersClient.list))
    }

    func testAccessOffMeansNoDraft() async {
        let model = makeModel(StubRemindersClient(.denied))
        await model.start()
        XCTAssertEqual(model.access, .off)
        await model.draft()
        XCTAssertNil(model.record)
    }

    func testDefaultsToTomorrowNineInTheDeviceZone() {
        let model = makeModel(StubRemindersClient(.granted))
        XCTAssertEqual(ReminderSpec.isoString(model.dueDate, in: warsaw), "2026-10-11T09:00:00+02:00")
    }

    func testDraftApproveAddsExactlyWhatWasShown() async throws {
        let client = StubRemindersClient(.granted)
        let model = makeModel(client)
        await model.start()
        model.dueDate = model.dueDate.addingTimeInterval(37)  // seconds are dropped
        await model.draft()
        XCTAssertEqual(model.record?.status, .needsApproval)
        let shown = try XCTUnwrap(model.shownSpec)
        XCTAssertEqual(shown.title, "Call the dentist")
        XCTAssertEqual(ReminderSpec.isoString(try XCTUnwrap(shown.due), in: warsaw), "2026-10-11T09:00:00+02:00")
        XCTAssertEqual(shown.list, StubRemindersClient.list)

        await model.approveAndAdd()
        XCTAssertEqual(model.record?.status, .confirmed)
        let written = await client.written
        XCTAssertEqual(written.map(\.title), ["Call the dentist"])
        XCTAssertEqual(written.first?.due, shown.due)
    }

    func testAccessTurnedOffAfterDraftingKeepsTheDraft() async {
        let client = StubRemindersClient(.granted)
        let model = makeModel(client)
        await model.start()
        await model.draft()
        await client.setAuthorization(.denied)
        await model.approveAndAdd()
        XCTAssertEqual(model.record?.status, .needsApproval)
        XCTAssertTrue(model.problem?.contains("Reminders access is off") ?? false)
        XCTAssertEqual(model.access, .off)
        let written = await client.written
        XCTAssertEqual(written, [])
    }

    func testEditingBlocksApprovalUntilTheDraftIsUpdated() async {
        let client = StubRemindersClient(.granted)
        let model = makeModel(client)
        await model.start()
        await model.draft()
        model.isEditing = true
        model.title = "Call the dentist about Friday"
        XCTAssertTrue(model.hasUnsavedEdits)
        await model.approveAndAdd()
        XCTAssertEqual(model.record?.status, .needsApproval)

        await model.saveEdits()
        XCTAssertFalse(model.isEditing)
        XCTAssertEqual(model.shownSpec?.title, "Call the dentist about Friday")
        await model.approveAndAdd()
        let written = await client.written
        XCTAssertEqual(written.map(\.title), ["Call the dentist about Friday"])
    }

    func testLongMemoryIsTrimmedToTheReminderLimit() {
        let model = makeModel(StubRemindersClient(.granted), title: String(repeating: "a", count: 600))
        XCTAssertEqual(model.title.count, ReminderSpec.maxTitleLength)
    }
}

actor StubRemindersClient: RemindersClient {
    static let list = ReminderList(id: "list-1", title: "Reminders")
    private var auth: RemindersAuthorization
    private(set) var requestCount = 0
    private(set) var written: [ReminderWrite] = []

    init(_ auth: RemindersAuthorization) { self.auth = auth }

    func setAuthorization(_ value: RemindersAuthorization) { auth = value }
    func authorization() async -> RemindersAuthorization { auth }

    func requestAccess() async throws -> Bool {
        requestCount += 1
        if auth == .notDetermined { auth = .granted }
        return auth == .granted
    }

    func defaultList() async -> ReminderList? { Self.list }
    func list(id: String) async -> ReminderList? { id == Self.list.id ? Self.list : nil }

    func create(_ write: ReminderWrite) async throws -> String {
        written.append(write)
        return "ek-\(written.count)"
    }

    func findReminder(reference: UUID) async throws -> String? {
        written.firstIndex { RemindersMarker.matches(url: $0.markerURL, notes: $0.markerNote, reference: reference) }
            .map { "ek-\($0 + 1)" }
    }
}
