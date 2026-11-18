import Foundation

/// Running ride statistics, updated in O(1) per fix for the live screen and Live Activity.
///
/// Uses the same rules as `RideStats.summarize`, which remains the source of truth for the saved ride.
public struct LiveRideStats: Equatable, Sendable {
    public private(set) var distanceMeters: Double = 0
    public private(set) var movingSeconds: Double = 0
    public private(set) var maxSpeedMps: Double = 0
    public private(set) var currentSpeedMps: Double = 0
    public private(set) var pointCount = 0

    private var last: TrackPoint?
    private var recentSpeeds: [Double] = []

    public init() {}

    public var avgMovingSpeedMps: Double {
        movingSeconds > 0 ? distanceMeters / movingSeconds : 0
    }

    public mutating func add(_ point: TrackPoint) {
        defer {
            last = point
            pointCount += 1
        }
        guard let last else {
            currentSpeedMps = max(0, point.speed ?? 0)
            return
        }
        let dt = point.timestamp.timeIntervalSince(last.timestamp)
        guard dt > 0 else { return }
        let d = last.coordinate.distance(to: point.coordinate)
        distanceMeters += d
        if d / dt >= RideStats.movingSpeedThreshold, dt <= RideStats.maxMovingGap {
            movingSeconds += dt
        }
        let speed = point.speed ?? d / dt
        currentSpeedMps = max(0, speed)

        // Same median-of-3 spike filter as RideStats, applied to the middle of the last three samples.
        recentSpeeds.append(speed)
        if recentSpeeds.count > 3 { recentSpeeds.removeFirst() }
        let filtered = recentSpeeds.count == 3 ? recentSpeeds.sorted()[1] : recentSpeeds.min() ?? 0
        maxSpeedMps = max(maxSpeedMps, filtered)
    }

    /// Breaks the distance chain, e.g. after a manual pause, so the gap isn't counted as riding.
    public mutating func breakSegment() {
        last = nil
        recentSpeeds.removeAll()
    }
}
