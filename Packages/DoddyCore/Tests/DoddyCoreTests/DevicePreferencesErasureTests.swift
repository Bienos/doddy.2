import Foundation
import XCTest
@testable import DoddyCore

/// The preferences (UserDefaults) side of "Erase everything on this iPhone". Everything is erased unless a rule says
/// to keep it, and every rule has a reason; a key the rules don't know is erased, so a new key can't be forgotten
/// (it can only be erased by mistake, which is recoverable). The tests also fail when a new `PreferenceKey` has not
/// been classified on purpose, and when a kept key is no longer in the app.
final class DevicePreferencesErasureTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "DevicePreferencesErasureTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func keys() -> Set<String> {
        Set(defaults.persistentDomain(forName: suiteName)?.keys.map { $0 } ?? [])
    }

    // MARK: What is erased and what is kept

    func testPersonalValuesAndSettingsAreErased() {
        for key in ["personality.nickname", "parking.spot", "parcelBook", "food.deliveryAddress", "deals.myShops", "pinnedNotes",
                    "privateNotes.ids", "news.follows", "studio.topics", "someKeyNobodyHasHeardOf"] {
            defaults.set("value", forKey: key)
        }
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        XCTAssertEqual(keys(), [])
    }

    func testTheSignInAndWhatTiesThisIPhoneToItsServersStayWhileSignedIn() {
        let kept = ["doddyAccount.backendUse.https://example.test", "doddyAccount.messagingUse.https://example.test",
                    "doddyAccount.appleRevoked.user-1", "deviceSession.expiresAt", "voiceUserID"]
        for key in kept { defaults.set("v", forKey: key) }
        defaults.set("x", forKey: "personality.nickname")
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        XCTAssertEqual(keys(), Set(kept))
    }

    func testAfterTheAccountWasDeletedTheSignInAndItsServerTiesGoToo() {
        for key in ["doddyAccount.backendUse.https://example.test", "deviceSession.expiresAt", "voiceUserID",
                    "memoryCopyOn", "webMemory.notes", "logbook.serverOn", "pushUpdatesOn", "textsToDoddyOn"] {
            defaults.set(true, forKey: key)
        }
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .afterAccountDeleted)
        XCTAssertEqual(keys(), [])
    }

    func testMarkersFlagsAndTheLanguageStayWhateverTheScope() {
        let kept = ["serverKeychainInstalled", "assistantKeychainInstalled", "accountKeysInstalled",
                    "welcomeSeen", "firstRunAccessSeen", "legalAcceptance", "quickStartOffered", "hadFirstConversation",
                    "appLanguage", "appLanguage.polishDefaultApplied",
                    "messages.conversationDeletedAt", "recaps.links.v1", "localData.ownerAccountID",
                    "voiceTokenServer", "messagingServerURL", "connectedAppsServerURL", "developer.directVoice"]
        for scope in [DeviceErasureScope.keepSignIn, .afterAccountDeleted] {
            for key in kept { defaults.set("v", forKey: key) }
            DefaultsErasure.erase(defaults, domain: suiteName, scope: scope)
            XCTAssertEqual(keys(), Set(kept), "scope \(scope)")
        }
    }

    /// Erasing must never turn something on that sends data off this iPhone: the person's choice stays as it was.
    func testSwitchesThatDecideWhatIsSentKeepTheirPosition() {
        for key in ["assistantConsent", "logbook.on", "rememberConversations"] {
            defaults.set(false, forKey: key)
        }
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        for key in ["assistantConsent", "logbook.on", "rememberConversations"] {
            XCTAssertEqual(defaults.object(forKey: key) as? Bool, false, "\(key) must stay off")
        }
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .afterAccountDeleted)
        XCTAssertEqual(defaults.object(forKey: "assistantConsent") as? Bool, false, "a choice stays after the account is gone too")
    }

    func testTheMemoryCopySwitchStaysOnSoTheEmptyIPhoneEmptiesTheServerCopy() {
        defaults.set(true, forKey: "memoryCopyOn")
        defaults.set(true, forKey: "memoryCopy.privateNotesCleanupConfirmed")
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        XCTAssertEqual(defaults.bool(forKey: "memoryCopyOn"), true)
        // The confirmation goes, so the next launch sends the (empty) list again if this send didn't reach the server.
        XCTAssertNil(defaults.object(forKey: "memoryCopy.privateNotesCleanupConfirmed"))
    }

    func testIOSOwnKeysAreNeitherErasedNorCounted() {
        defaults.set(["pl"], forKey: "AppleLanguages")
        defaults.set(true, forKey: "NSInterfaceStyle")
        defaults.set("x", forKey: "com.apple.something")
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        XCTAssertEqual(keys(), ["AppleLanguages", "NSInterfaceStyle", "com.apple.something"])
        XCTAssertEqual(DefaultsErasure.leftover(defaults, domain: suiteName, scope: .keepSignIn), [])
    }

    // MARK: Read-back

    func testTheReadBackNamesWhatShouldHaveGoneAndDidNot() {
        defaults.set("x", forKey: "personality.nickname")
        defaults.set(true, forKey: "welcomeSeen")
        XCTAssertEqual(DefaultsErasure.leftover(defaults, domain: suiteName, scope: .keepSignIn), ["personality.nickname"])
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        XCTAssertEqual(DefaultsErasure.leftover(defaults, domain: suiteName, scope: .keepSignIn), [])
    }

    func testRunningItTwiceIsHarmless() {
        defaults.set("x", forKey: "personality.nickname")
        defaults.set(true, forKey: "welcomeSeen")
        DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        let again = DefaultsErasure.erase(defaults, domain: suiteName, scope: .keepSignIn)
        XCTAssertEqual(again, [])
        XCTAssertEqual(keys(), ["welcomeSeen"])
    }

    func testAnEmptyDomainHasNothingLeft() {
        XCTAssertEqual(DefaultsErasure.leftover(defaults, domain: suiteName, scope: .keepSignIn), [])
    }

    // MARK: Every kept key has a reason, and the table is not stale

    func testEveryRuleToKeepHasAReasonAndTheScopeDecidesTheRest() {
        for (key, reason) in DevicePreferences.keptKeys {
            XCTAssertEqual(DevicePreferences.rule(for: key, scope: .keepSignIn), .keep(reason), key)
        }
        XCTAssertEqual(DevicePreferences.rule(for: "doddyAccount.anything", scope: .keepSignIn), .keep(.signIn))
        XCTAssertEqual(DevicePreferences.rule(for: "doddyAccount.anything", scope: .afterAccountDeleted), .erase)
        XCTAssertEqual(DevicePreferences.rule(for: "unknown.key", scope: .keepSignIn), .erase)
        XCTAssertEqual(DevicePreferences.rule(for: "AppleLocale", scope: .keepSignIn), .ignore)
    }

    /// A kept key that no source mentions any more is a stale rule: it would quietly keep nothing, or hide a rename.
    func testEveryKeptKeyIsStillUsedByTheApp() throws {
        let text = try AppSourceScan.swiftFiles().filter { !$0.path.hasSuffix("DevicePreferences.swift") }
            .map(\.text).joined(separator: "\n")
        for key in DevicePreferences.keptKeys.keys {
            XCTAssertTrue(text.contains("\"\(key)\""), "`\(key)` is kept on purpose but the app no longer uses it: remove or rename its rule")
        }
        for prefix in DevicePreferences.keptPrefixes.keys {
            XCTAssertTrue(text.contains("\"\(prefix)"), "`\(prefix)…` is kept on purpose but the app no longer uses it")
        }
    }

    /// What is kept is said in the doc (`docs/architecture/DEVICE_DATA_STORES.md`), key by key, so a person reading it
    /// knows what an erase leaves.
    func testTheDocNamesEveryKeptKey() throws {
        guard let doc = AppSourceScan.text(of: "docs/architecture/DEVICE_DATA_STORES.md") else {
            return XCTFail("docs/architecture/DEVICE_DATA_STORES.md is missing")
        }
        for key in DevicePreferences.keptKeys.keys {
            XCTAssertTrue(doc.contains("`\(key)`"), "the doc doesn't name the kept key `\(key)`")
        }
        for prefix in DevicePreferences.keptPrefixes.keys {
            XCTAssertTrue(doc.contains("`\(prefix)*`"), "the doc doesn't name the kept key family `\(prefix)*`")
        }
        for reason in KeptReason.allCases {
            XCTAssertFalse(reason.rawValue.isEmpty)
        }
    }

    // MARK: A new PreferenceKey must be classified on purpose

    func testEveryPreferenceKeyIsClassifiedOnPurpose() throws {
        let keys = try preferenceKeys()
        XCTAssertGreaterThan(keys.count, 40, "the parser found too few keys: has `PreferenceKey` moved?")
        let unclassified = keys.filter { !DevicePreferences.isClassified($0.value) }
        XCTAssertEqual(
            unclassified.map { "PreferenceKey.\($0.name) = \"\($0.value)\"" }, [],
            "A new `PreferenceKey` must be classified for \"Erase everything on this iPhone\": add it to "
            + "`DevicePreferences.erasedKeys` (erased: personal values and ordinary settings) or to `keptKeys` with a reason "
            + "(a sign-in or server tie, a first-run flag, a choice about what is sent). Unclassified keys are erased anyway.")
    }

    func testNoKeyIsBothErasedAndKept() {
        XCTAssertEqual(DevicePreferences.erasedKeys.intersection(DevicePreferences.keptKeys.keys), [])
    }

    func testTheClassifiedErasedKeysAreStillPreferenceKeys() throws {
        let present = Set(try preferenceKeys().map(\.value))
        let stale = DevicePreferences.erasedKeys.subtracting(present)
        XCTAssertEqual(stale, [], "`erasedKeys` lists keys that are no longer in `PreferenceKey`: remove them")
    }

    // MARK: Parsing `PreferenceKey`

    private struct NamedKey {
        let name: String
        let value: String
    }

    /// Keys whose value is another constant, not a literal.
    private func referenced(_ expression: String) -> String? {
        switch expression {
        case "TalkLaunchMode.preferenceKey": return TalkLaunchMode.preferenceKey
        case "LaunchPreferencesMigration.islandExpandsKey": return LaunchPreferencesMigration.islandExpandsKey
        case "LegalAcceptance.preferenceKey": return LegalAcceptance.preferenceKey
        default: return nil
        }
    }

    private func preferenceKeys() throws -> [NamedKey] {
        guard let text = AppSourceScan.text(of: "DoddyApp/App/RootView.swift") else { throw XCTSkip("RootView.swift not found") }
        guard let start = text.range(of: "enum PreferenceKey {"), let end = text.range(of: "\n}\n", range: start.upperBound..<text.endIndex) else {
            XCTFail("`enum PreferenceKey` not found in RootView.swift")
            return []
        }
        var found: [NamedKey] = []
        let pattern = try NSRegularExpression(pattern: #"^\s*static let (\w+) = (.+?)\s*(?://.*)?$"#)
        for line in text[start.upperBound..<end.lowerBound].split(separator: "\n") {
            let line = String(line)
            guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let name = Range(match.range(at: 1), in: line), let rhs = Range(match.range(at: 2), in: line) else { continue }
            let expression = String(line[rhs])
            if expression.hasPrefix("\""), expression.hasSuffix("\""), expression.count >= 2 {
                found.append(NamedKey(name: String(line[name]), value: String(expression.dropFirst().dropLast())))
            } else if let value = referenced(expression) {
                found.append(NamedKey(name: String(line[name]), value: value))
            } else if expression == "true" || expression == "false" {
                continue // a default value (`assistantConsentDefault`), not a key
            } else {
                XCTFail("PreferenceKey.\(line[name]) = \(expression): teach `preferenceKeys()` about this constant")
            }
        }
        return found.filter { !$0.name.hasSuffix("Default") }
    }
}
