import MapKit
import RideKit
import SwiftUI

/// Follow a friend's ride in progress: the road so far and their last known position.
/// No live speed is shown — it helps nobody and worries family.
struct LiveRideView: View {
    let friendID: String
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL
    @State private var position: MapCameraPosition = .automatic

    private var friend: FriendSnapshot? { recorder.friends.friends.first { $0.id == friendID } }

    var body: some View {
        Group {
            if let friend, let live = friend.live, live.status(at: .now) != .expired {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let status = live.status(at: context.date)
                    ZStack(alignment: .bottom) {
                        Map(position: $position) {
                            if live.path.count > 1 {
                                MapPolyline(coordinates: live.path.map(\.clCoordinate))
                                    .stroke(Brand.highwayYellow, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            }
                            Annotation(friend.name, coordinate: live.position.clCoordinate) {
                                Image(systemName: "motorcycle")
                                    .font(.headline)
                                    .foregroundStyle(Brand.asphalt)
                                    .padding(8)
                                    .background(status == .live ? Brand.highwayYellow : Brand.chalk, in: .circle)
                                    .overlay(Circle().stroke(Brand.asphalt, lineWidth: 2))
                            }
                        }
                        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                        .mapControls { MapCompass() }

                        card(friend: friend, live: live, status: status, now: context.date)
                            .padding()
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("Not riding now", systemImage: "flag.checkered")
                } description: {
                    Text("\(friend?.name ?? "Your friend") isn't sharing a ride live. If they shared it, the ride shows up under Recent rides.")
                }
            }
        }
        .navigationTitle(friend.map { "\($0.name) is riding" } ?? "Live ride")
        .toolbarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await recorder.friends.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func card(friend: FriendSnapshot, live: LiveRide, status: LiveRide.Status, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LiveBadge(status: status)
                Text(live.rideName).font(.headline).lineLimit(1)
                Spacer()
                Text(Format.distance(live.distanceMeters)).font(Brand.stat)
            }
            Text(LiveStatusText.describe(status, updatedAt: live.updatedAt, now: now))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Text("Riding for \(Format.roadTime(now.timeIntervalSince(live.startedAt)))")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button("Open in Google Maps", systemImage: "map") {
                    openURL(GoogleMapsLink.url(for: live.position))
                }
                .font(.footnote)
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

/// Every stop from friends' shared rides on one map. Tap one to add it to your wishlist.
struct FriendsSpotsMapView: View {
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL
    @State private var selection: String?
    @State private var message: String?

    private struct Item: Identifiable {
        var stop: SharedRide.Stop
        var friend: String
        var rideName: String
        var id: String { "\(rideName)|\(stop.id)" }
    }

    private var items: [Item] {
        recorder.friends.feed.flatMap { entry in
            entry.ride.ride.stops.filter { !$0.name.isEmpty }.map { Item(stop: $0, friend: entry.friend.name, rideName: entry.ride.ride.name) }
        }
    }

    var body: some View {
        let items = items
        ZStack(alignment: .bottom) {
            Map(selection: $selection) {
                ForEach(items) { item in
                    Marker(item.stop.name, systemImage: (SpotCategory(rawValue: item.stop.category) ?? .other).systemImage,
                           coordinate: item.stop.coordinate.clCoordinate)
                        .tint(Brand.asphalt)
                        .tag(item.id)
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))

            if let selected = items.first(where: { $0.id == selection }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selected.stop.name).font(.headline)
                    Text("\(selected.friend) · \(selected.rideName)").font(.subheadline).foregroundStyle(.secondary)
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button {
                            add(selected)
                        } label: {
                            Label("Add to my wishlist", systemImage: "star").foregroundStyle(Brand.asphalt)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.highwayYellow)
                        Button("Google Maps", systemImage: "map") { openURL(selected.stop.googleMapsURL) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
                .padding()
            } else if items.isEmpty {
                Text("Named stops from friends’ rides appear here.")
                    .font(.footnote)
                    .padding(12)
                    .background(.regularMaterial, in: .capsule)
                    .padding()
            }
        }
        .navigationTitle("Friends’ spots")
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: selection) { message = nil }
    }

    private func add(_ item: Item) {
        switch recorder.spots.mark(at: item.stop.coordinate, status: .wantToGo, name: item.stop.name,
                                   category: SpotCategory(rawValue: item.stop.category) ?? .other) {
        case .created(let spot):
            spot.notes = "From \(item.friend)’s ride “\(item.rideName)”."
            try? recorder.context.save()
            message = "Added to your wishlist."
        case .revisited(let spot):
            message = "Already in your spots as “\(spot.displayName)”."
        }
    }
}
