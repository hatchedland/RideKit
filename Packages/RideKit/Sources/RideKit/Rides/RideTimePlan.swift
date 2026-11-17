import Foundation

/// How this rider actually rides, learned from their own past rides: how fast they move and how much
/// of a ride they spend stopped (chai, photos, fuel). Google's times assume no stops at all.
public struct RidePace: Sendable, Equatable {
    /// Typical moving speed, `nil` without enough rides to say.
    public var movingSpeedMps: Double?
    /// Share of a ride's elapsed time spent stopped, 0…1.
    public var stopShare: Double
    /// How many rides this is based on (0: the defaults).
    public var rideCount: Int

    public init(movingSpeedMps: Double?, stopShare: Double, rideCount: Int) {
        self.movingSpeedMps = movingSpeedMps
        self.stopShare = stopShare
        self.rideCount = rideCount
    }

    /// Before the app knows the rider: about 10 minutes stopped per hour on the road, the common
    /// touring advice (a short break every hour or ~75 km).
    public static let `default` = RidePace(movingSpeedMps: nil, stopShare: 0.15, rideCount: 0)

    /// Rides shorter than this say little about a day out (a run to the shops, a test ride).
    public static let minimumDistance: Double = 20_000
    public static let minimumMovingSeconds: Double = 20 * 60
    /// Recent rides describe the rider best; older ones are ignored.
    public static let recentRides = 20
    /// Stop shares outside this are a forgotten End button or a non-stop dash; clamp them.
    static let stopShareRange = 0.05...0.45

    public struct Sample: Sendable {
        public var distanceMeters: Double
        public var movingSeconds: Double
        public var elapsedSeconds: Double
        public init(distanceMeters: Double, movingSeconds: Double, elapsedSeconds: Double) {
            self.distanceMeters = distanceMeters
            self.movingSeconds = movingSeconds
            self.elapsedSeconds = elapsedSeconds
        }
    }

    /// Learns the pace from rides, newest first. Speed is distance-weighted (long rides count more);
    /// the stop share is the median, so one lazy lunch doesn't skew it.
    public static func learn(from rides: [Sample]) -> RidePace {
        let usable = rides
            .filter { $0.distanceMeters >= minimumDistance && $0.movingSeconds >= minimumMovingSeconds
                && $0.elapsedSeconds >= $0.movingSeconds }
            .prefix(recentRides)
        guard usable.count >= 2 else { return .default }
        let distance = usable.reduce(0) { $0 + $1.distanceMeters }
        let moving = usable.reduce(0) { $0 + $1.movingSeconds }
        let shares = usable
            .map { 1 - $0.movingSeconds / $0.elapsedSeconds }
            .map { min(max($0, stopShareRange.lowerBound), stopShareRange.upperBound) }
            .sorted()
        let median = shares.count.isMultiple(of: 2)
            ? (shares[shares.count / 2 - 1] + shares[shares.count / 2]) / 2
            : shares[shares.count / 2]
        return RidePace(movingSpeedMps: distance / moving, stopShare: median, rideCount: usable.count)
    }
}

/// "About 4 h 40 with your usual breaks · arrive 3:10 pm · sunset 6:02 pm", and when to leave to
/// arrive in daylight. Worked out before the ride, so nothing new needs looking at while riding.
public struct RideTimePlan: Sendable, Equatable {
    public var departure: Date
    /// Time on the move.
    public var movingSeconds: Double
    /// Time stopped on the way, at the rider's usual rate.
    public var breakSeconds: Double
    public var arrival: Date
    /// Sunset at the destination on the day of arrival; `nil` near the poles or for multi-day rides.
    public var sunset: Date?
    /// Leave by this to arrive `daylightMargin` before sunset; `nil` without a sunset.
    public var latestDeparture: Date?
    public var pace: RidePace

    public var totalSeconds: Double { movingSeconds + breakSeconds }
    public var arrivesAfterDark: Bool { sunset.map { arrival > $0 } ?? false }
    /// Still possible to arrive in daylight by leaving later than now (or right now).
    public var canStillArriveInDaylight: Bool { latestDeparture.map { $0 >= departure } ?? true }

    /// Arriving a little before sunset leaves time to find the stay and park in the light.
    public static let daylightMargin: Double = 20 * 60
    /// Longer than this is more than a day's ride; a single sunset says nothing useful.
    public static let longestDayRide: Double = 14 * 3600
    /// Google's road time is the floor and this times it the ceiling, whatever the rider's history.
    static let slowestFactor = 1.6

    public init(departure: Date, distanceMeters: Double, roadSeconds: Double, destination: Coordinate,
                pace: RidePace) {
        self.departure = departure
        self.pace = pace

        // Google knows the roads; the rider's history knows the rider. Average them, but never call
        // the ride faster than Google's road time or absurdly slower.
        var moving = roadSeconds
        if let speed = pace.movingSpeedMps, speed > 0 {
            let personal = distanceMeters / speed
            moving = min(max((roadSeconds + personal) / 2, roadSeconds), roadSeconds * Self.slowestFactor)
        }
        movingSeconds = moving
        breakSeconds = moving * pace.stopShare / (1 - pace.stopShare)
        arrival = departure.addingTimeInterval(moving + breakSeconds)

        if moving + breakSeconds <= Self.longestDayRide,
           // The day's sunset, taken from the departure (an arrival after midnight would otherwise
           // find the next day's sunset and look like daylight).
           let sunset = Sun.sunset(near: departure, at: destination) {
            self.sunset = sunset
            latestDeparture = sunset.addingTimeInterval(-Self.daylightMargin - moving - breakSeconds)
        } else {
            sunset = nil
            latestDeparture = nil
        }
    }
}
