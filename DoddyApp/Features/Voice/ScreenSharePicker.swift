import DoddyCore
import ReplayKit
import SwiftUI
import UIKit

/// "Show screen" (decision 2026-11-09-doddy-looks-at-the-screen): starts sharing the iPhone screen with Doddy's
/// broadcast extension (`DoddyScreen`). iOS always asks the person with its own "Start Broadcast" sheet; no app
/// can start sharing without that tap, and iOS shows that the screen is shared until they stop it.
///
/// Two ways in:
/// - `ScreenShareButton`: the system picker button itself, the supported way.
/// - `ScreenSharePicker.present()`: opens the same sheet without a tap on that button, when the person asked
///   Doddy out loud ("patrz na ekran") and Doddy is on screen. Apple has no API for this; it sends the picker
///   button its own tap. If a future iOS changes the picker, `present()` returns false and Doddy asks the
///   person to tap "Show screen" instead, so nothing depends on it.
enum ScreenSharePicker {
    /// The broadcast extension's bundle id: the app's own id plus `.screen` (project.yml, `DoddyScreen`).
    static var extensionBundleID: String? {
        Bundle.main.bundleIdentifier.map { $0 + ScreenShare.extensionBundleSuffix }
    }

    /// Opens iOS's "Start Broadcast" sheet for Doddy. False when it couldn't: the app isn't in the foreground,
    /// or the picker has no button to tap. Only call it right after the person asked for it.
    @MainActor
    @discardableResult
    static func present() -> Bool {
        guard UIApplication.shared.applicationState == .active,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?
                .keyWindow
        else { return false }
        let picker = makePicker()
        picker.frame = CGRect(x: -100, y: -100, width: 1, height: 1)
        picker.alpha = 0.01
        window.addSubview(picker)
        defer {
            // The sheet is iOS's own; the picker isn't needed once it was asked to show it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { picker.removeFromSuperview() }
        }
        guard let button = picker.subviews.compactMap({ $0 as? UIButton }).first else { return false }
        button.sendActions(for: .touchUpInside)
        return true
    }

    static func makePicker() -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        // Only Doddy in the list, and never the microphone: the extension reads the picture only.
        picker.preferredExtension = extensionBundleID
        picker.showsMicrophoneButton = false
        return picker
    }
}

/// The picker as a SwiftUI view, for a "Show screen" button: a tap on it opens iOS's sheet.
struct ScreenShareButton: UIViewRepresentable {
    var tint: UIColor = .label

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = ScreenSharePicker.makePicker()
        picker.accessibilityLabel = NSLocalizedString("Show screen to Doddy", comment: "Starts sharing the screen with Doddy")
        picker.accessibilityIdentifier = "voice.showScreen"
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        for case let button as UIButton in picker.subviews {
            button.tintColor = tint
            button.imageView?.tintColor = tint
        }
    }
}
