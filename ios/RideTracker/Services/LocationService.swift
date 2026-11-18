import CoreLocation
import Foundation
import RideKit

/// Streams filtered GPS fixes during a ride, including with the screen locked.
///
/// Uses the async Core Location API. `CLServiceSession` handles the "When In Use" prompt, and
/// `CLBackgroundActivitySession` keeps updates flowing in the background (the "Location updates"
/// background mode must be on). No "Always" permission is needed.
@MainActor
final class LocationService {
    enum Event {
        case fix(TrackPoint)
        case denied
        case unavailable
    }

    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var task: Task<Void, Never>?
    private var filter = LocationFilter()

    /// The most recent accepted fix, used by "Mark spot".
    private(set) var lastFix: TrackPoint?

    var authorizationStatus: CLAuthorizationStatus { CLLocationManager().authorizationStatus }

    /// Starts streaming. Call while the app is in the foreground (for the background session to attach).
    func start(onEvent: @escaping @MainActor (Event) -> Void) {
        stop()
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        filter.reset()

        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, !Task.isCancelled else { return }
                    if update.authorizationDenied || update.authorizationDeniedGlobally {
                        onEvent(.denied)
                        continue
                    }
                    if update.locationUnavailable {
                        onEvent(.unavailable)
                        continue
                    }
                    guard let location = update.location else { continue }
                    let point = TrackPoint(location)
                    if self.filter.evaluate(point) == .accepted {
                        self.lastFix = point
                        onEvent(.fix(point))
                    }
                }
            } catch {
                onEvent(.unavailable)
            }
        }
    }

    /// Stops updates but keeps the background session, so the app stays alive during a manual pause
    /// (the Photos observer keeps filling the ride album).
    func suspendUpdates() {
        task?.cancel()
        task = nil
    }

    func stop() {
        task?.cancel()
        task = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
    }

    /// One-off current location for adding a spot outside a ride.
    func currentLocation() async throws -> Coordinate? {
        if let lastFix, Date.now.timeIntervalSince(lastFix.timestamp) < 15 {
            return lastFix.coordinate
        }
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
            if let location = update.location, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 {
                return Coordinate(location.coordinate)
            }
        }
        return nil
    }
}

extension Coordinate {
    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

extension TrackPoint {
    init(_ location: CLLocation) {
        self.init(
            timestamp: location.timestamp,
            coordinate: Coordinate(location.coordinate),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speed: location.speedAccuracy >= 0 && location.speed >= 0 ? location.speed : nil,
            course: location.courseAccuracy >= 0 && location.course >= 0 ? location.course : nil,
            horizontalAccuracy: location.horizontalAccuracy
        )
    }
}
