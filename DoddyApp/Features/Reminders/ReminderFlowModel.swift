import DoddyCore
import Foundation
import Observation

/// Add-to-Reminders flow from a memory: access → draft → exact approval → verified receipt.
/// The ledger owns state and rules; EventKit is reached only through `RemindersClient`.
@MainActor
@Observable
final class ReminderFlowModel {
    enum Access: Equatable {
        case checking
        /// iOS hasn't asked yet; the view explains why before the system prompt.
        case notAsked
        case off
        case restricted
        case ready(ReminderList)
        /// Access granted but iOS has no list to add to.
        case noList
    }

    private let ledger: ActionLedger
    private let client: any RemindersClient
    private let now: () -> Date

    private(set) var access: Access = .checking
    private(set) var record: ActionRecord?
    private(set) var isWorking = false
    private(set) var problem: String?
    /// Form fields. They reach the ledger only through `draft()` or `saveEdits()`.
    var title: String
    var hasDueDate = true
    var dueDate: Date
    var isEditing = false
    let timeZone: TimeZone

    init(
        ledger: ActionLedger, client: any RemindersClient, suggestedTitle: String,
        timeZone: TimeZone = .current, now: @escaping () -> Date = Date.init
    ) {
        self.ledger = ledger
        self.client = client
        self.timeZone = timeZone
        self.now = now
        title = String(suggestedTitle.prefix(ReminderSpec.maxTitleLength))
        dueDate = Self.tomorrowMorning(after: now(), in: timeZone)
    }

    var list: ReminderList? {
        if case .ready(let list) = access { return list }
        return nil
    }

    var spec: ReminderSpec? {
        guard let list = record.flatMap({ try? ReminderSpec(payload: $0.payload).list }) ?? self.list else { return nil }
        return ReminderSpec(title: title, due: hasDueDate ? Self.wholeMinute(dueDate) : nil, timeZone: timeZone, list: list)
    }

    /// The approved payload, decoded for display.
    var shownSpec: ReminderSpec? {
        record.flatMap { try? ReminderSpec(payload: $0.payload) }
    }

    var hasUnsavedEdits: Bool {
        guard let record, let spec else { return record != nil }
        return (try? ActionPayload.reminder(spec)) != record.payload
    }

    func start() async {
        switch await client.authorization() {
        case .notDetermined: access = .notAsked
        case .denied: access = .off
        case .restricted: access = .restricted
        case .granted:
            if let list = await client.defaultList() { access = .ready(list) } else { access = .noList }
        }
    }

    /// Shows the iOS prompt. Called only from the explained "Continue" button.
    func requestAccess() async {
        do {
            _ = try await client.requestAccess()
        } catch {
            problem = "iOS couldn't ask for Reminders access. Nothing was added."
        }
        await start()
    }

    func draft() async {
        guard let spec else { return }
        await run {
            let drafted = try await self.ledger.propose(ActionProposal(payload: try .reminder(spec)))
            return try await self.ledger.requestApproval(drafted.id)
        }
    }

    func saveEdits() async {
        guard let id = record?.id, let spec else { return }
        await run {
            _ = try await self.ledger.edit(id, payload: try .reminder(spec))
            return try await self.ledger.requestApproval(id)
        }
        if problem == nil { isEditing = false }
    }

    /// The tap approves exactly `record.payload`, the details on screen.
    func approveAndAdd() async {
        guard let shown = record, !hasUnsavedEdits, !isEditing else { return }
        await run {
            _ = try await self.ledger.approve(shown.id, reviewedPayload: shown.payload)
            return try await self.ledger.execute(shown.id)
        }
        // Still waiting means it didn't run (for example access was turned off since drafting):
        // refresh the access state the view shows.
        if record?.status == .needsApproval { await start() }
    }

    func checkStatus() async {
        guard let id = record?.id else { return }
        await run { try await self.ledger.reconcile(id) }
    }

    func cancel() async {
        guard let id = record?.id else { return }
        await run { try await self.ledger.cancel(id) }
    }

    private func run(_ step: @escaping () async throws -> ActionRecord) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await step()
            show(updated)
            problem = nil
        } catch {
            problem = ActionStatusCopy.problem(for: error)
            if let id = record?.id, let latest = try? await ledger.record(id) { show(latest) }
        }
    }

    private func show(_ updated: ActionRecord) {
        record = updated
        guard let spec = try? ReminderSpec(payload: updated.payload) else { return }
        title = spec.title
        hasDueDate = spec.due != nil
        if let due = spec.due { dueDate = due }
    }

    static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    /// Default suggestion only; the user sees and can change it before anything is drafted.
    static func tomorrowMorning(after date: Date, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
