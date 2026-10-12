import RideKit
import SwiftUI

/// The songs played in the Music app during a ride. Tap a song to open it in Apple Music.
struct SoundtrackSection: View {
    let ride: Ride
    @Environment(\.openURL) private var openURL

    var body: some View {
        let songs = ride.soundtrack
        if !songs.isEmpty {
            Section {
                ForEach(songs) { song in
                    Button {
                        if let url = song.appleMusicURL { openURL(url) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "music.note")
                                .foregroundStyle(.pink)
                                .frame(width: 28, height: 28)
                                .background(.pink.opacity(0.15), in: .rect(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.body).foregroundStyle(.primary).lineLimit(1)
                                Text([song.artist, song.startedAt.formatted(date: .omitted, time: .shortened)]
                                    .filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward.app").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityHint("Opens in Apple Music")
                }
            } header: {
                HStack {
                    Text("🎵 Soundtrack · \(songs.count) songs")
                    Spacer()
                    ShareLink(item: AppleMusicLink.shareText(rideName: ride.name, songs: songs.map(\.song))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .font(.footnote)
                    .textCase(nil)
                }
            } footer: {
                Text("Songs you played in the Music app for at least 30 seconds during the ride.")
            }
        }
    }
}
