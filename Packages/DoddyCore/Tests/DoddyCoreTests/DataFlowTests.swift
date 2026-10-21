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

    func testOffSwitchesShowAsNotSent() throws {
        XCTAssertFalse(row("tokenServer", base).isActive)
        XCTAssertFalse(row("doddyServer", base).isActive)
        XCTAssertFalse(row("askDoddy", base).isActive)
        XCTAssertTrue(row("elevenlabs", base).isActive)
        // Place search (ADR-196) is user-started, so always listed; places themselves stay here.
        XCTAssertEqual(row("placeSearch", base).destination, "Apple Maps (place search and travel time)")
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("Places you set for reminders") })
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains("Earlier wordings of notes you corrected, except in files you export."))
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("Notes suggested after a conversation:") }, "save suggestions are on-device")
        let siriOff = try XCTUnwrap(DataFlow.rows(base).first { $0.id == "siri" })
        XCTAssertFalse(siriOff.isActive, "off unless the app says the switch is on")
        var siriState = base
        siriState.siriReadsNotes = true
        let siriOn = try XCTUnwrap(DataFlow.rows(siriState).first { $0.id == "siri" })
        XCTAssertTrue(siriOn.isActive)
        XCTAssertTrue(siriOn.what.contains("the note Siri reads back"))
        XCTAssertEqual(row("elevenlabs", base).what, "Your voice, the conversation, your saved notes, your list names (items only when Doddy reads or changes a list) and your personality settings.")
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

    /// ADR-566: handed-over tasks go to the messaging server and Anthropic, only with a server set.
    func testErrandsRowNamesAnthropicAndNeverTheNotes() {
        XCTAssertFalse(row("errands", base).isActive)
        XCTAssertTrue(row("errands", base).note?.contains("can't be handed over") ?? false)
        var state = base
        state.messagingServerSet = true
        let errands = row("errands", state)
        XCTAssertTrue(errands.isActive)
        XCTAssertTrue(errands.destination.contains("Anthropic"))
        XCTAssertTrue(errands.what.contains("Never your saved notes"))
        XCTAssertTrue(errands.note?.contains("no words from the task") ?? false)
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

    func testNewsWriterIsNamedOnlyAsTheServerReportsIt() {
        var state = base
        state.messagingServerSet = true
        let unknown = row("messagingServer", state)
        XCTAssertTrue(unknown.destination.contains("Anthropic or OpenAI"))
        XCTAssertTrue(unknown.note?.contains("headlines to Anthropic or OpenAI") == true)
        state.newsWriterProvider = "openai"
        let openAI = row("messagingServer", state)
        XCTAssertTrue(openAI.destination.contains("OpenAI"))
        XCTAssertFalse(openAI.destination.contains("Anthropic"))
        XCTAssertFalse(openAI.note?.contains("Anthropic") == true)
        state.newsWriterProvider = "anthropic"
        XCTAssertFalse(row("messagingServer", state).destination.contains("OpenAI"))
    }

    func testRememberedConversationsLineFollowsTheSwitch() {
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains("Conversations: none are remembered."))
        var state = base
        state.rememberConversations = true
        XCTAssertFalse(DataFlow.staysOnPhone(state).contains("Conversations: none are remembered."))
    }

    // ADR-440: what Doddy learned reaches a conversation only when the user switched that on.
    func testLearnedFactsAreListedOnlyWhenSharedWithVoice() {
        XCTAssertFalse(row("elevenlabs", base).what.contains("What I've learned"))
        var shared = base
        shared.learnedSharedWithVoice = true
        XCTAssertTrue(row("elevenlabs", shared).what.contains("the facts and routines you confirmed under What I've learned"))
        XCTAssertTrue(DataFlow.staysOnPhone(base).contains { $0.hasPrefix("What Doddy learned") }, "proposals and counts are always on the phone")
    }
}

/// Settings → Privacy's Network and Cloud AI rows come from the same rows as What leaves this
/// iPhone (audit 2026-10-12 §5 #6, ADR-447), so they can't list less than that screen.
final class DataFlowSummaryTests: XCTestCase {
    private let base = DataFlowState(
        rememberConversations: false, shareProfileWithVoice: false, tokenServerSet: false,
        connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false, askDoddyUsesNotes: true)

    private var everything: DataFlowState {
        var state = base
        state.tokenServerSet = true
        state.doddyServerSet = true
        state.askDoddyOn = true
        state.messagingServerSet = true
        state.siriReadsNotes = true
        state.sharedLists = 1
        state.voiceProvider = .openAIRealtime
        return state
    }

    func testEveryRowIsNamedInTheNetworkSummaryOrDeliberatelyLeftOut() {
        for row in DataFlow.rows(everything) {
            XCTAssertTrue(
                DataFlow.networkNames[row.id] != nil || DataFlow.notInNetworkSummary.contains(row.id),
                "\(row.id) is in What leaves this iPhone but not in Settings' Network row")
        }
        XCTAssertTrue(DataFlow.notInNetworkSummary.isDisjoint(with: DataFlow.networkNames.keys))
    }

    func testNetworkNamesExactlyTheActiveRows() {
        let summary = DataFlow.networkSummary(everything)
        for row in DataFlow.rows(everything) where row.isActive {
            if let name = DataFlow.networkNames[row.id] {
                XCTAssertTrue(summary.contains(name), "\(row.id) is on but missing: \(summary)")
            }
        }
        // The audit's missing ones are there when they're on.
        for name in ["your Doddy messaging server", "Apple Maps", "European Central Bank", "iCloud", "Siri", "the Ask Doddy gateway"] {
            XCTAssertTrue(summary.contains(name), name)
        }
    }

    func testSwitchedOffServicesAreNotNamed() {
        var state = base
        state.siriReadsNotes = false
        state.pauseAll = true
        let summary = DataFlow.networkSummary(state)
        for name in ["voice token server", "Doddy server", "messaging server", "Ask Doddy", "Siri", "iCloud", "European Central Bank", "OpenAI"] {
            XCTAssertFalse(summary.contains(name), "\(name) is off but named: \(summary)")
        }
        XCTAssertTrue(summary.hasPrefix("ElevenLabs (while talking)"), "voice is always possible")
        XCTAssertTrue(summary.hasSuffix("What leaves this iPhone says what goes."))
    }

    func testCloudAINamesEveryAIServiceThatIsOn() {
        XCTAssertEqual(DataFlow.cloudAISummary(base), "ElevenLabs (voice)")
        // OpenAI runs the voice where the token server is set (ADR-442): ElevenLabs gets no voice then.
        XCTAssertEqual(
            DataFlow.cloudAISummary(everything),
            "OpenAI (voice); OpenAI (Ask Doddy); ElevenLabs (phone calls) and Anthropic or OpenAI (daily news) on your messaging server; Anthropic (tasks you hand over)")
        XCTAssertFalse(DataFlow.networkSummary(everything).contains("ElevenLabs (while talking)"))
        var elevenLabs = everything
        elevenLabs.voiceProvider = .elevenLabs
        XCTAssertTrue(DataFlow.cloudAISummary(elevenLabs).hasPrefix("ElevenLabs (voice); OpenAI (Ask Doddy)"))
        var state = everything
        state.newsWriterProvider = "anthropic"
        XCTAssertTrue(DataFlow.cloudAISummary(state).contains("Anthropic (daily news)"))
    }
}
