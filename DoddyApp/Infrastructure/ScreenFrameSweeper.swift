import DoddyCore
import Foundation
import UIKit

/// The picture of the screen that the sharing extension keeps (`ScreenShareFiles`) is cleaned when Doddy starts
/// and whenever it comes back to the front, so a picture that was left behind (iOS ended the extension without a
/// word) doesn't stay on the iPhone. The rule is `ScreenFrameRetention` in DoddyCore, tested on Linux; this only
/// asks at the two moments. It reads and deletes a small file in the App Group folder and sends nothing anywhere.
@MainActor
final class ScreenFrameSweeper {
    static let shared = ScreenFrameSweeper()

    private var observer: NSObjectProtocol?

    private init() {}

    /// Once, at launch (`AppDelegate.application(_:didFinishLaunchingWithOptions:)`).
    func install() {
        guard observer == nil else { return }
        ScreenShareFiles.sweep(.launch)
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { _ in
            ScreenShareFiles.sweep(.foreground)
        }
    }
}
