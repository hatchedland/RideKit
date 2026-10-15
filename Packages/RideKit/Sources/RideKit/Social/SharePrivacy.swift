import Foundation

/// A place the rider never wants to reveal to friends, such as home or work.
public struct PrivacyZone: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var center: Coordinate
    /// Meters.
    public var radius: Double

    public static let defaultRadius: Double = 500

    public init(id: UUID = UUID(), name: String, center: Coordinate, radius: Double = PrivacyZone.defaultRadius) {
        self.id = id
        self.name = name
        self.center = center
        self.radius = radius
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        center.distance(to: coordinate) <= radius
    }
}

/// What friends are allowed to see of a ride: everything inside a privacy zone is removed, and the
/// first and last stretch of every shared ride is cut off so the start and end don't give away
/// where the rider lives.
public struct SharePrivacy: Hashable, Sendable, Codable {
    public var zones: [PrivacyZone]
    /// Meters cut from each end of a shared track. 0 turns it off.
    public var endTrim: Double

    public static let defaultEndTrim: Double = 500

    public init(zones: [PrivacyZone] = [], endTrim: Double = SharePrivacy.defaultEndTrim) {
        self.zones = zones
        self.endTrim = max(0, endTrim)
    }

    /// `true` if a coordinate lies in any privacy zone.
    public func hides(_ coordinate: Coordinate) -> Bool {
        zones.contains { $0.contains(coordinate) }
    }

    /// The part of the track friends may see.
    public func redact(_ track: [TrackPoint]) -> [TrackPoint] {
        let visible = track.filter { !hides($0.coordinate) }
        guard endTrim > 0, visible.count > 1 else { return visible }
        let total = Odometer(track: visible).distance(at: visible[visible.count - 1].timestamp) ?? 0
        guard total > endTrim * 2 else { return [] }

        // Cumulative distance per point, then keep the middle.
        var cumulative = [0.0]
        cumulative.reserveCapacity(visible.count)
        for index in 1..<visible.count {
            cumulative.append(cumulative[index - 1] + visible[index - 1].coordinate.distance(to: visible[index].coordinate))
        }
        return visible.indices.filter { cumulative[$0] >= endTrim && cumulative[$0] <= total - endTrim }.map { visible[$0] }
    }

    /// `true` if a point of the ride may be shown: outside every zone and not near where the ride
    /// started or ended (so a photo at the rider's gate isn't shared even without a zone).
    public func shows(_ coordinate: Coordinate, track: [TrackPoint]) -> Bool {
        guard !hides(coordinate) else { return false }
        guard endTrim > 0 else { return true }
        let ends = [track.first, track.last].compactMap { $0?.coordinate }
        return ends.allSatisfy { $0.distance(to: coordinate) > endTrim }
    }
}
