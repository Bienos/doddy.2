import DoddyCore
import Foundation

/// Which features this build shows (decision 2026-11-07-release-scope). A Release or TestFlight build
/// shows `ReleaseScope.shipping`, always, and never reads the switch. A Debug build shows every feature
/// until Settings › About › Advanced › "Show every feature" is turned off (decision
/// 2026-11-08-debug-shows-every-feature), so the owner sees the whole app when running from Xcode.
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
