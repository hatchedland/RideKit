import Foundation

/// A spot reduced to what matching needs (mapped from the SwiftData `Spot` in the app).
public struct SpotReference: Hashable, Sendable {
    public var id: UUID
    public var coordinate: Coordinate

    public init(id: UUID, coordinate: Coordinate) {
        self.id = id
        self.coordinate = coordinate
    }
}

/// Where a ride's photo or video shows up inside the app.
public enum MediaPlacement: Equatable, Sendable {
    /// Taken within the radius of a spot.
    case spot(UUID)
    /// Has a location but isn't near any spot: pinned on the route.
    case route(Coordinate)
    /// No location data: only in the ride gallery and album.
    case unplaced
}

public enum MediaPlacer {
    /// Default radius for "this photo belongs to that spot" and wishlist auto-visit.
    public static let defaultSpotRadius: Double = 150

    public static func place(
        _ item: MediaCandidate,
        spots: [SpotReference],
        radius: Double = defaultSpotRadius
    ) -> MediaPlacement {
        guard let coordinate = item.coordinate, coordinate.isValid else { return .unplaced }
        if let match = spots.nearest(to: coordinate, within: radius, by: \.coordinate) {
            return .spot(match.element.id)
        }
        return .route(coordinate)
    }

    public static func place(
        _ items: [MediaCandidate],
        spots: [SpotReference],
        radius: Double = defaultSpotRadius
    ) -> [String: MediaPlacement] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, place($0, spots: spots, radius: radius)) })
    }
}
