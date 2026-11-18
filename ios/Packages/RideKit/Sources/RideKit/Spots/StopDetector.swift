import Foundation

/// A period during a ride when the rider was stationary.
public struct Stop: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var center: Coordinate

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public enum StopDetector {
    /// Slower than this (m/s ≈ 5 km/h) counts as stopped.
    public static let stopSpeed = 1.39
    /// Stopped for at least this long (s) counts as a real stop, not a red light.
    public static let minimumDuration: TimeInterval = 120

    public static func stops(
        in points: [TrackPoint],
        minimumDuration: TimeInterval = minimumDuration
    ) -> [Stop] {
        var result: [Stop] = []
        var run: [TrackPoint] = []

        func flush() {
            defer { run.removeAll() }
            guard let first = run.first, let last = run.last,
                  last.timestamp.timeIntervalSince(first.timestamp) >= minimumDuration else { return }
            let lat = run.map(\.coordinate.latitude).reduce(0, +) / Double(run.count)
            let lon = run.map(\.coordinate.longitude).reduce(0, +) / Double(run.count)
            result.append(Stop(start: first.timestamp, end: last.timestamp, center: Coordinate(latitude: lat, longitude: lon)))
        }

        for (index, point) in points.enumerated() {
            let speed: Double
            if let reported = point.speed, reported >= 0 {
                speed = reported
            } else if index > 0 {
                let previous = points[index - 1]
                let dt = point.timestamp.timeIntervalSince(previous.timestamp)
                speed = dt > 0 ? point.coordinate.distance(to: previous.coordinate) / dt : 0
            } else {
                speed = 0
            }
            if speed < stopSpeed {
                run.append(point)
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}
