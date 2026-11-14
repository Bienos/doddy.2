import Foundation
import XCTest
@testable import DoddyCore

/// The list of places the app keeps something about a person on this iPhone (`DeviceStoreID`, with the doc
/// `docs/architecture/DEVICE_DATA_STORES.md`), and the rule that nothing is left out of "Erase everything on this
/// iPhone". Like `FileProtectionInventoryTests`, these read the sources: a file that starts keeping something in
/// Application Support, Caches, the App Group folder, the Keychain, iCloud or the search index must be registered
/// here with the stores that erase it, or the build's tests fail.
///
/// Platforms: iPhone (the app, widgets, share and screen extensions). The Watch and Mac apps are paused.
final class DeviceStoreInventoryTests: XCTestCase {
    /// What a file has to mention to count as keeping something on this iPhone: Application Support, Caches, Documents or
    /// Library, the App Group folder, the Keychain, UserDefaults suites, iCloud, the search index, and the folder next to
    /// the notes database that photos, voice memos and recordings are put in. Temporary files are not listed: the plan
    /// empties the whole temporary folder, so none can be forgotten.
    static let locationMarkers: [String] = [
        ".applicationSupportDirectory", ".cachesDirectory", ".documentDirectory", ".libraryDirectory",
        "containerURL(forSecurityApplicationGroupIdentifier", "kSecClass", "UserDefaults(suiteName",
        "NSUbiquitousKeyValueStore", "CKContainer(", "CSSearchableIndex(", "static func beside(database",
    ]

    // MARK: Nothing new is kept without being registered

    func testEveryFileThatKeepsSomethingOnTheIPhoneIsRegistered() throws {
        let registered = Set(DeviceStoreInventory.sources.keys).union(DeviceStoreInventory.reviewedNotStores.keys)
        let unregistered = try AppSourceScan.swiftFiles()
            .filter { file in !file.path.hasPrefix("Packages/DoddyCore/Sources/DoddyCore/DeviceErasure/") }
            .filter { file in Self.locationMarkers.contains { file.text.contains($0) } }
            .map(\.path)
            .filter { !registered.contains($0) }
        XCTAssertEqual(
            unregistered, [],
            "These files keep something on the iPhone (Application Support, Caches, the App Group folder, the Keychain, "
            + "iCloud or Spotlight) but are not in `DeviceStoreInventory`. Add them with the `DeviceStoreID` that erases what "
            + "they keep (add a store if none fits, and its step in `EraseThisIPhone.swift`), or into `reviewedNotStores` "
            + "with the reason they keep nothing of the person's.")
    }

    func testEveryRegisteredFileStillExistsAndStillKeepsSomething() throws {
        let files = try AppSourceScan.swiftFiles()
        for path in Set(DeviceStoreInventory.sources.keys).union(DeviceStoreInventory.reviewedNotStores.keys) {
            guard let file = files.first(where: { $0.path == path }) else {
                XCTFail("\(path) is registered but no longer exists: remove its entry")
                continue
            }
            XCTAssertTrue(Self.locationMarkers.contains { file.text.contains($0) },
                          "\(path) no longer keeps anything on the iPhone: remove its entry")
        }
        for (path, reason) in DeviceStoreInventory.reviewedNotStores {
            XCTAssertGreaterThan(reason.count, 30, "\(path) needs a real reason")
            XCTAssertNil(DeviceStoreInventory.sources[path], "\(path) is both a store and not a store")
        }
    }

    func testEveryStoreThatLivesInAFileHasAFileThatKeepsIt() {
        let covered = Set(DeviceStoreInventory.sources.values.flatMap { $0 })
        for id in DeviceStoreID.allCases where !DeviceStoreInventory.notFoundBySourceScan.contains(id) {
            XCTAssertTrue(covered.contains(id), "\(id) has no registered source file: list it in `sources`, or in `notFoundBySourceScan` with a reason")
        }
        for (id, reason) in DeviceStoreInventory.notFoundBySourceScanReasons {
            XCTAssertGreaterThan(reason.count, 20, "\(id) needs a real reason")
        }
        XCTAssertEqual(Set(DeviceStoreInventory.notFoundBySourceScanReasons.keys), DeviceStoreInventory.notFoundBySourceScan)
    }

    // MARK: The plan covers every store

    /// The app's plan is a `switch` over every `DeviceStoreID` (so a new case is a compile error there); this
    /// also checks the file names every store, so it can't be a `default:`.
    func testTheAppsPlanHasAStepForEveryStore() throws {
        guard let plan = AppSourceScan.text(of: "DoddyApp/Features/Privacy/EraseThisIPhone.swift") else {
            return XCTFail("DoddyApp/Features/Privacy/EraseThisIPhone.swift (the app's plan) is missing")
        }
        for id in DeviceStoreID.allCases {
            XCTAssertTrue(plan.contains("case .\(id.rawValue)"), "the plan in EraseThisIPhone.swift has no `case .\(id.rawValue)`")
        }
        XCTAssertFalse(plan.contains("default:"), "the plan's switch must list every store, not use `default:`")
    }

    func testTheDocNamesEveryStore() throws {
        guard let doc = AppSourceScan.text(of: "docs/architecture/DEVICE_DATA_STORES.md") else {
            return XCTFail("docs/architecture/DEVICE_DATA_STORES.md is missing")
        }
        for id in DeviceStoreID.allCases {
            XCTAssertTrue(doc.contains("`\(id.rawValue)`"), "the doc doesn't mention the store `\(id.rawValue)`")
        }
        for service in DeviceKeychain.services {
            XCTAssertTrue(doc.contains(service.name), "the doc doesn't mention the Keychain service \(service.name)")
        }
    }

    func testEveryStoreIsRequiredByTheScopeThatErasesIt() {
        XCTAssertEqual(DeviceErasureScope.afterAccountDeleted.requiredStores, Set(DeviceStoreID.allCases))
        XCTAssertEqual(
            DeviceErasureScope.keepSignIn.requiredStores, Set(DeviceStoreID.allCases).subtracting([.keychainServerHandles]),
            "keeping the sign-in is the only thing the default scope leaves out")
    }

    // MARK: Backup rules agree with the code

    /// Excluded stores really set the flag in each file that keeps them, and included ones don't, so a rule can't
    /// change by accident in either direction.
    func testBackupRulesMatchWhatTheSourcesDo() throws {
        let files = try AppSourceScan.swiftFiles()
        let marker = "isExcludedFromBackup = true"
        for (path, stores) in DeviceStoreInventory.sources {
            guard let file = files.first(where: { $0.path == path }) else { continue }
            let sets = file.text.contains(marker)
            let rules = Set(stores.map(\.backup))
            if rules == [.excluded] {
                XCTAssertTrue(sets, "\(path) keeps \(stores) which are kept out of backups, but never sets `isExcludedFromBackup`")
            } else if rules == [.included] {
                XCTAssertFalse(sets, "\(path) keeps \(stores) which are in backups, but sets `isExcludedFromBackup`: change the store's rule")
            }
        }
    }

    func testKeychainItemsStayOnThisDevice() throws {
        // The files that add Keychain items; the plan itself (DeviceErasure/) and the eraser only delete.
        let files = try AppSourceScan.swiftFiles().filter { $0.text.contains("SecItemAdd") }
        XCTAssertGreaterThanOrEqual(files.count, 6)
        for file in files {
            XCTAssertTrue(file.text.contains("ThisDeviceOnly"), "\(file.path) keeps Keychain items that could be backed up or synced")
            XCTAssertFalse(file.text.contains("kSecAttrSynchronizable"), "\(file.path) syncs Keychain items to iCloud")
        }
    }

    func testTheRuleForBackupsIsWrittenDownInOnePlace() {
        // Included: what the person saved to keep. Excluded: what Doddy fetched, recorded or drafted for its own work.
        let included = DeviceStoreID.allCases.filter { $0.backup == .included }
        XCTAssertEqual(Set(included), [
            .notesAndLists, .learnedFacts, .profile, .callCases, .errands, .messagesThread, .recordings,
            .notePhotoFiles, .noteAudioFiles, .madeFiles, .preferences,
        ])
        let excluded = DeviceStoreID.allCases.filter { $0.backup == .excluded }
        XCTAssertEqual(Set(excluded), [
            .trainingLog, .trainingPlan, .recordingFiles, .conversationTranscripts, .activityList, .unfinishedNotes,
            .invoiceDraft, .trips,
        ])
    }

    // MARK: Keychain

    func testEveryKeychainServiceInTheSourcesIsClassified() throws {
        let known = Set(DeviceKeychain.services.map(\.name))
        var used = Set<String>()
        let pattern = try NSRegularExpression(pattern: #""(com\.bienos\.doddy2\.[A-Za-z0-9\-]+)""#)
        for file in try AppSourceScan.swiftFiles() where file.text.contains("kSecClass") && !file.path.contains("/DeviceErasure/") {
            for match in pattern.matches(in: file.text, range: NSRange(file.text.startIndex..., in: file.text)) {
                if let range = Range(match.range(at: 1), in: file.text) { used.insert(String(file.text[range])) }
            }
        }
        XCTAssertGreaterThanOrEqual(used.count, 8)
        XCTAssertEqual(used.subtracting(known), [], "A Keychain service the app uses is not in `DeviceKeychain.services`: say whether it is erased or kept")
        XCTAssertEqual(known.subtracting(used), [], "`DeviceKeychain.services` lists a service the app no longer uses: remove it")
    }

    func testKeychainRulesByScope() {
        // Keys the person pasted in, and retired items, always go.
        XCTAssertTrue(DeviceKeychain.shouldErase(service: "com.bienos.doddy2.account-keys", scope: .keepSignIn))
        XCTAssertTrue(DeviceKeychain.shouldErase(service: "com.bienos.doddy2.gateway", scope: .keepSignIn))
        XCTAssertTrue(DeviceKeychain.shouldErase(service: "com.bienos.doddy2.voice-access-code", scope: .keepSignIn))
        // The sign-in and what ties this iPhone to its servers stay, unless the account was deleted.
        for name in ["doddy-account", "voice-session", "connected-apps", "server", "device"] {
            XCTAssertFalse(DeviceKeychain.shouldErase(service: "com.bienos.doddy2.\(name)", scope: .keepSignIn), name)
            XCTAssertTrue(DeviceKeychain.shouldErase(service: "com.bienos.doddy2.\(name)", scope: .afterAccountDeleted), name)
        }
        // Anything the table doesn't know is erased, so a new service can't be forgotten.
        XCTAssertTrue(DeviceKeychain.shouldErase(service: "com.bienos.doddy2.some-new-thing", scope: .keepSignIn))
    }

    /// Which of the two Keychain stores a service belongs to, so each is read back on its own.
    func testEachKeychainServiceBelongsToOneOfTheTwoStores() {
        for service in DeviceKeychain.services {
            switch service.role {
            case .personalKey, .retired:
                XCTAssertEqual(DeviceKeychain.store(for: service.name), .keychainPersonalKeys, service.name)
            case .signIn, .serverTie:
                XCTAssertEqual(DeviceKeychain.store(for: service.name), .keychainServerHandles, service.name)
            }
        }
        XCTAssertEqual(DeviceKeychain.store(for: "com.bienos.doddy2.some-new-thing"), .keychainPersonalKeys,
                       "an unknown service is treated as a personal key: always erased")
    }

    func testServicesToKeepAreListedForTheResultLine() {
        XCTAssertEqual(
            Set(DeviceKeychain.keptServices(scope: .keepSignIn)),
            ["com.bienos.doddy2.doddy-account", "com.bienos.doddy2.voice-session", "com.bienos.doddy2.connected-apps",
             "com.bienos.doddy2.server", "com.bienos.doddy2.device"])
        XCTAssertEqual(DeviceKeychain.keptServices(scope: .afterAccountDeleted), [])
    }
}
