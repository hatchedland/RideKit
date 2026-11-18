import Foundation

/// A ride in progress as friends see it. The rider's phone republishes it every minute or so
/// while sharing live; friends read it and turn it into a `LiveRide.Status`.
public struct LiveRide: Hashable, Sendable, Codable {
    public var formatVersion: Int = 1
    public var rideID: UUID
    public var rideName: String
    public var startedAt: Date
    /// When the rider's phone last had a fix to report.
    public var updatedAt: Date
    public var position: Coordinate
    public var distanceMeters: Double
    public var isPaused: Bool
    /// The road so far, thinned (see `LiveRide.thinned`). Already privacy-redacted.
    public var path: [Coordinate]

    /// Live sharing switches itself off after this long, even if the ride never ends (crash, forgotten phone).
    public static let maximumDuration: TimeInterval = 12 * 3600
    public static let maximumPathPoints = 400

    public init(rideID: UUID, rideName: String, startedAt: Date, updatedAt: Date, position: Coordinate,
                distanceMeters: Double, isPaused: Bool, path: [Coordinate]) {
        self.rideID = rideID
        self.rideName = rideName
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.position = position
        self.distanceMeters = distanceMeters
        self.isPaused = isPaused
        self.path = path
    }

    public enum Status: Equatable, Sendable {
        /// Updated within the last 2 minutes.
        case live
        /// Paused by the rider or auto-pause (a chai stop).
        case paused
        /// 2–10 minutes old: probably a slow network.
        case delayed(minutes: Int)
        /// No update for over 10 minutes. Common in the hills; shown calmly, never as an alarm.
        case noSignal(since: Date)
        /// Past `maximumDuration`: no longer shown.
        case expired
    }

    public static let liveWindow: TimeInterval = 2 * 60
    public static let delayedWindow: TimeInterval = 10 * 60

    public func status(at now: Date) -> Status {
        if now.timeIntervalSince(startedAt) > Self.maximumDuration { return .expired }
        let age = max(0, now.timeIntervalSince(updatedAt))
        if age > Self.delayedWindow { return .noSignal(since: updatedAt) }
        if isPaused { return .paused }
        if age > Self.liveWindow { return .delayed(minutes: Int(age / 60)) }
        return .live
    }

    public func encoded() throws -> Data { try SharedRide.encoder.encode(self) }

    public static func decode(_ data: Data) throws -> LiveRide {
        try SharedRide.decoder.decode(LiveRide.self, from: data)
    }

    /// Keeps a point only once the rider has moved `spacing` meters from the last kept one, then
    /// evenly drops points to stay under `limit`. The latest point is always kept.
    public static func thinned(_ coordinates: [Coordinate], spacing: Double = 50, limit: Int = maximumPathPoints) -> [Coordinate] {
        guard let last = coordinates.last else { return [] }
        var kept: [Coordinate] = []
        for coordinate in coordinates where kept.last.map({ $0.distance(to: coordinate) >= spacing }) ?? true {
            kept.append(coordinate)
        }
        if kept.last != last { kept.append(last) }
        guard kept.count > limit, limit > 1 else { return kept }
        let step = Double(kept.count - 1) / Double(limit - 1)
        return (0..<limit).map { kept[Int((Double($0) * step).rounded())] }
    }
}

/// Decides when the rider's phone republishes its live position, so friends see a fresh dot without
/// draining the battery or CloudKit's request budget.
public struct LivePublishThrottle: Sendable {
    /// Publish at least this often while moving.
    public var interval: TimeInterval
    /// Publish sooner after riding this far.
    public var distance: Double
    /// Never more often than this, even when paused/resumed in a burst.
    public var minimumInterval: TimeInterval

    private var lastTime: Date?
    private var lastPosition: Coordinate?
    private var lastPaused: Bool?

    public init(interval: TimeInterval = 60, distance: Double = 1_000, minimumInterval: TimeInterval = 15) {
        self.interval = interval
        self.distance = distance
        self.minimumInterval = minimumInterval
    }

    /// Returns `true` (and remembers this publish) if now is a good time to publish.
    public mutating func shouldPublish(at time: Date, position: Coordinate, isPaused: Bool) -> Bool {
        guard let lastTime, let lastPosition else { return record(time, position, isPaused) }
        let elapsed = time.timeIntervalSince(lastTime)
        guard elapsed >= minimumInterval else { return false }
        if isPaused != lastPaused || elapsed >= interval || lastPosition.distance(to: position) >= distance {
            return record(time, position, isPaused)
        }
        return false
    }

    public mutating func reset() {
        lastTime = nil
        lastPosition = nil
        lastPaused = nil
    }

    private mutating func record(_ time: Date, _ position: Coordinate, _ isPaused: Bool) -> Bool {
        lastTime = time
        lastPosition = position
        lastPaused = isPaused
        return true
    }
}
