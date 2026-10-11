import Foundation

/// Long-press the app icon (ADR-339): New note, Talk to Doddy, Find, and Where I parked when a
/// spot is saved. Each only opens a screen; nothing is saved or changed by the action itself.
public enum QuickAction: String, CaseIterable, Sendable {
    case newNote = "doddy.quick.newNote"
    case talk = "doddy.quick.talk"
    case find = "doddy.quick.find"
    case parking = "doddy.quick.parking"

    /// The actions to show, in order. "Where I parked" only when there's a spot to show.
    public static func shown(hasParkingSpot: Bool) -> [QuickAction] {
        hasParkingSpot ? [.talk, .newNote, .find, .parking] : [.talk, .newNote, .find]
    }
}
