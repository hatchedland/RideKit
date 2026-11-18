import Foundation

/// Wishlist logic: which "want to go" spots a ride visited, and which to alert about while riding.
public enum WishlistMatcher {

    public struct Visit: Equatable, Sendable {
        public enum Evidence: Equatable, Sendable {
            case stopped(Stop)
            case photo(mediaID: String)
        }

        public var spotID: UUID
        public var date: Date
        public var evidence: Evidence
    }

    /// A wishlist spot counts as visited when, within `radius`, the rider either **stopped**
    /// (≥ 2 min below walking pace) or **took a photo/video**. Merely riding past doesn't count.
    /// Each spot is reported once, with its earliest evidence.
    public static func visits(
        wishlist: [SpotReference],
        track: [TrackPoint],
        media: [MediaCandidate],
        radius: Double = MediaPlacer.defaultSpotRadius
    ) -> [Visit] {
        let stops = StopDetector.stops(in: track)
        var result: [Visit] = []

        for spot in wishlist {
            var candidates: [Visit] = []
            if let stop = stops.first(where: { $0.center.distance(to: spot.coordinate) <= radius }) {
                candidates.append(Visit(spotID: spot.id, date: stop.start, evidence: .stopped(stop)))
            }
            if let photo = media
                .filter({ ($0.coordinate?.distance(to: spot.coordinate) ?? .infinity) <= radius })
                .min(by: { $0.capturedAt < $1.capturedAt }) {
                candidates.append(Visit(spotID: spot.id, date: photo.capturedAt, evidence: .photo(mediaID: photo.id)))
            }
            if let earliest = candidates.min(by: { $0.date < $1.date }) {
                result.append(earliest)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Distance at which the rider is told a wishlist spot is near.
    public static let nearbyAlertDistance: Double = 2_000

    /// Wishlist spots within `distance` of `position` that haven't been announced yet this ride,
    /// nearest first.
    public static func nearbyAlerts(
        position: Coordinate,
        wishlist: [SpotReference],
        alreadyAlerted: Set<UUID>,
        distance: Double = nearbyAlertDistance
    ) -> [(spot: SpotReference, distance: Double)] {
        wishlist
            .filter { !alreadyAlerted.contains($0.id) }
            .map { ($0, $0.coordinate.distance(to: position)) }
            .filter { $0.1 <= distance }
            .sorted { $0.1 < $1.1 }
            .map { (spot: $0.0, distance: $0.1) }
    }
}

public enum RevisitDetector {
    /// Marking a spot this close to an existing one offers "Add visit to …?" instead of a duplicate.
    public static let radius: Double = 100

    public static func existingSpot(near coordinate: Coordinate, in spots: [SpotReference]) -> SpotReference? {
        spots.nearest(to: coordinate, within: radius, by: \.coordinate)?.element
    }
}
