import Foundation

/// A ride told as a trail: **stops** (where photos were taken or spots marked) joined by **legs**
/// of road, in the order they happened.
///
/// ```
/// start ─ leg ─ stop ─ leg ─ stop ─ leg ─ end
/// ```
/// `legs.count == stops.count + 1`: the leg before each stop, plus the leg after the last one.
public struct Trail: Equatable, Sendable {
    public var stops: [Stop]
    public var legs: [Leg]

    public struct Stop: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable {
            /// A saved spot.
            case spot(UUID)
            /// Photos taken together away from any spot. The app suggests a name and offers "Save as spot".
            case cluster
        }

        /// Stable across rebuilds: the spot's UUID, or the cluster's first media ID.
        public var id: String
        public var kind: Kind
        public var coordinate: Coordinate
        public var arrivedAt: Date
        public var departedAt: Date
        /// Meters along the route from the start, `nil` without a track.
        public var distanceFromStart: Double?
        /// Media IDs, oldest first.
        public var mediaIDs: [String]
    }

    public struct Leg: Equatable, Sendable {
        public var start: Date
        public var end: Date
        /// Meters ridden on this leg, `nil` without a track.
        public var distance: Double?
        /// Photos with no location that weren't taken at a stop: "on the road".
        public var mediaIDs: [String]
        /// Songs that started on this leg (IDs as passed in).
        public var songIDs: [String]

        public var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// A photo or video of the ride, reduced to what the trail needs.
    public struct Media: Hashable, Sendable {
        public var id: String
        public var capturedAt: Date
        public var coordinate: Coordinate?
        /// The spot it's attached to, if any (see `MediaPlacer`).
        public var spotID: UUID?

        public init(id: String, capturedAt: Date, coordinate: Coordinate? = nil, spotID: UUID? = nil) {
            self.id = id
            self.capturedAt = capturedAt
            self.coordinate = coordinate
            self.spotID = spotID
        }
    }

    /// A spot that should appear on the trail even without photos (e.g. marked while riding).
    public struct Spot: Hashable, Sendable {
        public var id: UUID
        public var coordinate: Coordinate
        public var markedAt: Date

        public init(id: UUID, coordinate: Coordinate, markedAt: Date) {
            self.id = id
            self.coordinate = coordinate
            self.markedAt = markedAt
        }
    }

    /// Photos within this distance of a cluster's first photo belong to the same stop.
    public static let clusterRadius: Double = MediaPlacer.defaultSpotRadius
    /// A longer gap between photos starts a new stop, even at the same place.
    public static let clusterGap: TimeInterval = 10 * 60
    /// A photo without location joins a stop if taken this close to it in time.
    public static let stopTimeSlack: TimeInterval = 10 * 60

    public static func build(
        rideStart: Date,
        rideEnd: Date,
        track: [TrackPoint],
        media: [Media],
        spots: [Spot],
        songs: [(id: String, startedAt: Date)] = []
    ) -> Trail {
        let odometer = Odometer(track: track)
        let sortedMedia = media.sorted { ($0.capturedAt, $0.id) < ($1.capturedAt, $1.id) }

        // 1. Spot stops: every spot that has photos here or was marked on this ride.
        var spotStops: [UUID: Stop] = [:]
        for spot in spots {
            spotStops[spot.id] = Stop(id: spot.id.uuidString, kind: .spot(spot.id), coordinate: spot.coordinate,
                                      arrivedAt: spot.markedAt, departedAt: spot.markedAt, distanceFromStart: nil, mediaIDs: [])
        }
        var unlocated: [Media] = []
        var clusters: [Stop] = []
        for item in sortedMedia {
            // Spots should all be passed in; one that wasn't is placed at its first photo.
            if let spotID = item.spotID, let coordinate = spotStops[spotID]?.coordinate ?? item.coordinate {
                var stop = spotStops[spotID] ?? Stop(
                    id: spotID.uuidString, kind: .spot(spotID), coordinate: coordinate,
                    arrivedAt: item.capturedAt, departedAt: item.capturedAt, distanceFromStart: nil, mediaIDs: []
                )
                stop.include(item)
                spotStops[spotID] = stop
            } else if let coordinate = item.coordinate, coordinate.isValid {
                // 2. Clusters: photos close in place and time, away from any spot.
                if var last = clusters.last,
                   last.coordinate.distance(to: coordinate) <= clusterRadius,
                   item.capturedAt.timeIntervalSince(last.departedAt) <= clusterGap {
                    last.include(item)
                    clusters[clusters.count - 1] = last
                } else {
                    clusters.append(Stop(id: item.id, kind: .cluster, coordinate: coordinate, arrivedAt: item.capturedAt,
                                         departedAt: item.capturedAt, distanceFromStart: nil, mediaIDs: [item.id]))
                }
            } else {
                unlocated.append(item)
            }
        }

        var stops = (Array(spotStops.values) + clusters).sorted { ($0.arrivedAt, $0.id) < ($1.arrivedAt, $1.id) }

        // 3. Photos without location: into the stop closest in time, if close enough.
        var onTheRoad: [Media] = []
        for item in unlocated {
            let nearest = stops.indices.min { stops[$0].timeDistance(to: item.capturedAt) < stops[$1].timeDistance(to: item.capturedAt) }
            if let nearest, stops[nearest].timeDistance(to: item.capturedAt) <= stopTimeSlack {
                stops[nearest].mediaIDs.append(item.id)
            } else {
                onTheRoad.append(item)
            }
        }
        for index in stops.indices {
            stops[index].distanceFromStart = odometer.distance(at: stops[index].arrivedAt)
        }

        // 4. Legs: the road before each stop, and after the last one.
        let start = min(track.first?.timestamp ?? rideStart, rideStart)
        let end = max(track.last?.timestamp ?? rideEnd, rideEnd)
        var boundaries: [(start: Date, end: Date)] = []
        var cursor = start
        for stop in stops {
            boundaries.append((cursor, max(cursor, stop.arrivedAt)))
            cursor = max(cursor, stop.departedAt)
        }
        boundaries.append((cursor, max(cursor, end)))

        var legs = boundaries.map { bounds in
            Leg(start: bounds.start, end: bounds.end, distance: odometer.distance(from: bounds.start, to: bounds.end),
                mediaIDs: [], songIDs: [])
        }
        // Something that happened at or after a leg's start belongs to the last such leg.
        func legIndex(at date: Date) -> Int {
            legs.lastIndex { $0.start <= date } ?? 0
        }
        for item in onTheRoad { legs[legIndex(at: item.capturedAt)].mediaIDs.append(item.id) }
        for song in songs.sorted(by: { $0.startedAt < $1.startedAt }) { legs[legIndex(at: song.startedAt)].songIDs.append(song.id) }

        return Trail(stops: stops, legs: legs)
    }
}

private extension Trail.Stop {
    mutating func include(_ item: Trail.Media) {
        arrivedAt = min(arrivedAt, item.capturedAt)
        departedAt = max(departedAt, item.capturedAt)
        mediaIDs.append(item.id)
    }

    func timeDistance(to date: Date) -> TimeInterval {
        if date < arrivedAt { return arrivedAt.timeIntervalSince(date) }
        if date > departedAt { return date.timeIntervalSince(departedAt) }
        return 0
    }
}

/// Distance ridden up to any moment of the ride.
struct Odometer {
    private let times: [Date]
    private let cumulative: [Double]

    init(track: [TrackPoint]) {
        var total = 0.0
        var cumulative: [Double] = []
        cumulative.reserveCapacity(track.count)
        for (index, point) in track.enumerated() {
            if index > 0 { total += track[index - 1].coordinate.distance(to: point.coordinate) }
            cumulative.append(total)
        }
        self.times = track.map(\.timestamp)
        self.cumulative = cumulative
    }

    /// Meters ridden by `date`, interpolated between fixes and clamped to the track. `nil` without a track.
    func distance(at date: Date) -> Double? {
        guard let first = times.first, let last = times.last else { return nil }
        if date <= first { return 0 }
        if date >= last { return cumulative[cumulative.count - 1] }
        var low = 0, high = times.count - 1
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < date { low = mid + 1 } else { high = mid }
        }
        let span = times[low].timeIntervalSince(times[low - 1])
        let fraction = span > 0 ? date.timeIntervalSince(times[low - 1]) / span : 1
        return cumulative[low - 1] + (cumulative[low] - cumulative[low - 1]) * fraction
    }

    func distance(from start: Date, to end: Date) -> Double? {
        guard let a = distance(at: start), let b = distance(at: end) else { return nil }
        return max(0, b - a)
    }
}
