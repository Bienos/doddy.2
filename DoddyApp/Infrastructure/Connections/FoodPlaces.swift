import DoddyCore
import Foundation
import MapKit

/// Home › Food's Apple Maps searches (decision `2026-11-13-food-search-nearby`): first the delivery address the
/// person typed (`search`, the same as a place reminder's), then the dish around that point. Both go straight
/// from this iPhone to Apple Maps; nothing goes to Doddy's server and nothing is kept but what the screen shows.
/// No location is read: the address is typed. `FoodSearch` in DoddyCore judges the answer.
extension PlaceLocation {
    /// Apple Maps' first match for a typed delivery address, or nil when it found none.
    func foodAddress(_ address: String) async throws -> PlaceSearchResult? {
        do {
            return try await search(address, near: nil).first
        } catch {
            if Self.isNotFound(error) { return nil }
            throw error
        }
    }

    /// Restaurants, cafés and bakeries Apple Maps finds for `dish` around `here`, as plain values; empty when it
    /// found none.
    func foodPlaces(_ dish: String, near here: PlaceCoordinate) async throws -> [FoodSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = dish
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery])
        // A box a little wider than FoodSearch.maxKilometres each way; the code drops anything further.
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: here.latitude, longitude: here.longitude),
            latitudinalMeters: 16_000, longitudinalMeters: 16_000)
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            if Self.isNotFound(error) { return [] }
            throw error
        }
        return response.mapItems.map { item in
            let coordinate = item.placemark.coordinate
            return FoodSearchResult(
                name: item.name ?? "", address: item.placemark.title ?? "",
                kind: Self.foodKind(item.pointOfInterestCategory),
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                phone: item.phoneNumber)
        }
    }

    private static func foodKind(_ category: MKPointOfInterestCategory?) -> FoodPlaceKind? {
        guard let category else { return nil }
        if category == .restaurant { return .restaurant }
        if category == .cafe { return .cafe }
        if category == .bakery { return .bakery }
        return nil
    }

    /// Apple Maps answers "nothing found" with an error, not with an empty list.
    private static func isNotFound(_ error: Error) -> Bool {
        (error as? MKError)?.code == .placemarkNotFound
    }
}
