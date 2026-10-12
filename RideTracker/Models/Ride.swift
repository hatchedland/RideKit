import Foundation
import RideKit
import SwiftData

@Model
final class Ride {
    var id: UUID = UUID()
    /// Typed by the rider at Start; also the Photos album name.
    var name: String = ""
    var notes: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date = Date.now

    // Summary is denormalised so lists and stats never decode the track.
    var distanceMeters: Double = 0
    var movingSeconds: Double = 0
    var maxSpeedMps: Double = 0
    var avgMovingSpeedMps: Double = 0
    var elevationGainMeters: Double = 0

    /// The whole track as one compressed blob (`TrackCodec`), synced as a CKAsset.
    @Attribute(.externalStorage) var trackData: Data?

    /// `PHAssetCollection.localIdentifier` of the ride's album in the Photos app.
    var albumLocalIdentifier: String?
    /// Keep sweeping for late-arriving photos until this date (end + 48 h).
    var albumSweepUntil: Date?
    var includeScreenshots: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Spot.ride) var spots: [Spot]? = []
    @Relationship(deleteRule: .cascade, inverse: \MediaLink.ride) var media: [MediaLink]? = []
    /// Songs from Apple Music played during the ride (added in schema V2).
    @Relationship(deleteRule: .cascade, inverse: \PlayedSong.ride) var songs: [PlayedSong]? = []

    init(id: UUID, name: String, startedAt: Date) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = startedAt
    }

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var soundtrack: [PlayedSong] { (songs ?? []).sorted { $0.startedAt < $1.startedAt } }

    var mediaWindow: RideMediaWindow {
        RideMediaWindow(start: startedAt, end: endedAt, includeScreenshots: includeScreenshots)
    }

    /// Decoded track points. Decoding a 2 h ride takes a few milliseconds; callers cache the result.
    func decodedTrack() -> [TrackPoint] {
        guard let trackData else { return [] }
        return (try? TrackCodec.decode(trackData)) ?? []
    }

    func apply(_ summary: RideSummary) {
        distanceMeters = summary.distanceMeters
        movingSeconds = summary.movingSeconds
        maxSpeedMps = summary.maxSpeedMps
        avgMovingSpeedMps = summary.avgMovingSpeedMps
        elevationGainMeters = summary.elevationGainMeters
    }
}
