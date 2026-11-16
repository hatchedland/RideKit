import Foundation

/// The road to the destination, from Google's Routes API with two-wheeler routing, and where the
/// rider is along it. Drawn ahead of the rider on the riding screen; its remaining length is the
/// "TO GO" distance. Turn-by-turn stays in the Google Maps app.
public struct RideRoute: Equatable, Sendable {
    public var coordinates: [Coordinate]
    public var distanceMeters: Double
    public var durationSeconds: Double
    /// Distance from the start of the route to each coordinate (same count as `coordinates`).
    public let cumulative: [Double]

    public init(coordinates: [Coordinate], distanceMeters: Double, durationSeconds: Double) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        var running = 0.0
        var cumulative = [0.0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            running += a.distance(to: b)
            cumulative.append(running)
        }
        self.cumulative = coordinates.isEmpty ? [] : cumulative
    }

    /// Farther than this from the route means the rider left it (a detour, a different road).
    public static let offRouteDistance: Double = 120

    public struct Progress: Equatable, Sendable {
        /// Road distance left from the rider's point on the route to the destination.
        public var remainingMeters: Double
        /// How far the rider is from the route line.
        public var offsetMeters: Double
        /// The rider's point on the route: index of the segment it's on, and the point itself.
        public var segment: Int
        public var snapped: Coordinate

        public var isOffRoute: Bool { offsetMeters > RideRoute.offRouteDistance }
    }

    /// Where `position` is along the route. `nil` for a route with fewer than two points.
    /// `after` limits the search to segments from that index on, so a route that doubles back
    /// (hairpins) doesn't snap the rider to the wrong leg.
    public func progress(at position: Coordinate, after segmentHint: Int = 0) -> Progress? {
        guard coordinates.count > 1 else { return nil }
        var best: Progress?
        for index in max(0, min(segmentHint, coordinates.count - 2))..<(coordinates.count - 1) {
            let a = coordinates[index], b = coordinates[index + 1]
            let (point, fraction) = Self.project(position, ontoSegmentFrom: a, to: b)
            let offset = point.distance(to: position)
            if best == nil || offset < best!.offsetMeters {
                let along = cumulative[index] + a.distance(to: b) * fraction
                best = Progress(remainingMeters: max(0, (cumulative.last ?? 0) - along), offsetMeters: offset,
                                segment: index, snapped: point)
            }
        }
        // The polyline's own length can differ slightly from Google's distance; scale to Google's.
        if var result = best, let length = cumulative.last, length > 0 {
            result.remainingMeters *= distanceMeters / length
            return result
        }
        return best
    }

    /// The part of the route still ahead of `progress`: drawn ahead of the rider.
    public func ahead(of progress: Progress) -> [Coordinate] {
        [progress.snapped] + coordinates[(progress.segment + 1)...]
    }

    /// Time left, assuming the rest of the ride goes at the route's average pace.
    public func remainingSeconds(for progress: Progress) -> Double {
        distanceMeters > 0 ? durationSeconds * progress.remainingMeters / distanceMeters : 0
    }

    /// Closest point on segment a→b, using a local flat projection (fine at segment scale).
    static func project(_ p: Coordinate, ontoSegmentFrom a: Coordinate, to b: Coordinate) -> (Coordinate, Double) {
        let lonScale = cos(a.latitude * .pi / 180)
        let ax = a.longitude * lonScale, ay = a.latitude
        let bx = b.longitude * lonScale, by = b.latitude
        let px = p.longitude * lonScale, py = p.latitude
        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (a, 0) }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
        return (a.interpolated(to: b, fraction: t), t)
    }
}

/// Google's Routes API: building the request and reading the answer. Pure, tested without network.
public enum GoogleRoutes {
    public static let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
    static let fieldMask = "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline"

    /// A two-wheeler route (motorcycles and scooters, where Google supports it, as in India).
    public static func request(from origin: Coordinate, to destination: Coordinate,
                               apiKey: String, bundleID: String, languageCode: String = "en") -> URLRequest {
        func waypoint(_ c: Coordinate) -> [String: Any] {
            ["location": ["latLng": ["latitude": c.latitude, "longitude": c.longitude]]]
        }
        let body: [String: Any] = [
            "origin": waypoint(origin),
            "destination": waypoint(destination),
            "travelMode": "TWO_WHEELER",
            "languageCode": languageCode,
            "units": "METRIC",
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    /// The first route in a response, or `nil` when Google found none (`{}`).
    public static func route(from data: Data) throws -> RideRoute? {
        struct Response: Decodable {
            struct Route: Decodable {
                struct Polyline: Decodable { var encodedPolyline: String? }
                var distanceMeters: Double?
                var duration: String?
                var polyline: Polyline?
            }
            var routes: [Route]?
        }
        guard let first = try JSONDecoder().decode(Response.self, from: data).routes?.first,
              let encoded = first.polyline?.encodedPolyline else { return nil }
        let coordinates = Polyline.decode(encoded)
        guard coordinates.count > 1 else { return nil }
        // Durations come as "5418s".
        let seconds = first.duration.flatMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) } ?? 0
        let route = RideRoute(coordinates: coordinates, distanceMeters: 0, durationSeconds: seconds)
        return RideRoute(coordinates: coordinates, distanceMeters: first.distanceMeters ?? route.cumulative.last ?? 0,
                         durationSeconds: seconds)
    }
}

/// Google's encoded polyline format (precision 5).
/// https://developers.google.com/maps/documentation/utilities/polylinealgorithm
public enum Polyline {
    public static func decode(_ encoded: String) -> [Coordinate] {
        var coordinates: [Coordinate] = []
        let bytes = Array(encoded.utf8)
        var index = 0, lat = 0, lon = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while index < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            coordinates.append(Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return coordinates
    }

    public static func encode(_ coordinates: [Coordinate]) -> String {
        var output = ""
        var lastLat = 0, lastLon = 0
        func append(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : (value << 1)
            while v >= 0x20 {
                output.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1F)) + 63)))
                v >>= 5
            }
            output.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
        }
        for c in coordinates {
            let lat = Int((c.latitude * 1e5).rounded()), lon = Int((c.longitude * 1e5).rounded())
            append(lat - lastLat); append(lon - lastLon)
            lastLat = lat; lastLon = lon
        }
        return output
    }
}
