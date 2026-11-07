import Foundation
import XCTest
@testable import DoddyCore

/// The release scope (decision 2026-11-07-release-scope): one list that hides a feature's every way in, and the tools the
/// live agent loses with it. Checked against `voice-agent/tools.json`, so a tool that belongs to no
/// feature and isn't core fails here before it can slip into a build unplaced.
final class ReleaseScopeTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func specNames() throws -> Set<String> {
        Set(try RealtimeToolCatalog.decode(Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/tools.json"))).map(\.name))
    }

    // MARK: Every tool is placed once

    func testEveryToolIsCoreOrBelongsToExactlyOneFeature() throws {
        var owners: [String: [Feature]] = [:]
        for feature in Feature.allCases {
            for tool in feature.tools { owners[tool, default: []].append(feature) }
        }
        for (tool, features) in owners {
            XCTAssertEqual(features.count, 1, "\(tool) belongs to \(features)")
            XCTAssertFalse(ReleaseScope.coreTools.contains(tool), "\(tool) is core and \(features)")
        }
        let placed = Set(owners.keys).union(ReleaseScope.coreTools)
        let spec = try specNames()
        XCTAssertEqual(spec.subtracting(placed), [], "in tools.json, in no feature and not core: place it")
        XCTAssertEqual(placed.subtracting(spec), [], "placed, but not in tools.json")
    }

    func testCoreToolsAreTheProductItself() {
        // Notes, lists, Apple Calendar and Reminders, Contacts, timers, the stopwatch, sums, a map or a
        // shortcut, the gap note, and the public lookups ElevenLabs runs. Nothing that needs Doddy's
        // servers or an account is core.
        for tool in ReleaseScope.coreTools {
            XCTAssertFalse(CloudToolName.all.contains(tool), "\(tool) needs the server: not core")
        }
        XCTAssertTrue(ReleaseScope.coreTools.isSuperset(of: ToolCatalog.webLookups))
        XCTAssertTrue(ReleaseScope.coreTools.contains(VoiceToolName.saveMemory))
        XCTAssertTrue(ReleaseScope.coreTools.contains(VoiceToolName.setTimer))
    }

    // MARK: The scopes

    func testEverythingHidesNothing() {
        let scope = ReleaseScope.everything
        for feature in Feature.allCases { XCTAssertTrue(scope.shows(feature), "\(feature)") }
        for connection in VoiceConnection.allCases { XCTAssertTrue(scope.shows(connection), "\(connection)") }
        XCTAssertEqual(scope.hiddenTools, [])
        XCTAssertEqual(scope.languages, AppLanguage.allCases)
        XCTAssertNil(scope.hiddenFeature(forTool: VoiceToolName.findDeals))
    }

    func testShippingKeepsTheProductAndHidesTheRest() {
        let scope = ReleaseScope.shipping
        // Shown: what the beta promises (V1_SCOPE.md).
        for feature in [Feature.messages, .photosAndCamera] {
            XCTAssertTrue(scope.shows(feature), "\(feature)")
        }
        for tool in ReleaseScope.coreTools {
            XCTAssertNil(scope.hiddenFeature(forTool: tool), "\(tool) is core and must run")
        }
        // Hidden: every server feature, every vendor, every permission the beta doesn't ask for.
        for feature in [Feature.deals, .errands, .onlineAccounts, .phoneCalls, .callCases, .recordings, .homeKit,
                        .translator, .planCard, .voiceProviderPicker, .parking, .leaveBy, .placeReminders] {
            XCTAssertFalse(scope.shows(feature), "\(feature)")
        }
        for tool in CloudToolName.all {
            XCTAssertNotNil(scope.hiddenFeature(forTool: tool), "\(tool) runs on the server: hidden in the beta")
        }
        XCTAssertEqual(scope.hiddenFeature(forTool: VoiceToolName.findDeals), .deals)
        XCTAssertEqual(scope.hiddenFeature(forTool: VoiceToolName.handOverErrand), .errands)
        XCTAssertEqual(scope.hiddenFeature(forTool: VoiceToolName.startTranslator), .translator)
        XCTAssertEqual(scope.hiddenFeature(forTool: VoiceToolName.proposePlan), .planCard)
    }

    func testShippingConnectionsFollowTheirFeature() {
        let scope = ReleaseScope.shipping
        // Each hidden feature with a switch takes its switch with it; the product's switches stay.
        XCTAssertFalse(scope.shows(VoiceConnection.home))
        XCTAssertFalse(scope.shows(VoiceConnection.steps))
        XCTAssertFalse(scope.shows(VoiceConnection.presentations))
        for connection in [VoiceConnection.calendar, .reminders, .contacts, .timers, .maps, .shortcuts, .messages, .photos, .camera] {
            XCTAssertTrue(scope.shows(connection), "\(connection)")
        }
        // A feature's switch is the switch its tools need, so the gate and the screen agree.
        for feature in Feature.allCases {
            guard let connection = feature.connection else { continue }
            for tool in feature.tools { XCTAssertEqual(VoiceConnection.serving(tool), connection, tool) }
        }
    }

    func testHiddenToolsAreSortedAndInTheSpec() throws {
        let hidden = ReleaseScope.shipping.hiddenTools
        XCTAssertEqual(hidden, hidden.sorted())
        XCTAssertEqual(Set(hidden).count, hidden.count)
        XCTAssertEqual(Set(hidden).subtracting(try specNames()), [], "a hidden tool the agent doesn't have")
        // The agent keeps exactly the core tools and the shown features' tools.
        let kept = try specNames().subtracting(hidden)
        let shownFeatureTools = Set(Feature.allCases.filter { ReleaseScope.shipping.shows($0) }.flatMap(\.tools))
        XCTAssertEqual(kept, ReleaseScope.coreTools.union(shownFeatureTools))
    }

    // MARK: Languages

    func testShippingOffersPolishEnglishAndTheIphonesLanguage() {
        let scope = ReleaseScope.shipping
        XCTAssertEqual(scope.languages, [.english, .polish, .followPhone])
        XCTAssertEqual(scope.languageChoices(current: .polish), [.english, .polish, .followPhone])
        // A choice from an older build stays visible, in the list's order, so it can be changed.
        XCTAssertEqual(scope.languageChoices(current: .german), [.english, .german, .polish, .followPhone])
        XCTAssertEqual(ReleaseScope.everything.languageChoices(current: .german), AppLanguage.allCases)
    }

    // MARK: The capability catalog

    func testHidingMarksTheFeaturesCapabilitiesLimited() {
        let catalog = CapabilityCatalog.shipping(serverConfigured: true)
        XCTAssertEqual(catalog.status(of: .textAssistant), .available)
        XCTAssertEqual(catalog.status(of: .pushUpdates), .available)
        let hidden = catalog.hiding(ReleaseScope.shipping)
        // Messages is shown in the beta: unchanged.
        XCTAssertEqual(hidden.status(of: .textAssistant), .available)
        // Updates, news and shared lists are hidden: limited, with the note.
        XCTAssertEqual(hidden.status(of: .pushUpdates), .limited(CapabilityCatalog.notInThisVersion))
        XCTAssertEqual(hidden.status(of: .textUpdates), .limited(CapabilityCatalog.notInThisVersion))
        XCTAssertEqual(hidden.status(of: .newsDigests), .limited(CapabilityCatalog.notInThisVersion))
        // Shared lists were already "limited" (only lists sync): the catalog's own note stays.
        XCTAssertEqual(hidden.status(of: .cloudSync), catalog.status(of: .cloudSync))
        XCTAssertFalse(hidden.isAvailable(.cloudSync))
        // The product's capabilities don't change.
        XCTAssertEqual(hidden.status(of: .voiceInput), .available)
        XCTAssertEqual(hidden.status(of: .noteReminders), .available)
        // Already not available: left as it was, not reworded.
        XCTAssertEqual(hidden.status(of: .phoneCalls), catalog.status(of: .phoneCalls))
        XCTAssertEqual(catalog.hiding(.everything).statuses, catalog.statuses)
    }

    func testHidingMessagesDisablesTypedQuestions() {
        let scope = ReleaseScope(hidden: [.messages])
        let catalog = CapabilityCatalog.shipping(serverConfigured: true).hiding(scope)
        XCTAssertFalse(catalog.isAvailable(.textAssistant))
    }

    // MARK: The Debug preview

    func testPreviewKeyIsTheOneTheUITestsPass() {
        // `DoddyUITests/UITestLaunch.swift` passes this key as a literal (the UI test target doesn't
        // link DoddyCore). Change both together, or the UI tests stop seeing hidden screens.
        XCTAssertEqual(ReleaseScope.previewEverythingKey, "releaseScope.previewEverything")
    }

    // MARK: Quick actions

    func testParkingQuickActionGoesWithTheFeature() {
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: true, scope: .everything).last, .parking)
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: true, scope: .shipping), [.talk, .newNote, .find])
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: false, scope: .everything), [.talk, .newNote, .find])
    }
}
