import Foundation

/// A song as reported by the music player (mapped from `MPMediaItem` in the app).
public struct NowPlayingSong: Hashable, Sendable {
    /// Stable identity for "is this still the same song": the player's persistent ID.
    public var id: String
    public var title: String
    public var artist: String
    public var album: String
    /// Apple Music catalog ID, when the song is from Apple Music (used for links).
    public var storeID: String?
    /// Track length in seconds, if known.
    public var duration: TimeInterval?

    public init(id: String, title: String, artist: String = "", album: String = "",
                storeID: String? = nil, duration: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.storeID = storeID
        self.duration = duration
    }
}

/// One song the rider actually listened to during a ride.
public struct SongPlay: Equatable, Sendable {
    public var song: NowPlayingSong
    public var startedAt: Date
    public var listenedSeconds: TimeInterval

    public init(song: NowPlayingSong, startedAt: Date, listenedSeconds: TimeInterval) {
        self.song = song
        self.startedAt = startedAt
        self.listenedSeconds = listenedSeconds
    }
}

/// Turns periodic "what's playing?" samples into the list of songs listened to.
///
/// - Only time while the player is actually **playing** counts.
/// - A song counts once listened to for 30 s, or half its length for very short tracks. Quick
///   skips don't count.
/// - Playing the same song again later (after another song) is a separate play.
/// - Pausing and resuming the same song continues the same play.
public struct SongLog: Sendable {
    public static let minimumListen: TimeInterval = 30
    /// Gaps between samples longer than this aren't counted as listening (e.g. the app was suspended).
    public static let maximumSampleGap: TimeInterval = 15

    private var current: SongPlay?
    private var lastSampleAt: Date?
    private var lastWasPlaying = false

    public init() {}

    /// Feeds one sample. Returns a play that just finished and qualifies, if any.
    @discardableResult
    public mutating func observe(_ song: NowPlayingSong?, isPlaying: Bool, at time: Date) -> SongPlay? {
        defer {
            lastSampleAt = time
            lastWasPlaying = isPlaying && song != nil
        }

        // Credit the time since the previous sample to the song that was playing then.
        if var play = current, lastWasPlaying, let last = lastSampleAt {
            let gap = time.timeIntervalSince(last)
            if gap > 0, gap <= Self.maximumSampleGap {
                play.listenedSeconds += gap
                current = play
            }
        }

        guard let song else { return nil }       // nothing playing: keep the current play open
        if current?.song.id == song.id { return nil }

        let finished = finishCurrent()
        current = SongPlay(song: song, startedAt: time, listenedSeconds: 0)
        return finished
    }

    /// Ends the log (ride ended). Returns the last play if it qualifies.
    public mutating func finish(at time: Date) -> SongPlay? {
        observe(nil, isPlaying: false, at: time)
        let finished = finishCurrent()
        current = nil
        return finished
    }

    /// The song playing right now, once it already qualifies (for showing it live).
    public var qualifiedCurrent: SongPlay? {
        guard let current, Self.qualifies(current) else { return nil }
        return current
    }

    public static func qualifies(_ play: SongPlay) -> Bool {
        let needed = min(minimumListen, (play.song.duration ?? .infinity) / 2)
        return play.listenedSeconds >= needed
    }

    private mutating func finishCurrent() -> SongPlay? {
        guard let play = current else { return nil }
        current = nil
        return Self.qualifies(play) ? play : nil
    }
}

public enum AppleMusicLink {
    /// Opens the song in Apple Music when it has a catalog ID, otherwise a search for it.
    public static func url(for song: NowPlayingSong) -> URL? {
        if let id = song.storeID, !id.isEmpty, id != "0", id.allSatisfy(\.isNumber) {
            return URL(string: "https://music.apple.com/song/\(id)")
        }
        var components = URLComponents(string: "https://music.apple.com/search")!
        components.queryItems = [URLQueryItem(name: "term", value: [song.title, song.artist].filter { !$0.isEmpty }.joined(separator: " "))]
        return components.url
    }

    /// "1. Title — Artist" lines, for sharing a ride's soundtrack as text.
    public static func shareText(rideName: String, songs: [NowPlayingSong]) -> String {
        let lines = songs.enumerated().map { index, song in
            "\(index + 1). \(song.title)\(song.artist.isEmpty ? "" : " — \(song.artist)")"
        }
        return (["🎵 Soundtrack of “\(rideName)”"] + lines).joined(separator: "\n")
    }
}
