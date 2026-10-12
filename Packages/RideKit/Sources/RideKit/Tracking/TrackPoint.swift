import Foundation

/// One accepted GPS fix of a ride.
public struct TrackPoint: Hashable, Sendable, Codable {
    public var timestamp: Date
    public var coordinate: Coordinate
    /// Meters above sea level, `nil` if unknown.
    public var altitude: Double?
    /// Meters per second as reported by GPS, `nil` if unknown.
    public var speed: Double?
    /// Degrees from true north, `nil` if unknown.
    public var course: Double?
    /// Horizontal accuracy radius in meters.
    public var horizontalAccuracy: Double
    /// Lean angle in degrees (negative = left), `nil` when not measured.
    public var lean: Double?

    public init(
        timestamp: Date,
        coordinate: Coordinate,
        altitude: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        horizontalAccuracy: Double = 5,
        lean: Double? = nil
    ) {
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.altitude = altitude
        self.speed = speed
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
        self.lean = lean
    }
}

public extension Array where Element == TrackPoint {
    /// Where the rider was at `date`, interpolated between the surrounding fixes.
    /// `nil` if `date` is outside the track or falls in a gap longer than `maxGap` seconds.
    func coordinate(at date: Date, maxGap: TimeInterval = 120) -> Coordinate? {
        guard let first, let last, date >= first.timestamp, date <= last.timestamp else { return nil }
        // Binary search for the first point at or after `date`.
        var low = 0, high = count - 1
        while low < high {
            let mid = (low + high) / 2
            if self[mid].timestamp < date { low = mid + 1 } else { high = mid }
        }
        let after = self[low]
        if after.timestamp == date || low == 0 { return after.coordinate }
        let before = self[low - 1]
        let span = after.timestamp.timeIntervalSince(before.timestamp)
        guard span <= maxGap else { return nil }
        let fraction = date.timeIntervalSince(before.timestamp) / span
        return before.coordinate.interpolated(to: after.coordinate, fraction: fraction)
    }
}
