import Foundation
import Testing
@testable import RideKit

@Suite("Friends: privacy")
struct SharePrivacyTests {
    let home = Fixtures.indiaGate
    /// 10 km heading north from home at 10 m/s.
    let track = Fixtures.track(segments: [(1000, 10)])

    @Test func zoneContainsPointsWithinItsRadius() {
        let zone = PrivacyZone(name: "Home", center: home, radius: 500)
        #expect(zone.contains(Fixtures.north(of: home, meters: 499)))
        #expect(!zone.contains(Fixtures.north(of: home, meters: 501)))
    }

    @Test func endTrimCutsBothEnds() {
        let visible = SharePrivacy(endTrim: 500).redact(track)
        let first = try! #require(visible.first), last = try! #require(visible.last)
        #expect(abs(first.coordinate.distance(to: home) - 500) <= 10)
        #expect(abs(last.coordinate.distance(to: track.last!.coordinate) - 500) <= 10)
    }

    @Test func noTrimAndNoZonesKeepsEverything() {
        #expect(SharePrivacy(endTrim: 0).redact(track) == track)
    }

    @Test func zonesRemoveEveryPointInside() {
        let office = Fixtures.north(of: home, meters: 5_000)
        let privacy = SharePrivacy(zones: [PrivacyZone(name: "Office", center: office, radius: 300)], endTrim: 0)
        let visible = privacy.redact(track)
        #expect(!visible.contains { privacy.hides($0.coordinate) })
        #expect(visible.count < track.count)
        #expect(visible.count > track.count - 70) // ~600 m of 10 m steps removed
    }

    @Test func rideShorterThanBothTrimsSharesNoTrack() {
        let short = Fixtures.track(segments: [(90, 10)]) // 900 m
        #expect(SharePrivacy(endTrim: 500).redact(short).isEmpty)
    }

    @Test func showsHidesPointsNearTheRideEndsOrInZones() {
        let privacy = SharePrivacy(zones: [PrivacyZone(name: "Office", center: Fixtures.north(of: home, meters: 5_000), radius: 300)])
        #expect(!privacy.shows(Fixtures.north(of: home, meters: 200), track: track))
        #expect(privacy.shows(Fixtures.north(of: home, meters: 2_000), track: track))
        #expect(!privacy.shows(Fixtures.north(of: home, meters: 5_100), track: track))
        #expect(!privacy.shows(Fixtures.north(of: home, meters: 9_800), track: track))
    }
}

@Suite("Friends: shared ride")
struct SharedRideTests {
    let home = Fixtures.indiaGate
    let track = Fixtures.track(segments: [(1000, 10)])

    func ride() -> SharedRide {
        SharedRide(
            id: UUID(),
            name: "Murthal run",
            startedAt: Fixtures.start,
            endedAt: Fixtures.start.addingTimeInterval(1000),
            distanceMeters: 10_000,
            stops: [
                .init(id: "gate", name: "", category: "other", coordinate: Fixtures.north(of: home, meters: 100),
                      arrivedAt: Fixtures.start, photoIDs: ["p1"]),
                .init(id: "dhaba", name: "Amrik Sukhdev", category: "food", coordinate: Fixtures.north(of: home, meters: 5_000),
                      arrivedAt: Fixtures.start.addingTimeInterval(500), photoIDs: ["p2"]),
            ],
            songs: [.init(title: "Safarnama", artist: "Lucky Ali", storeID: "123", startedAt: Fixtures.start)],
            photos: [
                .init(id: "p1", capturedAt: Fixtures.start, coordinate: Fixtures.north(of: home, meters: 100)),
                .init(id: "p2", capturedAt: Fixtures.start.addingTimeInterval(500), coordinate: Fixtures.north(of: home, meters: 5_000)),
                .init(id: "p3", capturedAt: Fixtures.start.addingTimeInterval(990), coordinate: Fixtures.north(of: home, meters: 9_900)),
                .init(id: "p4", capturedAt: Fixtures.start.addingTimeInterval(600), coordinate: nil, isVideo: true),
            ]
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let original = ride()
        #expect(try SharedRide.decode(original.encoded()) == original)
    }

    @Test func refusesAFormatFromANewerApp() throws {
        var future = ride()
        future.formatVersion = SharedRide.currentFormatVersion + 1
        #expect(throws: SharedRide.FormatError.newerVersion(SharedRide.currentFormatVersion + 1)) {
            try SharedRide.decode(future.encoded())
        }
    }

    @Test func redactionDropsHiddenStopsTheirPhotosAndHiddenLocations() {
        let redacted = ride().redacted(by: SharePrivacy(), track: track)
        #expect(redacted.stops.map(\.id) == ["dhaba"])
        #expect(redacted.photos.map(\.id) == ["p2", "p3", "p4"])
        #expect(redacted.photos.first { $0.id == "p3" }?.coordinate == nil) // near the end: kept, unpinned
        #expect(redacted.photos.first { $0.id == "p2" }?.coordinate != nil)
        #expect(redacted.songs.count == 1)
    }

    @Test func stopLinksToGoogleMapsAndSongsToAppleMusic() {
        let shared = ride()
        #expect(shared.stops[1].googleMapsURL.absoluteString.hasPrefix("https://www.google.com/maps/search/?api=1&query="))
        #expect(shared.songs[0].appleMusicURL?.absoluteString == "https://music.apple.com/song/123")
    }
}

@Suite("Friends: live ride")
struct LiveRideTests {
    let start = Fixtures.start

    func live(updatedAfter seconds: TimeInterval, paused: Bool = false) -> LiveRide {
        LiveRide(rideID: UUID(), rideName: "Ride", startedAt: start, updatedAt: start.addingTimeInterval(seconds),
                 position: Fixtures.indiaGate, distanceMeters: 1_000, isPaused: paused, path: [Fixtures.indiaGate])
    }

    @Test func statusFollowsTheAgeOfTheLastUpdate() {
        let ride = live(updatedAfter: 3600)
        #expect(ride.status(at: start.addingTimeInterval(3600 + 30)) == .live)
        #expect(ride.status(at: start.addingTimeInterval(3600 + 5 * 60)) == .delayed(minutes: 5))
        #expect(ride.status(at: start.addingTimeInterval(3600 + 11 * 60)) == .noSignal(since: ride.updatedAt))
    }

    @Test func pausedWinsOverDelayedButNotOverNoSignal() {
        let ride = live(updatedAfter: 3600, paused: true)
        #expect(ride.status(at: start.addingTimeInterval(3600 + 5 * 60)) == .paused)
        #expect(ride.status(at: start.addingTimeInterval(3600 + 20 * 60)) == .noSignal(since: ride.updatedAt))
    }

    @Test func expiresTwelveHoursAfterStart() {
        let ride = live(updatedAfter: 60)
        #expect(ride.status(at: start.addingTimeInterval(LiveRide.maximumDuration + 1)) == .expired)
    }

    @Test func roundTripsThroughJSON() throws {
        let ride = live(updatedAfter: 10)
        #expect(try LiveRide.decode(ride.encoded()) == ride)
    }

    @Test func thinningKeepsSpacingAndTheLatestPoint() {
        let points = Fixtures.track(segments: [(1000, 10)]).map(\.coordinate) // a point every 10 m
        let thinned = LiveRide.thinned(points, spacing: 45, limit: 1_000) // every 5th point
        #expect(thinned.count == 201)
        #expect(thinned.last == points.last)
        #expect(LiveRide.thinned([]).isEmpty)
    }

    @Test func thinningCapsThePointCount() {
        let points = Fixtures.track(segments: [(5000, 10)]).map(\.coordinate)
        let thinned = LiveRide.thinned(points, spacing: 10, limit: 100)
        #expect(thinned.count == 100)
        #expect(thinned.first == points.first)
        #expect(thinned.last == points.last)
    }
}

@Suite("Friends: live publish throttle")
struct LivePublishThrottleTests {
    let start = Fixtures.start
    let here = Fixtures.indiaGate

    @Test func publishesFirstThenEveryInterval() {
        var throttle = LivePublishThrottle(interval: 60, distance: 1_000, minimumInterval: 15)
        let r1 = throttle.shouldPublish(at: start, position: here, isPaused: false)
        #expect(r1)
        let r2 = throttle.shouldPublish(at: start.addingTimeInterval(30), position: here, isPaused: false)
        #expect(!r2)
        let r3 = throttle.shouldPublish(at: start.addingTimeInterval(60), position: here, isPaused: false)
        #expect(r3)
    }

    @Test func publishesEarlyAfterDistanceOrPauseChange() {
        var throttle = LivePublishThrottle(interval: 60, distance: 1_000, minimumInterval: 15)
        _ = throttle.shouldPublish(at: start, position: here, isPaused: false)
        let r4 = throttle.shouldPublish(at: start.addingTimeInterval(20), position: Fixtures.north(of: here, meters: 1_200), isPaused: false)
        #expect(r4)
        let r5 = throttle.shouldPublish(at: start.addingTimeInterval(40), position: Fixtures.north(of: here, meters: 1_200), isPaused: true)
        #expect(r5)
    }

    @Test func neverMoreOftenThanTheMinimum() {
        var throttle = LivePublishThrottle(interval: 60, distance: 1_000, minimumInterval: 15)
        _ = throttle.shouldPublish(at: start, position: here, isPaused: false)
        let r6 = throttle.shouldPublish(at: start.addingTimeInterval(5), position: here, isPaused: true)
        #expect(!r6)
        throttle.reset()
        let r7 = throttle.shouldPublish(at: start.addingTimeInterval(6), position: here, isPaused: true)
        #expect(r7)
    }
}
