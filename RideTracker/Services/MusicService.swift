import Foundation
import MediaPlayer
import RideKit

/// Reads what the Music app is playing, to build a ride's soundtrack.
///
/// Uses MediaPlayer's system music player, which needs only the "Apple Music" permission
/// (no MusicKit entitlement, so it works with free Personal Team builds too). Only the Music app
/// is visible: other apps (Spotify, YouTube Music, …) don't share what they play.
@MainActor
final class MusicService {
    private let player = MPMusicPlayerController.systemMusicPlayer

    var authorizationStatus: MPMediaLibraryAuthorizationStatus { MPMediaLibrary.authorizationStatus() }

    @discardableResult
    func requestAccess() async -> MPMediaLibraryAuthorizationStatus {
        await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    /// The current song and whether it's actually playing (not paused).
    func nowPlaying() -> (song: NowPlayingSong?, isPlaying: Bool) {
        guard authorizationStatus == .authorized, let item = player.nowPlayingItem else { return (nil, false) }
        let storeID = item.playbackStoreID
        let title = item.title ?? "Unknown song"
        let artist = item.artist ?? ""
        // Streaming items can have no persistent ID; fall back to the catalog ID, then the name.
        let id = item.persistentID != 0 ? String(item.persistentID)
            : (!storeID.isEmpty && storeID != "0" ? storeID : "\(title)|\(artist)")
        let song = NowPlayingSong(
            id: id,
            title: title,
            artist: artist,
            album: item.albumTitle ?? "",
            storeID: storeID.isEmpty || storeID == "0" ? nil : storeID,
            duration: item.playbackDuration > 0 ? item.playbackDuration : nil
        )
        return (song, player.playbackState == .playing)
    }
}
