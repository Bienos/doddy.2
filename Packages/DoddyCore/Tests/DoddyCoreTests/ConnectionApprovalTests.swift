import XCTest
@testable import DoddyCore

/// Allowing an on-phone function from the conversation (ADR-562): which card shows, what the
/// Allow tap came to, and that nothing counts as allowed without the user's tap and iOS's yes.
final class ConnectionApprovalTests: XCTestCase {
    typealias Permission = ConnectionApproval.SystemPermission

    // MARK: Which card

    func testOnlyARefusalFromIOSSendsTheUserToIPhoneSettings() {
        XCTAssertEqual(ConnectionApproval.card(for: .granted), .allow, "switch off, iOS fine: one tap")
        XCTAssertEqual(ConnectionApproval.card(for: .notAsked), .allow, "iOS never asked: its prompt shows on the tap")
        XCTAssertEqual(ConnectionApproval.card(for: .denied), .openSystemSettings, "iOS said no before: only iPhone Settings can change it")
    }

    // MARK: The Allow tap

    func testTheTapCountsAsAllowedOnlyWhenTheSwitchEndedUpOn() {
        for before in [Permission.granted, .notAsked, .denied] {
            XCTAssertEqual(ConnectionApproval.outcome(before: before, switchIsOn: true), .allowed, "\(before)")
        }
        XCTAssertEqual(ConnectionApproval.outcome(before: .notAsked, switchIsOn: false), .declined,
                       "a no in iOS's own prompt is the user's no: nothing changes, the card goes")
        XCTAssertEqual(ConnectionApproval.outcome(before: .granted, switchIsOn: false), .declined)
        XCTAssertEqual(ConnectionApproval.outcome(before: .denied, switchIsOn: false), .blockedBySystem,
                       "no prompt could show: the card offers iPhone Settings instead")
    }

    func testAllowRunsOnceAtATimeAndTheCardGoesWhenAllowedOrDeclined() {
        for outcome in [ConnectionApproval.Outcome.allowed, .declined] {
            var request = ConnectionApprovalCard(connection: .calendar, permission: .notAsked)
            XCTAssertEqual(request.card, .allow)
            XCTAssertTrue(request.beginAllow())
            XCTAssertTrue(request.isWorking)
            XCTAssertFalse(request.beginAllow(), "a second tap while iOS's prompt is up does nothing")
            XCTAssertFalse(request.canDecline, "Not now waits for the prompt's own answer")
            XCTAssertFalse(request.finish(outcome), "\(outcome): the card goes")
            XCTAssertFalse(request.isWorking)
        }
    }

    func testARefusalFromBeforeTurnsTheCardIntoOpenIPhoneSettings() {
        var request = ConnectionApprovalCard(connection: .contacts, permission: .granted)
        XCTAssertTrue(request.beginAllow())
        XCTAssertTrue(request.finish(.blockedBySystem), "the card stays")
        XCTAssertEqual(request.card, .openSystemSettings)
        XCTAssertFalse(request.isWorking)
        XCTAssertFalse(request.beginAllow(), "Allow is no longer offered")
        XCTAssertTrue(request.canDecline)
    }

    // MARK: iPhone Settings

    func testIPhoneSettingsAllowsOnReturnOnlyAfterTheCardSentTheUserThereAndIOSSaysYes() {
        var request = ConnectionApprovalCard(connection: .reminders, permission: .denied)
        XCTAssertEqual(request.card, .openSystemSettings)
        XCTAssertFalse(request.allowsOnReturn(.granted), "coming back without the tap allows nothing")

        XCTAssertTrue(request.sendToSettings())
        XCTAssertTrue(request.sentToSettings)
        XCTAssertFalse(request.allowsOnReturn(.denied), "still off in iOS: the card stays")
        XCTAssertFalse(request.allowsOnReturn(.notAsked))
        XCTAssertTrue(request.allowsOnReturn(.granted))
    }

    func testAnAllowCardNeverOpensIPhoneSettings() {
        var request = ConnectionApprovalCard(connection: .timers, permission: .notAsked)
        XCTAssertFalse(request.sendToSettings())
        XCTAssertFalse(request.sentToSettings)
        XCTAssertFalse(request.allowsOnReturn(.granted))
    }

    // MARK: What the agent hears

    func testTheAgentAsksForTheTapInOneLineAndIsNeverToldToSendTheUserToSettings() {
        for connection in VoiceConnection.allCases {
            let allow = VoiceToolReply.notConnected(connection)
            XCTAssertEqual(allow, VoiceToolReply.notConnected(connection, card: .allow))
            XCTAssertTrue(allow.hasPrefix("\(connection.title) isn't connected yet."), allow)
            XCTAssertTrue(allow.contains("Say only: \"Allow it on screen and I'll carry on.\""), allow)
            XCTAssertTrue(allow.contains("Don't send them to Settings."), allow)
            XCTAssertFalse(allow.contains("Settings, Connections"), allow)
            XCTAssertTrue(allow.contains("Nothing was looked up or changed."), allow)
            XCTAssertTrue(allow.contains("\"(app)\""), "the agent knows how it will hear the yes")

            let settings = VoiceToolReply.notConnected(connection, card: .openSystemSettings)
            XCTAssertTrue(settings.hasPrefix("\(connection.title) isn't connected yet:"), settings)
            XCTAssertTrue(settings.contains("only iPhone Settings can change that"), settings)
            XCTAssertTrue(settings.contains("Nothing was looked up or changed."), settings)
        }
    }

    func testWhatDoddyDidStillReadsTheReplyAsNotDone() {
        // ActivityEntry reads "<title> isn't connected" from the start of the reply.
        for card in [ConnectionApproval.Card.allow, .openSystemSettings] {
            let (outcome, note) = ActivityEntry.outcome(of: VoiceToolReply.notConnected(.reminders, card: card), isLookup: true)
            XCTAssertEqual(outcome, .notDone, "a lookup that couldn't run is never 'looked up'")
            XCTAssertEqual(note, "Reminders isn't connected.")
        }
    }

    func testTheAppMessagesSayWhatHappenedAndNothingMore() {
        let allowed = ConnectionApproval.allowedMessage(.calendar)
        XCTAssertTrue(allowed.hasPrefix("The user just allowed Calendar on screen."))
        XCTAssertTrue(allowed.contains("try it once more now"))
        XCTAssertFalse(allowed.hasPrefix("(app)"), "the controller adds the prefix, as for its other app messages")

        let declined = ConnectionApproval.declinedContext(.blik)
        XCTAssertTrue(declined.hasPrefix("The user chose not to allow BLIK transfers"))
        XCTAssertTrue(declined.contains("nothing was looked up or changed"))
        XCTAssertTrue(declined.contains("Don't try it again"))
    }
}
