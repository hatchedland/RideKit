import Foundation

/// Shows the ride as "paused" at red lights and stops, and back to riding when moving again.
///
/// Auto-pause only changes what the live screen shows (and lowers the GPS rate). Recording never
/// stops, and the Photos album window always covers the whole ride.
public struct AutoPauseDetector: Sendable {
    public enum Sensitivity: String, CaseIterable, Sendable, Codable {
        case low, normal, high
    }

    /// Speed (m/s) below which the clock starts counting toward a pause.
    public var stopSpeed: Double
    /// How long (s) the rider must stay below `stopSpeed` before pausing.
    public var stopDuration: TimeInterval
    /// Speed (m/s) above which a paused ride resumes. Higher than `stopSpeed` to avoid flapping.
    public var resumeSpeed: Double

    public private(set) var isPaused = false
    private var slowSince: Date?

    public init(sensitivity: Sensitivity = .normal) {
        switch sensitivity {
        case .low: (stopSpeed, stopDuration, resumeSpeed) = (0.8, 20, 2.5)
        case .normal: (stopSpeed, stopDuration, resumeSpeed) = (1.0, 8, 2.0)
        case .high: (stopSpeed, stopDuration, resumeSpeed) = (1.4, 4, 1.8)
        }
    }

    /// Feeds one speed sample. Returns `true` if the paused state changed.
    @discardableResult
    public mutating func update(speed: Double, at time: Date) -> Bool {
        if isPaused {
            guard speed >= resumeSpeed else { return false }
            isPaused = false
            slowSince = nil
            return true
        }
        guard speed < stopSpeed else {
            slowSince = nil
            return false
        }
        let since = slowSince ?? time
        slowSince = since
        if time.timeIntervalSince(since) >= stopDuration {
            isPaused = true
            return true
        }
        return false
    }
}
