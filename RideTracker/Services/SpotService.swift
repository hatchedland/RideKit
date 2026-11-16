import CoreLocation
import Foundation
import MapKit
import RideKit
import SwiftData

/// Creates spots and fills them in afterwards, so marking one is instant: a suggested name and
/// category from the nearest Google Places landmark, and the address and town from Apple's reverse
/// geocoder (free, and it's only an address).
@MainActor
final class SpotService {
    private let context: ModelContext
    private let resolver = ShortLinkResolver()
    private let places: GooglePlacesClient

    init(context: ModelContext, places: GooglePlacesClient? = nil) {
        self.context = context
        self.places = places ?? .app
    }

    enum AddResult {
        case created(Spot)
        /// Within 100 m of an existing spot; a visit was added instead of creating a duplicate.
        case revisited(Spot)
    }

    /// Marks a spot at `coordinate`. During a ride the spot is visited; otherwise it uses `status`.
    /// `visitedAt` dates the visit, e.g. when a trail stop is saved as a spot after the ride.
    @discardableResult
    func mark(
        at coordinate: Coordinate,
        status: SpotStatus = .visited,
        name: String = "",
        category: SpotCategory = .other,
        sourceURL: String? = nil,
        rideID: UUID? = nil,
        allowRevisit: Bool = true,
        visitedAt: Date = .now
    ) -> AddResult {
        let all = (try? context.fetch(FetchDescriptor<Spot>())) ?? []

        if allowRevisit, let match = RevisitDetector.existingSpot(near: coordinate, in: all.map(\.reference)),
           let existing = all.first(where: { $0.id == match.id }) {
            if status == .visited { existing.markVisited(on: visitedAt) }
            try? context.save()
            return .revisited(existing)
        }

        let spot = Spot(name: name, coordinate: coordinate, status: status, category: category, sourceURL: sourceURL)
        if status == .visited { spot.visits = [visitedAt] }
        if let rideID {
            spot.ride = try? context.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.id == rideID })).first
        }
        context.insert(spot)
        try? context.save()
        Task { await enrich(spot) }
        return .created(spot)
    }

    /// Fills in address, locality and, if the rider hasn't named it, a nearby landmark's name.
    func enrich(_ spot: Spot) async {
        let place = await Self.reverseGeocode(spot.coordinate)
        if let address = place.address { spot.address = address }
        if let locality = place.locality { spot.locality = locality }

        if spot.name.isEmpty {
            if let landmark = await nearestLandmark(to: spot.coordinate) {
                spot.name = landmark.name
                if spot.category == .other { spot.category = SpotCategory(rawValue: landmark.spotCategory) ?? .other }
            } else if let address = spot.address {
                spot.name = address
            }
            spot.nameIsSuggested = !spot.name.isEmpty
        }
        try? context.save()
    }

    /// Address and city/area for a coordinate. Runs off the main actor because the MapKit request
    /// types aren't `Sendable`; only plain strings come back.
    nonisolated static func reverseGeocode(_ coordinate: Coordinate) async -> (address: String?, locality: String?) {
        guard let request = MKReverseGeocodingRequest(location: coordinate.clLocation),
              let item = try? await request.mapItems.first
        else { return (nil, nil) }
        return (
            item.address?.shortAddress ?? item.address?.fullAddress,
            item.addressRepresentations?.cityWithContext ?? item.addressRepresentations?.cityName
        )
    }

    /// Google Places within 150 m, nearest first. Used for name suggestions.
    func landmarks(near coordinate: Coordinate, radius: Double = MediaPlacer.defaultSpotRadius) async -> [Place] {
        await places.nearby(coordinate, radius: radius)
    }

    private func nearestLandmark(to coordinate: Coordinate) async -> Place? {
        await landmarks(near: coordinate).first
    }

    /// Search by name ("Chandratal Lake"), preferring places near `near`.
    func search(_ query: String, near: Coordinate?) async -> [Place] {
        await places.search(query, near: near)
    }

    /// Coordinates from pasted text: any Google Maps link (short links are expanded) or "lat, lon".
    func coordinate(fromPasted text: String) async throws -> Coordinate? {
        try await resolver.coordinate(from: text)
    }

    func delete(_ spot: Spot) {
        context.delete(spot)
        try? context.save()
    }
}

