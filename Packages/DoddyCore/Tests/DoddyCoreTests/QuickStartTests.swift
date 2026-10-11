import DoddyCore
import XCTest

/// Quick start (ADR-310): what is pre-ticked, the owner's times, and what is never changed.
final class QuickStartTests: XCTestCase {
    func testNotificationsArePreTickedButSharingTheProfileIsNot() {
        let suggested = QuickStartChoices.suggested
        XCTAssertTrue(suggested.morningCheckIn && suggested.eveningWrapUp && suggested.weeklyTidyUp)
        XCTAssertFalse(suggested.useProfileInVoice, "sending answers to ElevenLabs needs its own tick")
    }

    func testSuggestedPlanUsesTheOwnersTimes() {
        let plan = QuickStart.plan(.suggested, profileSaved: true)
        XCTAssertEqual(plan.morning, MorningCheckInSettings(isOn: true, hour: 8, minute: 0, weekdaysOnly: true))
        XCTAssertEqual(plan.evening, EveningWrapUpSettings(isOn: true, hour: 21, minute: 0))
        XCTAssertEqual(plan.tidyUp, TidyUpSettings(isOn: true, weekday: 1, hour: 18, minute: 0), "1 = Sunday")
        XCTAssertFalse(plan.useProfileInVoice)
    }

    func testUntickedItemsAreLeftAloneNotTurnedOff() {
        let choices = QuickStartChoices(morningCheckIn: false, eveningWrapUp: true, weeklyTidyUp: false, useProfileInVoice: false)
        let plan = QuickStart.plan(choices, profileSaved: false)
        XCTAssertNil(plan.morning)
        XCTAssertNil(plan.tidyUp)
        XCTAssertNotNil(plan.evening)
        XCTAssertFalse(plan.isEmpty)
    }

    func testProfileIsSharedOnlyWhenTickedAndSaved() {
        let ticked = QuickStartChoices(morningCheckIn: false, eveningWrapUp: false, weeklyTidyUp: false, useProfileInVoice: true)
        XCTAssertTrue(QuickStart.plan(ticked, profileSaved: true).useProfileInVoice)
        XCTAssertFalse(QuickStart.plan(ticked, profileSaved: false).useProfileInVoice, "nothing saved, nothing to send")
        XCTAssertTrue(QuickStart.plan(ticked, profileSaved: false).isEmpty)
    }

    func testWhatIsAlreadyOnKeepsItsOwnTime() {
        let current = QuickStart.Current(morningCheckIn: true, eveningWrapUp: false, weeklyTidyUp: true, useProfileInVoice: true)
        let plan = QuickStart.plan(.suggested, profileSaved: true, current: current)
        XCTAssertNil(plan.morning, "a 07:30 set in Settings is not replaced by 08:00")
        XCTAssertNil(plan.tidyUp)
        XCTAssertEqual(plan.evening, QuickStart.evening)
        let allOn = QuickStart.Current(morningCheckIn: true, eveningWrapUp: true, weeklyTidyUp: true, useProfileInVoice: true)
        XCTAssertTrue(QuickStart.plan(.suggested, profileSaved: true, current: allOn).isEmpty)
    }

    func testNothingTickedIsAnEmptyPlan() {
        let none = QuickStartChoices(morningCheckIn: false, eveningWrapUp: false, weeklyTidyUp: false, useProfileInVoice: false)
        XCTAssertFalse(none.anyNotification)
        XCTAssertTrue(QuickStart.plan(none, profileSaved: true).isEmpty)
    }

    func testSettingsStoredByTheQuickStartReadBackTheSame() {
        let defaults = UserDefaults(suiteName: "QuickStartTests.\(UUID())")!
        QuickStart.morning.store(defaults)
        QuickStart.evening.store(defaults)
        QuickStart.tidyUp.store(defaults)
        XCTAssertEqual(MorningCheckInSettings.stored(defaults), QuickStart.morning)
        XCTAssertEqual(EveningWrapUpSettings.stored(defaults), QuickStart.evening)
        XCTAssertEqual(TidyUpSettings.stored(defaults), QuickStart.tidyUp)
    }
}
