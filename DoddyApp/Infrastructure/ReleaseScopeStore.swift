import DoddyCore
import Foundation

/// Which features this build shows (ADR-732): `ReleaseScope.shipping`, always. A Debug build can
/// show everything through Settings › About › Advanced › "Show every feature", so the owner can try a
/// hidden feature on their own phone; a Release or TestFlight build never reads that key, so what a
/// tester gets is the shipping scope and nothing else. Read at each use, not cached: the toggle
/// takes effect on the next screen, and the next tool call, without a restart.
enum ReleaseScopeStore {
    static var current: ReleaseScope {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: ReleaseScope.previewEverythingKey) { return .everything }
        #endif
        return .shipping
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
