import RideKit
import SwiftUI

/// Follow a friend's ride in progress: the road so far and their last known position.
/// No live speed is shown — it helps nobody and worries family.
struct LiveRideView: View {
    let friendID: String
    @Environment(RideRecorder.self) private var recorder
    @Environment(\.openURL) private var openURL

    private var friend: FriendSnapshot? { recorder.friends.friends.first { $0.id == friendID } }

    var body: some View {
        Group {
            if let friend, let live = friend.live, live.status(at: .now) != .expired {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let status = live.status(at: context.date)
                    ZStack(alignment: .bottom) {
                        GoogleMapView(
                            lines: live.path.count > 1
                                ? [MapLine(id: "path", coordinates: live.path, color: Brand.highwayYellow, width: 5)]
                                : [],
                            pins: [MapPin(id: "rider", coordinate: live.position, title: friend.name, systemImage: "motorcycle",
                                          tint: status == .live ? Brand.highwayYellow : Brand.chalk, style: .rider)],
                            camera: .fitContent,
                            look: .muted,
                            showsCompass: true,
                            padding: UIEdgeInsets(top: 0, left: 0, bottom: 150, right: 0)
                        )

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
        GoogleMapView(
            pins: items.map { item in
                MapPin(id: item.id, coordinate: item.stop.coordinate, title: item.stop.name,
                       systemImage: (SpotCategory(rawValue: item.stop.category) ?? .other).icon,
                       tint: item.id == selection ? Brand.highwayYellow : Brand.asphalt)
            },
            camera: .fitContent,
            look: .muted,
            onTapPin: { id in
                selection = id
                message = nil
            },
            onTapMap: { selection = nil }
        )
        .overlay(alignment: .bottom) {
            if items.isEmpty {
                Text("Named stops from friends’ rides appear here.")
                    .font(.footnote)
                    .padding(12)
                    .background(.regularMaterial, in: .capsule)
                    .padding()
            }
        }
        .mapDrawer(item: Binding(
            get: { items.first { $0.id == selection } },
            set: { selection = $0?.id }
        )) { selected in
            VStack(alignment: .leading, spacing: 12) {
                MapDrawerHeader(
                    title: selected.stop.name,
                    subtitle: "\(selected.friend) · \(selected.rideName)",
                    systemImage: (SpotCategory(rawValue: selected.stop.category) ?? .other).icon
                )
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
                .padding(.horizontal)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                }
                Spacer()
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
