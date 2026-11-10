import DoddyCore
import SwiftUI
import UIKit

/// An opaque cover over the whole screen, sheets and alerts included, while Doddy is not in front and
/// the Face ID lock is on (ADR-723). Without it the app switcher's picture of Doddy shows the last
/// screen, and a sheet open over the app would show in it whatever the lock's own cover hides.
///
/// A window of its own (as the listening pill's was until 9 Nov 2026):
/// above sheets and alerts, below the system's own. It exists only for a person who turned the lock on;
/// with the lock off nothing is made and nothing is shown (`AppLockPolicy.coverShown`, tested in DoddyCore).
/// It is plain, not a blur of what is under it, so the picture holds nothing.
@MainActor
final class PrivacyCover {
    static let shared = PrivacyCover()
    private var window: UIWindow?

    private init() {}

    /// Called with the scene's phase from `RootView`: shown while it isn't active and the lock is on,
    /// hidden otherwise. When Doddy comes back to the front the window is made (hidden) so the next
    /// time he leaves it only has to be shown.
    func update(sceneIsActive: Bool) {
        guard AppLock.shared.lockOn else {
            window?.isHidden = true
            return
        }
        if window == nil { window = makeWindow() }
        window?.isHidden = !AppLockPolicy.coverShown(lockOn: true, sceneIsActive: sceneIsActive)
    }

    private func makeWindow() -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        let controller = UIViewController()
        controller.view.backgroundColor = UIColor(Theme.canvas)
        let window = UIWindow(windowScene: scene)
        // Above sheets, alerts and the listening indicator, below the system's own.
        window.windowLevel = .alert + 2
        window.rootViewController = controller
        window.isHidden = true
        return window
    }
}

/// Closes every sheet, cover and alert presented over the app's own screens, without animation (ADR-723).
/// The Face ID cover is part of the app's own view, so anything presented over the app stays above it;
/// when the lock comes back, nothing may.
@MainActor
enum PresentedScreens {
    static func dismissAll() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            // Only the app's own windows: the cover and the listening indicator have their own levels.
            for window in scene.windows where window.windowLevel == .normal {
                window.rootViewController?.dismiss(animated: false)
            }
        }
    }
}
