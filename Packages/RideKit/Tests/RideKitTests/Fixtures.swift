import Foundation
@testable import RideKit

enum Fixtures {
    static let start = Date(timeIntervalSinceReferenceDate: 813_456_000) // a fixed instant for repeatable tests
    static let indiaGate = Coordinate(latitude: 28.612912, longitude: 77.229510)

    /// Meters per degree of latitude for RideKit's earth radius.
    static let metersPerDegreeLat = Coordinate.earthRadius * .pi / 180

    /// `meters` north of `origin`.
    static func north(of origin: Coordinate, meters: Double) -> Coordinate {
        Coordinate(latitude: origin.latitude + meters / metersPerDegreeLat, longitude: origin.longitude)
    }

    /// `meters` east of `origin`.
    static func east(of origin: Coordinate, meters: Double) -> Coordinate {
        let perDegree = metersPerDegreeLat * cos(origin.latitude * .pi / 180)
        return Coordinate(latitude: origin.latitude, longitude: origin.longitude + meters / perDegree)
    }

    /// One fix per second, heading north, following `segments` of (seconds, speed m/s).
    static func track(
        from origin: Coordinate = indiaGate,
        startingAt start: Date = start,
        segments: [(seconds: Int, speed: Double)],
        altitude: ((Int) -> Double)? = nil
    ) -> [TrackPoint] {
        var points: [TrackPoint] = []
        var position = origin
        var t = 0
        points.append(TrackPoint(timestamp: start, coordinate: position, altitude: altitude?(0), speed: segments.first?.speed ?? 0))
        for segment in segments {
            for _ in 0..<segment.seconds {
                t += 1
                position = north(of: position, meters: segment.speed)
                points.append(TrackPoint(
                    timestamp: start.addingTimeInterval(TimeInterval(t)),
                    coordinate: position,
                    altitude: altitude?(t),
                    speed: segment.speed
                ))
            }
        }
        return points
    }
}
