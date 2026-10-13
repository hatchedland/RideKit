import RideKit
import SwiftData
import SwiftUI

/// The ride as a trail: start, then each stop with its photos, joined by the road between
/// (distance, time, songs, photos without location), then the end. Rows for a `List` section.
struct RideTrailRows: View {
    let ride: Ride
    let track: [TrackPoint]
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL
    @Query private var allSpots: [Spot]
    @State private var trail: Trail?
    @State private var viewing: MediaLink?

    var body: some View {
        Group {
            if let trail {
                endpoint("Start", ride.startedAt)
                ForEach(trail.stops.indices, id: \.self) { index in
                    leg(trail.legs[index])
                    stop(trail.stops[index])
                }
                if let last = trail.legs.last { leg(last) }
                endpoint("End", ride.endedAt)
            }
        }
        .listRowSeparator(.hidden)
        .task(id: inputKey) {
            let built = buildTrail()
            trail = built
            await recorder.trailNamer.resolve(built.stops.filter { $0.kind == .cluster }.map(\.coordinate))
        }
        .fullScreenCover(item: $viewing) { link in
            MediaViewer(links: sortedMedia, initial: link)
        }
    }

    // MARK: Rows

    private func endpoint(_ title: String, _ date: Date) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Brand.asphalt)
                .stroke(Brand.highwayYellow, lineWidth: 3)
                .frame(width: 16, height: 16)
                .frame(width: Self.railWidth)
            Text(title.uppercased()).font(Brand.label)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func leg(_ leg: Trail.Leg) -> some View {
        // Back-to-back stops: just a short stretch of road, no numbers.
        let trivial = (leg.distance ?? 0) < 100 && leg.duration < 120 && leg.songIDs.isEmpty && leg.mediaIDs.isEmpty
        HStack(alignment: .top, spacing: 12) {
            RoadRail().frame(width: Self.railWidth)
            VStack(alignment: .leading, spacing: 6) {
                if !trivial {
                    Text(legSummary(leg))
                        .font(.caption.weight(.semibold).width(.expanded))
                        .foregroundStyle(.secondary)
                }
                ForEach(songs(leg.songIDs)) { song in
                    Button {
                        if let url = song.appleMusicURL { openURL(url) }
                    } label: {
                        Label("\(song.title)\(song.artist.isEmpty ? "" : " — \(song.artist)")", systemImage: "music.note")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Opens in Apple Music")
                }
                if !leg.mediaIDs.isEmpty {
                    Text("On the road").font(.caption).foregroundStyle(.secondary)
                    strip(leg.mediaIDs)
                }
            }
            .padding(.vertical, trivial ? 4 : 6)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    @ViewBuilder
    private func stop(_ stop: Trail.Stop) -> some View {
        let spot = spotFor(stop)
        let suggestion = stop.kind == .cluster ? recorder.trailNamer.suggestion(for: stop.coordinate) : nil

        HStack(alignment: .top, spacing: 12) {
            MilestoneMark(filled: spot != nil)
                .frame(width: 18)
                .frame(width: Self.railWidth)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                if let spot {
                    NavigationLink(value: spot) { stopTitle(spot.displayName, suggested: spot.nameIsSuggested, stop: stop) }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        stopTitle(suggestion?.name ?? "Stop", suggested: suggestion != nil, stop: stop)
                        Spacer()
                        Button("Save as spot", systemImage: "plus") { save(stop, suggestion: suggestion) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                if !stop.mediaIDs.isEmpty { strip(stop.mediaIDs) }
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func stopTitle(_ name: String, suggested: Bool, stop: Trail.Stop) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(name).font(.headline).lineLimit(2)
                if suggested {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Suggested name")
                }
            }
            Text(stopMeta(stop)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func strip(_ ids: [String]) -> some View {
        let links = ids.compactMap { mediaByID[$0] }
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(links) { link in
                    Button { viewing = link } label: {
                        AssetThumbnail(localIdentifier: link.localIdentifier, isVideo: link.isVideo)
                            .frame(width: 88, height: 88)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(link.isVideo ? "Video" : "Photo")
                    .accessibilityValue(link.capturedAt.formatted(date: .omitted, time: .shortened))
                }
            }
        }
        .frame(height: 88)
    }

    // MARK: Text

    private func legSummary(_ leg: Trail.Leg) -> String {
        var parts: [String] = []
        if let distance = leg.distance, distance >= 100 { parts.append(Format.distance(distance)) }
        parts.append(Format.roadTime(leg.duration))
        return parts.joined(separator: " · ")
    }

    private func stopMeta(_ stop: Trail.Stop) -> String {
        var parts: [String] = []
        if let distance = stop.distanceFromStart { parts.append(Format.milestone(distance)) }
        parts.append(stop.arrivedAt.formatted(date: .omitted, time: .shortened))
        let photos = stop.mediaIDs.count
        if photos > 0 { parts.append(photos == 1 ? "1 photo" : "\(photos) photos") }
        return parts.joined(separator: " · ")
    }

    // MARK: Data

    private static let railWidth: CGFloat = 24

    private var sortedMedia: [MediaLink] {
        (ride.media ?? []).sorted { $0.capturedAt < $1.capturedAt }
    }

    private var mediaByID: [String: MediaLink] {
        Dictionary((ride.media ?? []).map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func songs(_ ids: [String]) -> [PlayedSong] {
        let wanted = Set(ids)
        return ride.soundtrack.filter { wanted.contains($0.id.uuidString) }
    }

    private func spotFor(_ stop: Trail.Stop) -> Spot? {
        guard case .spot(let id) = stop.kind else { return nil }
        return allSpots.first { $0.id == id }
    }

    /// Changes whenever the trail would: photos moving between spots, spots added, the track loading.
    private var inputKey: String {
        let media = (ride.media ?? []).map { "\($0.localIdentifier)>\($0.spot?.id.uuidString ?? "")" }.sorted()
        return "\(track.count)|\(media.joined(separator: ","))|\(trailSpots.map(\.id))|\(ride.songs?.count ?? 0)"
    }

    /// Spots marked on this ride, plus any spot visited during it (revisits, auto-visited wishlist).
    private var trailSpots: [Trail.Spot] {
        let window = ride.startedAt...max(ride.startedAt, ride.endedAt)
        var result: [UUID: Trail.Spot] = [:]
        for spot in allSpots {
            let visit = spot.visits.filter { window.contains($0) }.min()
            let markedHere = spot.ride?.id == ride.id
            guard markedHere || visit != nil else { continue }
            result[spot.id] = Trail.Spot(id: spot.id, coordinate: spot.coordinate, markedAt: visit ?? spot.createdAt)
        }
        return result.values.sorted { $0.markedAt < $1.markedAt }
    }

    private func buildTrail() -> Trail {
        Trail.build(
            rideStart: ride.startedAt,
            rideEnd: ride.endedAt,
            track: track,
            media: (ride.media ?? []).map {
                Trail.Media(id: $0.localIdentifier, capturedAt: $0.capturedAt, coordinate: $0.coordinate, spotID: $0.spot?.id)
            },
            spots: trailSpots,
            songs: (ride.songs ?? []).map { (id: $0.id.uuidString, startedAt: $0.startedAt) }
        )
    }

    /// Turns a photo stop into a real spot, visited when the photos were taken, and attaches its photos.
    private func save(_ stop: Trail.Stop, suggestion: TrailNamer.Suggestion?) {
        let result = recorder.spots.mark(
            at: stop.coordinate,
            status: .visited,
            name: suggestion?.isLandmark == true ? suggestion?.name ?? "" : "",
            category: suggestion?.category ?? .other,
            rideID: ride.id,
            visitedAt: stop.arrivedAt
        )
        if case .created(let spot) = result, suggestion?.isLandmark == true {
            spot.nameIsSuggested = true
        }
        recorder.organizer.replace(mediaOf: ride, radius: AppSettings.spotRadius)
    }
}

/// The road between stops: a dashed centre line.
private struct RoadRail: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: geo.size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
            }
            .stroke(Brand.highwayYellow, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
        }
        .accessibilityHidden(true)
    }
}
