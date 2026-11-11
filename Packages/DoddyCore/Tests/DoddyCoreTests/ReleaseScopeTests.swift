import Foundation
import XCTest
@testable import DoddyCore

/// The release scope (decision 2026-11-07-release-scope, reversed by 2026-11-10-no-beta-scope: every build shows everything):
/// one list that can hide a feature's every way in, and the tools the live agent would lose with it. Checked against `voice-agent/tools.json`, so a tool that belongs to no
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

    func testShippingShowsEverything() {
        // Owner, 10 Nov 2026: "forget the beta as if it didn't exist". `shipping` hides nothing.
        let scope = ReleaseScope.shipping
        XCTAssertEqual(scope, .everything)
        XCTAssertEqual(scope.hidden, [])
        for feature in Feature.allCases { XCTAssertTrue(scope.shows(feature), "\(feature)") }
        for connection in VoiceConnection.allCases { XCTAssertTrue(scope.shows(connection), "\(connection)") }
        for tool in try! specNames() { XCTAssertNil(scope.hiddenFeature(forTool: tool), "\(tool) must run in the shipping scope") }
        // The ones the beta used to hide, named so a regression shows which.
        XCTAssertNil(scope.hiddenFeature(forTool: VoiceToolName.handOverErrand))
        XCTAssertNil(scope.hiddenFeature(forTool: VoiceToolName.makePresentation))
        XCTAssertNil(scope.hiddenFeature(forTool: VoiceToolName.proposePlan))
        XCTAssertNil(scope.hiddenFeature(forTool: VoiceToolName.makeSomething))
        XCTAssertNil(scope.hiddenFeature(forTool: PaymentToolName.payForPage))
        XCTAssertNil(scope.hiddenFeature(forTool: VoiceToolName.callPlaces))
        XCTAssertNil(scope.hiddenFeature(forTool: CloudToolName.draftEmail))
    }

    func testAScopeThatHidesFeaturesStillWorks() {
        // The machinery is kept for a future decision to hide something again.
        let scope = ReleaseScope(hidden: [.errands, .homeKit])
        XCTAssertEqual(scope.hiddenFeature(forTool: VoiceToolName.handOverErrand), .errands)
        XCTAssertNil(scope.hiddenFeature(forTool: VoiceToolName.setTimer))
        XCTAssertFalse(scope.shows(VoiceConnection.home))
        XCTAssertTrue(scope.shows(VoiceConnection.calendar))
    }

    func testEveryFeaturesSwitchIsTheSwitchItsToolsNeed() {
        // A feature's switch is the switch its tools need, so the gate and the screen agree.
        for feature in Feature.allCases {
            guard let connection = feature.connection else { continue }
            for tool in feature.tools { XCTAssertEqual(VoiceConnection.serving(tool), connection, tool) }
        }
    }

    func testShippingToolsAreAllInTheSpec() throws {
        // Since 10 Nov 2026 the agent keeps every tool in the spec: nothing is taken off it.
        XCTAssertEqual(ReleaseScope.shipping.hiddenTools, [])
        let spec = try specNames()
        let shownFeatureTools = Set(Feature.allCases.filter { ReleaseScope.shipping.shows($0) }.flatMap(\.tools))
        XCTAssertEqual(spec, ReleaseScope.coreTools.union(shownFeatureTools), "every tool in tools.json is reachable")
    }

    func testHiddenToolsOfAScopeAreSortedAndInTheSpec() throws {
        let hidden = ReleaseScope(hidden: Set(Feature.allCases)).hiddenTools
        XCTAssertEqual(hidden, hidden.sorted())
        XCTAssertEqual(Set(hidden).count, hidden.count)
        XCTAssertEqual(Set(hidden).subtracting(try specNames()), [], "a hidden tool the agent doesn't have")
        let kept = try specNames().subtracting(hidden)
        XCTAssertEqual(kept, ReleaseScope.coreTools)
    }

    // MARK: Languages

    func testShippingOffersEveryLanguage() {
        let scope = ReleaseScope.shipping
        XCTAssertEqual(scope.languages, AppLanguage.allCases)
        XCTAssertEqual(scope.languageChoices(current: .german), AppLanguage.allCases)
        // A scope that isn't `everything` offers the two a native speaker has read, plus the current choice.
        let other = ReleaseScope(hidden: [.errands])
        XCTAssertEqual(other.languages, [.english, .polish, .followPhone])
        XCTAssertEqual(other.languageChoices(current: .german), [.english, .german, .polish, .followPhone])
    }

    // MARK: The capability catalog

    func testShippingLeavesTheCapabilitiesAsTheyAre() {
        let catalog = CapabilityCatalog.shipping(serverConfigured: true)
        XCTAssertEqual(catalog.hiding(ReleaseScope.shipping).statuses, catalog.statuses)
    }

    func testHidingMarksTheFeaturesCapabilitiesLimited() {
        let catalog = CapabilityCatalog.shipping(serverConfigured: true)
        XCTAssertEqual(catalog.status(of: .textAssistant), .available)
        XCTAssertEqual(catalog.status(of: .pushUpdates), .available)
        let hidden = catalog.hiding(ReleaseScope(hidden: [.updates, .dailyNews, .sharedLists]))
        XCTAssertEqual(hidden.status(of: .textAssistant), .available)
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

    func testDebugBuildShowsEverythingUntilTheSwitchIsTurnedOff() {
        // Decision 2026-11-08-debug-shows-every-feature: a fresh Debug install shows every feature.
        XCTAssertEqual(ReleaseScope.debug(showEverything: nil), .everything)
        XCTAssertEqual(ReleaseScope.debug(showEverything: true), .everything)
        // `shipping` is `everything` since 10 Nov 2026 (decision 2026-11-10-no-beta-scope), so the switch changes nothing.
        XCTAssertEqual(ReleaseScope.debug(showEverything: false), .shipping)
        XCTAssertEqual(ReleaseScope.debug(showEverything: false), .everything)
        XCTAssertTrue(ReleaseScope.debugShowsEverythingByDefault)
    }

    // MARK: Quick actions

    func testParkingQuickActionGoesWithTheFeature() {
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: true, scope: .everything).last, .parking)
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: true, scope: .shipping).last, .parking, "shown since 10 Nov 2026")
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: true, scope: ReleaseScope(hidden: [.parking])), [.talk, .newNote, .find])
        XCTAssertEqual(QuickAction.shown(hasParkingSpot: false, scope: .everything), [.talk, .newNote, .find])
    }
}
