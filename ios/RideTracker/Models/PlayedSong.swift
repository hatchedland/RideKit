import Foundation
import RideKit
import SwiftData

/// A song from Apple Music that was played during a ride (listened to for at least 30 s).
@Model
final class PlayedSong {
    var id: UUID = UUID()
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    /// Apple Music catalog ID; empty for songs that aren't in the Apple Music catalog.
    var storeID: String = ""
    var startedAt: Date = Date.now
    var listenedSeconds: Double = 0
    /// Where the rider was when the song started.
    var latitude: Double?
    var longitude: Double?

    var ride: Ride?

    init(play: SongPlay, at coordinate: Coordinate?) {
        self.title = play.song.title
        self.artist = play.song.artist
        self.album = play.song.album
        self.storeID = play.song.storeID ?? ""
        self.startedAt = play.startedAt
        self.listenedSeconds = play.listenedSeconds
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
    }

    var song: NowPlayingSong {
        NowPlayingSong(id: storeID.isEmpty ? "\(title)|\(artist)" : storeID, title: title, artist: artist,
                       album: album, storeID: storeID.isEmpty ? nil : storeID)
    }

    var appleMusicURL: URL? { AppleMusicLink.url(for: song) }
}
