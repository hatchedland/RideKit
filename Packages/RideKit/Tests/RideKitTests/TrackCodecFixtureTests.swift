import Foundation
import Testing
@testable import RideKit

/// The shared golden file in `spec/fixtures` that the Android port decodes too.
/// Regenerate the .bin (only when the format version changes) with
/// `RIDEKIT_WRITE_FIXTURES=1 ./scripts/test.sh --filter TrackCodecFixture`.
@Suite("Track codec fixture")
struct TrackCodecFixtureTests {
    struct File: Decodable { let points: [Point] }
    struct Point: Decodable {
        let t: Double, lat: Double, lon: Double
        let alt: Double?, speed: Double?, course: Double?, hAcc: Double, lean: Double?
        var trackPoint: TrackPoint {
            TrackPoint(timestamp: Date(timeIntervalSince1970: t), coordinate: Coordinate(latitude: lat, longitude: lon),
                       altitude: alt, speed: speed, course: course, horizontalAccuracy: hAcc, lean: lean)
        }
    }

    static let dir = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../spec/fixtures").standardized

    @Test func goldenFileDecodes() throws {
        let expected = try JSONDecoder().decode(File.self, from: Data(contentsOf: Self.dir.appending(path: "track-v2.json"))).points
        let binURL = Self.dir.appending(path: "track-v2.bin")
        if ProcessInfo.processInfo.environment["RIDEKIT_WRITE_FIXTURES"] == "1" {
            try TrackCodec.encode(expected.map(\.trackPoint)).write(to: binURL)
        }
        let bin = try Data(contentsOf: binURL)
        #expect(Array(bin.prefix(4)) == Array("RTK".utf8) + [2])

        let decoded = try TrackCodec.decode(bin)
        #expect(decoded.count == expected.count)
        for (p, e) in zip(decoded, expected) {
            #expect(p.timestamp.timeIntervalSince1970 == e.t)
            #expect(p.coordinate.latitude == e.lat)
            #expect(p.coordinate.longitude == e.lon)
            #expect(p.altitude.map(Float.init) == e.alt.map(Float.init))
            #expect(p.speed.map(Float.init) == e.speed.map(Float.init))
            #expect(p.course.map(Float.init) == e.course.map(Float.init))
            #expect(Float(p.horizontalAccuracy) == Float(e.hAcc))
            #expect(p.lean.map(Float.init) == e.lean.map(Float.init))
        }
    }
}
