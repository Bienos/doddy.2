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
    func testTheControlOpeningDoddyStartsTheConversationWithTheGreetingOnce() {
        let router = makeRouter()
        router.talkButtonOpenedApp()
        XCTAssertTrue(router.isVoicePresented)
        XCTAssertTrue(router.takeTalkToDoddyOpening(), "the shortcut greeting is used")
        XCTAssertFalse(router.takeTalkToDoddyOpening(), "only once")
    }

    @MainActor
    func testTheControlIgnoresBackTapsOnlyOpenChoice() {
        let key = PreferenceKey.backTapAction
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set(BackTapAction.openApp.rawValue, forKey: key)
        let router = makeRouter()
        router.talkButtonOpenedApp()
        XCTAssertTrue(router.isVoicePresented, "the Action Button's own choice says talk")
    }

    @MainActor
    func testASecondPressWithTheConversationOpenDoesntGreetAgain() {
        let router = makeRouter()
        router.talkButtonOpenedApp()
        _ = router.takeTalkToDoddyOpening()
        router.talkButtonOpenedApp()
        XCTAssertTrue(router.isVoicePresented)
        XCTAssertFalse(router.takeTalkToDoddyOpening(), "a conversation already open isn't a new opening")
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
