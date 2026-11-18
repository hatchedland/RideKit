import Foundation

public struct RideSummary: Equatable, Sendable {
    public var distanceMeters: Double = 0
    public var durationSeconds: Double = 0
    public var movingSeconds: Double = 0
    public var maxSpeedMps: Double = 0
    public var avgMovingSpeedMps: Double = 0
    public var elevationGainMeters: Double = 0
    public var maxLeanLeftDegrees: Double?
    public var maxLeanRightDegrees: Double?

    public init() {}
}

/// Pure functions that turn a track into ride statistics.
public enum RideStats {
    /// Below this speed (m/s, ≈ 5 km/h) the rider counts as stopped.
    public static let movingSpeedThreshold = 1.4
    /// Altitude must change by this much (m) before it counts, to ignore GPS altitude jitter.
    public static let elevationHysteresis = 3.0
    /// A gap longer than this (s) between fixes is never counted as moving time.
    public static let maxMovingGap: TimeInterval = 300

    public static func summarize(_ points: [TrackPoint]) -> RideSummary {
        var summary = RideSummary()
        guard let first = points.first, let last = points.last else { return summary }
        summary.durationSeconds = last.timestamp.timeIntervalSince(first.timestamp)

        var speeds: [Double] = []
        speeds.reserveCapacity(points.count)

        for (previous, current) in zip(points, points.dropFirst()) {
            let d = previous.coordinate.distance(to: current.coordinate)
            let dt = current.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { continue }
            summary.distanceMeters += d
            if d / dt >= movingSpeedThreshold, dt <= maxMovingGap {
                summary.movingSeconds += dt
            }
            speeds.append(current.speed ?? d / dt)
        }

        // A median-of-3 filter removes single-sample GPS speed spikes before taking the max.
        summary.maxSpeedMps = medianOf3(speeds).max() ?? 0
        summary.avgMovingSpeedMps = summary.movingSeconds > 0 ? summary.distanceMeters / summary.movingSeconds : 0
        summary.elevationGainMeters = elevationGain(points.compactMap(\.altitude))

        let leans = points.compactMap(\.lean)
        if !leans.isEmpty {
            summary.maxLeanLeftDegrees = leans.filter { $0 < 0 }.map(abs).max()
            summary.maxLeanRightDegrees = leans.filter { $0 > 0 }.max()
        }
        return summary
    }

    static func medianOf3(_ values: [Double]) -> [Double] {
        guard values.count >= 3 else { return values }
        return values.indices.map { i in
            let window = values[max(0, i - 1)...min(values.count - 1, i + 1)].sorted()
            return window[window.count / 2]
        }
    }

    static func elevationGain(_ altitudes: [Double]) -> Double {
        guard var reference = altitudes.first else { return 0 }
        var gain = 0.0
        for altitude in altitudes.dropFirst() {
            let delta = altitude - reference
            if delta >= elevationHysteresis {
                gain += delta
                reference = altitude
            } else if delta <= -elevationHysteresis {
                reference = altitude
            }
        }
        return gain
    }
}
