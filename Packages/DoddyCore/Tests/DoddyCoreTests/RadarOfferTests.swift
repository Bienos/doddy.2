import XCTest
@testable import DoddyCore

/// What On my radar offers about "tell me when" (decision 2026-11-13-radar-fixes; owner's review, 12 Nov 2026: alerts are
/// off on the server, yet "Tell me…" showed and offered only "Here only").
final class RadarOfferTests: XCTestCase {
    private func state(available: Bool) throws -> RadarServerState {
        try JSONDecoder().decode(RadarServerState.self, from: Data(#"{"available":\#(available),"push":false,"alerts":[],"hits":[]}"#.utf8))
    }

    private let cpk = NewsFollow.words(label: "CPK", keywords: ["CPK"])

    func testOnlyTheServersOwnAnswerCounts() throws {
        XCTAssertEqual(RadarAlertsAvailability(nil), .unknown, "no answer is not a yes")
        XCTAssertEqual(RadarAlertsAvailability(try state(available: false)), .off)
        XCTAssertEqual(RadarAlertsAvailability(try state(available: true)), .on)
        XCTAssertTrue(RadarTellMe.offersServerChecks(.on))
        XCTAssertFalse(RadarTellMe.offersServerChecks(.off))
        XCTAssertFalse(RadarTellMe.offersServerChecks(.unknown))
    }

    func testTellMeIsHiddenWhileTheServerChecksNothingAndNothingIsSet() {
        let plain = RadarAlert(followID: cpk.id)
        XCTAssertFalse(RadarTellMe.showsButton(.off, alert: plain), "its only choice would be Here only")
        XCTAssertFalse(RadarTellMe.showsButton(.unknown, alert: plain))
        XCTAssertTrue(RadarTellMe.showsButton(.on, alert: plain))
        XCTAssertNil(RadarTellMe.line(plain, .off, polish: true), "no Tylko tutaj line with nothing else to choose")
        XCTAssertNil(RadarTellMe.line(plain, .unknown, polish: false))
        XCTAssertEqual(RadarTellMe.line(plain, .on, polish: false), "Shown here only")
    }

    func testWhatThePersonAlreadySetCanStillBeChanged() {
        let flags = RadarAlert(followID: cpk.id, words: ["lotnisko"], how: .app)
        XCTAssertTrue(RadarTellMe.showsButton(.off, alert: flags), "flag words can be changed or cleared")
        XCTAssertEqual(RadarTellMe.line(flags, .off, polish: true), "Tylko tutaj; artykuły, w których pada lotnisko, dostają flagę")
        let checked = RadarAlert(followID: cpk.id, words: ["lotnisko"], how: .instant)
        XCTAssertTrue(RadarTellMe.showsButton(.unknown, alert: checked), "a server check can be turned off")
        XCTAssertTrue(RadarTellMe.showsButton(.off, alert: RadarAlert(followID: cpk.id, how: .daily)))
    }

    func testACheckIsNeverSaidToRunWhenTheServerSaysItChecksNothing() {
        let checked = RadarAlert(followID: cpk.id, words: ["lotnisko"], how: .instant)
        XCTAssertEqual(RadarTellMe.line(checked, .off, polish: false), "Shown here only; stories that mention lotnisko get a flag")
        XCTAssertEqual(RadarTellMe.line(checked, .on, polish: false), "Doddy's server tells you as it happens when a story mentions lotnisko")
        XCTAssertEqual(RadarTellMe.line(checked, .unknown, polish: false), checked.summary(polish: false),
                       "with no answer, what the server confirmed when it was saved")
    }

    func testSavedHereOnlyOnceTheServerSaysItChecksNothing() {
        let daily = RadarAlert(followID: cpk.id, words: ["lotnisko"], how: .daily, dailyTime: "07:30")
        XCTAssertEqual(RadarTellMe.kept(daily, .off), RadarAlert(followID: cpk.id, words: ["lotnisko"], how: .app, dailyTime: "07:30"))
        XCTAssertEqual(RadarTellMe.kept(daily, .unknown), daily, "a missing answer never turns a check off by itself")
        XCTAssertEqual(RadarTellMe.kept(daily, .on), daily)
        let here = RadarAlert(followID: cpk.id, words: ["x1"], how: .app)
        XCTAssertEqual(RadarTellMe.kept(here, .off), here)
    }

    func testTheSheetSaysWhyOnlyHereIsOffered() {
        XCTAssertNil(RadarTellMe.hereOnlyReason(.on))
        XCTAssertEqual(RadarTellMe.hereOnlyReason(.off), .serverDoesNotCheck)
        XCTAssertEqual(RadarTellMe.hereOnlyReason(.unknown), .noAnswer)
    }
}
