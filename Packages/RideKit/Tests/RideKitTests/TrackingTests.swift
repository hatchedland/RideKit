import Foundation
import Testing
@testable import RideKit

@Suite("Coordinate")
struct CoordinateTests {
    @Test func distanceMatchesKnownValue() {
        // India Gate → Qutub Minar is ~10.7 km as the crow flies.
        let qutub = Coordinate(latitude: 28.524428, longitude: 77.185456)
        #expect(abs(Fixtures.indiaGate.distance(to: qutub) - 10_670) < 150)
    }

    @Test func distanceOfOneDegreeLatitude() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 1, longitude: 0)
        #expect(abs(a.distance(to: b) - 111_195) < 1)
    }

    @Test func validity() {
        #expect(Coordinate(latitude: 90, longitude: 180).isValid)
        #expect(!Coordinate(latitude: 91, longitude: 0).isValid)
        #expect(!Coordinate(latitude: .nan, longitude: 0).isValid)
    }

    @Test func nearestWithinRadius() {
        let spots = [100.0, 40.0, 500.0].map { Fixtures.north(of: Fixtures.indiaGate, meters: $0) }
        let hit = spots.nearest(to: Fixtures.indiaGate, within: 150, by: { $0 })
        #expect(hit.map { abs($0.distance - 40) < 0.5 } == true)
        #expect(spots.nearest(to: Fixtures.indiaGate, within: 30, by: { $0 }) == nil)
    }
}

@Suite("Track codec & buffer")
struct TrackStorageTests {
    @Test func codecRoundTrips() throws {
        var points = Fixtures.track(segments: [(600, 15)], altitude: { 200 + Double($0) * 0.1 })
        points[3].speed = nil
        points[4].lean = -32.5
        points[5].course = 271
        let decoded = try TrackCodec.decode(TrackCodec.encode(points))
        #expect(decoded.count == points.count)
        for (a, b) in zip(points, decoded) {
            #expect(a.timestamp == b.timestamp)
            #expect(a.coordinate == b.coordinate)       // doubles: exact
            #expect(a.speed.map(Float.init) == b.speed.map(Float.init))
            #expect(a.lean.map(Float.init) == b.lean.map(Float.init))
            #expect(abs((a.altitude ?? 0) - (b.altitude ?? 0)) < 0.001)
        }
    }

    @Test func codecCompressesLongRide() throws {
        let twoHours = Fixtures.track(segments: [(7_200, 16)], altitude: { 300 + sin(Double($0) / 60) * 20 })
        let size = try TrackCodec.encode(twoHours).count
        #expect(size < 7_200 * TrackCodec.bytesPerPoint)
        #expect(size < 250_000)
    }

    @Test func codecRejectsGarbage() {
        #expect(throws: TrackCodec.DecodeError.notCompressed) { try TrackCodec.decode(Data([1, 2, 3])) }
    }

    @Test func codecEmptyTrack() throws {
        #expect(try TrackCodec.decode(TrackCodec.encode([])).isEmpty)
    }

    @Test func bufferRecoversAfterCrash() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let ride = ActiveRide(name: "Rishikesh run", startedAt: Fixtures.start)
        let points = Fixtures.track(segments: [(30, 10)])
        do {
            let buffer = TrackBuffer(directory: dir)
            try buffer.begin(ride)
            for p in points { try buffer.append(p) }
            var updated = ride
            updated.albumIdentifier = "ALBUM-1"
            try buffer.updateMetadata(updated)
        } // buffer dropped without `clear()` = app killed

        // Simulate a half-written final record.
        let handle = try FileHandle(forWritingTo: dir.appending(path: "active-ride.points"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 7, count: 13))
        try handle.close()

        let recovered = try #require(TrackBuffer(directory: dir).recover())
        #expect(recovered.ride.name == "Rishikesh run")
        #expect(recovered.ride.albumIdentifier == "ALBUM-1")
        #expect(recovered.ride.startedAt == Fixtures.start)
        #expect(recovered.points == points)
    }

    @Test func bufferClearRemovesRide() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let buffer = TrackBuffer(directory: dir)
        try buffer.begin(ActiveRide(name: "x", startedAt: .now))
        #expect(buffer.hasActiveRide)
        buffer.clear()
        #expect(!buffer.hasActiveRide)
        #expect(buffer.recover() == nil)
    }

    @Test func interpolatesPositionAtTime() {
        let track = Fixtures.track(segments: [(10, 10)])
        let mid = track.coordinate(at: Fixtures.start.addingTimeInterval(4.5))
        let expected = Fixtures.north(of: Fixtures.indiaGate, meters: 45)
        #expect(mid.map { $0.distance(to: expected) < 0.01 } == true)
        #expect(track.coordinate(at: Fixtures.start.addingTimeInterval(-1)) == nil)
        #expect(track.coordinate(at: Fixtures.start.addingTimeInterval(11)) == nil)
    }
}

@Suite("Location filter")
struct LocationFilterTests {
    let now = Fixtures.start.addingTimeInterval(100)

    func fix(_ seconds: Double, _ meters: Double, accuracy: Double = 5) -> TrackPoint {
        TrackPoint(
            timestamp: Fixtures.start.addingTimeInterval(seconds),
            coordinate: Fixtures.north(of: Fixtures.indiaGate, meters: meters),
            horizontalAccuracy: accuracy
        )
    }

    /// Feeds fixes in order and returns each verdict.
    func verdicts(_ fixes: [TrackPoint]) -> [LocationFilter.Verdict] {
        var filter = LocationFilter()
        return fixes.map { filter.evaluate($0, now: now) }
    }

    @Test func acceptsGoodFixes() {
        #expect(verdicts([fix(95, 0), fix(96, 20)]) == [.accepted, .accepted])
    }

    @Test func rejectsBadFixes() {
        let result = verdicts([
            fix(95, 0, accuracy: 65),
            fix(95, 0, accuracy: -1),
            fix(50, 0),
            fix(95, 0),
            fix(95, 5),
            fix(96, 400),   // 400 m in 1 s
            fix(97, 30),    // the rejected jump didn't move the reference
        ])
        #expect(result == [.rejectedInaccurate, .rejectedInvalid, .rejectedStale, .accepted,
                           .rejectedOutOfOrder, .rejectedJump, .accepted])
    }
}

@Suite("Ride stats")
struct RideStatsTests {
    @Test func emptyTrack() {
        #expect(RideStats.summarize([]) == RideSummary())
    }

    @Test func distanceMovingTimeAndAverage() {
        // 10 min at 20 m/s, 3 min stopped, 5 min at 10 m/s.
        let points = Fixtures.track(segments: [(600, 20), (180, 0), (300, 10)])
        let s = RideStats.summarize(points)
        #expect(abs(s.distanceMeters - 15_000) < 5)
        #expect(s.durationSeconds == 1_080)
        #expect(s.movingSeconds == 900)
        #expect(abs(s.avgMovingSpeedMps - 15_000.0 / 900) < 0.01)
        #expect(abs(s.maxSpeedMps - 20) < 0.001)
    }

    @Test func maxSpeedIgnoresSingleSpike() {
        var points = Fixtures.track(segments: [(60, 15)])
        points[30].speed = 60  // one bogus sample
        #expect(abs(RideStats.summarize(points).maxSpeedMps - 15) < 0.001)
    }

    @Test func elevationGainIgnoresJitter() {
        // Climb 100 m with ±1 m noise, then descend.
        let points = Fixtures.track(segments: [(400, 10)], altitude: { t in
            let base = t <= 200 ? Double(t) * 0.5 : 100 - Double(t - 200) * 0.5
            return 500 + base + (t.isMultiple(of: 2) ? 1 : -1)
        })
        let gain = RideStats.summarize(points).elevationGainMeters
        #expect(gain > 95 && gain < 105)
    }

    @Test func leanExtremes() {
        var points = Fixtures.track(segments: [(5, 10)])
        points[1].lean = -20; points[2].lean = 35; points[3].lean = -41; points[4].lean = 12
        let s = RideStats.summarize(points)
        #expect(s.maxLeanLeftDegrees == 41)
        #expect(s.maxLeanRightDegrees == 35)
    }
}

@Suite("Auto-pause")
struct AutoPauseTests {
    /// Feeds (seconds after start, speed) samples and returns whether each one changed the state.
    func changes(_ detector: inout AutoPauseDetector, _ samples: [(Double, Double)]) -> [Bool] {
        samples.map { detector.update(speed: $0.1, at: Fixtures.start.addingTimeInterval($0.0)) }
    }

    @Test func pausesAfterStopDurationAndResumesWithHysteresis() {
        var d = AutoPauseDetector(sensitivity: .normal)
        #expect(changes(&d, [(0, 15), (1, 0.3), (5, 0.3), (9, 0.2)]) == [false, false, false, true])
        #expect(d.isPaused)
        // Creeping forward at 1.5 m/s stays paused; 3 m/s resumes.
        #expect(changes(&d, [(10, 1.5), (11, 3)]) == [false, true])
        #expect(!d.isPaused)
    }

    @Test func briefSlowdownDoesNotPause() {
        var d = AutoPauseDetector()
        #expect(changes(&d, [(0, 0.5), (5, 0.5), (6, 8), (7, 0.5), (12, 0.5)]).allSatisfy { !$0 })
        #expect(!d.isPaused)
    }
}

@Suite("Live ride stats")
struct LiveRideStatsTests {
    @Test func matchesFullSummary() {
        var points = Fixtures.track(segments: [(300, 18), (150, 0), (200, 9)])
        points[100].speed = 70   // spike, filtered the same way in both
        var live = LiveRideStats()
        points.forEach { live.add($0) }
        let full = RideStats.summarize(points)
        #expect(abs(live.distanceMeters - full.distanceMeters) < 0.001)
        #expect(live.movingSeconds == full.movingSeconds)
        #expect(abs(live.avgMovingSpeedMps - full.avgMovingSpeedMps) < 0.001)
        #expect(abs(live.maxSpeedMps - 18) < 0.001)
        #expect(live.currentSpeedMps == 9)
        #expect(live.pointCount == points.count)
    }

    @Test func breakSegmentSkipsTheGap() {
        let first = Fixtures.track(segments: [(10, 10)])
        let resumedFrom = Fixtures.north(of: Fixtures.indiaGate, meters: 5_000)
        let second = Fixtures.track(from: resumedFrom, startingAt: Fixtures.start.addingTimeInterval(600), segments: [(10, 10)])
        var live = LiveRideStats()
        first.forEach { live.add($0) }
        live.breakSegment()
        second.forEach { live.add($0) }
        #expect(abs(live.distanceMeters - 200) < 0.01)
    }
}
