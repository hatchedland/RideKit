import CoreLocation
import Foundation
import MapKit
import RideKit
import SwiftData

/// Creates spots and fills in their address and a suggested landmark name using Apple Maps data
/// (free, no API key). Spots are saved first and enriched afterwards, so marking one is instant.
@MainActor
final class SpotService {
    private let context: ModelContext
    private let resolver = ShortLinkResolver()

    init(context: ModelContext) {
        self.context = context
    }

    enum AddResult {
        case created(Spot)
        /// Within 100 m of an existing spot; a visit was added instead of creating a duplicate.
        case revisited(Spot)
    }

    /// Marks a spot at `coordinate`. During a ride the spot is visited; otherwise it uses `status`.
    @discardableResult
    func mark(
        at coordinate: Coordinate,
        status: SpotStatus = .visited,
        name: String = "",
        category: SpotCategory = .other,
        sourceURL: String? = nil,
        rideID: UUID? = nil,
        allowRevisit: Bool = true
    ) -> AddResult {
        let all = (try? context.fetch(FetchDescriptor<Spot>())) ?? []

        if allowRevisit, let match = RevisitDetector.existingSpot(near: coordinate, in: all.map(\.reference)),
           let existing = all.first(where: { $0.id == match.id }) {
            if status == .visited { existing.markVisited(on: .now) }
            try? context.save()
            return .revisited(existing)
        }

        let spot = Spot(name: name, coordinate: coordinate, status: status, category: category, sourceURL: sourceURL)
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
                spot.name = landmark.name ?? ""
                if spot.category == .other { spot.category = SpotCategory(landmark.pointOfInterestCategory) }
            } else if let address = spot.address {
                spot.name = address
            }
            spot.nameIsSuggested = !spot.name.isEmpty
        }
        try? context.save()
    }

    /// Address and city/area for a coordinate. Runs off the main actor because the MapKit request
    /// types aren't `Sendable`; only plain strings come back.
    nonisolated private static func reverseGeocode(_ coordinate: Coordinate) async -> (address: String?, locality: String?) {
        guard let request = MKReverseGeocodingRequest(location: coordinate.clLocation),
              let item = try? await request.mapItems.first
        else { return (nil, nil) }
        return (
            item.address?.shortAddress ?? item.address?.fullAddress,
            item.addressRepresentations?.cityWithContext ?? item.addressRepresentations?.cityName
        )
    }

    /// Points of interest within 150 m, nearest first. Used for name suggestions.
    func landmarks(near coordinate: Coordinate, radius: CLLocationDistance = MediaPlacer.defaultSpotRadius) async -> [MKMapItem] {
        let request = MKLocalPointsOfInterestRequest(center: coordinate.clCoordinate, radius: radius)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let here = coordinate.clLocation
        return response.mapItems.sorted {
            $0.location.distance(from: here) < $1.location.distance(from: here)
        }
    }

    private func nearestLandmark(to coordinate: Coordinate) async -> MKMapItem? {
        await landmarks(near: coordinate).first
    }

    /// Search by name for adding wishlist spots ("Chandratal Lake").
    func search(_ query: String, near region: MKCoordinateRegion?) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        if let region { request.region = region }
        return (try? await MKLocalSearch(request: request).start().mapItems) ?? []
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

extension SpotCategory {
    init(_ category: MKPointOfInterestCategory?) {
        switch category {
        case .restaurant?, .cafe?, .bakery?, .foodMarket?, .brewery?, .winery?: self = .food
        case .gasStation?, .evCharger?: self = .fuel
        case .hotel?, .campground?: self = .stay
        case .museum?, .castle?, .landmark?, .fortress?, .nationalMonument?: self = .monument
        case .automotiveRepair?: self = .mechanic
        case .nationalPark?, .park?, .beach?: self = .nature
        default: self = .other
        }
    }
}
