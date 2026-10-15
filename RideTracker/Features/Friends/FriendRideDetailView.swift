import MapKit
import RideKit
import SwiftUI

/// A friend's shared ride, told as a trail like your own: stops with their photos, the road
/// between, the soundtrack. Every stop can go straight into your wishlist.
struct FriendRideDetailView: View {
    let friend: FriendSnapshot
    let item: FriendSnapshot.Ride
    @Environment(\.openURL) private var openURL
    @State private var viewing: SharedRide.Photo?

    private var ride: SharedRide { item.ride }

    var body: some View {
        List {
            Section {
                FriendRideMap(track: item.track, stops: ride.stops)
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("\(friend.name) hides the start, the end and private places of every shared ride.")
            }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        stat("DISTANCE", Format.distance(ride.distanceMeters))
                        stat("TIME", Format.duration(ride.endedAt.timeIntervalSince(ride.startedAt)))
                    }
                    GridRow {
                        stat("MOVING", Format.duration(ride.movingSeconds))
                        stat("TOP SPEED", "\(Format.speed(ride.maxSpeedMps)) \(Format.speedUnit())")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Stops") {
                if ride.stops.isEmpty {
                    Text("No stops shared on this ride.").foregroundStyle(.secondary)
                }
                ForEach(ride.stops) { stop in
                    FriendStopRow(stop: stop, friendName: friend.name, rideName: ride.name, photos: photos(stop.photoIDs),
                                  photoFiles: item.photoFiles) { viewing = $0 }
                }
            }

            let loose = loosePhotos
            if !loose.isEmpty {
                Section("On the road") {
                    PhotoStrip(photos: loose, files: item.photoFiles) { viewing = $0 }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            if !ride.songs.isEmpty {
                Section("Soundtrack") {
                    ForEach(Array(ride.songs.enumerated()), id: \.offset) { _, song in
                        Button {
                            if let url = song.appleMusicURL { openURL(url) }
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(song.title).foregroundStyle(.primary)
                                    if !song.artist.isEmpty { Text(song.artist).font(.caption).foregroundStyle(.secondary) }
                                }
                            } icon: {
                                Image(systemName: "music.note")
                            }
                        }
                        .accessibilityHint("Opens in Apple Music")
                    }
                }
            }
        }
        .navigationTitle(ride.name)
        .navigationSubtitle("\(friend.name) · \(ride.endedAt.formatted(date: .abbreviated, time: .omitted))")
        .toolbarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewing) { photo in
            FriendPhotoViewer(photos: ride.photos, files: item.photoFiles, initial: photo)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Brand.label).foregroundStyle(.secondary)
            Text(value).font(Brand.stat)
        }
        .accessibilityElement(children: .combine)
    }

    private func photos(_ ids: [String]) -> [SharedRide.Photo] {
        ids.compactMap { id in ride.photos.first { $0.id == id } }
    }

    /// Shared photos that aren't at any stop.
    private var loosePhotos: [SharedRide.Photo] {
        let atStops = Set(ride.stops.flatMap(\.photoIDs))
        return ride.photos.filter { !atStops.contains($0.id) }
    }
}

private struct FriendStopRow: View {
    let stop: SharedRide.Stop
    let friendName: String
    let rideName: String
    let photos: [SharedRide.Photo]
    let photoFiles: [String: URL]
    var onTap: (SharedRide.Photo) -> Void

    @Environment(RideRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL
    @State private var added: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(meta).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Add to my wishlist", systemImage: "star") { addToWishlist() }
                    Button("Open in Google Maps", systemImage: "map") { openURL(stop.googleMapsURL) }
                } label: {
                    Image(systemName: added == nil ? "star" : "star.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                } primaryAction: {
                    addToWishlist()
                }
                .accessibilityLabel(added == nil ? "Add to my wishlist" : "In your spots")
            }
            if let added {
                Text(added).font(.caption).foregroundStyle(.secondary)
            }
            if !photos.isEmpty {
                PhotoStrip(photos: photos, files: photoFiles, onTap: onTap)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String { stop.name.isEmpty ? "Stop" : stop.name }

    private var meta: String {
        var parts: [String] = []
        if let distance = stop.distanceFromStart { parts.append(Format.milestone(distance)) }
        parts.append(stop.arrivedAt.formatted(date: .omitted, time: .shortened))
        if let category = SpotCategory(rawValue: stop.category), category != .other { parts.append(category.title) }
        return parts.joined(separator: " · ")
    }

    private func addToWishlist() {
        guard added == nil else { return }
        switch recorder.spots.mark(at: stop.coordinate, status: .wantToGo, name: stop.name,
                                   category: SpotCategory(rawValue: stop.category) ?? .other) {
        case .created(let spot):
            spot.notes = "From \(friendName)’s ride “\(rideName)”."
            try? recorder.context.save()
            added = "Added to your wishlist."
        case .revisited(let spot):
            added = "Already in your spots as “\(spot.displayName)”."
        }
    }
}

private struct PhotoStrip: View {
    let photos: [SharedRide.Photo]
    let files: [String: URL]
    var onTap: (SharedRide.Photo) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(photos) { photo in
                    if let url = files[photo.id] {
                        Button { onTap(photo) } label: {
                            FilePhoto(url: url)
                                .frame(width: 88, height: 88)
                                .clipShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.isVideo ? "Still from a video" : "Photo")
                    }
                }
            }
        }
        .frame(height: 88)
    }
}

private struct FriendPhotoViewer: View {
    let photos: [SharedRide.Photo]
    let files: [String: URL]
    let initial: SharedRide.Photo
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String = ""

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(photos.filter { files[$0.id] != nil }) { photo in
                    FullPhoto(url: files[photo.id]!)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .onAppear { selection = initial.id }
    }
}

private struct FullPhoto: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image { Image(uiImage: image).resizable().scaledToFit() } else { ProgressView().tint(.white) }
        }
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) { [url] in UIImage(contentsOfFile: url.path()) }.value
        }
    }
}

/// The redacted route in highway yellow, with the friend's stops.
struct FriendRideMap: View {
    let track: [TrackPoint]
    let stops: [SharedRide.Stop]

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                MapPolyline(coordinates: segment)
                    .stroke(Brand.asphalt, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: segment)
                    .stroke(Brand.highwayYellow, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            ForEach(stops) { stop in
                Marker(stop.name.isEmpty ? "Stop" : stop.name,
                       systemImage: (SpotCategory(rawValue: stop.category) ?? .other).systemImage,
                       coordinate: stop.coordinate.clCoordinate)
                    .tint(Brand.asphalt)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    /// Breaks the line where points were removed (privacy zones) or GPS dropped out.
    private var segments: [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        for (index, point) in track.enumerated() {
            if index > 0 {
                let previous = track[index - 1]
                let gap = point.timestamp.timeIntervalSince(previous.timestamp) > 60
                    || point.coordinate.distance(to: previous.coordinate) > 1_000
                if gap {
                    if current.count > 1 { result.append(current) }
                    current = []
                }
            }
            current.append(point.coordinate.clCoordinate)
        }
        if current.count > 1 { result.append(current) }
        return result
    }
}
