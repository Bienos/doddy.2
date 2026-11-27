import XCTest
@testable import DoddyCore

/// Steering the app by voice (decision 2026-11-27-voice-first-doddy): open a screen, change a setting from the list.
final class AppControlVoiceTests: XCTestCase {
    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    func testAScreenIsOneOfTheAppsOwn() {
        XCTAssertEqual(parse(VoiceToolName.openScreen, #"{"screen":"tasks"}"#), .openScreen(.tasks))
        XCTAssertEqual(parse(VoiceToolName.openScreen, #"{"screen":" My_City "}"#), .openScreen(.myCity))
        for json in [#"{}"#, #"{"screen":"safari"}"#, #"{"screen":"https://example.com"}"#] {
            guard case .invalid = parse(VoiceToolName.openScreen, json) else { return XCTFail("\(json) opens nothing") }
        }
    }

    func testAScreenOfAHiddenFeatureBelongsToThatFeature() {
        XCTAssertEqual(AppScreen.tasks.feature, .errands)
        XCTAssertEqual(AppScreen.radar.feature, .following)
        XCTAssertNil(AppScreen.settings.feature, "every build has Settings")
    }

    func testASettingIsFromTheListAndTakesOnlyItsOwnValues() {
        XCTAssertEqual(parse(VoiceToolName.changeSetting, #"{"setting":"humour","value":"off"}"#), .changeSetting(.humour, value: "off"))
        XCTAssertEqual(parse(VoiceToolName.changeSetting, #"{"setting":"reply_length","value":"Brief"}"#), .changeSetting(.replyLength, value: "brief"))
        XCTAssertEqual(parse(VoiceToolName.changeSetting, #"{"setting":"character_art","value":"off"}"#), .changeSetting(.characterArt, value: "off"))
        let refused = [
            #"{"setting":"app_lock","value":"off"}"#,  // privacy stays in Settings, by hand
            #"{"setting":"humour","value":"maximum"}"#,  // not one of its values
            #"{"setting":"humour"}"#,
            #"{"value":"off"}"#,
            #"{"setting":"remember_conversations","value":"yes"}"#,  // a switch is on or off
        ]
        for json in refused {
            guard case .invalid = parse(VoiceToolName.changeSetting, json) else { return XCTFail("\(json) changes nothing") }
        }
    }

    func testTheValuesAreTheSettingsOwn() {
        XCTAssertEqual(VoiceSetting.humour.values, ["off", "subtle", "playful"])
        XCTAssertEqual(VoiceSetting.replyLength.values, ["brief", "balanced", "detailed"])
        XCTAssertEqual(VoiceSetting.appearance.values, ["system", "light", "dark"])
        XCTAssertTrue(VoiceSetting.listenOnOpen.isSwitch)
        XCTAssertTrue(VoiceSetting.humour.fromNextConversation)
        XCTAssertFalse(VoiceSetting.appearance.fromNextConversation)
        XCTAssertEqual(Set(VoiceSetting.allCases.map(\.rawValue)), [
            "humour", "reply_length", "tone", "mood", "voice_speed", "voice_expressiveness", "appearance", "character_art",
            "note_saved_island", "listen_on_open", "remember_conversations", "suggest_notes",
        ], "a setting joins the list on purpose")
    }

    func testBothRunAtOnceAndNeitherWhileLockedWithTheFaceIDLock() {
        for name in AppControlVoice.atOnceTools {
            XCTAssertTrue(AskFirst.runsAtOnce(name), name)
            XCTAssertEqual(ConfirmationTiers.tier(for: name), .atOnce, name)
            XCTAssertFalse(ProtectedDataPolicy.allows(tool: name, protectedDataAvailable: false, appLockOn: true), name)
        }
        XCTAssertEqual(AskFirst.need(for: .openScreen(.tasks)), .runsNow)
        XCTAssertEqual(AskFirst.need(for: .changeSetting(.humour, value: "off")), .runsNow)
    }

    func testRepliesSayWhatHappened() {
        XCTAssertTrue(AppControlVoice.opening(.tasks).hasPrefix("opened:"))
        XCTAssertTrue(AppControlVoice.changed(.humour, to: "off").contains("next conversation"))
        XCTAssertFalse(AppControlVoice.changed(.appearance, to: "dark").contains("next conversation"))
        XCTAssertTrue(AppControlVoice.alreadySet(.mood, "calm").hasPrefix("not changed:"))
        XCTAssertTrue(AppControlVoice.notChanged(.mood).hasPrefix("failed:"))
    }
}
