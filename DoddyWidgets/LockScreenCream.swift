import SwiftUI

/// Doddy's Lock Screen cards are cream in light and dark mode alike (ADR-266, owner: "make it
/// cream in the app"). The card colour is fixed, and the card's contents are drawn in the light
/// colour scheme, so the asset catalog's text colours (Ink, SecondaryText, AccentText, Confirmed,
/// Error) use their dark-on-cream values and Doddy needs no paper backing.
extension Color {
    /// The `CardBackground` light value: Doddy's paper cream.
    static let lockScreenCream = Color(red: 0xFF / 255, green: 0xF7 / 255, blue: 0xE9 / 255)
    /// The `Ink` light value, for the system's action buttons on the cream card.
    static let lockScreenInk = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x15 / 255)
}

extension View {
    /// The cream Lock Screen card: fixed background, contents in the light colour scheme.
    func doddyCreamLockScreen() -> some View {
        environment(\.colorScheme, .light)
            .activityBackgroundTint(.lockScreenCream)
            .activitySystemActionForegroundColor(.lockScreenInk)
    }
}
