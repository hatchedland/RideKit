import RideKit
import SwiftUI

/// The ride's songs live on the trail (each where it played). This is the one action for all of
/// them: save the soundtrack as an Apple Music playlist and open it in the Music app.
struct SoundtrackSection: View {
    let ride: Ride
    @Environment(\.openURL) private var openURL
    @State private var saving = false
    @State private var message: String?

    private let music = MusicService()

    var body: some View {
        let songs = ride.soundtrack
        if !songs.isEmpty {
            Section {
                HStack(spacing: 12) {
                    Button(action: open) {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.title3)
                                .foregroundStyle(Brand.asphalt)
                                .frame(width: 40, height: 40)
                                .background(Brand.highwayYellow, in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open soundtrack in Apple Music").font(.headline).foregroundStyle(.primary)
                                Text(message ?? "\(songs.count) songs, saved as a playlist")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if saving { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .accessibilityHint("Saves this ride's songs as a playlist and opens the Music app")

                    ShareLink(item: AppleMusicLink.shareText(rideName: ride.name, songs: songs.map(\.song))) {
                        Image(systemName: "square.and.arrow.up").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Share the song list")
                }
            } footer: {
                Text("Songs you played in the Music app for at least 30 seconds. They're on the trail where they played.")
            }
        }
    }

    private func open() {
        let songs = ride.soundtrack
        let catalog = songs.map(\.storeID).filter { !$0.isEmpty }
        saving = true
        Task {
            defer { saving = false }
            do {
                let count = try await music.savePlaylist(rideID: ride.id, name: ride.name, storeIDs: catalog)
                let skipped = songs.count - catalog.count
                message = skipped > 0
                    ? "\(count) songs in “Ride Tracker · \(ride.name)” · \(skipped) not in Apple Music"
                    : "In your library as “Ride Tracker · \(ride.name)”"
                openURL(URL(string: "music://")!)
            } catch MusicService.PlaylistError.notAllowed {
                message = "Allow Media & Apple Music for Ride Tracker in Settings to save playlists."
            } catch {
                message = "Couldn't save the playlist. Try again."
            }
        }
    }
}
