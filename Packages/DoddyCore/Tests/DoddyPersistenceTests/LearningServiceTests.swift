import DoddyCore
@testable import DoddyPersistence
import Foundation
import GRDB
import XCTest

/// The learning loop end to end on real SQLite (ADR-324 Phase C): what is recorded, what is
/// proposed, what a card's Save does, "That's wrong", the voice agent's text, housekeeping, delete.
final class LearningServiceTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _date: Date
        init(_ date: Date) { _date = date }
        var date: Date {
            get { lock.withLock { _date } }
            set { lock.withLock { _date = newValue } }
        }
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let noon = Date(timeIntervalSince1970: 1_760_000_000)
    private var day: TimeInterval { 86_400 }

    private func make(_ clock: Clock) throws -> (service: LearningService, database: DoddyDatabase) {
        let database = try DoddyDatabase.inMemory()
        let service = LearningService(
            facts: SQLiteLearnedFactRepository(database: database, now: { clock.date }),
            procedures: SQLiteProcedureRepository(database: database, now: { clock.date }),
            outcomes: SQLiteOutcomeEventRepository(database: database),
            now: { clock.date }, calendar: utc)
        return (service, database)
    }

    private func moment(
        on: Bool = true, paused: Bool = false, isPrivate: Bool = false, connections: Set<VoiceConnection> = [.reminders, .timers, .calendar]
    ) -> LearningMoment {
        LearningMoment(learningOn: on, connectionsPaused: paused, connectionsOn: connections, isPrivate: isPrivate)
    }

    private func preference(_ text: String = "I prefer reminders at 9:00") -> [SaveSuggestion] {
        [SaveSuggestion(id: 1, text: text, reason: .preference)]
    }

    /// Records one completed change per tool, as "What Doddy did" would, in one conversation `daysAgo` days back.
    private func recordConversation(_ service: LearningService, tools: [String], session: String, daysAgo: Int, clock: Clock) async throws {
        let original = clock.date
        defer { clock.date = original }
        for (index, tool) in tools.enumerated() {
            clock.date = original.addingTimeInterval(-Double(daysAgo) * day - 3_600 + Double(index) * 60)
            let entry = ActivityEntry(at: clock.date, app: .reminders, title: tool, detail: "x", outcome: .done, tool: tool)
            let failures = await service.recordActivity(entry, previous: nil, recent: [], sessionID: session)
            XCTAssertEqual(failures, [])
        }
    }

    // MARK: Facts

    func testNothingIsProposedWhenOffPrivateOrPaused() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        for blocked in [moment(on: false), moment(isPrivate: true), moment(paused: true)] {
            let cards = try await service.proposeAfterConversation(leftoverSuggestions: preference(), moment: blocked)
            XCTAssertEqual(cards, [])
        }
        let rows = try await service.facts.list(status: nil)
        XCTAssertEqual(rows, [], "a dropped proposal is not even stored")
    }

    func testFactCardSaveRejectAndNeverAgain() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        let cards = try await service.proposeAfterConversation(leftoverSuggestions: preference(), moment: moment())
        XCTAssertEqual(cards.count, 1)
        guard case .fact(let proposed) = try XCTUnwrap(cards.first) else { return XCTFail("expected a fact card") }
        XCTAssertEqual(proposed.status, .proposed)
        let beforeSave = try await service.facts.list(status: .confirmed)
        XCTAssertEqual(beforeSave, [], "showing a card saves nothing")

        let saved = try await service.confirm(cards[0])
        guard case .fact(let confirmed) = saved else { return XCTFail() }
        XCTAssertEqual(confirmed.status, .confirmed)
        XCTAssertEqual(confirmed.value, "I prefer reminders at 9:00")

        // The same sentence on another day: known evidence, nothing proposed.
        clock.date = noon.addingTimeInterval(day)
        let again = try await service.proposeAfterConversation(leftoverSuggestions: preference("i prefer reminders at 9:00"), moment: moment())
        XCTAssertEqual(again, [])

        // "Never this" on a different sentence holds for good.
        let other = preference("I prefer tea in the morning")
        let card = try await service.proposeAfterConversation(leftoverSuggestions: other, moment: moment())
        try await service.reject(try XCTUnwrap(card.first))
        clock.date = noon.addingTimeInterval(10 * day)
        let later = try await service.proposeAfterConversation(leftoverSuggestions: other, moment: moment())
        XCTAssertEqual(later, [])
    }

    func testSensitiveSentencesAndTheDailyCapAreDroppedBeforeAnyRow() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        let sensitive = try await service.proposeAfterConversation(leftoverSuggestions: preference("I prefer the pills for my diabetes"), moment: moment())
        XCTAssertEqual(sensitive, [])
        var shown = 0
        for index in 0..<5 {
            let cards = try await service.proposeAfterConversation(leftoverSuggestions: preference("I prefer option number \(index) on weekdays"), moment: moment())
            shown += cards.count
        }
        XCTAssertEqual(shown, 3, "three a day, the owner's default")
        clock.date = noon.addingTimeInterval(day)
        let next = try await service.proposeAfterConversation(leftoverSuggestions: preference("I prefer option number 9 on weekdays"), moment: moment())
        XCTAssertEqual(next.count, 1, "a new day, a new allowance")
    }

    func testUnansweredProposalsExpireAfterSevenDays() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        let cards = try await service.proposeAfterConversation(leftoverSuggestions: preference(), moment: moment())
        XCTAssertEqual(cards.count, 1)
        clock.date = noon.addingTimeInterval(6 * day)
        try await service.housekeeping()
        let stillThere = try await service.facts.list(status: .proposed)
        XCTAssertEqual(stillThere.count, 1)
        clock.date = noon.addingTimeInterval(8 * day)
        try await service.housekeeping()
        let gone = try await service.facts.list(status: .proposed)
        XCTAssertEqual(gone, [])
    }

    // MARK: Procedures

    func testRepeatedSequenceBecomesAProcedureCardThenRunsMarksUsedAndFeedsTheAgent() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        let tools = [VoiceToolName.createReminder, VoiceToolName.setTimer]
        try await recordConversation(service, tools: tools, session: "c1", daysAgo: 0, clock: clock)
        try await recordConversation(service, tools: tools, session: "c2", daysAgo: 2, clock: clock)
        let tooEarly = try await service.proposeAfterConversation(leftoverSuggestions: [], moment: moment())
        XCTAssertEqual(tooEarly, [], "two days are not a habit")
        try await recordConversation(service, tools: tools, session: "c3", daysAgo: 4, clock: clock)

        let offConnection = try await service.proposeAfterConversation(leftoverSuggestions: [], moment: moment(connections: [.calendar]))
        XCTAssertEqual(offConnection, [], "reminders and timers are off, so it could not run")

        let cards = try await service.proposeAfterConversation(leftoverSuggestions: preference(), moment: moment())
        guard case .procedure(let proposed) = try XCTUnwrap(cards.first) else { return XCTFail("a procedure comes before a fact") }
        XCTAssertEqual(cards.count, 1, "one card a conversation")
        XCTAssertEqual(proposed.steps.map(\.toolName), tools)

        let agentBefore = try await service.voiceContext(shared: true, connectionsOn: [.reminders, .timers], connectionsPaused: false)
        XCTAssertEqual(agentBefore, LearningPrompt.empty, "a proposal is not yet learned")
        let saved = try await service.confirm(cards[0])
        guard case .procedure(let confirmed) = saved else { return XCTFail() }
        XCTAssertEqual(confirmed.status, .confirmed)

        let notShared = try await service.voiceContext(shared: false, connectionsOn: [.reminders, .timers], connectionsPaused: false)
        XCTAssertEqual(notShared, LearningPrompt.notShared)
        let shared = try await service.voiceContext(shared: true, connectionsOn: [.reminders, .timers], connectionsPaused: false)
        XCTAssertTrue(shared.contains("create_reminder (ask: title, due) → set_timer (ask: minutes)"), shared)
        let paused = try await service.voiceContext(shared: true, connectionsOn: [.reminders, .timers], connectionsPaused: true)
        XCTAssertEqual(paused, LearningPrompt.empty, "paused: no procedure is handed over")
        let remindersOff = try await service.voiceContext(shared: true, connectionsOn: [.timers], connectionsPaused: false)
        XCTAssertEqual(remindersOff, LearningPrompt.empty, "a step's connection is off: not handed over")

        let notUsed = try await service.planRan(tools: [VoiceToolName.setTimer, VoiceToolName.createReminder])
        XCTAssertNil(notUsed, "another order is another plan")
        let used = try await service.planRan(tools: tools)
        XCTAssertEqual(used?.useCount, 1)

        // Rejecting nothing here, but the sequence now has a row: it is not proposed again.
        try await recordConversation(service, tools: tools, session: "c4", daysAgo: 0, clock: clock)
        clock.date = noon.addingTimeInterval(day)
        let again = try await service.proposeAfterConversation(leftoverSuggestions: [], moment: moment())
        XCTAssertEqual(again, [])
    }

    func testProcedureNeverThisHoldsWhenALaterDayAddsEvidence() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        let tools = [VoiceToolName.createReminder, VoiceToolName.setTimer]
        for (index, session) in ["a", "b", "c"].enumerated() {
            try await recordConversation(service, tools: tools, session: session, daysAgo: index * 2, clock: clock)
        }
        let cards = try await service.proposeAfterConversation(leftoverSuggestions: [], moment: moment())
        try await service.reject(try XCTUnwrap(cards.first))
        clock.date = noon.addingTimeInterval(day)
        try await recordConversation(service, tools: tools, session: "d", daysAgo: 0, clock: clock)
        let afterNewDay = try await service.proposeAfterConversation(leftoverSuggestions: [], moment: moment())
        XCTAssertEqual(afterNewDay, [], "the evidence changed but the answer did not")
    }

    // MARK: "That's wrong"

    func testThatsWrongRetiresThenCountsOneCorrection() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        let cards = try await service.proposeAfterConversation(leftoverSuggestions: preference(), moment: moment())
        guard case .fact(let fact) = try await service.confirm(try XCTUnwrap(cards.first)) else { return XCTFail() }
        let before = try await service.metrics()
        XCTAssertEqual(before.correctionsThisWeek, 0)

        try await service.thatsWrong(fact: fact)
        let stored = try await service.facts.fact(id: fact.id)
        XCTAssertEqual(stored?.status, .retired, "kept and visible, out of use")
        let after = try await service.metrics()
        XCTAssertEqual(after.correctionsThisWeek, 1)
        let agent = try await service.voiceContext(shared: true, connectionsOn: [], connectionsPaused: false)
        XCTAssertEqual(agent, LearningPrompt.empty, "a retired fact is not handed to the agent")
        let events = try await service.outcomes.list(since: .distantPast, limit: 10)
        XCTAssertEqual(events.last?.detail.correction, .thatsWrong)
        XCTAssertEqual(events.last?.detail.learnedItemID, fact.id)

        do { try await service.thatsWrong(fact: fact); XCTFail("a retired fact cannot be retired twice") }
        catch { XCTAssertEqual(error as? LearningStoreError, .wrongStatus(fact.id, .retired)) }
        let still = try await service.metrics()
        XCTAssertEqual(still.correctionsThisWeek, 1, "no correction is written when nothing was retired")
    }

    // MARK: Metrics, gaps, housekeeping, delete

    func testMetricsGapsAndChangedSteps() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        try await service.recordGap(.music, requestID: "r1", sessionID: "c1")
        try await service.recordGap(.music, requestID: "r2", sessionID: "c1")
        try await service.recordGap(.smartHome, requestID: "r3", sessionID: nil)
        try await service.recordChangedStep(tool: VoiceToolName.createReminder, requestID: "r4", sessionID: "c1")
        let undone = ActivityEntry(at: noon, app: .reminders, title: "Add reminder", detail: nil, outcome: .done, tool: "create_reminder")
        var undoneAgain = undone
        undoneAgain.undoState = .undone(noon)
        let failures = await service.recordActivity(undoneAgain, previous: undone, recent: [], sessionID: "c1")
        XCTAssertEqual(failures, [])
        let metrics = try await service.metrics()
        XCTAssertEqual(metrics.correctionsThisWeek, 2)
        XCTAssertEqual(metrics.gaps, [.music: 2, .smartHome: 1])
        clock.date = noon.addingTimeInterval(8 * day)
        let aWeekLater = try await service.metrics()
        XCTAssertEqual(aWeekLater.correctionsThisWeek, 0)
        XCTAssertEqual(aWeekLater.gaps[.music], 2, "gaps stay for the 90 days")
        clock.date = noon.addingTimeInterval(91 * day)
        try await service.housekeeping()
        let gone = try await service.metrics()
        XCTAssertEqual(gone.gaps, [:])
    }

    func testUnusedProceduresRetireAfterNinetyDays() async throws {
        let clock = Clock(noon)
        let (service, _) = try make(clock)
        let tools = [VoiceToolName.createReminder, VoiceToolName.setTimer]
        for (index, session) in ["a", "b", "c"].enumerated() {
            try await recordConversation(service, tools: tools, session: session, daysAgo: index, clock: clock)
        }
        let cards = try await service.proposeAfterConversation(leftoverSuggestions: [], moment: moment())
        _ = try await service.confirm(try XCTUnwrap(cards.first))
        clock.date = noon.addingTimeInterval(89 * day)
        let none = try await service.housekeeping()
        XCTAssertEqual(none, [])
        clock.date = noon.addingTimeInterval(91 * day)
        let retired = try await service.housekeeping()
        XCTAssertEqual(retired.count, 1)
        XCTAssertEqual(retired.first?.status, .retired)
    }

    func testDeleteAllEmptiesEverythingAndSaysSoOnlyAfterReadingBack() async throws {
        let clock = Clock(noon)
        let (service, database) = try make(clock)
        let cards = try await service.proposeAfterConversation(leftoverSuggestions: preference(), moment: moment())
        _ = try await service.confirm(try XCTUnwrap(cards.first))
        try await service.recordGap(.payment, requestID: "r1", sessionID: nil)
        try await service.deleteAll()
        let facts = try await service.facts.list(status: nil)
        let procedures = try await service.procedures.list(status: nil)
        let events = try await service.outcomes.list(since: .distantPast, limit: 10)
        XCTAssertEqual(facts.count + procedures.count + events.count, 0)
        let index = try await database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM learned_facts_fts") ?? -1
        }
        XCTAssertEqual(index, 0)
    }
}
