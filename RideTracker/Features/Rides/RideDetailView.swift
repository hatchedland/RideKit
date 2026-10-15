import Charts
import MapKit
import RideKit
import SwiftUI

struct RideDetailView: View {
    @Bindable var ride: Ride
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss

    @State private var track: [TrackPoint] = []
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var gpxURL: URL?
    @State private var shareRequest: MediaShareRequest?
    @State private var mediaMode = MediaMode.trail

    enum MediaMode { case trail, grid }

    var body: some View {
        List {
            Section {
                RideMap(track: track, spots: ride.spots ?? [], media: ride.media ?? [])
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
            }

            Section { RideStatsGrid(ride: ride) }

            if track.count > 10 {
                Section("Speed") {
                    SpeedChart(track: track)
                        .frame(height: 160)
                }
            }

            let media = (ride.media ?? []).sorted { $0.capturedAt < $1.capturedAt }
            Section {
                if !media.isEmpty {
                    Picker("Show", selection: $mediaMode) {
                        Text("Trail").tag(MediaMode.trail)
                        Text("Grid").tag(MediaMode.grid)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }

                if mediaMode == .trail || media.isEmpty {
                    RideTrailRows(ride: ride, track: track)
                } else {
                    MediaGrid(links: media)
                        .listRowInsets(EdgeInsets())
                }
            } header: {
                HStack {
                    Text(media.isEmpty ? "Trail" : "Trail · \(media.count) photos & videos")
                    Spacer()
                    if !media.isEmpty {
                        Button("Share all", systemImage: "square.and.arrow.up") {
                            shareRequest = MediaShareRequest(localIdentifiers: media.map(\.localIdentifier))
                        }
                        .font(.footnote)
                        .textCase(nil)
                    }
                }
            } footer: {
                if !media.isEmpty {
                    Text("Also in the Photos app under Albums › Ride Tracker › \(ride.name).")
                }
            }

            SoundtrackSection(ride: ride)

            RideFriendsSection(ride: ride)

            Section("Notes") {
                TextField("How was the ride?", text: $ride.notes, axis: .vertical)
                    .lineLimit(2...8)
            }

            Section {
                Button("Delete ride", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(ride.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        newName = ride.name
                        renaming = true
                    }
                    if let gpxURL {
                        ShareLink(item: gpxURL) { Label("Export GPX", systemImage: "square.and.arrow.up") }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename ride", isPresented: $renaming) {
            TextField("Ride name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { Task { await recorder.rename(ride, to: newName) } }
        } message: {
            Text("The Photos album is renamed too.")
        }
        .confirmationDialog("Delete “\(ride.name)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete ride, keep album", role: .destructive) { delete(album: false) }
            if ride.albumLocalIdentifier != nil {
                Button("Delete ride and album", role: .destructive) { delete(album: true) }
            }
        } message: {
            Text("Your photos and videos are never deleted. Spots you marked stay in your Spots.")
        }
        .mediaSharing($shareRequest)
        .task(id: ride.trackData) {
            track = ride.decodedTrack()
            gpxURL = writeGPX()
        }
    }

    private func delete(album: Bool) {
        Task {
            await recorder.delete(ride, deleteAlbum: album)
            dismiss()
        }
    }

    private func writeGPX() -> URL? {
        let spots = (ride.spots ?? []).map {
            ExportSpot(name: $0.displayName, notes: $0.notes, category: $0.category.title,
                       visited: $0.status == .visited, coordinate: $0.coordinate)
        }
        let xml = GeoExport.gpx(name: ride.name, track: track, spots: spots)
        let safeName = ride.name.replacing(/[^\w\- ]/, with: "")
        let url = URL.temporaryDirectory.appending(path: "\(safeName.isEmpty ? "ride" : safeName).gpx")
        return (try? xml.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}

/// Route coloured by speed, with spots ★ and photo pins 📷.
struct RideMap: View {
    let track: [TrackPoint]
    let spots: [Spot]
    let media: [MediaLink]

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = track.first {
                Marker("Start", systemImage: "flag.fill", coordinate: first.coordinate.clCoordinate).tint(Brand.highwayYellow)
            }
            if let last = track.last, track.count > 1 {
                Marker("End", systemImage: "flag.checkered", coordinate: last.coordinate.clCoordinate).tint(Brand.asphalt)
            }
            ForEach(spots) { spot in
                Marker(spot.displayName, systemImage: spot.category.systemImage, coordinate: spot.coordinate.clCoordinate)
                    .tint(spot.status.tint)
            }
            ForEach(media.filter { $0.spot == nil && $0.coordinate != nil }) { link in
                Annotation("", coordinate: link.coordinate!.clCoordinate) {
                    Image(systemName: link.isVideo ? "video.fill" : "camera.fill")
                        .font(.caption2)
                        .padding(5)
                        .background(Brand.asphalt, in: .circle)
                        .foregroundStyle(Brand.chalk)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
    }

    /// Splits the route into runs of similar speed (slow → fast: blue → green → orange → red),
    /// and breaks it at GPS gaps so tunnels aren't drawn as straight lines.
    private var segments: [(coordinates: [CLLocationCoordinate2D], color: Color)] {
        guard track.count > 1 else { return [] }
        func bucket(_ p: TrackPoint) -> Int {
            switch Format.speedValue(p.speed ?? 0, usesMetric: true) {
            case ..<30: 0
            case ..<60: 1
            case ..<90: 2
            default: 3
            }
        }
        let colors: [Color] = [.blue, .green, .orange, .red]
        var result: [(coordinates: [CLLocationCoordinate2D], color: Color)] = []
        var current = [track[0].coordinate.clCoordinate]
        var currentBucket = bucket(track[0])
        for (previous, point) in zip(track, track.dropFirst()) {
            let gap = point.timestamp.timeIntervalSince(previous.timestamp) > 60
            let b = bucket(point)
            if gap || b != currentBucket {
                if current.count > 1 { result.append((current, colors[currentBucket])) }
                current = gap ? [] : [previous.coordinate.clCoordinate]
                currentBucket = b
            }
            current.append(point.coordinate.clCoordinate)
        }
        if current.count > 1 { result.append((current, colors[currentBucket])) }
        return result
    }
}

struct SpeedChart: View {
    let track: [TrackPoint]

    /// At most ~300 samples so the chart stays fast on long rides.
    private var samples: [(time: Date, speed: Double)] {
        let step = max(1, track.count / 300)
        return stride(from: 0, to: track.count, by: step).map {
            (track[$0].timestamp, Format.speedValue(track[$0].speed ?? 0))
        }
    }

    var body: some View {
        Chart(samples, id: \.time) { sample in
            AreaMark(x: .value("Time", sample.time), y: .value("Speed", sample.speed))
                .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.4), .blue.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Time", sample.time), y: .value("Speed", sample.speed))
                .foregroundStyle(.blue)
        }
        .chartYAxisLabel(Format.speedUnit())
    }
}
