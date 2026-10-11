import DoddyCore
import SwiftUI

/// How to get the "Doddy Camera" Shortcut that "open the camera" runs (ADR-291, ADR-300).
/// `.full` is the section in Settings → Connections → Shortcuts; `.card` sits under Run on the
/// voice card, where the user needs it, and stays small so it doesn't compete with Run.
/// With the owner's shared link it is one tap to add; without it, the steps to make it.
struct CameraShortcutHelp: View {
    enum Style { case full, card }

    let style: Style

    @Environment(\.openURL) private var openURL
    @State private var showsSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if style == .full {
                Text("Say “open the camera” and Doddy runs your \(CameraShortcut.name) shortcut, which opens the Camera app. Doddy never uses the camera itself and can't see your photos.")
            }
            if let link = CameraShortcut.installLink {
                if style == .full {
                    Text("Add the shortcut once. Shortcuts shows it first, and you tap Add Shortcut.")
                        .foregroundStyle(Theme.secondaryText)
                }
                addButton(link)
            } else if style == .card && !showsSteps {
                Button("Don't have the shortcut? Show me how") { showsSteps = true }
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("voice.cameraShortcutHelp")
            } else {
                Text("Make it once in the Shortcuts app: tap +, add the action Open App, choose Camera, and name the shortcut \(CameraShortcut.name).")
                    .font(style == .card ? .footnote : .body)
                    .foregroundStyle(Theme.secondaryText)
                if let shortcuts = URL(string: "shortcuts://") {
                    Button {
                        openURL(shortcuts)
                    } label: {
                        Label("Open Shortcuts", systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("connection.openShortcuts")
                }
            }
        }
    }

    @ViewBuilder
    private func addButton(_ link: URL) -> some View {
        switch style {
        case .full:
            Button {
                openURL(link)
            } label: {
                Label("Add camera shortcut", systemImage: "camera")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("connection.addCameraShortcut")
        case .card:
            Button {
                openURL(link)
            } label: {
                Label("Don't have the shortcut? Add it", systemImage: "camera")
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .accessibilityIdentifier("voice.addCameraShortcut")
        }
    }
}
