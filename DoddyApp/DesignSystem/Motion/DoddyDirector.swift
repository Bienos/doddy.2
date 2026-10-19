import DoddyCore
import Foundation
import Observation

/// The one persistent Doddy's director (motion v2, docs/design/MOTION_V2_PLAN.md section 4,
/// option B). MV2: the registry of the surfaces he can stand on. Each surface view reports its
/// window frame here (`.motionSurface(_:)`) and offers a slot on its top edge where he will be
/// drawn while he stands on it. Doddy doesn't move yet.
///
/// UI-free on purpose (Foundation, Observation, DoddyCore), so `scripts/typecheck_app_logic.sh`
/// compiles it on Linux. Frames change on every scroll frame, so they are not observed: no view
/// redraws because a surface moved.
@MainActor
@Observable
final class DoddyDirector {
    static let shared = DoddyDirector()

    /// The motion world is on: an iPhone-sized layout (Q13, iPad keeps today's pictures) with
    /// Doddy's pictures shown. Off, the screens keep no room for him (no stage line, no card
    /// gutter, no list inset), so "Hide Doddy's pictures" leaves no gap.
    var isActive = false

    /// The last window frame each surface reported (kept while it is off screen, so a surface
    /// coming back with an unchanged frame still has one).
    @ObservationIgnored private(set) var frames: [MotionSurfaceID: MotionRect] = [:]
    /// How many views report each surface right now (a list can briefly have two cards claim the
    /// same rule while it reorders). On screen: more than zero.
    @ObservationIgnored private var mountCount: [MotionSurfaceID: Int] = [:]
    /// Frames the layout around a surface needs: Ask's Send button ("send"), the undo bar's Undo
    /// ("undo"), each tab button ("tab.home", "tab.memories", "tab.settings").
    @ObservationIgnored private(set) var marks: [String: MotionRect] = [:]
    /// The Memories cards in the order shown: `rule(i)` is the card of `ruleIDs[i]`.
    @ObservationIgnored private(set) var ruleIDs: [UUID] = []

    init() {}

    // MARK: Reports from the screens

    func surfaceMoved(_ id: MotionSurfaceID, to frame: MotionRect) {
        frames[id] = frame
    }

    func surfaceAppeared(_ id: MotionSurfaceID) {
        mountCount[id, default: 0] += 1
    }

    func surfaceGone(_ id: MotionSurfaceID) {
        let n = (mountCount[id] ?? 0) - 1
        mountCount[id] = n > 0 ? n : nil
    }

    func markMoved(_ name: String, to frame: MotionRect) {
        marks[name] = frame
    }

    func markGone(_ name: String) {
        marks[name] = nil
    }

    /// The Memories list shows these notes, in this order. Rules past the end are forgotten.
    func cardsShown(_ ids: [UUID]) {
        ruleIDs = ids
        for id in Array(frames.keys) {
            if let i = id.ruleIndex, i >= ids.count { frames[id] = nil }
        }
    }

    // MARK: Reading

    func isMounted(_ id: MotionSurfaceID) -> Bool { mountCount[id] != nil }

    /// The surface's frame if its view is on screen now.
    func frame(of id: MotionSurfaceID) -> MotionRect? {
        isMounted(id) ? frames[id] : nil
    }
}
