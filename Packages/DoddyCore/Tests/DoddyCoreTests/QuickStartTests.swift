import DoddyCore
import XCTest

/// Quick start (ADR-324): what is pre-ticked, the owner's times, and what is never changed.
final class QuickStartTests: XCTestCase {
    func testNotificationsArePreTickedButSharingTheProfileIsNot() {
        let suggested = QuickStartChoices.suggested(remindersConnected: true)
        XCTAssertTrue(suggested.morningCheckIn && suggested.eveningWrapUp && suggested.weeklyTidyUp && suggested.weeklyLookBack)
        XCTAssertFalse(suggested.useProfileInVoice, "sending answers to ElevenLabs needs its own tick")
    }

    func testEveningWrapUpIsPreTickedOnlyWithRemindersConnected() {
        let suggested = QuickStartChoices.suggested(remindersConnected: false)
        XCTAssertFalse(suggested.eveningWrapUp, "its screen would only ask for Reminders")
        XCTAssertTrue(suggested.morningCheckIn && suggested.weeklyTidyUp)
        XCTAssertNil(QuickStart.plan(suggested, profileSaved: false).evening)
    }

    func testSuggestedPlanUsesTheOwnersTimes() {
        let plan = QuickStart.plan(.suggested(remindersConnected: true), profileSaved: true)
        XCTAssertEqual(plan.morning, MorningCheckInSettings(isOn: true, hour: 8, minute: 0, weekdaysOnly: true))
        XCTAssertEqual(plan.evening, EveningWrapUpSettings(isOn: true, hour: 21, minute: 0))
        XCTAssertEqual(plan.tidyUp, TidyUpSettings(isOn: true, weekday: 1, hour: 18, minute: 0), "1 = Sunday")
        XCTAssertEqual(plan.lookBack, WeeklyLookBackSettings(isOn: true, weekday: 1, hour: 19, minute: 0))
        XCTAssertFalse(plan.useProfileInVoice)
    }

    func testUntickedItemsAreLeftAloneNotTurnedOff() {
        let choices = QuickStartChoices(morningCheckIn: false, eveningWrapUp: true, weeklyTidyUp: false, weeklyLookBack: false, useProfileInVoice: false)
        let plan = QuickStart.plan(choices, profileSaved: false)
        XCTAssertNil(plan.morning)
        XCTAssertNil(plan.tidyUp)
        XCTAssertNotNil(plan.evening)
        XCTAssertFalse(plan.isEmpty)
    }

    func testProfileIsSharedOnlyWhenTickedAndSaved() {
        let ticked = QuickStartChoices(morningCheckIn: false, eveningWrapUp: false, weeklyTidyUp: false, weeklyLookBack: false, useProfileInVoice: true)
        XCTAssertTrue(QuickStart.plan(ticked, profileSaved: true).useProfileInVoice)
        XCTAssertFalse(QuickStart.plan(ticked, profileSaved: false).useProfileInVoice, "nothing saved, nothing to send")
        XCTAssertTrue(QuickStart.plan(ticked, profileSaved: false).isEmpty)
    }

    func testWhatIsAlreadyOnKeepsItsOwnTime() {
        let current = QuickStart.Current(morningCheckIn: true, eveningWrapUp: false, weeklyTidyUp: true, weeklyLookBack: true, useProfileInVoice: true)
        let plan = QuickStart.plan(.suggested(remindersConnected: true), profileSaved: true, current: current)
        XCTAssertNil(plan.morning, "a 07:30 set in Settings is not replaced by 08:00")
        XCTAssertNil(plan.tidyUp)
        XCTAssertNil(plan.lookBack)
        XCTAssertEqual(plan.evening, QuickStart.evening)
        let allOn = QuickStart.Current(morningCheckIn: true, eveningWrapUp: true, weeklyTidyUp: true, weeklyLookBack: true, useProfileInVoice: true)
        XCTAssertTrue(QuickStart.plan(.suggested(remindersConnected: true), profileSaved: true, current: allOn).isEmpty)
    }

    func testLookBackNeverRingsInTheSameMinuteAsTheTidyUp() {
        XCTAssertEqual(QuickStart.lookBack.weekday, QuickStart.tidyUp.weekday)
        XCTAssertNotEqual(QuickStart.lookBack.hour * 60 + QuickStart.lookBack.minute,
                          QuickStart.tidyUp.hour * 60 + QuickStart.tidyUp.minute)
    }

    func testNothingTickedIsAnEmptyPlan() {
        let none = QuickStartChoices(morningCheckIn: false, eveningWrapUp: false, weeklyTidyUp: false, weeklyLookBack: false, useProfileInVoice: false)
        XCTAssertFalse(none.anyNotification)
        XCTAssertTrue(QuickStart.plan(none, profileSaved: true).isEmpty)
    }

    func testSettingsStoredByTheQuickStartReadBackTheSame() {
        let defaults = UserDefaults(suiteName: "QuickStartTests.\(UUID())")!
        QuickStart.morning.store(defaults)
        QuickStart.evening.store(defaults)
        QuickStart.tidyUp.store(defaults)
        QuickStart.lookBack.store(defaults)
        XCTAssertEqual(MorningCheckInSettings.stored(defaults), QuickStart.morning)
        XCTAssertEqual(EveningWrapUpSettings.stored(defaults), QuickStart.evening)
        XCTAssertEqual(TidyUpSettings.stored(defaults), QuickStart.tidyUp)
        XCTAssertEqual(WeeklyLookBackSettings.stored(defaults), QuickStart.lookBack)
    }
}
