import Foundation

/// Where the rider said they're going, picked on the Start sheet ("Where to?").
/// Optional: "Just ride" starts without one. Never shared with friends.
public struct RideDestination: Codable, Hashable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    /// Set when the destination is one of the rider's spots (usually a wishlist spot).
    public var spotID: UUID?

    public init(name: String, coordinate: Coordinate, spotID: UUID? = nil) {
        self.name = name
        self.coordinate = coordinate
        self.spotID = spotID
    }

    /// Close enough to count as there: the same 150 m as a spot.
    public static let arrivalRadius: Double = MediaPlacer.defaultSpotRadius

    /// Straight-line distance left, in meters. Shown as "km to go"; the road is longer on ghats,
    /// but a number that only ever comes from GPS can't be wrong in a confusing way.
    public func remainingDistance(from position: Coordinate) -> Double {
        coordinate.distance(to: position)
    }

    public func isReached(at position: Coordinate, radius: Double = arrivalRadius) -> Bool {
        remainingDistance(from: position) <= radius
    }

    /// When the ride first came within `radius`, or `nil` if it never did (turned back, changed plans).
    public func reachedAt(track: [TrackPoint], radius: Double = arrivalRadius) -> Date? {
        track.first { isReached(at: $0.coordinate, radius: radius) }?.timestamp
    }
}

/// What the "Where to?" list shows before and while the rider types.
public enum DestinationSuggestions {
    public struct Suggestion: Hashable, Sendable {
        public enum Source: Hashable, Sendable { case wishlist, recent }
        public var destination: RideDestination
        public var source: Source
        /// Straight-line meters from the rider, when their location is known.
        public var distance: Double?
    }

    /// Wishlist spots first (nearest first when the location is known, otherwise in the order given),
    /// then recent destinations that aren't already listed, both filtered by `query`.
    public static func suggestions(
        query: String,
        wishlist: [RideDestination],
        recent: [RideDestination],
        from position: Coordinate?,
        wishlistLimit: Int = 5,
        recentLimit: Int = 3
    ) -> [Suggestion] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ destination: RideDestination) -> Bool {
            needle.isEmpty || destination.name.localizedStandardContains(needle)
        }
        func suggestion(_ destination: RideDestination, _ source: Suggestion.Source) -> Suggestion {
            Suggestion(destination: destination, source: source, distance: position.map { destination.remainingDistance(from: $0) })
        }

        var wished = wishlist.filter(matches).map { suggestion($0, .wishlist) }
        if position != nil {
            wished.sort { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
        }
        wished = Array(wished.prefix(wishlistLimit))

        var listed = wished.map(\.destination)
        var recents: [Suggestion] = []
        for destination in recent where matches(destination) {
            let duplicate = listed.contains {
                $0.spotID != nil && $0.spotID == destination.spotID
                    || $0.name.caseInsensitiveCompare(destination.name) == .orderedSame
                    || $0.coordinate.distance(to: destination.coordinate) <= RideDestination.arrivalRadius
            }
            guard !duplicate else { continue }
            listed.append(destination)
            recents.append(suggestion(destination, .recent))
            if recents.count == recentLimit { break }
        }
        return wished + recents
    }
}

extension RideNaming {
    /// The name the Start sheet fills in when a destination is picked: "Ride to Zostel Ooty".
    /// The rider can still edit it; `resolve` then dates it if the name is taken.
    public static func name(goingTo destination: RideDestination) -> String {
        let place = destination.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? "" : "Ride to \(place)"
    }
}

extension GoogleMapsLink {
    /// Turn-by-turn directions in Google Maps from the rider's current location, routed for
    /// motorcycles and scooters where Google supports it (`two-wheeler`), by car elsewhere.
    public static func directionsURL(to destination: Coordinate) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: destination.queryString),
            URLQueryItem(name: "travelmode", value: "two-wheeler"),
        ]
        return components.url!
    }
}
