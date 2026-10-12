import Foundation
import RideKit
import SwiftData

/// A reference to a photo or video in the Photos library. The media itself is never copied.
@Model
final class MediaLink {
    var id: UUID = UUID()
    /// `PHAsset.localIdentifier` on the device that created the link.
    var localIdentifier: String = ""
    /// `PHCloudIdentifier.stringValue`, stable across the user's devices with iCloud Photos.
    var cloudIdentifier: String?
    var kindRaw: String = MediaCandidate.Kind.photo.rawValue
    var capturedAt: Date = Date.now
    var latitude: Double?
    var longitude: Double?
    /// The rider placed this item by hand; automatic matching won't move it.
    var isManual: Bool = false

    var spot: Spot?
    var ride: Ride?

    init(candidate: MediaCandidate, cloudIdentifier: String?) {
        self.localIdentifier = candidate.id
        self.cloudIdentifier = cloudIdentifier
        self.kindRaw = candidate.kind.rawValue
        self.capturedAt = candidate.capturedAt
        self.latitude = candidate.coordinate?.latitude
        self.longitude = candidate.coordinate?.longitude
    }

    var kind: MediaCandidate.Kind { MediaCandidate.Kind(rawValue: kindRaw) ?? .photo }

    var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    var isVideo: Bool { kind == .video || kind == .screenRecording }
}
