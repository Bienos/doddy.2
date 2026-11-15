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
/// Since 14 Nov 2026 also "where am I?" by voice (decision 2026-11-14-approximate-location-by-voice): one reading about
/// a kilometre sure, and the area's name from Apple's geocoder for that position rounded (`WhereAmI` in DoddyCore).
@MainActor
final class PlaceLocation: NSObject, CLLocationManagerDelegate {
    static let shared = PlaceLocation()

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// Calls of `approximateFix` waiting for the one `requestLocation()` in flight; each ends at its own timeout.
    private var fixWaiters: [UUID: CheckedContinuation<LocationFix?, Never>] = [:]
    /// One geocoder for "where am I?": Apple's geocoder takes one request at a time.
    private let geocoder = CLGeocoder()
    private var areaWaiters: [UUID: CheckedContinuation<AreaNames?, Never>] = [:]

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
    /// seconds. Read once, only when asked (a place reminder, or saving a parking spot, ADR-301).
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

    // MARK: Where am I? (decision 2026-11-14-approximate-location-by-voice)

    /// One reading about a kilometre sure (`kCLLocationAccuracyKilometer`: iOS may answer from Wi-Fi and cell towers
    /// without GPS), or nil after `timeout` seconds or when iOS reports an error. Read only now, never kept here.
    func approximateFix(timeout: TimeInterval) async -> LocationFix? {
        await withCheckedContinuation { (continuation: CheckedContinuation<LocationFix?, Never>) in
            let id = UUID()
            let alreadyAsked = !fixWaiters.isEmpty
            fixWaiters[id] = continuation
            if !alreadyAsked {
                manager.desiredAccuracy = kCLLocationAccuracyKilometer
                manager.requestLocation()
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finishFix(id, with: nil)
            }
        }
    }

    /// The last position iOS gave Doddy, with its own timestamp. `WhereAmI.best` decides whether it is recent enough.
    func lastKnownFix() -> LocationFix? {
        manager.location.map { Self.fix($0) }
    }

    /// The district, town, region and country Apple's geocoder gives for a position the caller already rounded
    /// (`WhereAmI.area`): only that rounded position goes to Apple. Nil when the geocoder is busy, fails or takes longer
    /// than `timeout` seconds.
    func areaNames(latitude: Double, longitude: Double, timeout: TimeInterval) async -> AreaNames? {
        guard !geocoder.isGeocoding else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<AreaNames?, Never>) in
            let id = UUID()
            areaWaiters[id] = continuation
            geocoder.reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude)) { placemarks, _ in
                let names = placemarks?.first.map {
                    AreaNames(district: $0.subLocality, town: $0.locality, region: $0.administrativeArea, country: $0.country)
                }
                Task { @MainActor in self.finishArea(id, with: names) }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finishArea(id, with: nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Only `approximateFix` asks this manager for updates (place reminders and parking use `CLLocationUpdate`).
        let newest = locations.last.map { Self.fix($0) }
        Task { @MainActor in self.finishAllFixes(with: newest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finishAllFixes(with: nil) }
    }

    private func finishFix(_ id: UUID, with fix: LocationFix?) {
        fixWaiters.removeValue(forKey: id)?.resume(returning: fix)
    }

    private func finishAllFixes(with fix: LocationFix?) {
        let resumed = fixWaiters
        fixWaiters = [:]
        resumed.values.forEach { $0.resume(returning: fix) }
    }

    private func finishArea(_ id: UUID, with names: AreaNames?) {
        areaWaiters.removeValue(forKey: id)?.resume(returning: names)
    }

    nonisolated private static func fix(_ location: CLLocation) -> LocationFix {
        LocationFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                    accuracyMeters: location.horizontalAccuracy, takenAt: location.timestamp)
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
