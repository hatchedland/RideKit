import Foundation

/// Decides which raw GPS fixes are good enough to keep.
///
/// Dense city streets, flyovers and tunnels produce wild fixes; dropping them keeps distance,
/// speed and the drawn route honest.
public struct LocationFilter: Sendable {
    public struct Configuration: Sendable {
        /// Reject fixes whose accuracy radius is worse than this (meters).
        public var maxHorizontalAccuracy: Double = 20
        /// Reject fixes older than this when they arrive (seconds); iOS sometimes replays cached fixes.
        public var maxAge: TimeInterval = 10
        /// Reject fixes that imply a jump faster than this from the last kept fix (m/s ≈ 250 km/h).
        public var maxImpliedSpeed: Double = 70

        public init() {}
    }

    public enum Verdict: Equatable, Sendable {
        case accepted
        case rejectedInvalid
        case rejectedInaccurate
        case rejectedStale
        case rejectedOutOfOrder
        case rejectedJump
    }

    public var configuration: Configuration
    public private(set) var lastAccepted: TrackPoint?

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// Evaluates `point`; if accepted, it becomes the new reference for jump detection.
    public mutating func evaluate(_ point: TrackPoint, now: Date = .now) -> Verdict {
        guard point.coordinate.isValid, point.horizontalAccuracy >= 0 else { return .rejectedInvalid }
        guard point.horizontalAccuracy <= configuration.maxHorizontalAccuracy else { return .rejectedInaccurate }
        guard now.timeIntervalSince(point.timestamp) <= configuration.maxAge else { return .rejectedStale }

        if let last = lastAccepted {
            let dt = point.timestamp.timeIntervalSince(last.timestamp)
            guard dt > 0 else { return .rejectedOutOfOrder }
            let implied = point.coordinate.distance(to: last.coordinate) / dt
            guard implied <= configuration.maxImpliedSpeed else { return .rejectedJump }
        }
        lastAccepted = point
        return .accepted
    }

    public mutating func reset() {
        lastAccepted = nil
    }
}
