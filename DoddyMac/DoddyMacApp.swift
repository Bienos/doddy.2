import AppKit
import SwiftUI

/// Doddy in the Mac menu bar (ADR-435): the first Mac prototype from the owner's Watch, iPad and
/// Mac review (slide 13, "Najpierw prototyp Maca w pasku menu"). A click on the menu bar icon
/// opens one small window to type a note, then Save or Cancel. No Dock icon (`LSUIElement`).
@main
struct DoddyMacApp: App {
    @State private var model = MacCaptureModel()

    var body: some Scene {
        MenuBarExtra {
            MacCaptureView()
                .environment(model)
        } label: {
            // Doddy's face from the owner's pack (ADR-438), in colour; the pencil if it is missing.
            if let face = Self.menuBarFace() {
                Image(nsImage: face).accessibilityLabel("Doddy")
            } else {
                Image(systemName: "square.and.pencil").accessibilityLabel("Doddy")
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// The face crop (`MenuBarDoddy`, a copy of the widgets' `WidgetDoddy_face`, 120 px) at menu bar
    /// size. A menu bar item ignores SwiftUI frames, so the size is set on the image itself.
    private static func menuBarFace() -> NSImage? {
        guard let image = NSImage(named: "MenuBarDoddy") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
