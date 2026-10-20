import XCTest
@testable import DoddyCore

final class OpenWaysOfferTests: XCTestCase {
    private let tested = BackTapSetupPhase.userReportedTested(at: Date(timeIntervalSince1970: 1_800_000_000))

    // MARK: The card

    func testTheCardIsDueBeforeAnythingHasBeenDecided() {
        XCTAssertTrue(OpenWaysOffer.cardDue(phase: .notStarted, state: OpenWaysOfferState(), connectedConversations: 1))
    }

    func testTheCardIsNeverDueWhileTheGuideOrTheTestIsOpenOrOnceItWorked() {
        let window = BackTapTestWindow(startedAt: .now, duration: 120)
        for phase in [BackTapSetupPhase.guiding, .testing(window), .receiptReceived(window, receivedAt: .now), tested] {
            XCTAssertFalse(OpenWaysOffer.cardDue(phase: phase, state: OpenWaysOfferState(), connectedConversations: 50), "\(phase)")
        }
    }

    func testAfterLaterTheCardWaitsForThreeMoreConversations() {
        var state = OpenWaysOfferState()
        state.deferred(atConversations: 2)
        XCTAssertFalse(OpenWaysOffer.cardDue(phase: .deferred, state: state, connectedConversations: 2))
        XCTAssertFalse(OpenWaysOffer.cardDue(phase: .deferred, state: state, connectedConversations: 4))
        XCTAssertTrue(OpenWaysOffer.cardDue(phase: .deferred, state: state, connectedConversations: 5))
        XCTAssertTrue(OpenWaysOffer.cardDue(phase: .deferred, state: state, connectedConversations: 9))
    }

    func testTheCardComesBackOnceAndAfterTheSecondLaterItStaysGone() {
        var state = OpenWaysOfferState()
        state.deferred(atConversations: 1)
        XCTAssertTrue(OpenWaysOffer.cardDue(phase: .deferred, state: state, connectedConversations: 4))
        state.deferred(atConversations: 4)
        XCTAssertEqual(state.deferrals, 2)
        XCTAssertFalse(OpenWaysOffer.cardDue(phase: .deferred, state: state, connectedConversations: 100))
    }

    func testSomeoneWhoPutItOffBeforeThisExistedCountsFromZero() {
        XCTAssertFalse(OpenWaysOffer.cardDue(phase: .deferred, state: OpenWaysOfferState(), connectedConversations: 2))
        XCTAssertTrue(OpenWaysOffer.cardDue(phase: .deferred, state: OpenWaysOfferState(), connectedConversations: 3))
    }

    func testUsingAWayEndsTheCardInEveryPhase() {
        var state = OpenWaysOfferState()
        state.wayUsed()
        for phase in [BackTapSetupPhase.notStarted, .deferred, .guiding] {
            XCTAssertFalse(OpenWaysOffer.cardDue(phase: phase, state: state, connectedConversations: 50), "\(phase)")
        }
    }

    // MARK: Done

    func testDoneMeansTheShortcutRanOrTheUserSaidTheTestWorked() {
        XCTAssertFalse(OpenWaysOffer.isDone(phase: .notStarted, state: OpenWaysOfferState()))
        XCTAssertFalse(OpenWaysOffer.isDone(phase: .deferred, state: OpenWaysOfferState(deferrals: 2)))
        XCTAssertTrue(OpenWaysOffer.isDone(phase: tested, state: OpenWaysOfferState()))
        XCTAssertTrue(OpenWaysOffer.isDone(phase: .notStarted, state: OpenWaysOfferState(usedAWay: true)))
    }

    func testStartingTheGuideAgainDoesNotUndoHavingUsedAWay() {
        var state = OpenWaysOfferState()
        state.wayUsed()
        XCTAssertTrue(OpenWaysOffer.isDone(phase: .guiding, state: state))
    }

    // MARK: The weekly reminder

    func testTheReminderWaitsForTheFirstConversation() {
        XCTAssertFalse(OpenWaysOffer.reminderWanted(phase: .notStarted, state: OpenWaysOfferState(), connectedConversations: 0))
        XCTAssertTrue(OpenWaysOffer.reminderWanted(phase: .notStarted, state: OpenWaysOfferState(), connectedConversations: 1))
    }

    func testTheReminderStillComesAfterLaterBecauseTheyHaveNotDoneItYet() {
        XCTAssertTrue(OpenWaysOffer.reminderWanted(phase: .deferred, state: OpenWaysOfferState(deferrals: 2), connectedConversations: 5))
    }

    func testTheReminderStopsWhenTheyUseAWayOrSayTheTestWorked() {
        XCTAssertFalse(OpenWaysOffer.reminderWanted(phase: .notStarted, state: OpenWaysOfferState(usedAWay: true), connectedConversations: 9))
        XCTAssertFalse(OpenWaysOffer.reminderWanted(phase: tested, state: OpenWaysOfferState(), connectedConversations: 9))
    }

    func testTheReminderStaysOffAfterTheSettingsSwitchAndStartsAFreshRoundWhenSwitchedOn() {
        var state = OpenWaysOfferState(remindersArmedAt: Date(timeIntervalSince1970: 1))
        state.setReminders(on: false)
        XCTAssertFalse(OpenWaysOffer.reminderWanted(phase: .notStarted, state: state, connectedConversations: 9))
        XCTAssertNotNil(state.remindersArmedAt, "turning it off doesn't pretend nothing was ever set")
        state.setReminders(on: true)
        XCTAssertTrue(OpenWaysOffer.reminderWanted(phase: .notStarted, state: state, connectedConversations: 9))
        XCTAssertNil(state.remindersArmedAt, "switching on arms a new round")
    }

    func testFourDatesAWeekApartAtElevenLocalTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Warsaw"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 21, minute: 40)))
        let dates = OpenWaysReminder.fireDates(after: now, calendar: calendar)
        XCTAssertEqual(dates.count, OpenWaysReminder.weeks)
        let expectedDays = [27, 3, 10, 17]
        let expectedMonths = [10, 11, 11, 11]
        for (index, date) in dates.enumerated() {
            let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            XCTAssertEqual(parts.day, expectedDays[index])
            XCTAssertEqual(parts.month, expectedMonths[index])
            XCTAssertEqual(parts.hour, OpenWaysReminder.hour)
            XCTAssertEqual(parts.minute, 0)
        }
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertGreaterThan(dates[0], now)
    }

    func testTheIdsAreFourAndBelongToNoOtherKindOfNotification() {
        let ids = OpenWaysReminder.ids()
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(Set(ids).count, 4)
        for id in ids {
            XCTAssertTrue(OpenWaysReminder.isReminder(notificationID: id))
            XCTAssertFalse(MorningCheckIn.isCheckIn(notificationID: id))
            XCTAssertFalse(Birthdays.isBirthday(notificationID: id))
            XCTAssertNil(NotificationBudget.kind(of: id), "they count as Doddy's own, in the reserved room")
        }
        XCTAssertFalse(OpenWaysReminder.isReminder(notificationID: "doddy.note.123"))
    }

    func testTheReminderSaysTheSameThingInPolishAndEnglishAndNamesNothingPersonal() {
        for language in [NotificationLanguage.english, .polish] {
            XCTAssertFalse(OpenWaysReminder.title(language).isEmpty)
            XCTAssertFalse(OpenWaysReminder.body(language).isEmpty)
        }
        XCTAssertNotEqual(OpenWaysReminder.title(.english), OpenWaysReminder.title(.polish))
        XCTAssertFalse(OpenWaysReminder.body(.english).contains("!"), "no pressure")
    }

    func testTheStateRoundTripsAndHoldsNoWords() throws {
        let state = OpenWaysOfferState(deferrals: 1, conversationsAtLastDefer: 3, usedAWay: false, remindersOff: false,
                                       remindersArmedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try JSONDecoder().decode(OpenWaysOfferState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]).keys
        XCTAssertEqual(Set(keys), ["deferrals", "conversationsAtLastDefer", "usedAWay", "remindersOff", "remindersArmedAt"])
    }
}
