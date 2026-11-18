#if DEBUG
import Foundation
import Photos
import RideKit
import SwiftData

/// Debug only: launch with `-seedSampleRide` to (re)create a Delhi → Murthal ride with a spot, a photo
/// stop, a photo without location and two songs, so screens like the trail can be checked in the
/// simulator. Photos point at whatever is in the simulator's library; their times and places are made up.
enum SampleRide {
    static let launchArgument = "-seedSampleRide"
    static let name = "Sample · Murthal run"
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    @MainActor
    static func seedIfRequested(into context: ModelContext) {
        guard requested else { return }
        let existing = (try? context.fetch(FetchDescriptor<Ride>(predicate: #Predicate { $0.name == name }))) ?? []
        // Rebuilt on every launch so it picks up the library once Photos access is granted.
        for ride in existing {
            for spot in ride.spots ?? [] { context.delete(spot) }
            context.delete(ride)
        }

        let start = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: .now.addingTimeInterval(-86_400))!
        let delhi = Coordinate(latitude: 28.729, longitude: 77.152)
        let kundli = Coordinate(latitude: 28.876, longitude: 77.121)
        let murthal = Coordinate(latitude: 29.0418, longitude: 77.0697)

        // 0–15 min Delhi → Kundli, 15–22 min stopped, 22–42 min Kundli → Murthal, 42–60 min at the dhaba.
        var points: [TrackPoint] = []
        func drive(_ from: Coordinate, _ to: Coordinate, minutes: ClosedRange<Double>) {
            let span = minutes.upperBound - minutes.lowerBound
            for step in stride(from: 0.0, through: span * 60, by: 5) {
                let at = start.addingTimeInterval(minutes.lowerBound * 60 + step)
                let moving = from != to
                points.append(TrackPoint(timestamp: at, coordinate: from.interpolated(to: to, fraction: step / (span * 60)),
                                         altitude: 220, speed: moving ? 17 : 0))
            }
        }
        drive(delhi, kundli, minutes: 0...15)
        drive(kundli, kundli, minutes: 15...22)
        drive(kundli, murthal, minutes: 22...42)
        drive(murthal, murthal, minutes: 42...60)

        let ride = Ride(id: UUID(), name: name, startedAt: start)
        ride.endedAt = start.addingTimeInterval(3600)
        ride.trackData = try? TrackCodec.encode(points)
        ride.apply(RideStats.summarize(points))
        context.insert(ride)

        let dhaba = Spot(name: "Amrik Sukhdev", coordinate: murthal, status: .visited, category: .food)
        dhaba.visits = [start.addingTimeInterval(43 * 60)]
        dhaba.ride = ride
        context.insert(dhaba)

        let assets = PHAsset.fetchAssets(with: .image, options: nil)
        var ids: [String] = []
        assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        func id(_ index: Int) -> String { ids.isEmpty ? "sample-\(index)" : ids[index % ids.count] }

        let photos: [(minute: Double, coordinate: Coordinate?, spot: Spot?)] = [
            (16, kundli, nil), (17, kundli, nil), (19, kundli, nil),     // photo stop at Kundli
            (30, nil, nil),                                              // no location, on the road
            (44, murthal, dhaba), (46, murthal, dhaba), (50, murthal, dhaba),
        ]
        for (index, photo) in photos.enumerated() {
            let candidate = MediaCandidate(id: "\(id(index))#\(index)", capturedAt: start.addingTimeInterval(photo.minute * 60),
                                           coordinate: photo.coordinate)
            let link = MediaLink(candidate: candidate, cloudIdentifier: nil)
            link.localIdentifier = id(index) // Same asset may repeat in a small library; that's fine here.
            link.ride = ride
            link.spot = photo.spot
            context.insert(link)
        }

        for (minute, title, artist) in [(3.0, "Safarnama", "Lucky Ali"), (25.0, "Ilahi", "Arijit Singh")] {
            let play = SongPlay(song: NowPlayingSong(id: title, title: title, artist: artist),
                                startedAt: start.addingTimeInterval(minute * 60), listenedSeconds: 200)
            let song = PlayedSong(play: play, at: nil)
            song.ride = ride
            context.insert(song)
        }
        try? context.save()
    }
}
#endif
