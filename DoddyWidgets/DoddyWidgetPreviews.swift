import ActivityKit
import DoddyCore
import SwiftUI
import WidgetKit

// Xcode canvas previews of Doddy in the widgets and Live Activities (ADR-336). Made-up content
// only. In the canvas there is no App Group, so the snapshot widgets say "Open Doddy to set up
// widgets"; Talk to Doddy, "Doddy, resting" and every Live Activity show the art.

private typealias Voice = DoddyVoiceAttributes.ContentState

#Preview("Voice · Lock Screen", as: .content, using: DoddyVoiceAttributes(startedAt: .now)) {
    DoddyVoiceLiveActivity()
} contentStates: {
    Voice(status: .listening, isMuted: false, islandStyle: .wholeDoddy)
    Voice(status: .thinking, isMuted: false, islandStyle: .wholeDoddy)
    Voice(status: .ended, isMuted: false, savedCount: 1, islandStyle: .wholeDoddy)
}

#Preview("Voice · island", as: .dynamicIsland(.expanded), using: DoddyVoiceAttributes(startedAt: .now)) {
    DoddyVoiceLiveActivity()
} contentStates: {
    Voice(status: .listening, isMuted: false, islandStyle: .wholeDoddy, greeting: "Hey Pat, what's up?")
    Voice(status: .listening, isMuted: false, islandStyle: .wholeDoddy)
    Voice(status: .speaking, isMuted: false, islandStyle: .wholeDoddy)
    Voice(status: .listening, isMuted: true, islandStyle: .wholeDoddy)
    Voice(status: .wakeListening, isMuted: false, islandStyle: .wholeDoddy)
}

#Preview("Voice · compact", as: .dynamicIsland(.compact), using: DoddyVoiceAttributes(startedAt: .now)) {
    DoddyVoiceLiveActivity()
} contentStates: {
    Voice(status: .listening, isMuted: false, islandStyle: .wholeDoddy)
}

#Preview("Read aloud · island", as: .dynamicIsland(.expanded),
         using: DoddyToolAttributes(kind: .readAloud, startedAt: .now, duration: 0)) {
    DoddyToolLiveActivity()
} contentStates: {
    DoddyToolAttributes.ContentState(isPaused: false, islandStyle: .wholeDoddy)
    DoddyToolAttributes.ContentState(isPaused: true, islandStyle: .wholeDoddy)
}

#Preview("Focus · island", as: .dynamicIsland(.expanded),
         using: DoddyToolAttributes(kind: .focus, startedAt: .now, duration: 1500)) {
    DoddyToolLiveActivity()
} contentStates: {
    DoddyToolAttributes.ContentState(isPaused: false, endsAt: .now.addingTimeInterval(900), islandStyle: .wholeDoddy)
}

#Preview("Stopwatch · island", as: .dynamicIsland(.expanded),
         using: DoddyToolAttributes(kind: .stopwatch, startedAt: .now, duration: 0)) {
    DoddyToolLiveActivity()
} contentStates: {
    DoddyToolAttributes.ContentState(isPaused: false, label: "Bieg", islandStyle: .wholeDoddy, countsFrom: .now.addingTimeInterval(-727))
    DoddyToolAttributes.ContentState(isPaused: true, islandStyle: .wholeDoddy, elapsed: 727)
}

#Preview("Breathing · island", as: .dynamicIsland(.expanded),
         using: DoddyToolAttributes(kind: .breathing, startedAt: .now, duration: 120)) {
    DoddyToolLiveActivity()
} contentStates: {
    DoddyToolAttributes.ContentState(isPaused: false, endsAt: .now.addingTimeInterval(90), islandStyle: .wholeDoddy)
}

#Preview("Shopping · Lock Screen", as: .content, using: ShoppingActivityAttributes(listID: UUID())) {
    ShoppingLiveActivity()
} contentStates: {
    ShoppingModeState(listName: "Shopping", openCount: 3, doneCount: 1, items: [
        .init(id: UUID(), text: "Oat milk", isDone: false),
        .init(id: UUID(), text: "Eggs", isDone: false),
        .init(id: UUID(), text: "Bread", isDone: false),
        .init(id: UUID(), text: "Tomatoes", isDone: true)
    ])
}

#Preview("Talk to Doddy", as: .systemSmall) {
    TalkToDoddyWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview("Talk to Doddy · Lock Screen", as: .accessoryCircular) {
    TalkToDoddyWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}

#Preview("Doddy, resting", as: .systemSmall) {
    DoddyRestWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
