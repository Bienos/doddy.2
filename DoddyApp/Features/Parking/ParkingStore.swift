import DoddyCore
import Foundation

/// The one parking spot kept on this iPhone (ADR-292), in the app's own preferences. Every write
/// is read back before Doddy says it happened.
enum ParkingStore {
    private static var defaults: UserDefaults { .standard }

    static func current() -> ParkingSpot? {
        Parking.decode(defaults.data(forKey: Parking.storageKey))
    }

    /// True only when the spot reads back exactly as written.
    static func save(_ spot: ParkingSpot) -> Bool {
        guard let data = Parking.encode(spot) else { return false }
        defaults.set(data, forKey: Parking.storageKey)
        return current() == spot
    }

    /// True only when nothing is kept any more.
    static func clear() -> Bool {
        defaults.removeObject(forKey: Parking.storageKey)
        return current() == nil
    }
}
