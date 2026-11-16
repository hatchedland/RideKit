import Foundation
import OSLog
import RideKit

/// Sends Google Places requests (built and parsed in RideKit's `GooglePlaces`) with the app's
/// Google Maps key. Every failure (offline, no key, quota, refused key) comes back as "no places",
/// so a spot is still saved instantly and just keeps its fallback name.
struct GooglePlacesClient: Sendable {
    let apiKey: String?
    let bundleID: String
    private static let log = Logger(subsystem: "com.hatchedland.ridetracker", category: "places")

    @MainActor
    static var app: GooglePlacesClient {
        GooglePlacesClient(apiKey: GoogleMapsSetup.apiKey, bundleID: Bundle.main.bundleIdentifier ?? "com.hatchedland.ridetracker")
    }

    private var languageCode: String { Locale.current.language.languageCode?.identifier ?? "en" }

    /// Places within `radius` meters, nearest first.
    func nearby(_ coordinate: Coordinate, radius: Double) async -> [Place] {
        guard let apiKey else { return [] }
        return await send(GooglePlaces.nearbyRequest(around: coordinate, radius: radius,
                                                     apiKey: apiKey, bundleID: bundleID, languageCode: languageCode))
    }

    /// Places matching `query`, preferring ones near `near`.
    func search(_ query: String, near: Coordinate?) async -> [Place] {
        guard let apiKey else { return [] }
        return await send(GooglePlaces.textRequest(query, near: near,
                                                   apiKey: apiKey, bundleID: bundleID, languageCode: languageCode))
    }

    private func send(_ request: URLRequest) async -> [Place] {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                Self.log.error("Places request failed: \(GooglePlaces.error(status: status, data: data).message, privacy: .public)")
                return []
            }
            return try GooglePlaces.places(from: data)
        } catch is CancellationError {
            return []
        } catch {
            Self.log.notice("Places unavailable: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

extension GooglePlacesClient {
    /// A two-wheeler route from Google's Routes API (same key); `nil` offline or on any failure,
    /// in which case the ride falls back to the straight-line distance.
    func route(from origin: Coordinate, to destination: Coordinate) async -> RideRoute? {
        guard let apiKey else { return nil }
        let request = GoogleRoutes.request(from: origin, to: destination, apiKey: apiKey, bundleID: bundleID,
                                           languageCode: Locale.current.language.languageCode?.identifier ?? "en")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try GoogleRoutes.route(from: data)
        } catch {
            return nil
        }
    }
}
