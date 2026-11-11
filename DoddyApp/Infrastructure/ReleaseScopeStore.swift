import DoddyCore
import Foundation

/// Which features this build shows. Every build shows everything since 10 Nov 2026 (decision
/// 2026-11-10-no-beta-scope: `ReleaseScope.shipping` is `.everything`). A Debug build still reads the
/// `previewEverythingKey` preference (the Advanced toggle is gone; a launch argument still works), and
/// the answer is the same either way.
/// Read at each use, not cached: the switch takes effect on the next screen, and the next tool call,
/// without a restart.
enum ReleaseScopeStore {
    static var current: ReleaseScope {
        #if DEBUG
        let defaults = UserDefaults.standard
        let key = ReleaseScope.previewEverythingKey
        // `bool(forKey:)` also reads a launch argument's "YES"/"NO"; nil only when never set.
        let setting: Bool? = defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
        return ReleaseScope.debug(showEverything: setting)
        #else
        // Owner, 10 Nov 2026: "forget the beta as if it didn't exist". Every build shows everything.
        return .shipping
        #endif
    }

    /// True when the toggle can exist at all (Debug builds only); the Advanced page shows it then.
    static var canPreviewEverything: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
