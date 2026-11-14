import DoddyCore
@testable import DoddyPersistence
import Foundation
import XCTest

/// Quiet memory (decision `2026-11-14-quiet-memory`; owner, 14 Nov 2026: "Niech zapisuje ale nie mówi użytkownikowi
/// co chwilę że zapisał"): with learning on and the person's own yes to keeping things quietly, what they said about
/// themselves is kept as a confirmed learned fact without a card, on this iPhone, read back from the database, and
/// marked as kept quietly so the Memory screen can show it and they can delete it. Never anything sensitive, never in a
/// private conversation, never a sentence they once said "Never this" to, and only a few at a time.
final class QuietMemoryTests: XCTestCase {
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

    private func make(_ clock: Clock) throws -> LearningService {
        let database = try DoddyDatabase.inMemory()
        return LearningService(
            facts: SQLiteLearnedFactRepository(database: database, now: { clock.date }),
            procedures: SQLiteProcedureRepository(database: database, now: { clock.date }),
            outcomes: SQLiteOutcomeEventRepository(database: database),
            now: { clock.date }, calendar: utc)
    }

    private func moment(on: Bool = true, quietly: Bool = true, paused: Bool = false, isPrivate: Bool = false,
                        sensitiveMode: Bool = false) -> LearningMoment {
        LearningMoment(learningOn: on, connectionsPaused: paused, connectionsOn: [.reminders], isPrivate: isPrivate,
                       sensitiveMode: sensitiveMode, keepsQuietly: quietly)
    }

    private func said(_ texts: [(String, SaveSuggestion.Reason)]) -> [SaveSuggestion] {
        texts.enumerated().map { SaveSuggestion(id: $0.offset + 1, text: $0.element.0, reason: $0.element.1) }
    }

    // MARK: What is kept

    func testWhatThePersonSaidAboutThemselvesIsKeptConfirmedAndMarkedQuiet() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        let kept = try await service.keepQuietlyAfterConversation(
            suggestions: said([("I prefer reminders at 9:00", .preference), ("My sister Marta lives in Gdańsk", .personalFact)]),
            moment: moment())
        XCTAssertEqual(kept.map(\.value), ["I prefer reminders at 9:00", "My sister Marta lives in Gdańsk"])
        XCTAssertTrue(kept.allSatisfy { $0.status == .confirmed && $0.provenance.keptQuietly })
        // Read back from the database, not taken from what was written.
        let stored = try await service.facts.list(status: .confirmed)
        XCTAssertEqual(Set(stored.map(\.id)), Set(kept.map(\.id)))
        XCTAssertTrue(stored.allSatisfy(\.provenance.keptQuietly))
    }

    func testOnlyPreferencesAndPersonalFactsAreKeptNotPlansCodesOrDates() async throws {
        let service = try make(Clock(noon))
        let kept = try await service.keepQuietlyAfterConversation(
            suggestions: said([("Dentist on Tuesday at 14:00", .dateOrNumber), ("Remember to call the plumber", .askedToRemember),
                               ("We plan to go to Rome in May", .plan), ("Marek recommended the bakery on Wilcza", .recommendation),
                               ("I like my coffee black", .preference)]),
            moment: moment())
        XCTAssertEqual(kept.map(\.value), ["I like my coffee black"], "the rest stay on the \"Worth keeping?\" card, as today")
    }

    // MARK: When nothing is kept

    func testNothingIsKeptWithoutBothSwitchesInAPrivateConversationPausedOrInSensitiveMode() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        for blocked in [moment(on: false), moment(quietly: false), moment(isPrivate: true), moment(paused: true), moment(sensitiveMode: true)] {
            let kept = try await service.keepQuietlyAfterConversation(suggestions: said([("I like my coffee black", .preference)]), moment: blocked)
            XCTAssertEqual(kept, [])
        }
        let rows = try await service.facts.list(status: nil)
        XCTAssertEqual(rows, [], "nothing written, not even a proposal")
    }

    func testNothingSensitiveIsEverKept() async throws {
        let service = try make(Clock(noon))
        let kept = try await service.keepQuietlyAfterConversation(
            suggestions: said([("I take medication for my depression", .personalFact), ("Mam cukrzycę typu 2", .personalFact),
                               ("I'm catholic and go to church on Sundays", .personalFact), ("My PIN is 4821", .personalFact),
                               ("My brother earns a lot", .personalFact)]),
            moment: moment())
        XCTAssertEqual(kept, [])
        let rows = try await service.facts.list(status: nil)
        XCTAssertEqual(rows, [])
    }

    func testASentenceThePersonOnceSaidNeverThisToIsNotKeptAndOneKeptIsNotKeptTwice() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        // "Never this" on the card, before quiet memory was on.
        let cards = try await service.proposeAfterConversation(
            leftoverSuggestions: said([("I prefer tea in the evening", .preference)]), moment: moment(quietly: false))
        let card = try XCTUnwrap(cards.first)
        try await service.reject(card)
        let again = try await service.keepQuietlyAfterConversation(
            suggestions: said([("I prefer tea in the evening", .preference)]), moment: moment())
        XCTAssertEqual(again, [], "a no stays a no")

        let first = try await service.keepQuietlyAfterConversation(suggestions: said([("I like my coffee black", .preference)]), moment: moment())
        XCTAssertEqual(first.count, 1)
        clock.date = noon.addingTimeInterval(3_600)
        let second = try await service.keepQuietlyAfterConversation(suggestions: said([("I like my coffee black", .preference)]), moment: moment())
        XCTAssertEqual(second, [], "the same words are kept once")
        let confirmedRows = try await service.facts.list(status: .confirmed)
        XCTAssertEqual(confirmedRows.count, 1)
    }

    func testTheSameWordsTwiceInOneConversationAreKeptOnce() async throws {
        let service = try make(Clock(noon))
        let kept = try await service.keepQuietlyAfterConversation(
            suggestions: said([("I like my coffee black", .preference), ("I like my coffee black", .preference)]), moment: moment())
        XCTAssertEqual(kept.count, 1)
    }

    // MARK: How many

    func testAFewPerConversationAndPerDay() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        func batch(_ start: Int) -> [SaveSuggestion] {
            said((start..<(start + 5)).map { ("I like dish number \($0) best", .preference) })
        }
        let first = try await service.keepQuietlyAfterConversation(suggestions: batch(0), moment: moment())
        XCTAssertEqual(first.count, LearningLimits.standard.quietPerConversation)
        var total = first.count
        for round in 1..<10 {
            clock.date = noon.addingTimeInterval(Double(round) * 60)
            total += try await service.keepQuietlyAfterConversation(suggestions: batch(round * 10), moment: moment()).count
        }
        XCTAssertEqual(total, LearningLimits.standard.quietPerDay)
        clock.date = noon.addingTimeInterval(86_400)
        let nextDay = try await service.keepQuietlyAfterConversation(suggestions: batch(500), moment: moment())
        XCTAssertEqual(nextDay.count, LearningLimits.standard.quietPerConversation, "a new day starts again")
    }

    // MARK: The card after the conversation

    func testWithQuietMemoryOnNoFactCardIsShownButARoutineCardStillIs() async throws {
        let service = try make(Clock(noon))
        let cards = try await service.proposeAfterConversation(
            leftoverSuggestions: said([("I like my coffee black", .preference)]), moment: moment())
        XCTAssertEqual(cards, [], "the fact is kept quietly instead, so it isn't also asked about")
        let withoutQuiet = try await service.proposeAfterConversation(
            leftoverSuggestions: said([("I like my tea green", .preference)]), moment: moment(quietly: false))
        XCTAssertEqual(withoutQuiet.count, 1, "with quiet memory off the card is as before")
    }

    func testFactsKeptQuietlyDontUseUpTheDaysCards() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        _ = try await service.keepQuietlyAfterConversation(
            suggestions: said([("I like a", .preference), ("I like b", .preference), ("I like c", .preference)]), moment: moment())
        clock.date = noon.addingTimeInterval(60)
        let cards = try await service.proposeAfterConversation(
            leftoverSuggestions: said([("I like green tea best", .preference)]), moment: moment(quietly: false))
        XCTAssertEqual(cards.count, 1, "three quiet facts today still leave room for a card")
    }

    // MARK: Using and removing them

    func testAQuietFactIsUsedLikeAConfirmedOneAndThatsWrongTakesItOutOfUse() async throws {
        let service = try make(Clock(noon))
        let kept = try await service.keepQuietlyAfterConversation(suggestions: said([("I like my coffee black", .preference)]), moment: moment())
        let fact = try XCTUnwrap(kept.first)
        let shared = try await service.voiceContext(shared: true, connectionsOn: [], connectionsPaused: false)
        XCTAssertTrue(shared.contains("I like my coffee black"))
        let notShared = try await service.voiceContext(shared: false, connectionsOn: [], connectionsPaused: false)
        XCTAssertFalse(notShared.contains("coffee"), "the voice gets it only with the person's sharing switch")
        try await service.thatsWrong(fact: fact)
        let after = try await service.voiceContext(shared: true, connectionsOn: [], connectionsPaused: false)
        XCTAssertFalse(after.contains("coffee"))
    }
}
