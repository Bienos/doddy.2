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
        // savedCount is a number of notes the user tapped Save on, never their text.
        XCTAssertEqual(Set(json.keys), ["status", "isMuted", "savedCount"])
        XCTAssertEqual(json["status"] as? String, "needsConfirmation")
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
