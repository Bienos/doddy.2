import XCTest
import DoddyCore
@testable import Doddy

/// ADR-579 and ADR-581 in the app target. NOT RUN in the authoring environment (no Xcode); hosted
/// CI runs them. The press rules themselves are DoddyCore's (`TalkLaunchTests`, on Linux).
final class TalkButtonAndLegalTests: XCTestCase {
    @MainActor
    private func makeRouter() -> ShortcutRouter {
        let defaults = UserDefaults(suiteName: "TalkButtonAndLegalTests.\(UUID().uuidString)")!
        return ShortcutRouter(setup: BackTapSetupModel(defaults: defaults))
    }

    @MainActor
    func testTheControlOpeningDoddyAsksHomeToTalkWithTheGreetingOnce() {
        let router = makeRouter()
        router.talkButtonOpenedApp()
        XCTAssertFalse(router.isVoicePresented, "the conversation starts on Home, not in the transcript sheet")
        XCTAssertEqual(router.takeTalkOnHome()?.greeted, true, "the shortcut greeting is used")
        XCTAssertNil(router.takeTalkOnHome(), "only once")
    }

    @MainActor
    func testTheControlIgnoresBackTapsOnlyOpenChoice() {
        let key = PreferenceKey.backTapAction
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set(BackTapAction.openApp.rawValue, forKey: key)
        let router = makeRouter()
        router.talkButtonOpenedApp()
        XCTAssertNotNil(router.takeTalkOnHome(), "the Action Button's own choice says talk")
    }

    @MainActor
    func testWithTheTranscriptOpenAPressStartsNothingNew() {
        let router = makeRouter()
        router.openVoiceForGate(greeted: true)
        XCTAssertTrue(router.isVoicePresented, "Home couldn't start it: the voice screen opens on the sign-in step")
        XCTAssertTrue(router.takeTalkToDoddyOpening(), "and greets once the step is done")
        router.talkButtonOpenedApp()
        XCTAssertNil(router.takeTalkOnHome(), "the open screen already shows the conversation")
    }

    func testAcceptingStoresTheRecordAndReadsItBack() {
        let key = LegalAcceptance.preferenceKey
        let previous = UserDefaults.standard.data(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(LegalAcceptanceStore.isNeeded(nil))

        XCTAssertTrue(LegalAcceptanceStore.accept(source: .onboarding, at: Date(timeIntervalSince1970: 1_792_000_000.5)))
        let record = LegalAcceptanceStore.record
        XCTAssertEqual(record?.termsVersion, LegalDocuments.termsVersion)
        XCTAssertEqual(record?.privacyVersion, LegalDocuments.privacyVersion)
        XCTAssertEqual(record?.source, .onboarding)
        XCTAssertFalse(LegalAcceptanceStore.isNeeded)
    }

    func testTheIslandSwitchIsOnUntilTurnedOff() {
        XCTAssertEqual(PreferenceKey.islandExpands, LaunchPreferencesMigration.islandExpandsKey)
        XCTAssertEqual(PreferenceKey.talkLaunchMode, TalkLaunchMode.preferenceKey)
        XCTAssertTrue(LaunchPreferencesMigration.islandExpands(nil))
    }
}
