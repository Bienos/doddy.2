import DoddyCore
import ReplayKit
import SwiftUI
import UIKit

/// "Show screen" (decision 2026-11-09-doddy-looks-at-the-screen): starts sharing the iPhone screen with Doddy's
/// broadcast extension (`DoddyScreen`). iOS always asks the person with its own "Start Broadcast" sheet; no app
/// can start sharing without that tap, and iOS shows that the screen is shared until they stop it.
///
/// Two ways in:
/// - `ScreenShareCapsule`: the system picker button itself, laid over a capsule with words, the supported way.
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
        configure(picker)
        return picker
    }

    /// Only Doddy in the list, and never the microphone: the extension reads the picture only.
    static func configure(_ picker: RPSystemBroadcastPickerView) {
        picker.preferredExtension = extensionBundleID
        picker.showsMicrophoneButton = false
    }
}

/// "Show screen" as a capsule with words on it (owner review, 13 Nov 2026: the round record glyph alone in Home's
/// header said nothing and sat in the way). It sits over Mute and End while Doddy talks on Home. iOS's own picker
/// lies over the whole capsule, so a tap anywhere on it is a tap on Apple's button, the supported way
/// (`ScreenSharePicker`); the capsule's words show through. While sharing is on the capsule says so, and the same
/// tap opens iOS's sheet, where Stop Broadcast ends it.
///
/// `compact` is the small mark in Home's header after the conversation: there only while sharing is on, so the
/// person sees it is still on and can stop it from Home. Whether it is on comes from the extension's state file
/// (`ScreenShareIndicator`); iOS shows its own indicator as well.
struct ScreenShareCapsule: View {
    var compact = false

    var body: some View {
        // The state file is a few bytes; reading it every two seconds is the whole cost.
        TimelineView(.periodic(from: .now, by: 2)) { context in
            let sharing = ScreenShareFiles.isSharing(now: context.date)
            if !compact || sharing {
                face(sharing: sharing)
                    .accessibilityHidden(true)
                    .overlay {
                        CoveringBroadcastPicker(label: spokenLabel(sharing: sharing))
                    }
                    .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private func face(sharing: Bool) -> some View {
        if compact {
            Image(systemName: "rectangle.inset.filled.on.rectangle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.quietSurface, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Theme.error).frame(width: 9, height: 9)
                }
        } else {
            Group {
                if sharing {
                    Label("Sharing screen · Stop", systemImage: "stop.circle")
                } else {
                    Label("Show screen", systemImage: "eye")
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Theme.quietSurface, in: Capsule())
            .overlay {
                if sharing { Capsule().strokeBorder(Theme.error, lineWidth: 1.5) }
            }
        }
    }

    private func spokenLabel(sharing: Bool) -> String {
        sharing
            ? NSLocalizedString("Screen shared with Doddy. Opens iOS's sheet, where Stop Broadcast ends it.",
                                comment: "VoiceOver label of the screen-sharing capsule while sharing is on")
            : NSLocalizedString("Show screen to Doddy", comment: "Starts sharing the screen with Doddy")
    }
}

/// iOS's picker stretched over the capsule.
private struct CoveringBroadcastPicker: UIViewRepresentable {
    let label: String

    func makeUIView(context: Context) -> CoveringPickerView {
        let picker = CoveringPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        ScreenSharePicker.configure(picker)
        return picker
    }

    func updateUIView(_ picker: CoveringPickerView, context: Context) {
        picker.spokenLabel = label
        picker.setNeedsLayout()
    }
}

/// The picker with its one button as large as the capsule and its glyph hidden: the capsule's words show through
/// and the tap is still Apple's button. VoiceOver reads the button, with the capsule's words.
final class CoveringPickerView: RPSystemBroadcastPickerView {
    var spokenLabel = ""

    override func layoutSubviews() {
        super.layoutSubviews()
        for case let button as UIButton in subviews {
            button.frame = bounds
            button.tintColor = .clear
            button.imageView?.alpha = 0
            button.accessibilityLabel = spokenLabel
            button.accessibilityIdentifier = "voice.showScreen"
        }
    }
}
