import DoddyCore
import Foundation
import MapKit

/// Travel time for "remind me when to leave" (ADR-335). Sends the start (where the iPhone is now)
/// and the destination to Apple Maps, once, when the card is made. Nothing is kept from it but the
/// number of seconds the card shows.
extension PlaceLocation {
    func travelTime(from start: PlaceCoordinate, to destination: PlaceCoordinate, mode: TravelMode, arriveBy: Date) async throws -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)))
        request.transportType = switch mode {
        case .driving: .automobile
        case .walking: .walking
        case .transit: .transit
        }
        request.arrivalDate = arriveBy
        let response = try await MKDirections(request: request).calculateETA()
        let seconds = response.expectedTravelTime
        return seconds > 0 ? seconds : nil
    }
}
