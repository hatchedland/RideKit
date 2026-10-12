import Foundation

/// A Photos library item, reduced to what the ride logic needs (mapped from `PHAsset` in the app).
public struct MediaCandidate: Hashable, Sendable {
    public enum Kind: String, Sendable, Codable {
        case photo, livePhoto, video, screenshot, screenRecording
    }

    /// `PHAsset.localIdentifier`.
    public var id: String
    public var capturedAt: Date
    public var coordinate: Coordinate?
    public var kind: Kind

    public init(id: String, capturedAt: Date, coordinate: Coordinate? = nil, kind: Kind = .photo) {
        self.id = id
        self.capturedAt = capturedAt
        self.coordinate = coordinate
        self.kind = kind
    }
}

/// Which library items belong in a ride's Photos album: everything captured between
/// **Start ride** and **End ride**, pauses included.
public struct RideMediaWindow: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var includeScreenshots: Bool

    /// After a ride ends, keep sweeping for items that reach the library late
    /// (iCloud sync from another device, AirDrop, Live Photo processing).
    public static let lateArrivalPeriod: TimeInterval = 48 * 3600
    /// How far before / after the ride the "forgot to tap Start?" offer looks.
    public static let edgeOfferPeriod: TimeInterval = 30 * 60

    public init(start: Date, end: Date, includeScreenshots: Bool = false) {
        self.start = start
        self.end = max(start, end)
        self.includeScreenshots = includeScreenshots
    }

    public func contains(_ item: MediaCandidate) -> Bool {
        guard item.capturedAt >= start, item.capturedAt <= end else { return false }
        switch item.kind {
        case .photo, .livePhoto, .video: return true
        case .screenshot, .screenRecording: return includeScreenshots
        }
    }

    /// Identifiers to add to the album: in the window and not already in it.
    public func itemsToAdd(from candidates: [MediaCandidate], alreadyInAlbum: Set<String>) -> [String] {
        candidates
            .filter { contains($0) && !alreadyInAlbum.contains($0.id) }
            .sorted { $0.capturedAt < $1.capturedAt }
            .map(\.id)
    }

    /// Whether the late-arrival sweep should still run for a ride that ended at `end`.
    public func needsLateSweep(now: Date) -> Bool {
        now <= end.addingTimeInterval(Self.lateArrivalPeriod)
    }

    /// Items captured just before Start or just after End, offered on the ride summary.
    public func edgeCandidates(from candidates: [MediaCandidate]) -> (before: [MediaCandidate], after: [MediaCandidate]) {
        let widened = RideMediaWindow(
            start: start.addingTimeInterval(-Self.edgeOfferPeriod),
            end: end.addingTimeInterval(Self.edgeOfferPeriod),
            includeScreenshots: includeScreenshots
        )
        let edge = candidates.filter { widened.contains($0) && !contains($0) }
        return (edge.filter { $0.capturedAt < start }, edge.filter { $0.capturedAt > end })
    }
}
