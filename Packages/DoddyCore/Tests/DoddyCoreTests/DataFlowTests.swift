import XCTest
@testable import DoddyCore

/// What leaves this iPhone follows the settings, never a fixed list.
final class DataFlowTests: XCTestCase {
    private let base = DataFlowState(
        rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
        connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)

    private func row(_ id: String, _ state: DataFlowState) -> DataFlowRow {
        DataFlow.rows(state).first { $0.id == id }!
    }

    func testOffSwitchesShowAsNotSent() {
        XCTAssertFalse(row("tokenServer", base).isActive)
        XCTAssertFalse(row("doddyServer", base).isActive)
        XCTAssertFalse(row("askDoddy", base).isActive)
        XCTAssertTrue(row("elevenlabs", base).isActive)
        // Place search (ADR-196) is user-started, so always listed; places themselves stay here.
        XCTAssertEqual(row("placeSearch", base).destination, "Apple Maps (place search)")
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("Places you set for reminders") })
        XCTAssertEqual(row("elevenlabs", base).what, "Your voice, the conversation, your saved notes and your personality settings.")
    }

    func testVoiceRowGrowsWithWhatIsSwitchedOn() {
        var state = base
        state.rememberConversations = true
        state.shareProfileWithVoice = true
        state.connectionsOn = [.reminders, .calendar]
        state.doddyServerSet = true
        let what = row("elevenlabs", state).what
        XCTAssertTrue(what.contains("your last few conversations"))
        XCTAssertTrue(what.contains("your introduction answers"))
        XCTAssertTrue(what.contains("(Calendar, Reminders)"))
        XCTAssertTrue(what.contains("results from your online accounts"))
    }

    func testPauseAllRemovesAppsFromTheVoiceRow() {
        var state = base
        state.connectionsOn = [.calendar]
        state.doddyServerSet = true
        state.pauseAll = true
        XCTAssertFalse(row("elevenlabs", state).what.contains("Calendar"))
        XCTAssertFalse(row("elevenlabs", state).what.contains("online accounts"))
        XCTAssertTrue(row("doddyServer", state).note?.contains("paused") ?? false)
    }

    func testAskDoddyMentionsNotesOnlyWhenAllowed() {
        var state = base
        state.askDoddyOn = true
        XCTAssertTrue(row("askDoddy", state).what.contains("saved notes"))
        state.askDoddyUsesNotes = false
        XCTAssertEqual(row("askDoddy", state).what, "Typed questions.")
    }

    func testMessagingServerRowListsNotesOnlyWhenTheCopyIsOn() {
        XCTAssertFalse(row("messagingServer", base).isActive)
        var state = base
        state.messagingServerSet = true
        XCTAssertTrue(row("messagingServer", state).isActive)
        XCTAssertFalse(row("messagingServer", state).what.contains("saved notes"))
        XCTAssertFalse(row("messagingServer", state).what.contains("notification token"))
        state.pushOn = true
        state.memoryCopyOn = true
        XCTAssertTrue(row("messagingServer", state).what.contains("this iPhone's notification token"))
        XCTAssertTrue(row("messagingServer", state).what.contains("a copy of your saved notes"))
    }

    func testRememberedConversationsLineFollowsTheSwitch() {
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains("Conversations: none are remembered."))
        var state = base
        state.rememberConversations = true
        XCTAssertFalse(DataFlow.staysOnPhone(state).contains("Conversations: none are remembered."))
    }
}
