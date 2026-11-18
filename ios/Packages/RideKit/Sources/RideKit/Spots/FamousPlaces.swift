import Foundation

/// "Famous places ahead" while riding: well-reviewed sights from Google Places within 2 km of the
/// rider and not behind them, announced passively (banner + Live Activity), the 3 nearest at a time.
/// Each place is announced once per ride, and never one that's already a saved spot (the wishlist
/// alert covers those).
public enum FamousPlaces {
    /// A place counts once it's this close to the rider — the same 2 km as the wishlist alert.
    public static let alertDistance: Double = 2_000
    /// At most this many places per announcement.
    public static let announceLimit = 3
    /// "Famous": at least this many Google reviews…
    public static let minimumReviews = 500
    /// …averaging at least this.
    public static let minimumRating = 4.0
    /// Each search covers this radius around the rider…
    public static let searchRadius: Double = 5_000
    /// …and a new one is made after riding this far, so consecutive circles overlap and nothing
    /// within `alertDistance` is missed (about one request every 3 km).
    public static let searchSpacing: Double = 3_000
    /// A place more than this many degrees off the rider's heading is behind them.
    public static let aheadAngle: Double = 90

    public static func isFamous(_ place: Place) -> Bool {
        (place.ratingCount ?? 0) >= minimumReviews && (place.rating ?? 0) >= minimumRating
    }

    /// One identity per place across overlapping searches: Google's id, else name + position.
    public static func key(for place: Place) -> String {
        place.id ?? "\(place.name)@\(place.coordinate.queryString)"
    }

    /// Whether to ask Google again: first fix of the ride, or `searchSpacing` from the last search.
    public static func needsSearch(at position: Coordinate, lastSearch: Coordinate?) -> Bool {
        guard let lastSearch else { return true }
        return position.distance(to: lastSearch) >= searchSpacing
    }

    /// The nearest famous places to announce now, nearest first, at most `limit`.
    ///
    /// - Parameters:
    ///   - course: degrees from north; `nil` (unknown or standing still) skips the "not behind" check.
    ///   - savedSpots: places within the spot radius of one of these are left out.
    public static func ahead(
        of position: Coordinate,
        course: Double?,
        candidates: [Place],
        alreadyAnnounced: Set<String>,
        savedSpots: [Coordinate] = [],
        distance: Double = alertDistance,
        limit: Int = announceLimit
    ) -> [(place: Place, distance: Double)] {
        var seen: Set<String> = []
        return candidates
            .filter { place in
                let key = key(for: place)
                guard isFamous(place), !alreadyAnnounced.contains(key), seen.insert(key).inserted else { return false }
                return savedSpots.nearest(to: place.coordinate, within: MediaPlacer.defaultSpotRadius, by: { $0 }) == nil
            }
            .map { (place: $0, distance: $0.coordinate.distance(to: position)) }
            .filter { $0.distance <= distance }
            .filter { candidate in
                guard let course, course >= 0, candidate.distance > MediaPlacer.defaultSpotRadius else { return true }
                return angle(between: course, and: bearing(from: position, to: candidate.place.coordinate)) <= aheadAngle
            }
            .sorted { $0.distance < $1.distance }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Direction of travel: the GPS course while moving, else the bearing over the last `meters`
    /// ridden (GPS drops its course in slow traffic, and the simulator never sends one). `nil` until
    /// the rider has covered that distance.
    public static func heading(of track: [TrackPoint], over meters: Double = 50, minimumSpeed: Double = 3) -> Double? {
        guard let last = track.last else { return nil }
        if let course = last.course, course >= 0, (last.speed ?? 0) >= minimumSpeed { return course }
        for point in track.dropLast().reversed().prefix(200) where point.coordinate.distance(to: last.coordinate) >= meters {
            return bearing(from: point.coordinate, to: last.coordinate)
        }
        return nil
    }

    /// Initial great-circle bearing in degrees from north (0..<360).
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Smallest difference between two headings (0...180).
    static func angle(between a: Double, and b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    /// "Srirangapatna Fort 1.2 km · Ranganathittu 1.8 km"
    public static func summary(_ places: [(place: Place, distance: Double)], distance format: (Double) -> String) -> String {
        places.map { "\($0.place.name) \(format($0.distance))" }.joined(separator: " · ")
    }
}
