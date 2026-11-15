import DoddyCore
@testable import DoddyPersistence
import Foundation
import XCTest

/// Quiet memory, step 3 (decision `2026-11-14-quiet-memory`): a fact kept quietly that changes one Doddy already uses
/// (the rules of decision `2026-11-14-changed-facts-update-the-note`: where the person lives or works, or the same words
/// with a different number) takes the old one out of use. The old one is retired, not deleted: it stays on the Memory
/// screen as replaced, and only the new one reaches a conversation. Two old facts that both fit, or none, change nothing.
final class QuietMemoryChangedFactsTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _date: Date
        init(_ date: Date) { _date = date }
        var date: Date {
            get { lock.withLock { _date } }
            set { lock.withLock { _date = newValue } }
        }
    }

    private let noon = Date(timeIntervalSince1970: 1_760_000_000)

    private func make(_ clock: Clock) throws -> LearningService {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let database = try DoddyDatabase.inMemory()
        return LearningService(
            facts: SQLiteLearnedFactRepository(database: database, now: { clock.date }),
            procedures: SQLiteProcedureRepository(database: database, now: { clock.date }),
            outcomes: SQLiteOutcomeEventRepository(database: database),
            now: { clock.date }, calendar: utc)
    }

    private func moment(quietly: Bool = true) -> LearningMoment {
        LearningMoment(learningOn: true, connectionsPaused: false, connectionsOn: [], isPrivate: false, keepsQuietly: quietly)
    }

    private func keep(_ service: LearningService, _ clock: Clock, _ text: String, minutesLater: Double) async throws -> [LearnedFact] {
        clock.date = noon.addingTimeInterval(minutesLater * 60)
        return try await service.keepQuietlyAfterConversation(
            suggestions: [SaveSuggestion(id: 1, text: text, reason: .personalFact)], moment: moment())
    }

    private func context(_ service: LearningService) async throws -> String {
        try await service.voiceContext(shared: true, connectionsOn: [], connectionsPaused: false)
    }

    func testANewPlaceToLiveRetiresTheOldOneAndOnlyTheNewOneIsUsed() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        let first = try await keep(service, clock, "I live in Warsaw now", minutesLater: 0)
        let warsaw = try XCTUnwrap(first.first)
        let second = try await keep(service, clock, "I live in Berlin now", minutesLater: 60)
        let berlin = try XCTUnwrap(second.first)
        let confirmed = try await service.facts.list(status: .confirmed)
        XCTAssertEqual(confirmed.map(\.id), [berlin.id])
        let retired = try await service.facts.list(status: .retired)
        XCTAssertEqual(retired.map(\.id), [warsaw.id], "kept and visible as replaced, not deleted")
        let shared = try await context(service)
        XCTAssertTrue(shared.contains("Berlin"))
        XCTAssertFalse(shared.contains("Warsaw"))
    }

    func testAFactConfirmedOnACardIsReplacedTheSameWay() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        let cards = try await service.proposeAfterConversation(
            leftoverSuggestions: [SaveSuggestion(id: 1, text: "I work at Acme these days", reason: .personalFact)],
            moment: moment(quietly: false))
        let saved = try await service.confirm(try XCTUnwrap(cards.first))
        guard case .fact(let acme) = saved else { return XCTFail("a fact") }
        _ = try await keep(service, clock, "I work at Initech these days", minutesLater: 60)
        let retiredIDs = try await service.facts.list(status: .retired).map(\.id)
        XCTAssertEqual(retiredIDs, [acme.id])
    }

    func testAChangeWithinOneConversationKeepsOnlyTheLatest() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        let kept = try await service.keepQuietlyAfterConversation(
            suggestions: [SaveSuggestion(id: 1, text: "I live in Warsaw now", reason: .personalFact),
                          SaveSuggestion(id: 2, text: "Actually I live in Berlin now", reason: .personalFact)],
            moment: moment())
        XCTAssertEqual(kept.map(\.value), ["Actually I live in Berlin now"], "what is returned is what is in use")
        let retired = try await service.facts.list(status: .retired)
        XCTAssertEqual(retired.map(\.value), ["I live in Warsaw now"])
    }

    func testADifferentThingIsNotAChange() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        _ = try await keep(service, clock, "I live in Warsaw now", minutesLater: 0)
        _ = try await keep(service, clock, "I work at Acme these days", minutesLater: 60)
        let confirmed = try await service.facts.list(status: .confirmed)
        XCTAssertEqual(confirmed.count, 2, "where you live and where you work are different things")
        let retired = try await service.facts.list(status: .retired)
        XCTAssertEqual(retired, [])
    }

    func testTwoOldFactsThatBothFitAreLeftAlone() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        // Two confirmed on cards (a card never retires anything), so both are in use.
        for (minutes, text) in [(0.0, "I live in Warsaw now"), (10.0, "Mieszkam w Krakowie od lat")] {
            clock.date = noon.addingTimeInterval(minutes * 60)
            let cards = try await service.proposeAfterConversation(
                leftoverSuggestions: [SaveSuggestion(id: 1, text: text, reason: .personalFact)], moment: moment(quietly: false))
            _ = try await service.confirm(try XCTUnwrap(cards.first))
        }
        _ = try await keep(service, clock, "I live in Berlin now", minutesLater: 60)
        let confirmed = try await service.facts.list(status: .confirmed)
        let retired = try await service.facts.list(status: .retired)
        XCTAssertEqual(confirmed.count, 3, "nobody knows which one changed, so none is retired")
        XCTAssertEqual(retired, [])
    }

    func testTheSameWordsWithANewNumberReplaceTheOldOne() async throws {
        let clock = Clock(noon)
        let service = try make(clock)
        let kept = try await keep(service, clock, "My shoe size is 42", minutesLater: 0)
        let old = try XCTUnwrap(kept.first)
        _ = try await keep(service, clock, "My shoe size is 43", minutesLater: 60)
        let retiredIDs = try await service.facts.list(status: .retired).map(\.id)
        XCTAssertEqual(retiredIDs, [old.id])
    }

    func testOnlyAFactKeptJustNowRetiresAnything() async throws {
        // A retired fact is not used again, and a fact that wasn't kept (sensitive, refused before) retires nothing.
        let clock = Clock(noon)
        let service = try make(clock)
        _ = try await keep(service, clock, "I live in Warsaw now", minutesLater: 0)
        let kept = try await keep(service, clock, "I live in Warsaw now", minutesLater: 60)
        XCTAssertEqual(kept, [], "the same words are not kept twice")
        let confirmed = try await service.facts.list(status: .confirmed)
        XCTAssertEqual(confirmed.count, 1, "and nothing was retired by them")
    }
}
