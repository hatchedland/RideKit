import Foundation
import Testing
@testable import RideKit

@Suite("Song log")
struct SongLogTests {
    let a = NowPlayingSong(id: "A", title: "Kun Faya Kun", artist: "A. R. Rahman", storeID: "1440829396", duration: 470)
    let b = NowPlayingSong(id: "B", title: "Safarnama", artist: "Lucky Ali", duration: 300)
    let jingle = NowPlayingSong(id: "J", title: "Jingle", duration: 20)

    func t(_ seconds: Double) -> Date { Fixtures.start.addingTimeInterval(seconds) }

    /// Samples every 5 s from `from` to `to` (inclusive).
    func play(_ log: inout SongLog, _ song: NowPlayingSong?, playing: Bool = true, from: Double, to: Double) -> [SongPlay] {
        stride(from: from, through: to, by: 5).compactMap { log.observe(song, isPlaying: playing, at: t($0)) }
    }

    @Test func songsListenedToAreLogged() {
        var log = SongLog()
        var plays = play(&log, a, from: 0, to: 120)
        plays += play(&log, b, from: 125, to: 300)
        if let last = log.finish(at: t(305)) { plays.append(last) }
        #expect(plays.map(\.song.id) == ["A", "B"])
        #expect(plays[0].startedAt == t(0))
        #expect(plays[0].listenedSeconds == 125)
        #expect(plays[1].listenedSeconds == 180)
    }

    @Test func quickSkipsDontCount() {
        var log = SongLog()
        var plays = play(&log, a, from: 0, to: 10)        // skipped after ~10 s
        plays += play(&log, b, from: 15, to: 100)
        if let last = log.finish(at: t(105)) { plays.append(last) }
        #expect(plays.map(\.song.id) == ["B"])
    }

    @Test func pausedTimeDoesntCount() {
        var log = SongLog()
        var plays = play(&log, a, from: 0, to: 15)                  // 15 s listened
        plays += play(&log, a, playing: false, from: 20, to: 200)   // paused at a red light… for a while
        #expect(log.qualifiedCurrent == nil)
        plays += play(&log, a, from: 205, to: 230)                  // resumed: same play continues
        if let last = log.finish(at: t(235)) { plays.append(last) }
        #expect(plays.count == 1)
        #expect(plays.first?.startedAt == t(0))
        // ~15–20 s before the pause + 30 s after resuming, accurate to one 5 s sample
        #expect(plays.first.map { $0.listenedSeconds >= 45 && $0.listenedSeconds <= 50 } == true)
    }

    @Test func replayAfterAnotherSongIsSeparate() {
        var log = SongLog()
        var plays = play(&log, a, from: 0, to: 60)
        plays += play(&log, b, from: 65, to: 130)
        plays += play(&log, a, from: 135, to: 200)
        if let last = log.finish(at: t(205)) { plays.append(last) }
        #expect(plays.map(\.song.id) == ["A", "B", "A"])
    }

    @Test func shortTracksNeedHalfTheirLength() {
        var log = SongLog()
        _ = play(&log, jingle, from: 0, to: 10)   // 15 s ≥ half of 20 s
        #expect(log.finish(at: t(15)).map(\.song.id) == "J")
    }

    @Test func longGapsAreNotListening() {
        var log = SongLog()
        log.observe(a, isPlaying: true, at: t(0))
        log.observe(a, isPlaying: true, at: t(600))   // app was suspended for 10 min
        #expect(log.finish(at: t(605)) == nil)
    }

    @Test func nothingPlaying() {
        var log = SongLog()
        #expect(play(&log, nil, playing: false, from: 0, to: 100).isEmpty)
        #expect(log.finish(at: t(105)) == nil)
    }

    @Test func appleMusicLinks() {
        #expect(AppleMusicLink.url(for: a)?.absoluteString == "https://music.apple.com/song/1440829396")
        let local = NowPlayingSong(id: "L", title: "My Song", artist: "Me", storeID: "0")
        #expect(AppleMusicLink.url(for: local)?.absoluteString == "https://music.apple.com/search?term=My%20Song%20Me")
    }

    @Test func shareText() {
        let text = AppleMusicLink.shareText(rideName: "Murthal run", songs: [a, NowPlayingSong(id: "X", title: "Untitled")])
        #expect(text == "🎵 Soundtrack of “Murthal run”\n1. Kun Faya Kun — A. R. Rahman\n2. Untitled")
    }
}
