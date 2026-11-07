import DoddyCore
import UIKit

/// The app icon's long-press menu (ADR-339). Each action only opens a screen, through the same
/// router as the shortcuts and controls; nothing is saved or changed by the action itself.
@MainActor
enum QuickActions {
    /// Sets the menu; called when Doddy goes to the background, so it matches the parking spot.
    static func install() {
        UIApplication.shared.shortcutItems = QuickAction.shown(hasParkingSpot: ParkingStore.current() != nil,
                                                               scope: ReleaseScopeStore.current).map(item)
    }

    /// Runs one action. False for anything Doddy doesn't know.
    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = QuickAction(rawValue: shortcutItem.type) else { return false }
        // An item from a menu installed by an older build, for a feature this build hides (ADR-813).
        if action == .parking, !ReleaseScopeStore.current.shows(.parking) { return false }
        let router = ShortcutRouter.shared
        switch action {
        case .talk: router.talkToDoddyInvoked()
        case .newNote: router.newNoteInvoked()
        case .find: router.findInDoddyInvoked(query: "")
        case .parking:
            // The saved spot in Maps, as the parking widget does (ADR-315). No spot, nothing opens.
            // With the Face ID lock up it waits for the unlock (ADR-723).
            router.runWhenUnlocked(.openParking) { openParkingSpot() }
        }
        return true
    }

    /// The saved parking spot in Apple Maps; no spot, nothing opens. The icon's menu and the parking
    /// widget's link (`RootView`) both come here, after the Face ID lock (ADR-723).
    static func openParkingSpot() {
        if let spot = ParkingStore.current(), let maps = Parking.mapsURL(spot) { UIApplication.shared.open(maps) }
    }

    private static func item(_ action: QuickAction) -> UIApplicationShortcutItem {
        let (title, symbol): (String, String) = switch action {
        case .talk: (NSLocalizedString("Talk to Doddy", comment: ""), "waveform")
        case .newNote: (NSLocalizedString("New note", comment: ""), "square.and.pencil")
        case .find: (NSLocalizedString("Find in Doddy", comment: ""), "magnifyingglass")
        case .parking: (NSLocalizedString("Where I parked", comment: ""), "car")
        }
        return UIApplicationShortcutItem(type: action.rawValue, localizedTitle: title, localizedSubtitle: nil,
                                         icon: UIApplicationShortcutIcon(systemImageName: symbol))
    }
}
