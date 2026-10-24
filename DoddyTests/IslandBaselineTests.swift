import ActivityKit
import AppIntents
import XCTest
@testable import Doddy

final class IslandBaselineTests: XCTestCase {
    func testConfirmationStatusAndPayloadDoNotExposeMemoryText() throws {
        let state = DoddyVoiceAttributes.ContentState(status: .needsConfirmation, isMuted: true)
        XCTAssertEqual(state.title, "Confirm in Doddy")
        XCTAssertEqual(state.symbolName, "hand.tap.fill")
        let data = try JSONEncoder().encode(state)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // savedCount is a number of notes the user tapped Save on, never their text; islandStyle is
        // the look picked in Settings (ADR-239). Nil fields (moment, greeting, …) aren't written.
        XCTAssertEqual(Set(json.keys), ["status", "isMuted", "savedCount", "islandStyle"])
        XCTAssertEqual(json["status"] as? String, "needsConfirmation")
    }

    /// In-conversation moments (ADR-240) carry only their kind, counts and language codes, so the
    /// lock screen never gets what a note, plan step or reminder says.
    func testMomentsCarryOnlyKindsCountsAndLanguageCodes() throws {
        let moments: [DoddyVoiceAttributes.ContentState.Moment] = [
            .noteWaiting, .noteSaved, .planWaiting(steps: 2), .planRunning(step: 1, of: 2),
            .reminderWaiting, .reminderAdding, .reminderSet, .translating(from: "en", to: "?", bothWays: true),
        ]
            + IslandAction.allCases.map { DoddyVoiceAttributes.ContentState.Moment.actionWaiting($0) }
            + IslandResult.allCases.map { DoddyVoiceAttributes.ContentState.Moment.resultReady($0) }
        for moment in moments {
            var state = DoddyVoiceAttributes.ContentState(status: .listening, isMuted: false)
            state.moment = moment
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["status", "isMuted", "savedCount", "islandStyle", "moment"], "\(moment)")
            // Every string anywhere in the payload is a fixed value: the status, the style, or a
            // language code of at most two letters ("?" while unknown).
            // ADR-608: a card's or a result's kind is one fixed word too.
            let fixed = Set(["listening", state.islandStyle.rawValue])
                .union(IslandAction.allCases.map(\.rawValue)).union(IslandResult.allCases.map(\.rawValue))
            for text in strings(in: json) where !fixed.contains(text) {
                XCTAssertLessThanOrEqual(text.count, 2, "\(moment) carries text: \(text)")
            }
        }
    }

    /// The "Hey Doddy" greeting (ADR-254) is the only free text the payload can carry, and only when set.
    func testGreetingIsWrittenOnlyWhenSet() throws {
        var state = DoddyVoiceAttributes.ContentState(status: .listening, isMuted: false)
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertNil(plain["greeting"])
        state.greeting = "Hey Pat, what's up?"
        let greeted = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        XCTAssertEqual(greeted["greeting"] as? String, "Hey Pat, what's up?")
        XCTAssertEqual(Set(greeted.keys), ["status", "isMuted", "savedCount", "islandStyle", "greeting"])
    }

    private func strings(in value: Any) -> [String] {
        switch value {
        case let text as String: return [text]
        case let dictionary as [String: Any]: return dictionary.values.flatMap { strings(in: $0) }
        case let array as [Any]: return array.flatMap { strings(in: $0) }
        default: return []
        }
    }

    @MainActor
    func testRealActivityStartUpdateAndEnd() async throws {
        try requireActivities()
        await clearActivities()
        let island = VoiceLiveActivity()
        defer { island.end() }
        island.show(.init(status: .testFixture, isMuted: false), startedAt: .now)
        let started = await waitUntil { Activity<DoddyVoiceAttributes>.activities.count == 1 }
        XCTAssertTrue(started)
        let activity = try XCTUnwrap(Activity<DoddyVoiceAttributes>.activities.first)
        XCTAssertNotNil(activity.content.staleDate)
        XCTAssertLessThan(VoiceLiveActivity.heartbeatEvery, VoiceLiveActivity.staleAfter)
        island.show(.init(status: .testFixture, isMuted: true), startedAt: .now)
        let updated = await waitUntil { activity.content.state.isMuted }
        XCTAssertTrue(updated)
        island.end()
        let ended = await waitUntil { Activity<DoddyVoiceAttributes>.activities.isEmpty }
        XCTAssertTrue(ended)
    }

    /// ADR-577: a start without opening Doddy checks `isShowing` before it takes the microphone,
    /// and `expand()` (the alert update that opens the island up) keeps the state it shows.
    @MainActor
    func testIsShowingFollowsTheActivityAndExpandKeepsItsState() async throws {
        try requireActivities()
        await clearActivities()
        let island = VoiceLiveActivity()
        defer { island.end() }
        XCTAssertFalse(island.isShowing)
        island.expand()  // nothing to open up: no activity is started for it
        XCTAssertTrue(Activity<DoddyVoiceAttributes>.activities.isEmpty)
        let greeting = DoddyVoiceAttributes.ContentState(status: .speaking, isMuted: false, greeting: "Hey Pat, what's up?")
        island.show(greeting, startedAt: .now)
        XCTAssertTrue(island.isShowing)
        island.expand()
        await island.settle()
        let activity = try XCTUnwrap(Activity<DoddyVoiceAttributes>.activities.first)
        XCTAssertEqual(activity.content.state, greeting)
        island.end()
        XCTAssertFalse(island.isShowing)
        let ended = await waitUntil { Activity<DoddyVoiceAttributes>.activities.isEmpty }
        XCTAssertTrue(ended)
    }

    @MainActor
    func testMuteAndEndIntentsReachHandlersAndRemoveActivity() async throws {
        try requireActivities()
        await clearActivities()
        let island = VoiceLiveActivity()
        var muted = false
        var ended = false
        let actions = VoiceActivityActions.shared
        defer {
            actions.toggleMute = nil
            actions.endConversation = nil
            island.end()
        }
        actions.toggleMute = {
            muted.toggle()
            island.show(.init(status: .testFixture, isMuted: muted), startedAt: .now)
        }
        actions.endConversation = { ended = true; island.end() }
        island.show(.init(status: .testFixture, isMuted: false), startedAt: .now)
        _ = try await ToggleDoddyMuteIntent().perform()
        XCTAssertTrue(muted)
        _ = try await EndDoddyConversationIntent().perform()
        XCTAssertTrue(ended)
        let removed = await waitUntil { Activity<DoddyVoiceAttributes>.activities.isEmpty }
        XCTAssertTrue(removed)
    }

    @MainActor
    func testEndIntentDismissesOrphanWithoutConversationHandler() async throws {
        try requireActivities()
        await clearActivities()
        VoiceActivityActions.shared.endConversation = nil
        let activity = try Activity.request(
            attributes: DoddyVoiceAttributes(startedAt: .now),
            content: ActivityContent(state: .init(status: .testFixture, isMuted: false), staleDate: .now),
            pushType: nil)
        _ = try await EndDoddyConversationIntent().perform()
        let removed = await waitUntil { activity.activityState == .ended || activity.activityState == .dismissed }
        XCTAssertTrue(removed)
        XCTAssertTrue(Activity<DoddyVoiceAttributes>.activities.isEmpty)
    }

    @MainActor
    private func requireActivities() throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw XCTSkip("Live Activities are disabled on this simulator; no lifecycle proof claimed.")
        }
    }

    @MainActor
    private func clearActivities() async {
        for activity in Activity<DoddyVoiceAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}
