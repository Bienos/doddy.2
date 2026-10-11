import SwiftUI

/// Doddy in the Mac menu bar (ADR-435): the first Mac prototype from the owner's Watch, iPad and
/// Mac review (slide 13, "Najpierw prototyp Maca w pasku menu"). A click on the menu bar icon
/// opens one small window to type a note, then Save or Cancel. No Dock icon (`LSUIElement`).
@main
struct DoddyMacApp: App {
    @State private var model = MacCaptureModel()

    var body: some Scene {
        MenuBarExtra("Doddy", systemImage: "square.and.pencil") {
            MacCaptureView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
