import Foundation

/// A WGS-84 latitude/longitude pair.
///
/// RideKit uses its own type instead of `CLLocationCoordinate2D` so the logic stays
/// `Sendable`, `Codable`, `Hashable` and testable without Core Location.
public struct Coordinate: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    /// Great-circle distance in meters (haversine). Accurate to well under 0.5% for
    /// the short distances this app cares about.
    public func distance(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * Coordinate.earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Linear interpolation; fine at the scale of consecutive GPS fixes.
    public func interpolated(to other: Coordinate, fraction: Double) -> Coordinate {
        Coordinate(
            latitude: latitude + (other.latitude - latitude) * fraction,
            longitude: longitude + (other.longitude - longitude) * fraction
        )
    }

    /// "28.613900,77.209000" — 6 decimals is ~0.1 m, plenty for a pin.
    public var queryString: String {
        "\(Coordinate.format(latitude)),\(Coordinate.format(longitude))"
    }

    static let earthRadius = 6_371_008.8

    static func format(_ value: Double) -> String {
        let s = String(format: "%.6f", value)
        return s == "-0.000000" ? "0.000000" : s
    }
}

public extension Collection {
    /// The element nearest to `coordinate` within `radius` meters, if any.
    func nearest(
        to coordinate: Coordinate,
        within radius: Double,
        by keyPath: (Element) -> Coordinate
    ) -> (element: Element, distance: Double)? {
        var best: (element: Element, distance: Double)?
        for element in self {
            let d = keyPath(element).distance(to: coordinate)
            if d <= radius, d < (best?.distance ?? .infinity) {
                best = (element, d)
            }
        }
        return best
    }
}
