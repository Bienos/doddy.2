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

    /// ADR-586: typed questions go through the messaging server to Anthropic, so they can only leave with a server set.
    func testAskDoddyNamesAnthropicAndNeedsTheMessagingServer() {
        var state = base
        XCTAssertEqual(row("askDoddy", state).note, "Ask Doddy is off, so nothing goes there.")
        state.askDoddyOn = true
        XCTAssertFalse(row("askDoddy", state).isActive, "on, but no server: nothing can be sent")
        XCTAssertEqual(row("askDoddy", state).note, "No messaging server is set, so typed questions can't be sent.")
        state.messagingServerSet = true
        let ask = row("askDoddy", state)
        XCTAssertTrue(ask.isActive)
        XCTAssertTrue(ask.destination.contains("Anthropic"))
        XCTAssertFalse(ask.destination.contains("OpenAI"))
        XCTAssertTrue(DataFlow.cloudAISummary(state).contains("Anthropic (Ask Doddy)"))
        XCTAssertFalse(DataFlow.cloudAISummary(state).contains("OpenAI (Ask Doddy)"))
    }

    func testAskDoddyMentionsNotesOnlyWhenAllowed() {
        var state = base
        state.askDoddyOn = true
        XCTAssertTrue(row("askDoddy", state).what.contains("saved notes"))
        state.askDoddyUsesNotes = false
        XCTAssertEqual(row("askDoddy", state).what, "Typed questions.")
    }

    /// ADR-570: handed-over tasks go to the messaging server and Anthropic, only with a server set.
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

    /// SHOPPING.md: leaflets go through the messaging server; nothing that identifies the user goes to the
    /// shops, and the row says Rossmann gets the item names as a search.
    func testLeafletsRowSaysNothingIdentifyingGoesToTheShops() {
        XCTAssertFalse(row("deals", base).isActive)
        XCTAssertTrue(row("deals", base).note?.contains("can't be checked") ?? false)
        var state = base
        state.messagingServerSet = true
        let deals = row("deals", state)
        XCTAssertTrue(deals.isActive)
        XCTAssertTrue(deals.destination.contains("Anthropic"))
        XCTAssertTrue(deals.what.contains("Nothing that identifies you goes to any shop."))
        XCTAssertTrue(deals.what.contains("rossmann.pl as a search"), "the one shop that gets the item names is named")
        XCTAssertTrue(deals.what.contains("Never your saved notes"))
        XCTAssertTrue(deals.note?.contains("only daily counts") ?? false)
        state.pauseAll = true
        XCTAssertFalse(row("deals", state).isActive, "paused: the server isn't asked")
        XCTAssertTrue(row("errands", state).what.contains("Serper"), "shopping tasks name the offer source")
    }

    /// SHOPPING_WATCH.md (ADR-614): a watched price goes to the messaging server, which reads the shop's page;
    /// the notification has no product words, nothing is bought, no AI service is involved, and nothing is sent
    /// without a server or while Connections are paused.
    func testPriceWatchRowSaysWhatGoesWhereAndThatNothingIsBought() {
        XCTAssertFalse(row("watches", base).isActive)
        XCTAssertEqual(row("watches", base).note, "No messaging server is set, so prices can't be watched.")
        XCTAssertFalse(DataFlow.networkSummary(base).contains("prices you watch"))
        var state = base
        state.messagingServerSet = true
        let watches = row("watches", state)
        XCTAssertTrue(watches.isActive)
        XCTAssertTrue(watches.destination.contains("messaging server"))
        XCTAssertTrue(watches.destination.contains("shops' pages"))
        for part in ["shop's name and page address", "the product's title", "the price you want", "a few times a day for 30 days",
                     "The notification has no product words", "Nothing is bought, ordered or signed in", "Never your saved notes"] {
            XCTAssertTrue(watches.what.contains(part), part)
        }
        XCTAssertTrue(watches.when.contains("when you say yes"))
        XCTAssertTrue(watches.note?.contains("keeps no page content") ?? false)
        XCTAssertTrue(DataFlow.networkSummary(state).contains("the shops' pages, read by your messaging server (prices you watch)"))
        // No model reads a watch: it is in no AI summary.
        XCTAssertFalse(watches.destination.contains("Anthropic"))
        XCTAssertFalse(DataFlow.cloudAISummary(state).localizedCaseInsensitiveContains("watch"))
        // Paused: nothing new goes, and the row says the server still checks what is already running.
        state.pauseAll = true
        let paused = row("watches", state)
        XCTAssertFalse(paused.isActive)
        XCTAssertTrue(paused.note?.contains("already watch") ?? false)
        XCTAssertTrue(paused.note?.contains("until you stop or delete them") ?? false)
        XCTAssertFalse(DataFlow.networkSummary(state).contains("prices you watch"))
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
        for name in ["your Doddy messaging server", "Apple Maps", "European Central Bank", "iCloud", "Siri", "Anthropic (Ask Doddy, through your messaging server)"] {
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
            "OpenAI (voice); Anthropic (Ask Doddy); ElevenLabs (phone calls) and Anthropic or OpenAI (daily news) on your messaging server; Anthropic (tasks you hand over); Anthropic (leaflets you check)")
        XCTAssertFalse(DataFlow.networkSummary(everything).contains("ElevenLabs (while talking)"))
        var elevenLabs = everything
        elevenLabs.voiceProvider = .elevenLabs
        XCTAssertTrue(DataFlow.cloudAISummary(elevenLabs).hasPrefix("ElevenLabs (voice); Anthropic (Ask Doddy)"))
        var state = everything
        state.newsWriterProvider = "anthropic"
        XCTAssertTrue(DataFlow.cloudAISummary(state).contains("Anthropic (daily news)"))
    }

    func testWebSignInSaysWhatTheBrowserSeesAndThatNotesStayHere() throws {
        // ADR-600.
        var state = base
        state.doddyServerSet = true
        let row = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webSignIn" })
        XCTAssertTrue(row.isActive)
        XCTAssertTrue(row.what.contains("Never your saved notes"))
        XCTAssertTrue(row.what.contains("files Doddy made"))
        state.doddyServerSet = false
        let off = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webSignIn" })
        XCTAssertFalse(off.isActive)
        XCTAssertNotNil(off.note)
    }

    func testKeptNotesAndConversationsHaveTheirOwnRowAndNameAnthropic() throws {
        // ADR-603.
        var state = base
        state.doddyServerSet = true
        let off = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertFalse(off.isActive)
        XCTAssertEqual(off.what, "Nothing: both switches are off.")
        XCTAssertTrue(DataFlow.rows(state).first { $0.id == "webSignIn" }?.what.contains("Never your saved notes, lists, profile or conversations.") ?? false)
        XCTAssertFalse(DataFlow.cloudAISummary(state).contains("web"))

        state.webNotesKept = true
        let notes = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertTrue(notes.isActive)
        XCTAssertTrue(notes.what.contains("saved notes (not private ones)"))
        XCTAssertFalse(notes.what.contains("conversations"))
        XCTAssertTrue(notes.destination.contains("Anthropic"))
        XCTAssertTrue(notes.note?.contains("the server can read it") ?? false, "it says plainly that this is not end-to-end")

        state.webConversationsKept = true
        let both = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertTrue(both.what.contains("conversations (not private ones), never audio"))
        XCTAssertTrue(both.note?.contains("1 year") ?? false)
        XCTAssertTrue(DataFlow.cloudAISummary(state).contains("Anthropic (questions you ask on the web"))
        XCTAssertTrue(DataFlow.networkSummary(state).contains("notes and conversations you keep there"))
        // The browser's row no longer claims the browser never sees notes.
        let browser = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webSignIn" })
        XCTAssertFalse(browser.what.contains("Never your saved notes"))
        XCTAssertTrue(browser.what.contains("notes and conversations you keep on Doddy's server"))
    }

    func testNothingIsSaidToGoToTheServerWithoutOne() throws {
        var state = base
        state.webNotesKept = true
        state.doddyServerSet = false
        let row = try XCTUnwrap(DataFlow.rows(state).first { $0.id == "webMemory" })
        XCTAssertFalse(row.isActive)
        XCTAssertEqual(row.note, "No Doddy server is set, so nothing goes there.")
    }
}
