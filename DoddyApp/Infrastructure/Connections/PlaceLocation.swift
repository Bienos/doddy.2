import CoreLocation
import DoddyCore
import Foundation
import MapKit
import UserNotifications

/// A point the user picked, as plain numbers (no CoreLocation types outside this folder).
struct PlaceCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// One Apple Maps search result.
struct PlaceSearchResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: PlaceCoordinate
}

/// Location for place reminders only (ADR-196). Asks for "While Using" with Precise Location, never
/// "Always"; reads one position when the user taps "Use where I am now"; searches Apple Maps when
/// the user types a place. It never tracks where the user goes: iOS watches the reminder's place
/// itself (`UNLocationNotificationTrigger`) and wakes nothing in Doddy when it fires.
@MainActor
final class PlaceLocation: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceLocation()

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<Void, Never>] = []

    override private init() {
        super.init()
        manager.delegate = self
    }

    func readiness() async -> LocationReadiness {
        // Apple asks not to call this on the main thread.
        let servicesOn = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        return Self.readiness(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization, servicesOn: servicesOn)
    }

    /// Shows the iOS prompt only if it was never answered. Returns the readiness afterwards.
    func requestWhenInUse() async -> LocationReadiness {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                waiting.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        return await readiness()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Also called once when the manager is created; only an answer resumes the waiters.
            guard status != .notDetermined else { return }
            let resumed = self.waiting
            self.waiting = []
            resumed.forEach { $0.resume() }
        }
    }

    /// One position accurate to 150 m, or `nil` after 15 seconds. Nothing is kept.
    func currentCoordinate() async -> PlaceCoordinate? {
        await currentFix(within: 150)?.coordinate
    }

    /// One position at least as sure as `meters`, with how sure iOS was, or `nil` after 15
    /// seconds. Read once, only when asked (a place reminder, or saving a parking spot, ADR-292).
    func currentFix(within meters: Double) async -> (coordinate: PlaceCoordinate, accuracy: Double)? {
        await withTaskGroup(of: (coordinate: PlaceCoordinate, accuracy: Double)?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location,
                           location.horizontalAccuracy >= 0, location.horizontalAccuracy <= meters {
                            return (PlaceCoordinate(
                                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                                location.horizontalAccuracy)
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Apple Maps search. Sends the typed words (and, if given, the area around `near`) to Apple.
    func search(_ text: String, near: PlaceCoordinate?) async throws -> [PlaceSearchResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        if let near {
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                latitudinalMeters: 20_000, longitudinalMeters: 20_000)
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(8).map { item in
            let coordinate = item.placemark.coordinate
            return PlaceSearchResult(
                name: item.name ?? "Place", address: item.placemark.title ?? "",
                coordinate: PlaceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }

    /// The trigger iOS watches for a place reminder: repeats on every arrival (or departure) until
    /// the user marks the reminder Done.
    nonisolated static func trigger(for place: ReminderPlace, identifier: String) -> UNLocationNotificationTrigger {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            radius: CLLocationDistance(place.radiusMeters), identifier: identifier)
        region.notifyOnEntry = place.onArrival
        region.notifyOnExit = !place.onArrival
        return UNLocationNotificationTrigger(region: region, repeats: true)
    }

    nonisolated static func readiness(
        status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization, servicesOn: Bool
    ) -> LocationReadiness {
        guard servicesOn else { return .unavailable }
        switch status {
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        case .authorizedWhenInUse, .authorizedAlways: return accuracy == .fullAccuracy ? .ready : .approximateOnly
        @unknown default: return .denied
        }
    }
}
